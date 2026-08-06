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
/// [POS-OFFLINE-OPERATIONS-002] Pass A: at BOTH server-verified moments (pair
/// success, restore success) the repository also persists the schema-versioned
/// CACHED PAIRING SCOPE (ids + device-session handle + display fields — never
/// the token) when the secret store carries the [DeviceContextCacheStore]
/// facet. [restoreOutcome] is the TYPED restore seam: a server verdict
/// (`rejected`) clears secret + cached scope; a transport-level failure
/// (`offline`) preserves both and — for the TRANSIENT kind only — surfaces the
/// cached scope as offline evidence. [restore] remains a thin wrapper mapping
/// everything non-restored to null, so existing callers (KDS) are unchanged.
///
/// Scope is always server-derived; the device supplies only the code (redeem) or the
/// token (restore/unpair). Failures are safe, typed [PairingFailure]s — never a raw
/// provider message or secret.
class SupabaseDevicePairingRepository
    implements DevicePairingRepository, DeviceSessionOutcomeManager {
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
    final context = _contextFrom(raw, deviceId);
    // Pass A: pairing succeeded against the server — durably cache the
    // verified scope (fail-soft: a cache hiccup must never fail a pairing).
    await _writeContextCache(context);
    return Success(context);
  }

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async =>
      switch (await restoreOutcome(expectedDeviceType: expectedDeviceType)) {
        DeviceSessionRestored(:final context) => context,
        // Rejected and offline both fail closed to null, exactly as before.
        DeviceSessionRestoreRejected() || DeviceSessionRestoreOffline() => null,
      };

  @override
  Future<DeviceRestoreOutcome> restoreOutcome({
    String? expectedDeviceType,
  }) async {
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      // A throwing secure-storage read fails closed to the pairing screen
      // (keep the stored secret — it may be readable on a later launch), and
      // is NO offline evidence: no cached scope is surfaced.
      return const DeviceSessionRestoreOffline();
    }
    if (cred == null) {
      // Nothing stored: there is no session to restore. Clear any ORPHANED
      // cached scope (a scope without its secret can never be evidence again).
      await _clearContextCache();
      return const DeviceSessionRestoreRejected();
    }
    final Object? raw;
    try {
      raw = await _transport.invoke('restore_device_session', <String, dynamic>{
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      // Transport-level failure: keep the secret and retry on a later launch.
      // ONLY the TRANSIENT kind is genuine offline evidence that may surface
      // the durable cached scope; auth/server/unknown transport failures stay
      // evidence-free (null cache -> callers fail closed as today).
      if (e.kind == SyncTransportErrorKind.transient) {
        return DeviceSessionRestoreOffline(
          cachedContext: await _readContextCache(
            expectedDeviceId: cred.deviceId,
            expectedDeviceType: expectedDeviceType,
          ),
        );
      }
      return const DeviceSessionRestoreOffline();
    } catch (_) {
      return const DeviceSessionRestoreOffline();
    }
    if (raw is! Map || raw['ok'] != true) {
      // A definitively invalid / revoked session -> clear the stale secret
      // AND the cached scope that was minted alongside it.
      await _store.clear();
      await _clearContextCache();
      return const DeviceSessionRestoreRejected();
    }
    final context = _contextFrom(raw, cred.deviceId);
    if (expectedDeviceType != null &&
        context.deviceType != expectedDeviceType) {
      // A valid session for the WRONG surface (e.g. a KDS token on a POS) must
      // never unlock this app: clear the misplaced LOCAL copy (secret + cached
      // scope) and fail closed. Deliberately NOT revoked server-side — the
      // session may be the live one of the real device of that type.
      await _store.clear();
      await _clearContextCache();
      return const DeviceSessionRestoreRejected();
    }
    // Pass A: the server re-verified the pairing — refresh the cached scope.
    await _writeContextCache(context);
    return DeviceSessionRestored(context);
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
    // Pass A: an unpaired device keeps no offline pairing evidence either.
    await _clearContextCache();
  }

  // ---------------------------------------------------------------------
  // [POS-OFFLINE-OPERATIONS-002] Pass A — the cached pairing scope, written
  // ONLY at server-verified moments and cleared with the secret. All three
  // helpers are no-ops when the injected store lacks the cache facet, and
  // fail-soft: cache trouble may never fail a server-verified pair/restore.
  // ---------------------------------------------------------------------

  Future<void> _writeContextCache(DeviceContext context) async {
    // Typed as Object so the `is` check PROMOTES (the cache facet is not a
    // subtype of the secret-store interface, only co-implemented by stores).
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return;
    try {
      await store.writeCachedContext(context);
    } catch (_) {
      // Fail-soft: the durable cache is an enhancement over the live restore.
    }
  }

  Future<DeviceContext?> _readContextCache({
    required String expectedDeviceId,
    required String? expectedDeviceType,
  }) async {
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return null;
    final DeviceContext? cached;
    try {
      cached = await store.readCachedContext(
        expectedDeviceId: expectedDeviceId,
      );
    } catch (_) {
      return null;
    }
    if (cached == null || !cached.isPaired) return null;
    // The same surface-type guard the live restore enforces: a cached KDS
    // scope must never unlock a POS. Treated as ABSENT (fail closed) — the
    // bytes are not destroyed, and no secret is cleared on a mere cache read.
    if (expectedDeviceType != null && cached.deviceType != expectedDeviceType) {
      return null;
    }
    return cached;
  }

  Future<void> _clearContextCache() async {
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return;
    try {
      await store.clearCachedContext();
    } catch (_) {
      // Fail-soft; a later verified write overwrites whatever remained.
    }
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
    // RF-118: the server rate-limited this caller after too many invalid codes.
    'locked' => PairingFailureKind.lockedOut,
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
