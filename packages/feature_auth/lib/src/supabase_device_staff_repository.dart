import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The real, backend-backed [DeviceStaffRepository] (sprint staff/PIN
/// foundation): calls `public.list_device_staff(p_device_id, p_session_token)`
/// through the authenticated (anonymous) anon-key transport.
///
/// TOKEN-PROVEN, like `restore_device_session` (RF-161): the raw device-session
/// token is read from OS-backed secure storage, sent over TLS, and verified by
/// hash server-side. The response is the MINIMAL PIN-pad projection (names +
/// roles + ids — no email, no PIN material, no money). Failures are safe,
/// typed [DeviceStaffFailure]s; the token is never logged or surfaced.
class SupabaseDeviceStaffRepository implements DeviceStaffRepository {
  SupabaseDeviceStaffRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      // A throwing secure-storage read fails closed as an invalid session
      // (the screen shows its retry/re-pair state — never a stuck spinner).
      return const Failure(DeviceStaffFailure.invalidSession);
    }
    if (cred == null) {
      return const Failure(DeviceStaffFailure.invalidSession);
    }
    final Object? raw;
    try {
      raw = await _transport.invoke('list_device_staff', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      return Failure(switch (e.kind) {
        SyncTransportErrorKind.auth => DeviceStaffFailure.invalidSession,
        SyncTransportErrorKind.transient => DeviceStaffFailure.network,
        _ => DeviceStaffFailure.unknown,
      });
    } catch (_) {
      return const Failure(DeviceStaffFailure.network);
    }
    if (raw is! Map || raw['ok'] != true) {
      return const Failure(DeviceStaffFailure.invalidSession);
    }
    return Success([
      for (final row in (raw['staff'] as List?) ?? const [])
        if (row is Map)
          DeviceStaffMember(
            employeeProfileId: (row['employee_profile_id'] ?? '').toString(),
            displayName: (row['display_name'] ?? '').toString(),
            role: (row['role'] ?? '').toString(),
          ),
    ]);
  }
}
