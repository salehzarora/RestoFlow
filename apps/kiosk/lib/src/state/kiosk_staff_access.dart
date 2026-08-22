import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// KIOSK-001-102 §5 — REAL staff access to the kiosk Device Settings.
///
/// The fixture 2468 PIN is a demo/design surface and never a production
/// boundary. In REAL mode the discreet ••• target opens THIS gate instead:
/// the SAME employee PIN system every staff surface uses —
/// `list_device_staff` (token-proven device staff projection) to pick the
/// operator, then `start_pin_session` (RF-123/RF-051) to verify the typed
/// PIN server-side (bcrypt; lockout/rate limits authoritative). The PIN
/// travels only as the RPC's opaque verifier over the authenticated TLS
/// transport — never logged, never stored, never in SharedPreferences. The
/// returned pin-session id is used purely as the unlock proof and is not
/// retained.
class KioskStaffAccess {
  KioskStaffAccess({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _staff = SupabaseDeviceStaffRepository(
         transport: transport,
         secretStore: secretStore,
       );

  final SyncRpcTransport _transport;
  final SupabaseDeviceStaffRepository _staff;

  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>> listStaff() =>
      _staff.listStaff();

  /// Verifies [pin] for [employeeProfileId] against the server. Returns null
  /// on success or a typed [KioskStaffPinError]; the PIN itself is passed
  /// through as the opaque verifier and never surfaces anywhere else.
  Future<KioskStaffPinError?> verifyPin({
    required String deviceSessionId,
    required String employeeProfileId,
    required String pin,
  }) async {
    final result = await PinSessionService(_transport).startPinSession(
      deviceSessionId: deviceSessionId,
      employeeProfileId: employeeProfileId,
      pinVerifier: pin,
    );
    return result.fold(
      (_) => null,
      (failure) => switch (failure) {
        AuthWrongPinFailure() => KioskStaffPinError.wrongPin,
        AuthLockedOrPreconditionFailure() => KioskStaffPinError.locked,
        AuthNetworkFailure() => KioskStaffPinError.network,
        _ => KioskStaffPinError.unknown,
      },
    );
  }
}

enum KioskStaffPinError { wrongPin, locked, network, unknown }

/// Null in demo mode (the fixture PIN sheet stays the demo surface); the
/// real composition root wires the shared-transport implementation.
final kioskStaffAccessProvider = Provider<KioskStaffAccess?>((ref) => null);

/// The paired device context, published by the pairing gate on activation
/// AND restore. Carries the `deviceSessionId` capability handle the real
/// staff gate needs (never the session token itself).
final kioskDeviceContextProvider = StateProvider<DeviceContext?>((ref) => null);
