import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The real, backend-backed [DeviceBranchTaxReader] (RF-117): calls
/// `public.get_device_branch_tax(p_device_id, p_session_token)` through the
/// authenticated (anonymous) anon-key transport.
///
/// TOKEN-PROVEN exactly like [SupabaseDeviceShiftClosePolicyRepository]: the raw
/// device-session token is read from OS-backed secure storage, sent over TLS, and
/// verified by hash server-side (no membership, no service role). The response
/// carries ONLY the branch tax policy (enabled + integer basis-point rate) — no
/// money, no secrets. Any failure (missing credential, transport error, invalid
/// session) resolves to `null` so the POS falls back to [BranchTax.disabled]
/// (tax default-OFF) rather than inventing a rate; the token is never logged.
class SupabaseDeviceBranchTaxRepository implements DeviceBranchTaxReader {
  SupabaseDeviceBranchTaxRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  @override
  Future<BranchTax?> load() async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return null;
    }
    if (cred == null) return null;
    final Object? raw;
    try {
      raw = await _transport.invoke('get_device_branch_tax', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final enabled = raw['tax_enabled'] == true;
    final rateBp = raw['tax_rate_bp'];
    // Integer basis points only — a missing/non-integer rate fails soft to OFF.
    if (rateBp is! int) return null;
    return BranchTax(enabled: enabled, rateBp: rateBp);
  }
}
