import 'package:flutter/foundation.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

// The DeviceContext MODEL now lives in restoflow_auth_identity (shared with
// POS/KDS — RF-153). Re-exported so existing dashboard imports keep working.
export 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show
        DeviceContext,
        DevicePairingRepository,
        PairingFailure,
        PairingFailureKind;

/// Holds the current [DeviceContext] (RF-152 foundation; the model is now the
/// shared `restoflow_auth_identity` one — RF-153).
///
/// ABSENT (null) by DEFAULT — RestoFlow never claims a POS/KDS device is paired.
/// Real pairing (RF-153) uses [adopt] with a backend-verified, scope-matched
/// context; it is cleared on sign-out. Kept as a plain [ChangeNotifier] so it is
/// injectable + unit-testable without a backend.
class DeviceContextController extends ChangeNotifier {
  DeviceContext? _context;

  /// The current device context, or null when no device is paired.
  DeviceContext? get context => _context;

  /// Whether a real device is currently paired (false until a real pairing).
  bool get hasPairedDevice => _context?.isPaired ?? false;

  /// Adopts a backend-verified device [context]. Fail-closed: ignores an unpaired
  /// context or one that does not match the active selected [organizationId] /
  /// [branchId] (never surfaces a device from another scope).
  void adopt(
    DeviceContext context, {
    required String organizationId,
    required String branchId,
  }) {
    if (!context.isPaired) return;
    if (!context.matchesScope(
      organizationId: organizationId,
      branchId: branchId,
    )) {
      return;
    }
    _context = context;
    notifyListeners();
  }

  /// Clears the device context (called on sign-out / unpair). No-op when absent.
  void clear() {
    if (_context == null) return;
    _context = null;
    notifyListeners();
  }
}
