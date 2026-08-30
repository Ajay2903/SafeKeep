# Cryptographic design review request: local-first mobile document vault

## What this is

A request for review of the cryptographic design of a **local-first mobile
vault application**. The app stores user documents (PDFs, photos) encrypted
on-device. There is no server, no accounts, and no server-side secret. The
user's passphrase is the root of all key material; if it is forgotten the
data is unrecoverable by design.

Encrypted blobs may later be copied by the user to their own third-party
cloud storage as a backup. Those blobs must remain secure in the hands of
anyone who obtains them.

Two questions are put directly to reviewers at the end, but critique of
anything here is welcome — particularly the parts flagged in *Known
weaknesses*.

**Implementation context** (relevant to several points below): the app is
written in Dart/Flutter. Argon2id, HKDF, and AES-GCM all come from a
pure-Dart cryptography library — **there is no hardware AES, and no
constant-time implementation guarantee**. The Argon2id implementation has
been verified against the RFC 9106 §5.3 test vector. Platform secure
storage (Android Keystore / iOS Keychain) and the biometric prompt are
native.

Identifiers such as the app name have been redacted; where a literal
constant matters cryptographically its structure is given exactly.

---

## 1. Threat model

### In scope

1. **Offline brute-force of a leaked or stolen encrypted backup.** The
   primary threat. An attacker obtains the encrypted blobs plus the
   non-secret metadata that travels with them (salt, KDF parameters,
   verification value) — for example by compromising the user's cloud
   storage account. They can then guess passphrases offline, unlimited, in
   parallel, with no rate limiting anywhere in the system. **The KDF cost
   is the only barrier.**
2. **Lost or stolen device, locked.** The device is powered on but the
   vault is locked. Key material must not be readable without passing the
   biometric/device-credential gate.
3. **Lost or stolen device, app backgrounded.** The vault auto-locks after
   a grace period so an unattended unlocked device does not stay readable
   indefinitely.
4. **Local storage compromise below the OS security boundary.** An
   attacker reads app-private files or pulls a device backup, but does not
   defeat Keystore/Keychain. Document blobs on disk must be useless
   without the key.
5. **Tampering with stored ciphertext.** Blobs in cloud storage can be
   modified by anyone who compromises that account. Modified data must be
   detected, never returned as plaintext.

### Explicitly out of scope

1. **A compromised or rooted OS.** If the attacker has root, can attach a
   debugger to the running process, or defeat Keystore/Keychain, they can
   recover the key. No mitigation is claimed.
2. **A compromised device while the vault is unlocked.** The key is in
   process memory by necessity during a session.
3. **Coercion / rubber-hose.** No duress passphrase, no plausible
   deniability.
4. **Supply-chain compromise of the crypto library or toolchain.**
5. **Malicious app updates.** The user trusts the binary they installed.
6. **Screen capture, clipboard, accessibility-service scraping** of
   decrypted content once displayed.
7. **Traffic analysis / metadata leakage from blob sizes.** Ciphertext
   length reveals plaintext length (see *Known weaknesses*).

### Explicit non-goal

**Recovery from a forgotten passphrase.** There is no escrow, no recovery
key, no backdoor. This is intentional and users are expected to be warned.

---

## 2. Primitives and parameters

### 2.1 Password-based key derivation — Argon2id

**Algorithm:** Argon2id, RFC 9106.

**Final parameters:**

| Parameter | Value |
|---|---|
| memory (`m`) | 49 152 KiB (48 MiB) |
| iterations (`t`) | 2 |
| parallelism (`p`) | 1 |
| output length (`τ`) | 32 bytes |
| salt (`S`) | 16 bytes, CSPRNG, unique per vault, stored in clear |
| secret (`K` / pepper) | not used |
| associated data (`X`) | not used |

**Why Argon2id over PBKDF2/scrypt.** The threat model has no rate limiting
at all, so per-guess cost is the entire defence. PBKDF2 parallelises on
GPUs and ASICs at near-zero marginal cost per additional guess. Argon2id's
memory hardness forces an attacker to allocate 48 MiB per *concurrent*
guess, which is what actually caps parallelism: an 8 GB GPU fits roughly
170 concurrent instances at 48 MiB versus roughly 420 at the OWASP
minimum of 19 MiB.

**Why these specific cost factors — empirical.** These were tuned on real
low-end hardware, not extrapolated:

