import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_order_inbox.dart';
import '../media/background_order_alert_bridge.dart';
import 'online_order_inbox_controller.dart';
import 'pos_offline_state.dart';
import 'pos_session.dart';

/// Finite, non-sensitive outcomes only. Never retain native exception text,
/// registration payloads, notification tokens or authority credentials here.
enum BackgroundOrderAlertFailure {
  unavailable,
  permissionDenied,
  notificationsDisabled,
  channelUnavailable,
  channelImportanceTooLow,
  channelSoundMissing,
  firebaseUnavailable,
  tokenUnavailable,
  registrationDisabled,
  registrationInvalidSession,
  registrationRejected,
  registrationUncertain,
  bindingFailed,
  cleanupFailed,
}

enum BackgroundOrderAlertRegistrationResult {
  notAttempted,
  confirmed,
  disabled,
  invalidSession,
  rejected,
  unavailable,
  uncertain,
}

/// A redacted activation snapshot. It contains classifications and booleans,
/// never IDs, tokens, secrets, raw responses or platform exception details.
class BackgroundOrderAlertDiagnostics {
  const BackgroundOrderAlertDiagnostics({
    this.permissionAllowed,
    this.notificationsEnabled,
    this.channelPresent,
    this.channelImportanceAllowed,
    this.channelSoundPresent,
    this.firebaseInitialized,
    this.tokenAcquired,
    this.registration = BackgroundOrderAlertRegistrationResult.notAttempted,
    this.bound,
    this.registrationQuarantined = false,
    this.cleanupQuarantined = false,
  });

  factory BackgroundOrderAlertDiagnostics.fromPreparation(Map prepared) {
    final raw = prepared['diagnostics'];
    final values = raw is Map ? raw : const {};
    bool? flag(String key) => values[key] is bool ? values[key] as bool : null;
    return BackgroundOrderAlertDiagnostics(
      permissionAllowed: flag('permission_allowed'),
      notificationsEnabled: flag('notifications_enabled'),
      channelPresent: flag('channel_present'),
      channelImportanceAllowed: flag('channel_importance_allowed'),
      channelSoundPresent: flag('channel_sound_present'),
      firebaseInitialized: flag('firebase_initialized'),
      tokenAcquired: flag('token_acquired'),
    );
  }

  final bool? permissionAllowed;
  final bool? notificationsEnabled;
  final bool? channelPresent;
  final bool? channelImportanceAllowed;
  final bool? channelSoundPresent;
  final bool? firebaseInitialized;
  final bool? tokenAcquired;
  final BackgroundOrderAlertRegistrationResult registration;
  final bool? bound;
  final bool registrationQuarantined;
  final bool cleanupQuarantined;

  BackgroundOrderAlertDiagnostics withResult({
    BackgroundOrderAlertRegistrationResult? registration,
    bool? bound,
    bool? registrationQuarantined,
    bool? cleanupQuarantined,
  }) => BackgroundOrderAlertDiagnostics(
    permissionAllowed: permissionAllowed,
    notificationsEnabled: notificationsEnabled,
    channelPresent: channelPresent,
    channelImportanceAllowed: channelImportanceAllowed,
    channelSoundPresent: channelSoundPresent,
    firebaseInitialized: firebaseInitialized,
    tokenAcquired: tokenAcquired,
    registration: registration ?? this.registration,
    bound: bound ?? this.bound,
    registrationQuarantined:
        registrationQuarantined ?? this.registrationQuarantined,
    cleanupQuarantined: cleanupQuarantined ?? this.cleanupQuarantined,
  );
}

class BackgroundOrderAlertState {
  const BackgroundOrderAlertState({
    this.available = false,
    this.enabled = false,
    this.busy = false,
    this.failed = false,
    this.authorizationExpired = false,
    this.failureReason,
    this.diagnostics = const BackgroundOrderAlertDiagnostics(),
  });
  final bool available;
  final bool enabled;
  final bool busy;
  final bool failed;
  final bool authorizationExpired;
  final BackgroundOrderAlertFailure? failureReason;
  final BackgroundOrderAlertDiagnostics diagnostics;
}

final backgroundOrderAlertClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Registration adapter uses the very same authenticated transport/secret store
/// as Inbox. It cannot submit, accept, reject or print an order.
typedef BackgroundOrderAlertRegistration =
    Future<Map> Function(
      Map<String, dynamic> params, {
      Future<bool> Function()? authorize,
      bool Function()? isCurrent,
    });

class _RegistrationUncertain implements Exception {
  const _RegistrationUncertain();
}

class _AlertFailure implements Exception {
  const _AlertFailure(this.reason);
  final BackgroundOrderAlertFailure reason;
}

BackgroundOrderAlertFailure _preparationFailure(
  Object? reason,
) => switch (reason) {
  'permission_denied' => BackgroundOrderAlertFailure.permissionDenied,
  'notifications_disabled' => BackgroundOrderAlertFailure.notificationsDisabled,
  'channel_missing' => BackgroundOrderAlertFailure.channelUnavailable,
  'channel_importance_low' =>
    BackgroundOrderAlertFailure.channelImportanceTooLow,
  'channel_sound_missing' => BackgroundOrderAlertFailure.channelSoundMissing,
  'firebase_unavailable' => BackgroundOrderAlertFailure.firebaseUnavailable,
  'token_unavailable' => BackgroundOrderAlertFailure.tokenUnavailable,
  _ => BackgroundOrderAlertFailure.unavailable,
};

