# restoflow_data_local

Local **Drift/SQLite** store for RestoFlow: the offline-first sync foundation
(outbox + processed-pull/inbox ledger + idempotency + sync-operation state +
tombstone/revision contract; RF-018) and the **fail-closed data-at-rest opening
policy** (RF-021). Pure Dart. Business entity tables land in RF-030+.

## Data-at-rest protection (RF-021)

> **Status: the abstraction + fail-closed policy are implemented now; real
> platform crypto (SQLCipher) + platform secure storage (Keychain/Keystore)
> wiring is DEFERRED until platform targets exist.** The repo currently has no
> native platform folders (`android/ios/windows/macos/linux/web`), so a real
> encrypted backend cannot yet be built or tested; RF-021 does **not** claim an
> encrypted local DB is implemented on any platform.

`ProtectedLocalDatabaseFactory` reuses the existing `LocalDatabase(QueryExecutor)`
seam (no Drift schema change, no regeneration of the committed generated code).
Normal open and first-time key creation are **separate** operations:

- **Normal open — `openPersistent(...)` ALWAYS fails closed.** It opens a
  persistent (on-disk) database **only** when (a) platform secure storage is
  available, (b) a real `DatabaseEncryptionStrategy` is available, and (c) an
  **already-provisioned** data-at-rest key exists in `SecureKeyStore`
  (`packages/core`). It has **no key generator** and **never creates, recreates,
  or rotates key material**. A **missing, wiped, or revoked** key →
  `SecretNotFoundException`; a corrupted key → `SecretCorruptedException`;
  storage/encryption unavailable → `SecureStorageUnavailableException` /
  `DataAtRestProtectionUnavailableException`. There is **no plaintext fallback**
  and **no silent unencrypted open** — wipe/revocation/missing key never
  silently recreates key material.
- **First-time creation — `provisionPersistentKey(...)` is explicit.** It is the
  ONLY path that generates a key, is never called by `openPersistent`, requires
  secure storage + encryption to be available, stores the generated key **only**
  through `SecureKeyStore`, never opens the DB, and never returns or logs raw key
  material. It **refuses to overwrite an existing key**
  (`SecretAlreadyExistsException`); rotation/recovery is a separate, explicit
  flow (deferred).
- The default `UnavailableEncryptionStrategy` has no real backend, so both
  `openPersistent` and `provisionPersistentKey` fail closed **today** — by
  design, until platform crypto is wired.
- `NativeDatabase.memory()` is **test-only / non-persistent** and is never used
  for real on-disk tenant data.

### Key lifecycle

1. **Create** — the local DB key is generated (CSPRNG) **only** through the
   explicit `provisionPersistentKey(...)` flow (never during a normal open),
   **only** after a paired/trusted device context, and **only** when platform
   secure storage + encryption are available. Provisioning refuses to overwrite
   an existing key. The key is never printed or logged.
2. **Store** — the key is stored **only** in platform secure storage, addressed
   by a `SecretRef` (`ref:local-db-key`). Never in plaintext files, shared
   preferences, env files, or logs.
3. **Rotate** — future SQLCipher `rekey` + secure-store replace, triggered by
   suspected exposure, device/personnel change, scheduled cadence, or a
   revocation event (docs/OPERATIONS_AND_RECOVERY.md §3.3). Implementation is
   deferred until platform crypto exists.
4. **Revoke** — secrets are wiped (`SecureKeyStore.wipeAll()`); the persistent DB
   becomes unreadable (crypto-erase); the device must re-pair/recover. The server
   remains the source of truth for revocation and rejects post-revocation
   operations on reconnect (RISK R-007; docs/OFFLINE_SYNC_SPEC.md §12).

### Platform support matrix

| Platform | Secure storage | At-rest DB encryption | Status |
|---|---|---|---|
| Android / iOS (later) | Keystore / Keychain | SQLCipher | Supported **when targets exist** |
| Desktop: Windows/macOS/Linux (later) | DPAPI / Keychain / libsecret | SQLCipher | Supported **with caveats**, when targets exist |
| Web | none equivalent | none (no true at-rest encryption) | **Limited/unsupported** unless explicitly approved |
| **Current repo (no native targets)** | not buildable yet | not buildable yet | **Real wiring deferred**; abstraction + fail-closed only |

The platform-backed `SecureKeyStore` adapter (`flutter_secure_storage`) is a
Flutter plugin and therefore lives outside pure-Dart `core` — its home is
`packages/auth_identity`, added once platform targets exist (deferred for RF-021
to avoid plugin/CI complexity with no testable platform).