| Configuration | M-series laptop (AOT) | Samsung Galaxy A21s (Exynos 850, profile build) |
|---|---|---|
| 64 MiB, t=3, p=1 | ~295 ms | **~6 000 ms** |
| **48 MiB, t=2, p=1 (chosen)** | ~156 ms | **~3 000 ms** |
| 32 MiB, t=2, p=1 | ~102 ms | — |
| 19 MiB, t=2, p=1 (OWASP floor) | ~57 ms | — |

The initial choice of 64 MiB / t=3 was made from the desktop figure and
proved roughly **19× slower** on a budget device — far beyond what a
JIT-versus-AOT gap explains. Argon2id is memory-bandwidth-bound and
punishes low-end memory subsystems disproportionately. 6 s exceeded
Android's ~5 s ANR threshold and made first-run setup unacceptable.

**Why iterations were cut rather than memory.** At a fixed wall-clock
budget, more memory with fewer passes dominates less memory with more
passes, because memory caps attacker parallelism while passes only add
serial work. 48 MiB/t=2 and 32 MiB/t=3 cost the same ~3 s on the target
device; the former retains 50 % more memory hardness. Iterations sit at
OWASP's floor of 2; memory sits ~2.5× above OWASP's 19 MiB floor.

`p = 1` because Argon2's parallelism parameter models the *attacker's*
per-guess parallelism and does not help the defender; it also keeps
derivation deterministic and single-threaded across devices.

**Passphrase encoding:** UTF-8, explicitly. (The platform string type is
UTF-16; relying on its default code units would derive different keys for
non-ASCII passphrases depending on the call path.)

**Threading:** derivation runs on a background isolate so the ~3 s never
blocks the platform thread.

**Who pays this cost:** only vault setup, passphrase unlock, and
passphrase verification. Biometric unlock reads the stored key directly
and performs no derivation — measured as effectively instant. So the 3 s
is paid once at onboarding and thereafter only on the fallback path.

### 2.2 Bulk encryption — AES-256-GCM

**Algorithm:** AES-256-GCM. 96-bit nonce, 128-bit (full, untruncated) tag.

**Why GCM.** AEAD is required, not optional: blobs are expected to sit in
storage an attacker may be able to write to, so decryption must *detect*
modification rather than return attacker-influenced plaintext. A
non-authenticated mode (CBC, CTR) would fail silently.

**Nonce generation.** A fresh 96-bit nonce is drawn from the platform
CSPRNG for **every** encryption call. Never a counter: a persisted counter
cannot be trusted across app reinstalls, crashes, restores, or a blob set
copied between devices, and nonce reuse under a fixed GCM key is
catastrophic (plaintext XOR recovery plus authentication-key recovery
enabling forgery).

96 bits is chosen because GCM consumes a 96-bit nonce directly rather than
compressing it through GHASH.

**Collision budget.** With random 96-bit nonces the birthday bound keeps
collision probability negligible below roughly 2³² encryptions under a
single key. A personal document vault is many orders of magnitude below
that. Note this budget is shared across all documents, since all documents
are encrypted under one key (see *Known weaknesses*).

**Associated data.** Every encryption binds the document's identity, so a
blob only authenticates in the position it was written for:

```
AAD = format_version (1 byte)
   || len(utf8(document_id))  (4 bytes, big-endian uint32)
   || utf8(document_id)
```

The AAD is not stored; it is reconstructed at decryption time from the
version byte in the header and the document identifier supplied by the
caller. Since all documents share one key, without this any blob was
valid in any position and an attacker with write access could substitute
one for another undetected. Including the version byte also authenticates
it — it lives in the blob header, which GCM does not otherwise cover.

The length prefix is not strictly required with a single trailing
variable-length field, but it removes the ambiguity that would appear the
moment any further field were appended.

### 2.3 Key separation — HKDF-SHA256

Covered in full in §3.

---

## 3. The HKDF domain-separation scheme (primary review target)

### 3.1 Construction

The Argon2id output is **never used directly as an encryption key.** It is
treated as input keying material and expanded into two independent keys.

```
IKM   = Argon2id(P = UTF8(passphrase),
                 S = salt,            // 16 bytes, per-vault, public
                 m = 49152, t = 2, p = 1,
                 τ = 32)              // 32 bytes

// RFC 5869 Extract, with an empty salt.
PRK   = HMAC-SHA256(key = <empty string>, msg = IKM)          // 32 bytes

// RFC 5869 Expand. Output length equals hash length, so a single
// block T(1) suffices and the counter byte is always 0x01.
K_enc = HMAC-SHA256(key = PRK, msg = INFO_ENC || 0x01)         // 32 bytes
K_ver = HMAC-SHA256(key = PRK, msg = INFO_VER || 0x01)         // 32 bytes

IKM and PRK are zeroed after expansion.
```

