import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_order_inbox.dart';
import '../media/background_order_alert_bridge.dart';
import 'online_order_inbox_controller.dart';
import 'pos_offline_state.dart';
import 'pos_session.dart';

class BackgroundOrderAlertState {
  const BackgroundOrderAlertState({
    this.available = false,
    this.enabled = false,
    this.busy = false,
    this.failed = false,
  });
  final bool available;
  final bool enabled;
  final bool busy;
  final bool failed;
}

/// Registration adapter uses the very same authenticated transport/secret store
/// as Inbox. It cannot submit, accept, reject or print an order.
final backgroundOrderAlertRegisterProvider =
    Provider<Future<Map> Function(Map<String, dynamic>)>((ref) {
      final transport = ref.watch(posAuthTransportProvider);
      final session = ref.watch(posSyncSessionProvider);
      final store = ref.watch(onlineOrderInboxSecretStoreProvider);
      var current = true;
      ref.onDispose(() => current = false);
      return (params) async {
        final credential = await store?.read();
        if (!current ||
            transport == null ||
            session == null ||
            credential == null ||
            credential.deviceId != session.deviceId ||
            credential.sessionToken.isEmpty) {
          throw StateError('alert_authority_unavailable');
        }
        final result = await transport.invoke('pos_register_order_alert', {
          ...params,
          'p_device_id': session.deviceId,
          'p_pin_session_id': session.pinSessionId,
          'p_device_session_token': credential.sessionToken,
        });
        if (!current || result is! Map || result['ok'] != true) {
          throw StateError('alert_registration_unavailable');
        }
        return result;
      };
    });

final backgroundOrderAlertEndpointProvider = Provider<String?>((ref) {
  const url = String.fromEnvironment('RESTOFLOW_SUPABASE_URL');
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/'))
    return null;
  return uri.resolve('/functions/v1/pos-order-alert-status').toString();
});

class BackgroundOrderAlerts extends Notifier<BackgroundOrderAlertState> {
  int _generation = 0;
  String? _identity;
  BackgroundOrderAlertBridge? _bridge;
  bool _foreground = true;
  bool _registering = false;
  bool _disposed = false;
  DateTime? _authorityExpiresAt;
  DateTime? _lastRegistrationAttempt;

