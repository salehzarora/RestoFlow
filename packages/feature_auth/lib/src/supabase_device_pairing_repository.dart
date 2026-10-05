import 'dart:async';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// BIZBOT's token-proven device pairing, restore and activity client.
/// Only an explicit invalid_session verdict destroys a credential. Unknown
/// replies block protected work but preserve the credential for recovery.
/// Credential mutations are serialized and generation-bound: an old request
/// cannot clear a newer pairing, even when its response arrives late.
class SupabaseDevicePairingRepository
    implements
        DevicePairingRepository,
        DeviceSessionOutcomeManager,
        DeviceSessionHeartbeatManager {
  SupabaseDevicePairingRepository({
    required SyncRpcTransport transport,
    required DeviceSessionSecretStore secretStore,
  }) : _transport = transport,
       _store = secretStore;

  final SyncRpcTransport _transport;
  final DeviceSessionSecretStore _store;
  final _changes = StreamController<DeviceSessionChange>.broadcast();
  DeviceContext? _activeDevice;
  int _generation = 0;
  bool _protectedBlocked = false;
  String? _expectedDeviceType;
  Future<void> _mutations = Future<void>.value();

  @override
  DeviceContext? get activeDevice => _activeDevice;
  @override
  Stream<DeviceSessionChange> get sessionChanges => _changes.stream;

  void _publish(
    DeviceContext? context, {
    bool invalidSession = false,
    bool unavailable = false,
  }) {
    _activeDevice = context;
    _changes.add(
      DeviceSessionChange(
        context,
        invalidSession: invalidSession,
        unavailable: unavailable,
        expectedDeviceType: _expectedDeviceType,
      ),
    );
  }

  void _block() {
    _protectedBlocked = true;
    if (_transport case final DeviceSessionGuardedTransport guarded)
      guarded.block();
  }

  void _allow() {
    _protectedBlocked = false;
    if (_transport case final DeviceSessionGuardedTransport guarded)
      guarded.allow();
  }

  Future<bool> _mutate(int generation, Future<void> Function() action) {
    final next = _mutations.then((_) async {
      if (generation != _generation) return false;
      await action();
      return generation == _generation;
    });
    _mutations = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    final generation = ++_generation;
    _expectedDeviceType = deviceType;
    _block();
    _publish(null);
    final Object? raw;
    try {
      raw = await _transport.invoke('redeem_device_pairing', {
        'p_enrollment_code': code.trim(),
        'p_device_type': deviceType,
      });
    } on SyncTransportException catch (e) {
      return Failure(PairingFailure(_mapTransport(e)));
    } catch (_) {
      return const Failure(PairingFailure(PairingFailureKind.network));
    }
    if (generation != _generation) {
      return const Failure(PairingFailure(PairingFailureKind.unknown));
    }
    if (raw is! Map || raw['ok'] != true) {
      return Failure(
        PairingFailure(_mapError(raw is Map ? raw['error']?.toString() : null)),
      );
    }
    final deviceId = _string(raw['device_id']);
    final token = _string(raw['session_token']);
    final context = deviceId == null ? null : _contextFrom(raw, deviceId);
    if (token == null || context == null || context.deviceType != deviceType) {
      return const Failure(PairingFailure(PairingFailureKind.unknown));
    }
    final written = await _mutate(generation, () async {
      await _store.write(
        DeviceSessionCredential(deviceId: deviceId!, sessionToken: token),
      );
      await _writeContextCache(context);
    });
    if (!written)
      return const Failure(PairingFailure(PairingFailureKind.unknown));
    _allow();
    _publish(context);
    return Success(context);
  }

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async =>
      switch (await restoreOutcome(expectedDeviceType: expectedDeviceType)) {
        DeviceSessionRestored(:final context) => context,
        _ => null,
      };

  @override
  Future<DeviceRestoreOutcome> restoreOutcome({
    String? expectedDeviceType,
  }) async {
    _expectedDeviceType = expectedDeviceType;
    final generation = ++_generation;
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      return _unavailable(generation);
    }
    if (generation != _generation)
      return const DeviceSessionRestoreUnavailable();
    if (cred == null) {
      _block();
      _publish(null);
      await _mutate(generation, _clearContextCache);
      return const DeviceSessionRestoreRejected();
    }
    final Object? raw;
    try {
      raw = await _transport.invoke('restore_device_session', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      if (generation != _generation)
        return const DeviceSessionRestoreUnavailable();
      if (e.kind == SyncTransportErrorKind.transient) {
        if (_protectedBlocked) return _unavailable(generation);
        final cached = await _readContextCache(
          expectedDeviceId: cred.deviceId,
          expectedDeviceType: expectedDeviceType,
        );
        if (generation != _generation)
          return const DeviceSessionRestoreUnavailable();
        if (cached != null) _publish(cached);
        return DeviceSessionRestoreOffline(cachedContext: cached);
      }
      return _unavailable(generation);
    } catch (_) {
      return _unavailable(generation);
    }
    if (generation != _generation)
      return const DeviceSessionRestoreUnavailable();
    if (_invalidSession(raw)) {
      if (!await _reject(generation))
        return const DeviceSessionRestoreUnavailable();
      return DeviceSessionRestoreRejected(reason: _reason(raw));
    }
    final context = raw is Map && raw['ok'] == true
        ? _contextFrom(raw, cred.deviceId)
        : null;
    if (context == null ||
        (expectedDeviceType != null &&
            context.deviceType != expectedDeviceType)) {
      return _unavailable(generation);
    }
    if (!await _mutate(generation, () => _writeContextCache(context))) {
      return const DeviceSessionRestoreUnavailable();
    }
    _allow();
    _publish(context);
    return DeviceSessionRestored(context);
  }

  DeviceSessionRestoreUnavailable _unavailable(int generation) {
    if (generation == _generation) {
      _block();
      _publish(null, unavailable: true);
    }
    return const DeviceSessionRestoreUnavailable();
  }

  @override
  Future<DeviceHeartbeatResult> heartbeat() async {
    final generation = _generation;
    final context = _activeDevice;
    if (context == null) return DeviceHeartbeatResult.superseded;
    final DeviceSessionCredential? cred;
    try {
      cred = await _store.read();
    } catch (_) {
      if (generation != _generation) return DeviceHeartbeatResult.superseded;
      _block();
      return DeviceHeartbeatResult.unavailable;
    }
    if (generation != _generation) return DeviceHeartbeatResult.superseded;
    if (cred == null || cred.deviceId != context.deviceId) {
      _block();
      return DeviceHeartbeatResult.unavailable;
    }
    final Object? raw;
    try {
      raw = await _transport.invoke('heartbeat_device_session', {
        'p_device_id': cred.deviceId,
        'p_session_token': cred.sessionToken,
      });
    } on SyncTransportException catch (e) {
      if (generation != _generation) return DeviceHeartbeatResult.superseded;
      // PostgREST schema-cache miss and PostgreSQL undefined_function:
      // additive deployment, not a revoked device. Retry at the next cadence.
      if (e.code == 'PGRST202' || e.code == '42883') {
        return _protectedBlocked
            ? DeviceHeartbeatResult.unavailable
            : DeviceHeartbeatResult.unsupported;
      }
      if (e.kind == SyncTransportErrorKind.transient)
        return DeviceHeartbeatResult.offline;
      _block();
      return DeviceHeartbeatResult.unavailable;
    } catch (_) {
      if (generation != _generation) return DeviceHeartbeatResult.superseded;
      _block();
      return DeviceHeartbeatResult.unavailable;
    }
    if (generation != _generation) return DeviceHeartbeatResult.superseded;
    if (_invalidSession(raw)) {
      return await _reject(generation)
          ? DeviceHeartbeatResult.invalidSession
          : DeviceHeartbeatResult.superseded;
    }
    final returned = raw is Map && raw['ok'] == true
        ? _contextFrom(raw, cred.deviceId)
        : null;
    if (returned == null ||
        returned.deviceSessionId != context.deviceSessionId ||
        returned.organizationId != context.organizationId ||
        returned.restaurantId != context.restaurantId ||
        returned.branchId != context.branchId ||
        returned.deviceType != context.deviceType) {
      _block();
      return DeviceHeartbeatResult.unavailable;
    }
    _allow();
    return DeviceHeartbeatResult.active;
  }

  Future<bool> _reject(int generation) async {
    if (generation != _generation) return false;
    _block();
    if (await _mutate(generation, () async {
      await _store.clear();
      await _clearContextCache();
    })) {
      _publish(null, invalidSession: true);
      return true;
    }
    return false;
  }

  @override
  Future<void> unpair() async {
    final generation = ++_generation;
    _block();
    _publish(null);
    final cred = await _store.read();
    if (generation != _generation) return;
    if (cred != null) {
      try {
        await _transport.invoke('revoke_device_session', {
          'p_device_id': cred.deviceId,
          'p_session_token': cred.sessionToken,
        });
      } catch (_) {
        // Explicit local unpair remains available offline.
      }
    }
    await _mutate(generation, () async {
      await _store.clear();
      await _clearContextCache();
    });
  }

  Future<void> _writeContextCache(DeviceContext context) async {
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return;
    try {
      await store.writeCachedContext(context);
    } catch (_) {}
  }

  Future<DeviceContext?> _readContextCache({
    required String expectedDeviceId,
    required String? expectedDeviceType,
  }) async {
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return null;
    try {
      final cached = await store.readCachedContext(
        expectedDeviceId: expectedDeviceId,
      );
      if (cached == null ||
          !cached.isPaired ||
          (expectedDeviceType != null &&
              cached.deviceType != expectedDeviceType))
        return null;
      return cached;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearContextCache() async {
    final Object store = _store;
    if (store is! DeviceContextCacheStore) return;
    try {
      await store.clearCachedContext();
    } catch (_) {}
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static DeviceContext? _contextFrom(Map raw, String deviceId) {
    final org = _string(raw['organization_id']);
    final restaurant = _string(raw['restaurant_id']);
    final branch = _string(raw['branch_id']);
    final session = _string(raw['device_session_id']);
    final type = _string(raw['device_type']);
    if (org == null ||
        restaurant == null ||
        branch == null ||
        session == null ||
        raw['device_id'] != deviceId ||
        !const {'pos', 'kds', 'kiosk'}.contains(type))
      return null;
    return DeviceContext(
      organizationId: org,
      branchId: branch,
      restaurantId: restaurant,
      deviceId: deviceId,
      deviceType: type,
      deviceSessionId: session,
    );
  }

  static bool _invalidSession(Object? raw) =>
      raw is Map && raw['ok'] == false && raw['error'] == 'invalid_session';

  static DeviceSessionRejectionReason _reason(Object? raw) =>
      switch (raw is Map ? raw['reason'] : null) {
        'expired' => DeviceSessionRejectionReason.expired,
        'revoked' => DeviceSessionRejectionReason.revoked,
        _ => DeviceSessionRejectionReason.invalid,
      };

  static PairingFailureKind _mapError(String? error) => switch (error) {
    'invalid_code' => PairingFailureKind.invalidCode,
    'expired' => PairingFailureKind.expired,
    'wrong_type' => PairingFailureKind.wrongScope,
    'invalid_type' => PairingFailureKind.invalidCode,
    'locked' => PairingFailureKind.lockedOut,
    'permission_denied' => PairingFailureKind.denied,
    _ => PairingFailureKind.unknown,
  };

  static PairingFailureKind _mapTransport(SyncTransportException e) =>
      switch (e.kind) {
        SyncTransportErrorKind.auth => PairingFailureKind.denied,
        SyncTransportErrorKind.transient => PairingFailureKind.network,
        SyncTransportErrorKind.server ||
        SyncTransportErrorKind.unknown => PairingFailureKind.unknown,
      };
}
