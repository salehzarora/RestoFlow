import 'package:restoflow_core/restoflow_core.dart';

/// One staff member a paired device may offer on its PIN pad — the MINIMAL,
/// money-free projection returned by `public.list_device_staff` (name + role +
/// id only; no email, no employee number, no PIN material).
class DeviceStaffMember {
  const DeviceStaffMember({
    required this.employeeProfileId,
    required this.displayName,
    required this.role,
  });

  final String employeeProfileId;
  final String displayName;

  /// The tenant role key (`cashier` / `kitchen_staff` / `manager`).
  final String role;
}

/// A safe device-staff failure (no raw provider text).
enum DeviceStaffFailure {
  /// The stored device session was rejected (revoked/expired) — re-pair.
  invalidSession,

  /// The backend could not be reached (retryable).
  network,

  unknown,
}

/// Lists the branch staff a paired device may offer on its PIN pad (RF-161
/// token-proven: the device proves possession of its stored session token; the
/// backend derives the branch — the device sends no scope).
abstract interface class DeviceStaffRepository {
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>> listStaff();
}