final backgroundOrderAlertRegisterProvider =
    Provider<BackgroundOrderAlertRegistration>((ref) {
      final transport = ref.watch(posAuthTransportProvider);
      final session = ref.watch(posSyncSessionProvider);
      final store = ref.watch(onlineOrderInboxSecretStoreProvider);
      var current = true;
      ref.onDispose(() => current = false);
      return (params, {authorize, isCurrent}) async {
        final credential = await store?.read();
        if (!current ||
            transport == null ||
            session == null ||
            credential == null ||
            credential.deviceId != session.deviceId ||
            credential.sessionToken.isEmpty) {
          throw StateError('alert_authority_unavailable');
        }
        // Credential reads can outlive OFF, pause or identity replacement.
        // Recheck before handing off to the existing authenticated transport.
        if (authorize != null && !await authorize()) {
          throw StateError('alert_authority_unavailable');
        }
        if (!current || (isCurrent != null && !isCurrent()))
          throw StateError('alert_authority_unavailable');
        Object? result;
        try {
          result = await transport.invoke('pos_register_order_alert', {
            ...params,
            'p_device_id': session.deviceId,
            'p_pin_session_id': session.pinSessionId,
            'p_device_session_token': credential.sessionToken,
          });
        } catch (_) {
          // The SDK timeout does not cancel HTTP. A later upsert for this same
          // installation could overwrite a newer registration. Generic server
          // classifications also include ambiguous gateway failures, so none
          // of these exceptions prove rollback. Never replay automatically.
          throw const _RegistrationUncertain();
        }
        if (!current || result is! Map) {
          throw StateError('alert_registration_unavailable');
        }
        if (result['ok'] != true) {
          // Only documented business classifications escape this boundary.
          // invalid_request is not proof of an installation ownership conflict.
          throw _AlertFailure(switch (result['error']) {
            'disabled' => BackgroundOrderAlertFailure.registrationDisabled,
            'invalid_session' =>
              BackgroundOrderAlertFailure.registrationInvalidSession,
            'invalid_request' =>
              BackgroundOrderAlertFailure.registrationRejected,
            _ => BackgroundOrderAlertFailure.unavailable,
          });
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

// Confirmed consent is memory-only and bounded. It is not a timeout/cancellation
// of the underlying native or HTTP operation, which keeps its serialized lane.
class _EnableIntent {
  _EnableIntent(this.generation, this.identity);
  final int generation;
  final String identity;
  final done = Completer<void>();
  Timer? expiry;
}

class _RegistrationAttempt {
  _RegistrationAttempt(this.generation, this.identity, this.bridge);
  final int generation;
  final String identity;
  final BackgroundOrderAlertBridge bridge;
  final done = Completer<void>();
  bool retainOptInOnExit = false;
}

class BackgroundOrderAlerts extends Notifier<BackgroundOrderAlertState> {
  int _generation = 0;
  String? _identity;
  BackgroundOrderAlertBridge? _bridge;
  bool _foreground = true;
  bool _disposed = false;
  bool _off = false;
  bool _explicitFailure = false;
  bool _buildEnabled = false;
  bool _waitingForNative = false;
  bool _tokenRefreshPending = false;
  // The MethodChannel is process-wide, including across provider replacement.
  // A disposed owner's late cleanup must finish before a new owner prepares.
  static _RegistrationAttempt? _nativeOwner;
  static Future<void>? _revocation;
  static bool _cleanupFailed = false;
  static bool _registrationUncertain = false;
  _RegistrationAttempt? _active;
  _EnableIntent? _intent;
  Completer<void>? _resume;
  DateTime? _authorityExpiresAt;
  DateTime? _lastRegistrationAttempt;
  Timer? _authorityRenewal;

  @override
  BackgroundOrderAlertState build() {
    final enabledBuild = ref.watch(backgroundOrderAlertsBuildEnabledProvider);
    _buildEnabled = enabledBuild;
    final previousIdentity = _identity;
    _identity = ref.watch(onlineOrderInboxIdentityProvider);
    if (previousIdentity != _identity && _bridge != null) {
      unawaited(_revoke(_bridge!));
    }
    _disposed = false;
    final gen = ++_generation;
    // Never release an unfinished native lane on rebuild/identity replacement.
    _finishIntent();
    _wake();
    _off = false;
    _explicitFailure = false;
    _authorityExpiresAt = null;
    _lastRegistrationAttempt = null;
    _authorityRenewal?.cancel();
    _authorityRenewal = null;
    if (!enabledBuild) return const BackgroundOrderAlertState();
    final bridge = ref.watch(backgroundOrderAlertBridgeProvider);
    _bridge = bridge;
    ref.listen(posOfflineModeProvider.select((s) => s.phase), (_, next) {
      if (next != PosOfflinePhase.online) {
        unawaited(_cancel(retainOptIn: _intent == null));
      } else if (_foreground) {
        _kick();
      }
    });
    ref.listen(onlineOrderInboxControllerProvider, (_, next) {
      if (next.failure == OnlineInboxFailure.invalidSession ||
          next.failure == OnlineInboxFailure.permissionDenied) {
        unawaited(_cancel());
      } else {
        _publish(next);
        if (_foreground && next.failure == null) _kick();
      }
    });
    bridge.setHints(
      tokenChanged: () {
        if (!_current(_generation)) return;
        _tokenRefreshPending = true;
        if (_foreground) _kick(force: true);
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
      _active?.retainOptInOnExit = false;
      _generation++;
      _authorityRenewal?.cancel();
      _authorityRenewal = null;
      _finishIntent();
      _wake();
      // Paused, already-bound delegation remains bounded in native code.
      // An unfinished enable must instead be revoked, including late completion.
      if (_active != null) {
        unawaited(_revoke(bridge));
      } else if (_foreground) {
        unawaited(_revoke(bridge, suspend: true));
      }
    });
    Future.microtask(() {
      if (_current(gen)) _kick();
    });
    return const BackgroundOrderAlertState(available: true);
  }

  bool _current(int gen) =>
      !_disposed &&
      _buildEnabled &&
      gen == _generation &&
      _identity != null &&
      ref.read(onlineOrderInboxIdentityProvider) == _identity;

  bool get _online =>
      ref.read(posOfflineModeProvider).phase == PosOfflinePhase.online;

  bool _authorized(int gen) {
    if (!_current(gen) || !_online) return false;
    final failure = ref.read(onlineOrderInboxControllerProvider).failure;
    return failure != OnlineInboxFailure.invalidSession &&
        failure != OnlineInboxFailure.permissionDenied;
  }

  bool _owns(_RegistrationAttempt attempt) =>
      identical(_active, attempt) &&
      _authorized(attempt.generation) &&
      _identity == attempt.identity;

  bool _confirmed(_RegistrationAttempt attempt) =>
      _intent?.generation == attempt.generation &&
      _intent?.identity == attempt.identity;

  void _finishIntent() {
    final intent = _intent;
    _intent = null;
    intent?.expiry?.cancel();
    if (intent != null && !intent.done.isCompleted) intent.done.complete();
  }

  void _wake() {
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) resume.complete();
  }

  // Revocation is serialized too: a newer prepare/bind cannot race old cleanup.
  Future<void> _revoke(
    BackgroundOrderAlertBridge bridge, {
    bool suspend = false,
    bool retainOptIn = false,
  }) {
    final previous = _revocation;
    final work = () async {
      if (previous != null) await previous;
      try {
        if (bridge is BackgroundOrderAlertRevocation) {
          final observed = bridge as BackgroundOrderAlertRevocation;
          if (!await observed.revoke(
            suspend: suspend,
            retainOptIn: retainOptIn,
          ))
            throw StateError('alert_cleanup_unavailable');
        } else if (suspend) {
          await bridge.suspend(retainOptIn: retainOptIn);
        } else {
          await bridge.disable();
        }
        _cleanupFailed = false;
      } catch (_) {
        // Do not start newer native work if cleanup itself is uncertain.
        _cleanupFailed = true;
        _finishIntent();
        if (!_disposed) {
          state = const BackgroundOrderAlertState(
            available: true,
            failed: true,
            failureReason: BackgroundOrderAlertFailure.cleanupFailed,
            diagnostics: BackgroundOrderAlertDiagnostics(
              cleanupQuarantined: true,
            ),
          );
        }
      }
    }();
    _revocation = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_revocation, work)) {
          _revocation = null;
          if (!_disposed && _intent != null) _kick();
        }
      }),
    );
    return work;
  }

  Future<void> _cancel({
    bool failed = false,
    bool retainOptIn = false,
    bool authorizationExpired = false,
  }) {
    _generation++;
    _active?.retainOptInOnExit = retainOptIn;
    _off = !retainOptIn;
    _explicitFailure = failed;
    _authorityExpiresAt = null;
    _authorityRenewal?.cancel();
    _authorityRenewal = null;
    _finishIntent();
    _wake();
    if (!_disposed)
      state = BackgroundOrderAlertState(
        available: _buildEnabled,
        failed: failed,
        authorizationExpired: authorizationExpired,
      );
    final bridge = _bridge;
    return bridge == null
        ? Future.value()
        : _revoke(bridge, suspend: retainOptIn, retainOptIn: retainOptIn);
  }

  int get authorityGeneration => _generation;

  Future<void> setEnabled(bool value) {
    if (!value) return _cancel();
    if (!_buildEnabled) return Future.value();
    if (_bridge == null ||
        !_authorized(_generation) ||
        _cleanupFailed ||
        _registrationUncertain) {
      if (!_disposed && _bridge != null)
        state = BackgroundOrderAlertState(
          available: true,
          failed: true,
          failureReason: _registrationUncertain
              ? BackgroundOrderAlertFailure.registrationUncertain
              : _cleanupFailed
              ? BackgroundOrderAlertFailure.cleanupFailed
              : BackgroundOrderAlertFailure.unavailable,
          diagnostics: BackgroundOrderAlertDiagnostics(
            registrationQuarantined: _registrationUncertain,
            cleanupQuarantined: _cleanupFailed,
          ),
        );
      return Future.value();
    }
    if (state.enabled) return Future.value();
    final existing = _intent;
    if (existing != null) return existing.done.future;
    _off = false;
    _explicitFailure = false;
    final intent = _EnableIntent(_generation, _identity!);
    _intent = intent;
    intent.expiry = Timer(const Duration(minutes: 2), () {
      if (identical(_intent, intent)) unawaited(_cancel(failed: true));
    });
    state = const BackgroundOrderAlertState(available: true, busy: true);
    _kick();
    return intent.done.future;
  }

  void _kick({bool force = false}) {
    if (!_authorized(_generation) ||
        !_foreground ||
        _active != null ||
        _cleanupFailed ||
        _registrationUncertain ||
        _off ||
        _explicitFailure)
      return;
    final wait = _nativeOwner?.done.future ?? _revocation;
    if (wait != null) {
      if (!_waitingForNative) {
        _waitingForNative = true;
        unawaited(
          wait.then((_) {
            _waitingForNative = false;
            if (!_disposed) _kick();
          }),
        );
      }
      return;
    }
    final now = ref.read(backgroundOrderAlertClockProvider)();
    if (_authorityExpiresAt != null && !_authorityExpiresAt!.isAfter(now)) {
      // Notification delegation cannot outlive the employee authority. Keep
      // the opt-in only; the ordinary PIN flow must establish a new identity.
      unawaited(
        _cancel(failed: true, retainOptIn: true, authorizationExpired: true),
      );
      return;
    }
    if (_intent == null && !force) {
      if (_authorityExpiresAt?.isAfter(now.add(const Duration(minutes: 2))) ??
          false)
        return;
      if (_lastRegistrationAttempt != null &&
          now.difference(_lastRegistrationAttempt!) <
              const Duration(minutes: 1))
        return;
    }
    final attempt = _RegistrationAttempt(_generation, _identity!, _bridge!);
    _tokenRefreshPending = false;
    _authorityRenewal?.cancel();
    _authorityRenewal = null;
    _active = attempt;
    _nativeOwner = attempt;
    _lastRegistrationAttempt = now;
    unawaited(_register(attempt));
  }

  Future<bool> _foregroundFor(_RegistrationAttempt attempt) async {
    while (_owns(attempt) && !_foreground) {
      _resume ??= Completer<void>();
      await _resume!.future;
    }
    return _owns(attempt) && _foreground;
  }

  Future<void> _register(_RegistrationAttempt attempt) async {
    final bridge = attempt.bridge;
    var diagnostics = const BackgroundOrderAlertDiagnostics();
    try {
      var explicit = _confirmed(attempt);
      var prepared = await bridge.prepare(requestPermission: explicit);
      if (!await _foregroundFor(attempt)) return;
      // Confirmed Enable may have arrived during passive preparation. Reuse an
      // already-enabled result; otherwise ask once, in the SAME native lane.
      if (!explicit && _confirmed(attempt) && prepared['enabled'] != true) {
        explicit = true;
        // This new SDK lookup starts after any hint already observed during
        // passive preparation, so only later hints need another reconciliation.
        _tokenRefreshPending = false;
        prepared = await bridge.prepare(requestPermission: true);
        if (!await _foregroundFor(attempt)) return;
      }
      if (_tokenRefreshPending) {
        // A token lookup can complete with an older token after onNewToken.
        // Re-read once in this SAME lane before issuing the RPC. A later hint
        // remains queued behind the issued registration; uncertainty still
        // quarantines that lane rather than replaying it.
        _tokenRefreshPending = false;
        prepared = await bridge.prepare();
        if (!await _foregroundFor(attempt)) return;
      }
      diagnostics = BackgroundOrderAlertDiagnostics.fromPreparation(prepared);
      if (prepared['available'] != true || prepared['enabled'] != true) {
        if (_confirmed(attempt)) {
          throw _AlertFailure(_preparationFailure(prepared['failure_reason']));
        }
        state = BackgroundOrderAlertState(
          available: prepared['available'] == true,
          diagnostics: diagnostics,
        );
        return;
      }
      final endpoint = ref.read(backgroundOrderAlertEndpointProvider);
      if (endpoint == null) throw StateError('alert_endpoint_unavailable');
      diagnostics = diagnostics.withResult(
        registration: BackgroundOrderAlertRegistrationResult.unavailable,
      );
      final result = await ref.read(backgroundOrderAlertRegisterProvider)(
        {
          'p_installation_id': prepared['installation_id'],
          'p_fcm_token': prepared['fcm_token'],
          'p_status_secret': prepared['status_secret'],
        },
        authorize: () => _foregroundFor(attempt),
        isCurrent: () => _owns(attempt) && _foreground,
      );
      // Keep the actual result over pause/resume: never replay an issued RPC.
      if (!await _foregroundFor(attempt)) return;
      final rawExpiry = result['authority_expires_at'];
      final deadline = rawExpiry is String
          ? DateTime.tryParse(rawExpiry)?.toUtc()
          : null;
      final registration = result['registration_id'];
      final registrationGeneration = result['generation'];
      if (result['ok'] != true ||
          registration is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
          ).hasMatch(registration) ||
          registrationGeneration is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
          ).hasMatch(registrationGeneration) ||
          deadline == null ||
          !deadline.isAfter(ref.read(backgroundOrderAlertClockProvider)()))
        throw StateError('alert_registration_unavailable');
      diagnostics = diagnostics.withResult(
        registration: BackgroundOrderAlertRegistrationResult.confirmed,
      );
      final bound = await bridge.bind({
        'identity': attempt.identity,
        'generation': prepared['generation'],
        'registration_id': registration,
        'registration_generation': registrationGeneration,
        'endpoint': endpoint,
        'authority_expires_at': deadline.toIso8601String(),
      });
      diagnostics = diagnostics.withResult(bound: bound);
      if (!await _foregroundFor(attempt)) return;
      if (!bound ||
          !deadline.isAfter(ref.read(backgroundOrderAlertClockProvider)()))
        throw const _AlertFailure(BackgroundOrderAlertFailure.bindingFailed);
      _authorityExpiresAt = deadline;
      state = BackgroundOrderAlertState(
        available: true,
        enabled: true,
        diagnostics: diagnostics,
      );
      _finishIntent();
      _publish(ref.read(onlineOrderInboxControllerProvider));
      _armAuthorityRenewal();
    } catch (error) {
      if (error is _RegistrationUncertain) _registrationUncertain = true;
      final failure = error is _RegistrationUncertain
          ? BackgroundOrderAlertFailure.registrationUncertain
          : error is _AlertFailure
          ? error.reason
          : BackgroundOrderAlertFailure.unavailable;
      diagnostics = diagnostics.withResult(
        registration: switch (failure) {
          BackgroundOrderAlertFailure.registrationUncertain =>
            BackgroundOrderAlertRegistrationResult.uncertain,
          BackgroundOrderAlertFailure.registrationDisabled =>
            BackgroundOrderAlertRegistrationResult.disabled,
          BackgroundOrderAlertFailure.registrationInvalidSession =>
            BackgroundOrderAlertRegistrationResult.invalidSession,
          BackgroundOrderAlertFailure.registrationRejected =>
            BackgroundOrderAlertRegistrationResult.rejected,
          _ => diagnostics.registration,
        },
        registrationQuarantined: _registrationUncertain,
      );
      if (_owns(attempt)) {
        _authorityExpiresAt = null;
        _explicitFailure = _confirmed(attempt);
        await _revoke(bridge, suspend: true);
        if (_owns(attempt)) {
          state = BackgroundOrderAlertState(
            available: true,
            failed: true,
            failureReason: _cleanupFailed
                ? BackgroundOrderAlertFailure.cleanupFailed
                : failure,
            diagnostics: diagnostics.withResult(
              cleanupQuarantined: _cleanupFailed,
            ),
          );
          _finishIntent();
        }
      }
    } finally {
      if (!_owns(attempt)) {
        // Android permission/token/bind may finish AFTER OFF. Do not release
        // ownership until late native authority is revoked; no new lane yet.
        final retain =
            attempt.retainOptInOnExit &&
            !_disposed &&
            !_off &&
            _identity == attempt.identity;
        await _revoke(bridge, suspend: retain, retainOptIn: retain);
      }
      if (identical(_active, attempt)) {
        _active = null;
        if (identical(_nativeOwner, attempt)) _nativeOwner = null;
        if (!attempt.done.isCompleted) attempt.done.complete();
        if (!_disposed && _tokenRefreshPending) {
          _kick(force: true);
        } else if (!_disposed && _intent != null) {
          _kick();
        }
      }
    }
  }

  void _armAuthorityRenewal() {
    _authorityRenewal?.cancel();
    _authorityRenewal = null;
    final deadline = _authorityExpiresAt;
    if (!_foreground ||
        !state.enabled ||
        deadline == null ||
        !_authorized(_generation) ||
        _off ||
        _explicitFailure)
      return;
    final now = ref.read(backgroundOrderAlertClockProvider)();
    var renewalAt = deadline.subtract(const Duration(minutes: 2));
    final throttled = _lastRegistrationAttempt?.add(const Duration(minutes: 1));
    if (throttled != null && renewalAt.isBefore(throttled))
      renewalAt = throttled;
    if (renewalAt.isAfter(deadline)) renewalAt = deadline;
    final generation = _generation;
    _authorityRenewal = Timer(
      renewalAt.isAfter(now) ? renewalAt.difference(now) : Duration.zero,
      () {
        _authorityRenewal = null;
        if (_current(generation) && _foreground) _kick();
      },
    );
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
    _authorityRenewal?.cancel();
    _authorityRenewal = null;
  }

  void onResume() {
    _foreground = true;
    _wake();
    if (_bridge != null) _kick(force: _tokenRefreshPending);
    _armAuthorityRenewal();
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