**Note on the empty Extract salt.** RFC 5869 specifies that an absent salt
be treated as `HashLen` zero bytes. HMAC pads any key shorter than the
block size with zeros, so an empty key and a 32-byte zero key yield an
identical PRK. This is therefore RFC 5869-conformant, not a deviation. No
salt is passed to Extract because the IKM is already a
uniformly-random, per-vault-salted Argon2id output.

**The `info` strings.** Two fixed ASCII byte strings of the form:

```
INFO_ENC = "<app-identifier>:v1:encryption"      (22 bytes as deployed)
INFO_VER = "<app-identifier>:v1:verification"    (24 bytes as deployed)
```

Properties: distinct; neither is a prefix of the other; both are compile-
time constants never influenced by user input; both carry a `v1` version
segment so the scheme can be revised without ambiguity. They are treated
as a wire format — changing either would orphan every existing vault.

### 3.2 What each key is used for

| Key | Length | Purpose | Persisted? |
|---|---|---|---|
| `K_enc` | 32 B | AES-256-GCM key for all document blobs | **Yes** — hardware-backed secure storage only |
| `K_ver` | 32 B | Passphrase verification value | **Yes** — stored, compared in constant time |
| `IKM` / `PRK` | 32 B | Transient intermediates | No — zeroed immediately |

**Passphrase verification** works by re-deriving `K_ver` from the entered
passphrase and the stored salt/parameters, then comparing against the
stored value using a constant-time comparison (accumulate XOR differences
over the full length; only the length check short-circuits, and lengths
are fixed by the format). This lets a passphrase be checked without
decrypting any document, and without storing the passphrase or any hash of
it in a form usable as an encryption key.

### 3.3 Why domain separation is load-bearing here

The concrete reason is the **backup / new-device restore scenario**, where
the two keys diverge in exposure:

- `salt`, KDF parameters, and `K_ver` are non-secret and are expected to
  travel alongside encrypted blobs into the user's cloud backup.
- `K_enc` never leaves hardware-backed storage on the originating device.
  A restored device re-derives it from the passphrase.

So there is a realistic situation in which an attacker holds `K_ver`, the
salt, the parameters, and the ciphertext, but not `K_enc`. Domain
separation is what makes `K_ver` useless to them: recovering `K_enc` from
`K_ver` requires either inverting HMAC-SHA256 to recover `PRK`, or
distinguishing two HKDF-Expand outputs under distinct `info` labels — both
of which reduce to breaking HMAC-SHA256 as a PRF.

Had the raw Argon2id output been stored as its own verifier, that same
attacker would simply hold the encryption key.

**What domain separation does *not* buy.** It does not protect against an
attacker who reads secure storage directly, since `K_enc` is stored there
too. And it does not prevent offline *guessing*: anyone with the salt,
parameters, and `K_ver` can test passphrase candidates offline. That
oracle is inherent to any offline vault that can verify a passphrase
without decrypting a document, and is precisely what the Argon2id cost is
sized against.

---

## 4. Key lifecycle

### 4.1 Setup (once per vault)

1. Generate a 16-byte salt from the platform CSPRNG.
2. Derive `IKM` via Argon2id, then `K_enc` and `K_ver` via HKDF (§3.1).
3. Persist to platform secure storage, in this order: salt, KDF
   parameters, `K_ver`, then `K_enc` last. (Initialisation is detected by
   the presence of `K_enc`, so a crash mid-write leaves the vault
   detectably uninitialised and retryable rather than half-formed.)
4. Zero `IKM`, `PRK`, and the local copies of the derived keys.
5. The vault is left unlocked — the user has just demonstrated knowledge
   of the passphrase.

**The passphrase itself is never persisted in any form.**

**KDF parameters are stored per vault, not hardcoded.** Argon2id is only
deterministic for a fixed parameter set, so a future release raising the
cost factors would otherwise re-derive a different key for every existing
vault and permanently orphan its documents. Each vault re-derives with the
parameters it was created under.

### 4.2 Storage at rest

| Item | Secret | Location |
|---|---|---|
| salt | no | platform secure storage |
| KDF parameters (JSON) | no | platform secure storage |
| `K_ver` | no* | platform secure storage |
| `K_enc` | **yes** | platform secure storage |
| document blobs | ciphertext | app-private filesystem |

