import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The real, backend-backed device pairing + session manager (RF-161), shared by
/// POS and KDS. It is the DEVICE side of the auth bridge:
///
///  * [pairWithCode] calls `public.redeem_device_pairing(code, deviceType)` through
///    the authenticated (anonymous) anon-key transport (DECISION D-011 — no
///    service-role key). On success it persists the raw device-session token to
///    [DeviceSessionSecretStore] (secure storage) and returns the server-derived
///    [DeviceContext]. The raw token is NEVER returned to the caller or logged.
///  * [restore] re-proves the stored token via `restore_device_session` on launch;
///    a definitively invalid/revoked session clears the stale secret (fail-closed),
///    while a transient/offline error keeps it for a later retry. A session whose
///    server-reported device type does not match [expectedDeviceType] is rejected
///    the same way (local clear only, NO server revoke) so a misplaced token can
///    never unlock the wrong surface.
///  * [unpair] revokes the session via `revoke_device_session` and clears the secret.
///
/// Scope is always server-derived; the device supplies only the code (redeem) or the
/// token (restore/unpair). Failures are safe, typed [PairingFailure]s — never a raw
/// provider message or secret.
class SupabaseDevicePairingRepository
    implements DevicePairingRepository, DeviceSessionManager {
  SupabaseDevicePairingRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    final Object? raw;
    try {
      raw = await _transport.invoke('redeem_device_pairing', <String, dynamic>{
        'p_enrollment_code': code.trim(),
        'p_device_type': deviceType,
      });
    } on SyncTransportException catch (e) {
      return Failure(PairingFailure(_mapTransport(e)));
    } catch (_) {
      return const Failure(PairingFailure(PairingFailureKind.network));
    }
    if (raw is! Map || raw['ok'] != true) {
      return Failure(
        PairingFailure(_mapError(raw is Map ? raw['error']?.toString() : null)),
      );
    }
    final deviceId = (raw['device_id'] ?? '').toString();
    final token = (raw['session_token'] ?? '').toString();
    if (deviceId.isEmpty || token.isEmpty) {
      return const Failure(PairingFailure(PairingFailureKind.unknown));
    }
    // Persist the raw token securely BEFORE returning the paired context.
    await _store.write(
      DeviceSessionCredential(deviceId: deviceId, sessionToken: token),
    );
    return Success(_contextFrom(raw, deviceId));
  }

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      // A throwing secure-storage read fails closed to the pairing screen
      // (keep the stored secret — it may be readable on a later launch).
      return null;
    }
    if (cred == null) return null;
    final Object? raw;
    try {
      raw = await _transport.invoke('restore_device_session', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException {
      // Transient / offline: keep the secret and retry on a later launch.
      return null;
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) {
      // A definitively invalid / revoked session -> clear the stale secret.
      await _store.clear();
      return null;
    }
    final context = _contextFrom(raw, cred.deviceId);
    if (expectedDeviceType != null &&
        context.deviceType != expectedDeviceType) {
      // A valid session for the WRONG surface (e.g. a KDS token on a POS) must
      // never unlock this app: clear the misplaced LOCAL copy and fail closed.
      // Deliberately NOT revoked server-side — the session may be the live one
      // of the real device of that type.
      await _store.clear();
      return null;
    }
    return context;
  }

  @override
  Future<void> unpair() async {
    final cred = await _store.read();
    if (cred != null) {
      try {
        await _transport.invoke('revoke_device_session', <String, dynamic>{
          'p_device_id': cred.deviceId,
          'p_session_token': cred.sessionToken,
        });
      } catch (_) {
        // Best-effort server revoke; the local secret is cleared regardless.
      }
    }
    await _store.clear();
  }

  DeviceContext _contextFrom(Map<dynamic, dynamic> raw, String deviceId) =>
      DeviceContext(
        organizationId: (raw['organization_id'] ?? '').toString(),
        branchId: (raw['branch_id'] ?? '').toString(),
        restaurantId: raw['restaurant_id']?.toString(),
        deviceId: deviceId,
        deviceType: raw['device_type']?.toString(),
        // The server-minted session HANDLE (never the token): held in memory
        // only, re-derived via restore each launch, consumed by
        // start_pin_session (RF-051 p_device_session_id).
        deviceSessionId: raw['device_session_id']?.toString(),
      );

  static PairingFailureKind _mapError(String? error) => switch (error) {
    'invalid_code' => PairingFailureKind.invalidCode,
    'expired' => PairingFailureKind.expired,
    'wrong_type' => PairingFailureKind.wrongScope,
    'invalid_type' => PairingFailureKind.invalidCode,
    'permission_denied' => PairingFailureKind.denied,
    _ => PairingFailureKind.unknown,
  };

  static PairingFailureKind _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => PairingFailureKind.denied,
        SyncTransportErrorKind.transient => PairingFailureKind.network,
        SyncTransportErrorKind.server => PairingFailureKind.unknown,
        SyncTransportErrorKind.unknown => PairingFailureKind.unknown,
      };
}
