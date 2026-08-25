import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/encryption/encryption_key_source.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/key_derivation.dart';

/// On-device crypto benchmark.
///
/// The unit suite proves the crypto is *correct*; nothing in it can tell
/// you whether Argon2id is fast enough on the phones you actually intend
/// to support. Desktop numbers do not transfer — a low-end Android device
/// is several times slower — so this has to run on real hardware.
///
/// # How to run it
///
/// ```sh
/// flutter devices        # find your device id
///
/// flutter test integration_test/crypto_benchmark_test.dart \
///   --flavor development -d <device-id> --profile
/// ```
///
/// Use `--profile`. Debug mode is materially slower and will make the
/// numbers look worse than a real build.
///
/// Results print to the console as a table.
///
/// # How to read the result
///
/// Android raises an ANR ("app isn't responding") if the *platform
/// thread* blocks for ~5 s. SafeKeep derives on a background isolate, so a
/// slow KDF shows up as a slow unlock rather than an ANR — but a
/// multi-second unlock is still bad, and 5 s is the hard ceiling this test
/// asserts against.
///
/// Guidance for the production 48 MiB profile:
///
/// * **under 1.5 s** — comfortable, keep the current parameters.
/// * **1.5-3 s** — acceptable for a vault unlock; check how it feels.
/// * **over 3 s** — consider dropping to 32 MiB. The table shows what
///   that would buy you on this specific device.
///
/// Tuning is cheap **now** and effectively permanent once real vaults
/// exist: each vault keeps deriving with the parameters it was created
/// under, so a later change only affects new vaults. See [KdfParameters].
///
/// # Note on `tester.runAsync`
///
/// Every measurement below runs inside [WidgetTester.runAsync]. This is
/// not optional: `testWidgets` executes in a fake-async zone, and
/// `KeyDerivation` awaits a real `Isolate.run`. Without `runAsync` the
/// fake clock never advances to let that isolate complete and the test
/// deadlocks until it times out. `runAsync` also means the [Stopwatch]
/// readings reflect real wall-clock time, which is the whole point here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const kdf = KeyDerivation();
  const passphrase = 'a representative passphrase for benchmarking';

  const profiles = <(String, KdfParameters)>[
    ('PRODUCTION  48 MiB t=2 p=1', KdfParameters.current),
    (
      'fallback    32 MiB t=2 p=1',
      KdfParameters(
        memoryKib: 32768,
        iterations: 2,
        parallelism: 1,
        keyLengthBytes: 32,
      ),
    ),
    (
      'OWASP floor 19 MiB t=2 p=1',
      KdfParameters(
        memoryKib: 19456,
        iterations: 2,
        parallelism: 1,
        keyLengthBytes: 32,
      ),
    ),
  ];

  testWidgets(
    'Argon2id derivation speed on this device',
    (tester) async {
      final salt = KeyDerivation.generateSalt();

      // Best of 3: the fastest run is the most stable estimate when other
      // apps are competing for CPU.
      Future<Duration> measure(KdfParameters parameters) async {
        var best = const Duration(days: 1);
        for (var i = 0; i < 3; i++) {
          final stopwatch = Stopwatch()..start();
          final keys = await kdf.deriveKeys(
            passphrase: passphrase,
            salt: salt,
            parameters: parameters,
          );
          stopwatch.stop();
          keys.destroy();
          if (stopwatch.elapsed < best) best = stopwatch.elapsed;
        }
        return best;
      }

      Duration? production;

      await tester.runAsync(() async {
        debugPrint('');
        debugPrint('=== Argon2id derivation (best of 3) ===');

        for (final (label, parameters) in profiles) {
          final elapsed = await measure(parameters);
          if (parameters == KdfParameters.current) production = elapsed;
          debugPrint('$label -> ${elapsed.inMilliseconds} ms');
        }
      });

      final productionTime = production!;
      debugPrint('');
      if (productionTime.inMilliseconds < 1500) {
        debugPrint('VERDICT: comfortable. Keep the current parameters.');
      } else if (productionTime.inMilliseconds < 3000) {
        debugPrint('VERDICT: acceptable, but check how the unlock feels.');
      } else {
        debugPrint(
          'VERDICT: slow. Consider lowering KdfParameters.current to '
          '32 MiB. Decide before real vaults exist.',
        );
      }
      debugPrint('');

      // Hard ceiling. An unlock past Android's ANR window is a defect,
      // not a tuning preference.
      expect(
        productionTime.inSeconds,
        lessThan(5),
        reason:
            'Argon2id at the production parameters took '
            '${productionTime.inMilliseconds} ms on this device, past the '
            '5 s Android ANR threshold. Lower KdfParameters.current.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'AES-GCM throughput on this device',
    (tester) async {
      final key = Uint8List(32)..fillRange(0, 32, 0x2A);
      final service = AesGcmEncryptionService(keySource: _FixedKey(key));

      await tester.runAsync(() async {
        debugPrint('');
        debugPrint('=== AES-256-GCM (pure Dart) ===');

        for (final megabytes in [1, 5, 10]) {
          final plaintext = Uint8List(megabytes * 1024 * 1024);

          final encryptWatch = Stopwatch()..start();
          final blob = await service.encrypt(plaintext, keyId: 'bench');
          encryptWatch.stop();

          final decryptWatch = Stopwatch()..start();
          await service.decrypt(blob, keyId: 'bench');
          decryptWatch.stop();

          debugPrint(
            '${megabytes}MB -> encrypt ${encryptWatch.elapsedMilliseconds} ms, '
            'decrypt ${decryptWatch.elapsedMilliseconds} ms',
          );
        }

        debugPrint('');
        debugPrint(
          'If these feel slow: package:cryptography_flutter swaps in '
          'native AES-GCM (~10x) and changes NOTHING about the stored '
          'blob format, so it needs no data migration. See TODO(phase2) '
          'in aes_gcm_encryption_service.dart.',
        );
        debugPrint('');
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets('sanity: RFC 9106 vector still passes on this device', (
    tester,
  ) async {
    // Guards against a platform-specific arithmetic difference in the
    // pure-Dart Argon2id. If this fails on a device but passes on
    // desktop, stop and investigate before shipping anything.
    List<int>? derived;

    await tester.runAsync(() async {
      final algorithm = Argon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );
      final key = await algorithm.deriveKey(
        secretKey: SecretKey(List<int>.filled(32, 0x01)),
        nonce: List<int>.filled(16, 0x02),
        optionalSecret: List<int>.filled(8, 0x03),
        associatedData: List<int>.filled(12, 0x04),
      );
      derived = await key.extractBytes();
    });

    expect(derived, <int>[
      0x0d, 0x64, 0x0d, 0xf5, 0x8d, 0x78, 0x76, 0x6c, //
      0x08, 0xc0, 0x37, 0xa3, 0x4a, 0x8b, 0x53, 0xc9,
      0xd0, 0x1e, 0xf0, 0x45, 0x2d, 0x75, 0xb6, 0x5e,
      0xb5, 0x25, 0x20, 0xe9, 0x6b, 0x01, 0xe6, 0x59,
    ]);
  });
}

/// Supplies one fixed key; the benchmark does not need a real vault.
class _FixedKey implements EncryptionKeySource {
  _FixedKey(this.key);

  final Uint8List key;

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => key;
}