\* not secret in the sense of revealing `K_enc`; it does enable offline
guessing, as noted in §3.3.

**Android:** Keystore-backed encrypted preferences — an AES-GCM storage
key wrapped by an RSA-OAEP (SHA-256/MGF1) key held in the Keystore. The
library's "reset on decryption error" behaviour is **disabled**: its
default silently wipes stored values when decryption fails, which for a
preferences cache is a reasonable self-heal but here would destroy the
vault key — and therefore every document — without warning. Failing
loudly is the only acceptable behaviour for this value.

**iOS/macOS:** Keychain with accessibility
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `ThisDeviceOnly`
excludes the key from iCloud Keychain sync and from encrypted device
backups: a second device is intended to be provisioned by entering the
passphrase, not by having the key handed to it.

### 4.3 Unlock

Two paths:

**Passphrase.** Re-derive using the *stored* salt and parameters, compare
`K_ver` in constant time, and on match load the freshly derived `K_enc`
into memory for the session. Cost: ~3 s on the reference device.

**Biometric / device credential.** The gate must return success **before**
`K_enc` is read out of secure storage. On success the stored key is loaded
directly; no derivation occurs. Biometrics are not required exclusively —
the device PIN/pattern/passcode is an accepted fallback, since requiring
biometrics outright locks out users with none enrolled or a failing
sensor. An authentication interrupted by backgrounding fails rather than
silently resuming on return.

### 4.4 In-memory handling during a session

`K_enc` is held in a mutable byte buffer for the duration of the unlocked
session. Callers requesting the key receive a **copy**, so that zeroing on
lock cannot corrupt an operation in flight.

### 4.5 Lock

Triggered explicitly, or automatically **30 seconds** after the app enters
the background. The grace period exists because file pickers, camera
intents, and share sheets all background the app during normal use;
locking on every transition trains users to disable the feature.

On lock the key buffer is overwritten with zeros and the reference
dropped. Any subsequent request for key material raises an error rather
than returning anything.

**Honest limitation:** this zeroization is best-effort. The runtime is
garbage-collected with no way to pin or securely wipe memory, so the GC
may already have copied the buffer. Worse, the passphrase arrives as an
immutable string type and **cannot be wiped at all**. This meaningfully
shortens the window in which key material sits in the heap; it is not a
guarantee of erasure.

### 4.6 Deletion

Deleting the vault removes `K_enc`, `K_ver`, the salt, and the parameters.
This is a cryptographic erase: because the salt is destroyed, the key
cannot be re-derived even from the correct passphrase, and every document
becomes unrecoverable whether or not the ciphertext still exists.

---

## 5. Stored blob format

```
Offset  Length  Field
------  ------  --------------------------------------------------
     0       1  format version (currently 0x02)
     1      12  nonce (96-bit, fresh CSPRNG output per encryption)
    13      16  GCM authentication tag (128-bit, untruncated)
    29       N  ciphertext (N == plaintext length)
```

Total size is always `29 + plaintext_length`. The tag additionally covers
the associated data described in §2.2, which is reconstructed rather than
stored.

Format version `0x01` was a pre-release format that bound no associated
data. It is rejected outright rather than supported, since accepting it
would reintroduce the substitution weakness the binding closes. The header is fixed-width so
parsing never depends on total length. The tag is stored at a fixed offset
*before* the ciphertext rather than appended.

The version byte exists so that a future change to the algorithm, KDF, or
layout is never ambiguous when reading an old blob.

### Failure handling

Parsing runs on untrusted input (a file on disk, or a blob restored from
cloud storage), so length and version are validated **before** any bytes
reach the cipher.

Two distinct failure classes:

1. **Malformed** — shorter than the 29-byte header, or an unrecognised
   version byte. Raised before decryption is attempted; means "this is not
   our format", not "this was tampered with".
2. **Authentication failure** — the GCM tag did not verify. Raised as a
   single error type that deliberately **does not distinguish** tampering,
   corruption, and a wrong key. Distinguishing them would leak information
   to an attacker, and no caller can act differently on the difference.

Callers must treat an authentication failure as fatal for that document:
never retry, never fall back to returning unverified plaintext. Nothing is
logged on this path, since an error path around decryption is exactly
where plaintext or key material would otherwise leak into logs.

Test coverage includes an exhaustive sweep flipping every individual byte
of a blob and asserting that each modification is rejected.

---

## 6. Known weaknesses and design choices already identified

Listed so reviewers can skip re-deriving them and focus on anything worse.

