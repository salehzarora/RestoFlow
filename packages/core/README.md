# restoflow_core

Cross-cutting **foundations** shared across the RestoFlow monorepo. Pure Dart -
**no Flutter, no IO, no POS/restaurant business rules**.

Owns (per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3): Result/error
types, environment selection, and logging hooks.

## Public surface (RF-011 scaffold)
- `Result<S, F>` (`Success` / `Failure`) - neutral functional result type.
- `AppEnvironment` - `dev` / `staging` / `prod` selector (carries **no**
  URLs/keys/secrets; values are injected at runtime - DECISION D-011).
- `RestoLogger` + `LogLevel` - logging hook interface (implementations must
  redact secrets and log money only as integer minor units).

## Security primitives (RF-021) — pure Dart

Pure-Dart, Flutter-free primitives for handling secret material and the
fail-closed local data-at-rest policy (docs/SECURITY_AND_THREAT_MODEL.md §12):

- `SecretValue` — opaque wrapper for raw secret material. `toString()` is
  redacted (`SecretValue(***redacted***)`); equality/`hashCode` are
  identity-based (never compare or expose the value). Raw access is ONLY via the
  explicit, grep-auditable `revealForStorageBoundary()` /
  `revealForCryptoBoundary()` — there is no implicit getter/serializer. Rejects
  empty / whitespace-only values.
- `SecretRef` — a **safe-to-log** opaque reference (e.g. `ref:local-db-key`).
  Holds no secret material; rejects empty refs and refs that look like raw
  secrets.
- `SecureKeyStore` — the platform-agnostic contract for storing device/session
  secrets and the data-at-rest key (`isAvailable` / `read` / `write` / `delete`
  / `wipeAll`). Secrets cross it only as `SecretValue`, keyed by `SecretRef`.
- Fail-closed errors: `SecureStorageUnavailableException`,
  `SecretNotFoundException`, `SecretCorruptedException`,
  `SecretAlreadyExistsException`, `DataAtRestProtectionUnavailableException`.
  **Messages never contain raw secret material** (only `SecretRef`s).
- `package:restoflow_core/testing.dart` exposes `InMemorySecureKeyStore`, a
  TEST-ONLY fake that simulates unavailable / missing / corrupted / wiped.

The real platform-backed `SecureKeyStore` adapter (iOS Keychain / Android
Keystore via `flutter_secure_storage`) is **deferred** until platform targets
exist — see `packages/data_local`'s README. **No Flutter / plugin dependency is
added to `core`.**

## Dependency direction
`core` depends on nothing app-specific; other packages may depend on `core`.

## Deferred
Concrete utilities are added as later tickets need them. **No business logic,
no money type** (the integer minor-unit money type lives in `packages/money`,
ticket RF-036 - DECISION D-007).
