import 'package:restoflow_core/restoflow_core.dart';

import 'device_context.dart';

/// A user-safe classification of a device-pairing failure. The UI maps each to a
/// localized message; the raw backend error / any secret is never surfaced.
enum PairingFailureKind {
  /// The pairing code was not accepted (wrong / already redeemed).
  invalidCode,

  /// The pairing code has expired (one-time/short-lived semantics).
  expired,

  /// The code belongs to another organization/branch than the active scope.
  wrongScope,

  /// Too many invalid pairing attempts — temporarily rate-limited (RF-118). A
  /// safe generic signal: it reveals only that the caller is throttled, never
  /// whether a code exists / belongs elsewhere / expired.
  lockedOut,

  /// The caller/device is not permitted to pair here.
  denied,

  /// The backend could not be reached.
  network,

  /// Anything else (unclassified).
  unknown,
}

/// A safe pairing failure (no raw provider text / secret).
class PairingFailure {
  const PairingFailure(this.kind);

  final PairingFailureKind kind;
}

/// Pairs a POS/KDS device to a branch/station using a backend-issued enrollment
/// code, returning a validated [DeviceContext] (RF-153).
///
/// This is the DEVICE side of pairing: the device submits only the [code] (the
/// backend RESOLVES the org/branch/station the code was issued for — the device
/// does not pre-know its scope). Contract:
///  - identity + scope are server-derived/verified; a real implementation calls
///    the RF-112 public device RPCs (`redeem_device_enrollment_code` etc.).
///  - NEVER fabricates a device: a failure yields a [PairingFailure]; a success
///    yields a [DeviceContext] whose [DeviceContext.isPaired] is true and whose
///    org/branch/station come from the backend.
///  - The sensitive device session token is never returned here (it is handled
///    per backend policy; secure persistence is a follow-up — see RF-154).
abstract interface class DevicePairingRepository {
  /// Redeems [code] to pair a device of [deviceType] (`pos`/`kds`). Fails closed
  /// with a safe [PairingFailure] on any rejection.
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  });
}

/// Restores / clears a previously-paired device SESSION (RF-161). Kept separate
/// from [DevicePairingRepository] so the pairing screen (which only redeems a code)
/// is unaffected; the real implementation implements BOTH. A gate can opt into
/// restore-on-launch by checking `repository is DeviceSessionManager`.
///
/// [restore] proves possession of the securely-stored device-session token against
/// the backend and returns the server-validated [DeviceContext], or null when there
/// is no valid stored session (fail-closed — the caller then shows the pairing UI).
/// When [expectedDeviceType] is given (`pos`/`kds`), a restored session for any
/// OTHER device type is rejected (null) and its LOCAL secret is cleared, so a
/// misplaced token can never unlock the wrong surface (a KDS session must never
/// unlock a POS); the session is NOT revoked server-side — it may legitimately
/// belong to the real device of that type.
/// [unpair] revokes the session server-side and clears the stored secret.
abstract interface class DeviceSessionManager {
  Future<DeviceContext?> restore({String? expectedDeviceType});
  Future<void> unpair();
}

/// [POS-OFFLINE-OPERATIONS-002] Pass A — the TYPED outcome of a device-session
/// restore. [DeviceSessionManager.restore] collapses "the server said no" and
/// "the server could not be reached" into one `null`, which forces an offline
/// cold boot to fail closed even when durable pairing evidence exists. This
/// outcome keeps the two apart:
///
///  * [DeviceSessionRestored] — the server re-verified the stored token; the
///    authoritative context is fresh.
///  * [DeviceSessionRestoreRejected] — a SERVER VERDICT (invalid/revoked
///    session, or a valid session of the wrong surface type). The stored
///    secret AND the cached pairing scope have been cleared (fail closed).
///  * [DeviceSessionRestoreOffline] — a TRANSPORT-level failure: nothing was
///    proven either way, so the secret and cached scope are PRESERVED for a
///    later retry. [DeviceSessionRestoreOffline.cachedContext] carries the
///    durable server-verified pairing scope ONLY when the failure was
///    transient (genuine offline evidence) and a valid cached record exists
///    for the stored secret's device id; otherwise it is null and the caller
///    behaves exactly as before (fail closed to the pairing screen).
sealed class DeviceRestoreOutcome {
  const DeviceRestoreOutcome();
}

/// The server re-verified the stored session: [context] is authoritative.
final class DeviceSessionRestored extends DeviceRestoreOutcome {
  const DeviceSessionRestored(this.context);

  final DeviceContext context;
}

/// A server VERDICT rejected the stored session; secret + cached scope are
/// cleared by the repository before this is returned.
final class DeviceSessionRestoreRejected extends DeviceRestoreOutcome {
  const DeviceSessionRestoreRejected();
}

/// The server could not be reached (transport-level failure); stored state is
/// preserved. [cachedContext] is the durable pairing scope when (and only
/// when) the failure was transient offline evidence and a valid cached record
/// matches the stored secret — null otherwise.
final class DeviceSessionRestoreOffline extends DeviceRestoreOutcome {
  const DeviceSessionRestoreOffline({this.cachedContext});

  final DeviceContext? cachedContext;
}

/// A [DeviceSessionManager] that can also report the typed restore outcome
/// (Pass A). Kept as a SEPARATE interface so existing managers/fakes and the
/// KDS surface keep compiling unchanged; gates opt in with an `is` check the
/// same way they already opt into [DeviceSessionManager].
abstract interface class DeviceSessionOutcomeManager
    implements DeviceSessionManager {
  /// Like [DeviceSessionManager.restore], but with the offline/rejected
  /// distinction (and the cached pairing scope on transient offline evidence).
  Future<DeviceRestoreOutcome> restoreOutcome({String? expectedDeviceType});
}
