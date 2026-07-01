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
