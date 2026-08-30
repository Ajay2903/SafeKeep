import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/theme/app_theme.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/data/storage/document_file_storage.dart';
import 'package:safekeep/data/vault_document_repository.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/l10n/l10n.dart';
import 'package:safekeep/presentation/app/vault_gate.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/auth/local_auth_biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/flutter_secure_storage_store.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';

/// The app root.
///
/// Dependencies are constructed here and injected, rather than reached
/// for as singletons, so tests and the debug harness can substitute fakes
/// without any global state to reset between them.
class App extends StatelessWidget {
  const App({
    required this.config,
    required this.databasePath,
    required this.blobDirectory,
    this.keyManager,
    this.biometricGate,
    this.database,
    this.repository,
    super.key,
  });

  final AppConfig config;

  /// Filesystem path for the encrypted metadata database.
  ///
  /// Resolved by the caller because `path_provider` needs a platform
  /// channel, keeping this widget constructible in a test.
  final String databasePath;

  /// Directory holding encrypted document blobs. Resolved by the caller
  /// for the same reason as [databasePath].
  final Directory blobDirectory;

  /// Overrides for testing. Production leaves these null and gets the
  /// real platform-backed implementations.
  final KeyManager? keyManager;
  final BiometricGate? biometricGate;
  final AppDatabase? database;
  final DocumentRepository? repository;

  @override
  Widget build(BuildContext context) {
    final gate = biometricGate ?? LocalAuthBiometricGate();
    final keys =
        keyManager ??
        VaultKeyManager(
          store: const FlutterSecureStorageStore(),
          biometricGate: gate,
        );
    final db =
        database ??
        AppDatabase(
          opener: SqlCipherDatabaseOpener(path: databasePath),
        );

    final vault =
        repository ??
        VaultDocumentRepository(
          encryption: AesGcmEncryptionService(keySource: keys),
          fileStorage: FileSystemDocumentFileStorage(
            directory: blobDirectory,
          ),
          dao: DocumentDao(database: db),
        );

    return MaterialApp(
      title: config.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider(
        create: (_) => VaultSessionCubit(
          keyManager: keys,
          biometricGate: gate,
          database: db,
        ),
        child: VaultGate(repository: vault),
      ),
    );
  }
}