**Recently closed:** an earlier revision bound no associated data, so with
a single key shared across documents any blob authenticated in any
position and could be substituted for another undetected. This was found
while preparing this document and is fixed as described in §2.2; the
format version was bumped to `0x02` and the previous format is rejected.
Critique of the AAD encoding itself is welcome.

1. **A single key encrypts all documents.** Simple, but it means no
   per-document crypto-erase, a shared nonce budget, and no compartment-
   alisation. The AAD binding in §2.2 removes the substitution
   consequence, but not the others. Per-document keys wrapped by `K_enc`
   were considered but not implemented.
2. **AES is implemented in pure software with key-dependent table
   lookups** (S-box / T-table style), and the library makes no
   constant-time claims. This is textbook cache-timing-attack surface. On
   a mobile device the attacker needs local code execution to exploit it,
   which is arguably out of scope — but the Argon2id and HMAC
   implementations carry the same caveat, and the constant-time verifier
   comparison is hand-written rather than provided by a hardened library.
   **How much should this worry us in practice?**
3. **Stored metadata is not authenticated by the application.** Salt, KDF
   parameters, and `K_ver` rely entirely on the OS for integrity. An
   attacker able to write to secure storage could replace the whole set
   with a vault of their own; the user's existing blobs would then fail to
   decrypt (denial of service), and documents added afterwards would be
   readable by the attacker. Authenticating this metadata under a third
   HKDF-derived key was considered — but that key would itself derive from
   the passphrase, so it is unclear this adds anything against an attacker
   who can already write to storage.
4. **No passphrase strength policy is enforced.** Since the KDF cost is
   the only barrier, a weak passphrase defeats the entire design. Nothing
   currently prevents a 4-character passphrase.
5. **Ciphertext length reveals plaintext length exactly.** No padding.
6. **Memory zeroization is best-effort and the passphrase cannot be wiped
   at all** (§4.5).
7. **No key rotation mechanism.** Changing the passphrase would require
   re-encrypting every document; not implemented.
8. **The verification value is an offline guessing oracle** (§3.3) —
   believed inherent, but flagged in case a better construction exists.

---

## 7. Questions put directly to reviewers

**Q1 — Is the HKDF domain-separation construction in §3 sound?**

Specifically: is `HKDF-SHA256(IKM = Argon2id output, salt = empty, info =
distinct constant labels)` an appropriate way to produce a stored
verification value that is cryptographically independent of the encryption
key? Points of particular doubt:

- Is omitting the Extract salt acceptable given the IKM is already a
  salted Argon2id output, or is there a reason to pass the vault salt
  again?
- Is the Extract step meaningful at all here, given the IKM is already
  uniformly random? Would `HKDF-Expand` alone, or two plain HMACs under
  distinct labels, be equally sound and simpler to reason about?
- Are the `info` labels adequately structured? They are distinct and
  non-prefix, but they are not length-prefixed or otherwise unambiguously
  encoded. Does that matter with a fixed, closed set of two compile-time
  constants?
- Is deriving both keys from a **shared PRK** a concern, versus running
  Argon2id twice with different parameters (obviously far more expensive)?

**Q2 — Is persisting `K_enc` in hardware-backed secure storage an
acceptable tradeoff, versus requiring passphrase re-entry on every
unlock?**

The current design stores the derived encryption key in Keystore/Keychain
so that biometric unlock does not require re-entering the passphrase. The
consequence, stated plainly: **after setup, the passphrase is no longer
the only thing protecting data on that device** — hardware-backed storage
plus the biometric gate are. An attacker who fully compromises the OS and
defeats biometrics recovers the key without ever knowing the passphrase.

The alternative — store only `K_ver` and re-derive `K_enc` from the
passphrase on every unlock — is strictly stronger: the key would never
exist at rest, and biometrics could only gate a session rather than
replace the passphrase. The cost is ~3 s and a passphrase entry on every
single unlock, which we judged would push users toward a weaker passphrase
or toward abandoning the lock entirely.

Blobs backed up off-device remain passphrase-protected either way; this
tradeoff only concerns data on a device the attacker physically holds.

**Is this the right call for the stated threat model, or is the
convenience not worth it here?**

---

## 8. Anything else

Critique of the threat model itself is as welcome as critique of the
construction — particularly if something important has been placed out of
scope that should not have been.

Concrete pointers to prior art, a standard construction this should have
followed instead, or a known-good reference implementation of an
equivalent scheme would all be valuable.