  @override
  BackgroundOrderAlertState build() {
    final enabledBuild = ref.watch(backgroundOrderAlertsBuildEnabledProvider);
    final previousIdentity = _identity;
    _identity = ref.watch(onlineOrderInboxIdentityProvider);
    if (previousIdentity != _identity && _bridge != null) {
      unawaited(_bridge!.disable());
    }
    _disposed = false;
    final gen = ++_generation;
    _registering = false;
    _authorityExpiresAt = null;
    _lastRegistrationAttempt = null;
    if (!enabledBuild) return const BackgroundOrderAlertState();
    final bridge = ref.watch(backgroundOrderAlertBridgeProvider);
    _bridge = bridge;
    // An identity transition cannot inherit a previous PIN's native authority.
    ref.listen(onlineOrderInboxIdentityProvider, (_, next) {
      if (next != _identity) unawaited(bridge.disable());
    });
    ref.listen(posOfflineModeProvider.select((s) => s.phase), (_, next) {
      if (next != PosOfflinePhase.online) {
        _authorityExpiresAt = null;
        unawaited(bridge.suspend(retainOptIn: true));
      } else if (_foreground) {
        unawaited(_register(_generation));
      }
    });
    ref.listen(onlineOrderInboxControllerProvider, (_, next) {
      if (next.failure == OnlineInboxFailure.invalidSession ||
          next.failure == OnlineInboxFailure.permissionDenied) {
        _authorityExpiresAt = null;
        unawaited(bridge.disable());
      } else {
        _publish(next);
        if (_foreground && next.failure == null)
          unawaited(_register(_generation));
      }
    });
    bridge.setHints(
      tokenChanged: () {
        if (_current(_generation) && _foreground)
          unawaited(_register(_generation, force: true));
      },
      pendingHint: () {
        if (_current(_generation) && _foreground)
          unawaited(
            ref.read(onlineOrderInboxControllerProvider.notifier).refresh(),
          );
      },
    );
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      // Normal Activity closure after pause must retain its bounded native
      // delegation. Explicit logout/unpair revoke at their existing writers;
      // identity changes also revoke above. Foreground teardown fails closed.
      if (_foreground) unawaited(bridge.suspend());
    });
    Future.microtask(() async {
      if (!_current(gen)) {
        await bridge.disable();
        return;
      }
      await _register(gen);
    });
    return const BackgroundOrderAlertState(available: true);
  }

  bool _current(int gen) =>
      !_disposed &&
      gen == _generation &&
      _identity != null &&
      ref.read(onlineOrderInboxIdentityProvider) == _identity;

  bool get _online =>
      ref.read(posOfflineModeProvider).phase == PosOfflinePhase.online;

  Future<void> setEnabled(bool value) async {
    final bridge = _bridge;
    if (bridge == null) return;
    if (!value) {
      final gen = ++_generation;
      _registering = false;
      _authorityExpiresAt = null;
      await bridge.disable();
      if (!_disposed && gen == _generation)
        state = const BackgroundOrderAlertState(available: true);
      return;
    }
    await _register(_generation, force: true, requestPermission: true);
  }

  Future<void> _register(
    int gen, {
    bool force = false,
    bool requestPermission = false,
  }) async {
    if (!_current(gen) || !_foreground || !_online || _registering) return;
    final now = DateTime.now().toUtc();
    if (!force &&
        (_authorityExpiresAt?.isAfter(now.add(const Duration(minutes: 2))) ??
            false))
      return;
    if (!force &&
        _lastRegistrationAttempt != null &&
        now.difference(_lastRegistrationAttempt!) < const Duration(minutes: 1))
      return;
    final bridge = _bridge!;
    _registering = true;
    _lastRegistrationAttempt = now;
    if (requestPermission)
      state = const BackgroundOrderAlertState(available: true, busy: true);
    try {
      final prepared = await bridge.prepare(
        requestPermission: requestPermission,
      );
      if (!_current(gen) || !_foreground || !_online) return;
      if (prepared['available'] != true || prepared['enabled'] != true) {
        state = BackgroundOrderAlertState(
          available: prepared['available'] == true,
        );
        return;
      }
      final endpoint = ref.read(backgroundOrderAlertEndpointProvider);
      if (endpoint == null) throw StateError('alert_endpoint_unavailable');
      final result = await ref.read(backgroundOrderAlertRegisterProvider)({
        'p_installation_id': prepared['installation_id'],
        'p_fcm_token': prepared['fcm_token'],
        'p_status_secret': prepared['status_secret'],
      });
      if (!_current(gen) || !_foreground || !_online) return;
      final deadline = DateTime.tryParse(
        result['authority_expires_at'] as String? ?? '',
      )?.toUtc();
      if (deadline == null || !deadline.isAfter(now))
        throw StateError('alert_authority_expired');
      final bound = await bridge.bind({
        'identity': _identity,
        'generation': prepared['generation'],
        'registration_id': result['registration_id'],
        'endpoint': endpoint,
        'authority_expires_at': deadline.toIso8601String(),
      });
      if (!_current(gen)) return;
      if (!bound) throw StateError('alert_native_binding_refused');
      _authorityExpiresAt = deadline;
      state = const BackgroundOrderAlertState(available: true, enabled: true);
      _publish(ref.read(onlineOrderInboxControllerProvider));
    } catch (_) {
      if (_current(gen)) {
        _authorityExpiresAt = null;
        await bridge.suspend();
        if (_current(gen))
          state = const BackgroundOrderAlertState(
            available: true,
            failed: true,
          );
      }
    } finally {
      if (gen == _generation) _registering = false;
    }
  }

  void _publish(OnlineOrderInboxState inbox) {
    if (!state.enabled ||
        _identity == null ||
        !_online ||
        _authorityExpiresAt == null ||
        !_foreground)
      return;
    final now = ref.read(onlineOrderInboxControllerProvider.notifier).now();
    unawaited(
      _bridge!.pending({
        'identity': _identity,
        'server_time': now.toIso8601String(),
        'requests': [
          for (final r in inbox.requests)
            if (r.status == OnlineOrderStatus.pending && !r.expiredAt(now))
              {'request_id': r.id, 'expires_at': r.expiresAt.toIso8601String()},
        ],
      }),
    );
  }

  void onPaused() {
    _foreground = false;
  }

  void onResume() {
    _foreground = true;
    if (_bridge != null) unawaited(_register(_generation));
  }

  Future<bool> consumeInboxTap() async {
    if (_identity == null || _bridge == null || !_foreground || !_online)
      return false;
    final gen = _generation;
    final tapped = await _bridge!.consumeInboxTap();
    return _current(gen) && tapped;
  }
}

final backgroundOrderAlertsProvider =
    NotifierProvider<BackgroundOrderAlerts, BackgroundOrderAlertState>(
      BackgroundOrderAlerts.new,
    );
