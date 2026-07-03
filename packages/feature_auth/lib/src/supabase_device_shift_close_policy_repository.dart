import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The real, backend-backed [DeviceShiftClosePolicyReader] (RF-113): calls
/// `public.get_device_pos_shift_close_enabled(p_device_id, p_session_token)`
/// through the authenticated (anonymous) anon-key transport.
///
/// TOKEN-PROVEN exactly like [SupabaseDevicePrinterAssignmentsRepository]: the
/// raw device-session token is read from OS-backed secure storage, sent over
/// TLS, and verified by hash server-side (no membership, no service role). The
/// response carries ONLY the boolean policy — no secrets, no money. Any
/// failure (missing credential, transport error, invalid session) resolves to
/// `null` so the POS falls back to the default-true policy rather than hiding a
/// legitimately-available workflow; the token is never logged or surfaced.
class SupabaseDeviceShiftClosePolicyRepository
    implements DeviceShiftClosePolicyReader {
  SupabaseDeviceShiftClosePolicyRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  @override
  Future<bool?> load() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return null;
    }
    if (cred == null) return null;
    final Object? raw;
    try {
      raw = await _transport.invoke(
        'get_device_pos_shift_close_enabled',
        <String, dynamic>{
          'p_device_id': cred.deviceId,
          'p_session_token': cred.sessionToken,
        },
      );
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    return raw['pos_shift_close_enabled'] == true;
  }
}
