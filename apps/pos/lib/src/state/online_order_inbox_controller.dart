import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../data/online_order_inbox.dart';
import '../media/online_order_alert_audio.dart';
import '../spool/online_order_print_hooks.dart';
export '../spool/online_order_print_hooks.dart'
    show onlineInboxAcceptedPrintProvider, onlineInboxCancelPrintProvider;
import 'order_sync_controller.dart';
import 'pos_device_context.dart';
import 'pos_offline_state.dart';
import 'pos_session.dart';
import 'pos_sync_scope_provider.dart';

/// Includes the pairing SESSION as well as every tenant and PIN boundary.
final onlineOrderInboxIdentityProvider = Provider<String?>((ref) {
  final scope = ref.watch(posSyncScopeProvider);
  final pin = ref.watch(posSyncSessionProvider);
  final device = ref.watch(posDeviceContextProvider);
  if (scope == null ||
      pin == null ||
      device == null ||
      !device.isPaired ||
      device.deviceType != 'pos' ||
      device.deviceId != pin.deviceId ||
      device.deviceSessionId == null) {
    return null;
  }
  return '${scope.key}|${device.deviceSessionId}|${pin.pinSessionId}';
});

class OnlineInboxIntent {
  const OnlineInboxIntent({
    required this.requestId,
    required this.decisionId,
    required this.decision,
    this.reason,
  });
  final String requestId;
  final String decisionId;
  final OnlineOrderDecision decision;
  final String? reason;
}

class OnlineOrderInboxState {
  const OnlineOrderInboxState({
    this.requests = const [],
    this.loading = false,
    this.deciding = false,
    this.uncertain = false,
    this.failure,
    this.intent,
    this.serverTime,
    this.hasMore = false,
    this.cursor,
    this.printOutcome,
  });
  final List<OnlineOrderRequest> requests;
  final bool loading;
  final bool deciding;
  final bool uncertain;
  final OnlineInboxFailure? failure;
  final OnlineInboxIntent? intent;
  final DateTime? serverTime;
  final bool hasMore;
  final OnlineInboxCursor? cursor;
  final WebOrderPrintOutcome? printOutcome;
  int pendingCountAt(DateTime now) => requests
      .where((r) => r.status == OnlineOrderStatus.pending && !r.expiredAt(now))
      .length;

  OnlineOrderInboxState copyWith({
    List<OnlineOrderRequest>? requests,
    bool? loading,
    bool? deciding,
    bool? uncertain,
    OnlineInboxFailure? failure,
    bool clearFailure = false,
    OnlineInboxIntent? intent,
    bool clearIntent = false,
    DateTime? serverTime,
    bool? hasMore,
    OnlineInboxCursor? cursor,
    bool clearCursor = false,
    WebOrderPrintOutcome? printOutcome,
  }) => OnlineOrderInboxState(
    requests: requests ?? this.requests,
    loading: loading ?? this.loading,
    deciding: deciding ?? this.deciding,
    uncertain: uncertain ?? this.uncertain,
    failure: clearFailure ? null : (failure ?? this.failure),
    intent: clearIntent ? null : (intent ?? this.intent),
    serverTime: serverTime ?? this.serverTime,
    hasMore: hasMore ?? this.hasMore,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    printOutcome: printOutcome ?? this.printOutcome,
  );
}

/// A singleton, memory-only coordinator. It never enqueues an order or a print.
/// An ambiguous decision HOLDS its intent until a locking targeted lookup has
/// resolved it. Only that same decision identity/payload can then be retried.
class OnlineOrderInboxController extends Notifier<OnlineOrderInboxState> {
  static const defaultPollInterval = Duration(seconds: 15);
  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  int _revision = 0;
  String? _identity;
  Future<void>? _fetching;
  DateTime? _serverSampleAt;
  DateTime? _serverTime;
  bool _securityBlocked = false;
  Timer? _alertTimer;
  DateTime? _alertWakeAt;
  DateTime? _nextAlertAt;
  final _alertedRequestIds = <String>{};
  final _confirmedExpiredAlertIds = <String>{};
  OnlineOrderAlertAudio? _audio;
  bool _alertsActive = false;
  bool _audioBusy = false;

  @override
  OnlineOrderInboxState build() {
    _identity = ref.watch(onlineOrderInboxIdentityProvider);
    ref.listen(onlineOrderInboxIdentityProvider, (_, next) {
      if (next == _identity) return;
      _generation++;
      _timer?.cancel();
      _timer = null;
      _stopAlerts();
    });
    ref.watch(onlineOrderInboxRepositoryProvider);
    _stopAlerts();
    _audio = ref.watch(onlineOrderAlertAudioProvider);
    ref.watch(onlineOrderInboxAlertIntervalProvider);
    ref.listen(posOfflineModeProvider.select((value) => value.phase), (_, _) {
      _syncAlerts();
    });
    // Presentation follows confirmed controller state, including locking
    // recovery. A local Accept/Reject tap never removes a pending alert.
    listenSelf((_, _) => _syncAlerts());
    _generation++;
    _revision++;
    _disposed = false;
    _fetching = null;
    _serverSampleAt = null;
    _serverTime = null;
    _securityBlocked = false;
    _confirmedExpiredAlertIds.clear();
    _timer?.cancel();
    _timer = null;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _stopAlerts();
    });
    final gen = _generation;
    Future.microtask(() {
      if (!_current(gen)) return;
      _armTimer();
      unawaited(refresh());
    });
    // Every PIN/device/pairing/scope transition discards ALL sensitive state.
    return const OnlineOrderInboxState();
  }

  bool _current(int gen) =>
      !_disposed &&
      gen == _generation &&
      _identity != null &&
      ref.read(onlineOrderInboxIdentityProvider) == _identity;

  DateTime now() {
    final local = ref.read(posSyncClockProvider)().toUtc();
    final sampled = _serverSampleAt;
    return sampled == null || _serverTime == null
        ? local
        : _serverTime!.add(local.difference(sampled));
  }

  void _sample(DateTime serverTime) {
    _serverTime = serverTime;
    _serverSampleAt = ref.read(posSyncClockProvider)().toUtc();
  }

  void onResume() {
    _foreground = true;
    _armTimer();
    _syncAlerts();
    unawaited(refresh());
  }

  void onPaused() {
    _foreground = false;
    _timer?.cancel();
    _timer = null;
    _stopAlerts();
    _cancelPendingPrint();
  }

  void _cancelPendingPrint() {
    try {
      ref.read(onlineInboxCancelPrintProvider)();
    } catch (_) {
      /* Disposal already removes authority. */
    }
  }

  void _stopAlerts() {
    _alertTimer?.cancel();
    _alertTimer = null;
    _alertWakeAt = null;
    _nextAlertAt = null;
    _alertedRequestIds.clear();
    final wasActive = _alertsActive;
    _alertsActive = false;
    final audio = _audio;
    if (audio != null && (wasActive || _audioBusy)) {
      unawaited(_ignoreAudioFailure(audio.stop));
    }
  }

  static Future<void> _ignoreAudioFailure(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      // Notification availability cannot affect an order or its decision.
    }
  }

  Future<void> _playAlert() async {
    final audio = _audio;
    if (audio == null || _audioBusy || !_alertsActive) return;
    _audioBusy = true;
    try {
      await _ignoreAudioFailure(audio.play);
    } finally {
      _audioBusy = false;
    }
  }

  /// One foreground-only sound schedule, owned by the existing poll/identity
  /// coordinator. Its next wake is the earlier of the cadence and expiry, so
  /// the final pending request stops immediately at its server-time deadline
  /// even when a discovery read is slow, failed or awaiting reconciliation.
  void _syncAlerts() {
    if (_disposed || !_foreground || _identity == null || _securityBlocked) {
      _stopAlerts();
      return;
    }
    final interval = ref.read(onlineOrderInboxAlertIntervalProvider);
    if (interval == null ||
        interval <= Duration.zero ||
        ref.read(posOfflineModeProvider).phase != PosOfflinePhase.online ||
        ref.read(onlineOrderInboxIdentityProvider) != _identity) {
      _stopAlerts();
      return;
    }
    final currentTime = now();
    _confirmedExpiredAlertIds.retainAll(state.requests.map((r) => r.id));
    final pending = state.requests
        .where(
          (r) =>
              r.status == OnlineOrderStatus.pending &&
              !_confirmedExpiredAlertIds.contains(r.id) &&
              !r.expiredAt(currentTime),
        )
        .toList();
    if (pending.isEmpty) {
      _stopAlerts();
      return;
    }
    _alertsActive = true;
    final pendingIds = pending.map((r) => r.id).toSet();
    final newArrival = pendingIds.difference(_alertedRequestIds).isNotEmpty;
    _alertedRequestIds
      ..retainAll(pendingIds)
      ..addAll(pendingIds);
    if (newArrival ||
        _nextAlertAt == null ||
        !currentTime.isBefore(_nextAlertAt!)) {
      _nextAlertAt = currentTime.add(interval);
      unawaited(_playAlert());
    }
    final firstExpiry = pending
        .map((r) => r.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final wakeAt = firstExpiry.isBefore(_nextAlertAt!)
        ? firstExpiry
        : _nextAlertAt!;
    if (_alertTimer != null && _alertWakeAt == wakeAt) return;
    _alertTimer?.cancel();
    _alertWakeAt = wakeAt;
    final gen = _generation;
    _alertTimer = Timer(wakeAt.difference(currentTime), () {
      _alertTimer = null;
      _alertWakeAt = null;
      if (!_current(gen)) return;
      // Re-evaluate expiry and update the existing badge/detail clock. This
      // timer never performs another RPC or starts another polling loop.
      state = state.copyWith(serverTime: now());
    });
  }

  void _armTimer() {
    if (_timer != null || !_foreground || _identity == null || _securityBlocked)
      return;
    final interval = ref.read(onlineOrderInboxPollIntervalProvider);
    if (interval == null) return;
    _timer = Timer.periodic(interval, (_) {
      // Expiry/age continue advancing even while an RPC is slow or fails.
      state = state.copyWith(serverTime: now());
      if (state.intent != null && !state.deciding) {
        unawaited(recoverDecision());
      } else {
        unawaited(refresh());
      }
    });
  }

  Future<void> refresh({bool loadMore = false}) {
    if (_fetching != null) return _fetching!;
    final gen = _generation;
    if (!_foreground ||
        !_current(gen) ||
        _securityBlocked ||
        state.intent != null ||
        (loadMore && !state.hasMore)) {
      return Future.value();
    }
    final rev = _revision;
    final cursor = loadMore ? state.cursor : null;
    state = state.copyWith(loading: true, clearFailure: true);
    final run = _fetch(gen, rev, cursor, loadMore);
    _fetching = run;
    return run.whenComplete(() {
      if (identical(_fetching, run)) _fetching = null;
    });
  }

  Future<void> _fetch(
    int gen,
    int rev,
    OnlineInboxCursor? cursor,
    bool loadMore,
  ) async {
    try {
      final page = await ref
          .read(onlineOrderInboxRepositoryProvider)
          .fetch(cursor: cursor);
      if (!_current(gen) || rev != _revision) return;
      if (page.requests.any((r) => r.status != OnlineOrderStatus.pending)) {
        throw const OnlineInboxException(OnlineInboxFailure.malformed);
      }
      _sample(page.serverTime);
      final rows = <String, OnlineOrderRequest>{
        if (loadMore)
          for (final row in state.requests) row.id: row,
        for (final row in page.requests) row.id: row,
      };
      state = state.copyWith(
        requests: List.unmodifiable(rows.values),
        loading: false,
        serverTime: now(),
        hasMore: page.hasMore,
        cursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        clearFailure: true,
      );
      // Reuse discovery's existing cadence for a READ-ONLY local recovery
      // projection; no new polling, claim, server request or print is started.
      // Do not create a presentation-only recovery reader just to invalidate
      // it. Riverpod's debug dependency check eagerly initializes an unread
      // target and schedules deferred work even with no UI observer.
      if (ref.exists(onlineInboxPrintRecoveryProvider)) {
        ref.invalidate(onlineInboxPrintRecoveryProvider);
      }
    } on OnlineInboxException catch (error) {
      if (!_current(gen) || rev != _revision) return;
      _fail(error.failure);
    } catch (_) {
      if (!_current(gen) || rev != _revision) return;
      _fail(OnlineInboxFailure.transport);
    }
  }

  void _fail(OnlineInboxFailure failure) {
    if (failure == OnlineInboxFailure.invalidSession ||
        failure == OnlineInboxFailure.permissionDenied) {
      _securityBlocked = true;
      _cancelPendingPrint();
      _timer?.cancel();
      _timer = null;
      // A terminal authority refusal removes customer data immediately.
      state = OnlineOrderInboxState(failure: failure);
    } else {
      state = state.copyWith(
        loading: false,
        deciding: false,
        failure: failure,
        serverTime: now(),
      );
    }
  }

  Future<void> decide(
    String requestId,
    OnlineOrderDecision decision, {
    String? reason,
  }) async {
    final gen = _generation;
    if (!_current(gen) ||
        !_foreground ||
        _securityBlocked ||
        state.intent != null)
      return;
    if (ref.read(posOfflineModeProvider).phase != PosOfflinePhase.online) {
      _fail(OnlineInboxFailure.transport);
      return;
    }
    final request = state.requests.where((r) => r.id == requestId).firstOrNull;
    if (request == null || request.status != OnlineOrderStatus.pending) return;
    if (request.expiredAt(now())) {
      _fail(OnlineInboxFailure.requestExpired);
      return;
    }
    final trimmedReason = reason?.trim();
    if (decision == OnlineOrderDecision.reject &&
        (trimmedReason == null ||
            trimmedReason.isEmpty ||
            trimmedReason.runes.length > 240 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmedReason))) {
      _fail(OnlineInboxFailure.invalidRequest);
      return;
    }
    final intent = OnlineInboxIntent(
      requestId: requestId,
      decisionId: ref.read(clientIdGeneratorProvider).newId(),
      decision: decision,
      reason: trimmedReason,
    );
    _revision++; // an older list response cannot overwrite this decision
    state = state.copyWith(
      intent: intent,
      deciding: true,
      loading: false,
      uncertain: false,
      clearFailure: true,
    );
    await _send(gen, intent, reconcileOnFailure: true);
  }

  Future<void> _send(
    int gen,
    OnlineInboxIntent intent, {
    required bool reconcileOnFailure,
  }) async {
    try {
      final result = await ref
          .read(onlineOrderInboxRepositoryProvider)
          .decide(
            requestId: intent.requestId,
            decisionId: intent.decisionId,
            decision: intent.decision,
            reason: intent.reason,
          );
      if (!_current(gen)) return;
      final expected = intent.decision == OnlineOrderDecision.accept
          ? OnlineOrderStatus.accepted
          : OnlineOrderStatus.rejected;
      if (result.requestId != intent.requestId || result.status != expected) {
        throw const OnlineInboxException(OnlineInboxFailure.malformed);
      }
      await _finish(
        gen,
        intent.requestId,
        result.status,
        result.canonicalOrderId,
      );
    } on OnlineInboxException catch (error) {
      if (!_current(gen)) return;
      if (error.failure == OnlineInboxFailure.transport ||
          error.failure == OnlineInboxFailure.malformed ||
          error.failure == OnlineInboxFailure.decisionConflict) {
        state = state.copyWith(uncertain: true);
        if (reconcileOnFailure) {
          await _reconcile(gen, intent);
        } else {
          state = state.copyWith(
            deciding: false,
            uncertain: true,
            failure: error.failure,
          );
        }
      } else {
        if (error.failure == OnlineInboxFailure.requestExpired) {
          // A trusted expiry refusal is already terminal for this request,
          // even if the last sampled clock has not reached its deadline yet.
          // Suppress only its presentation alert; decision recovery is unchanged.
          _confirmedExpiredAlertIds.add(intent.requestId);
        }
        state = state.copyWith(
          clearIntent: true,
          deciding: false,
          uncertain: false,
        );
        _fail(error.failure);
      }
    } catch (_) {
      if (!_current(gen)) return;
      state = state.copyWith(uncertain: true);
      if (reconcileOnFailure) {
        await _reconcile(gen, intent);
      } else {
        state = state.copyWith(
          deciding: false,
          failure: OnlineInboxFailure.transport,
        );
      }
    }
  }

  Future<void> recoverDecision() async {
    final intent = state.intent;
    final gen = _generation;
    if (intent == null ||
        state.deciding ||
        !_foreground ||
        !_current(gen) ||
        _securityBlocked)
      return;
    state = state.copyWith(deciding: true, uncertain: true, clearFailure: true);
    await _reconcile(gen, intent);
  }

  Future<void> _reconcile(int gen, OnlineInboxIntent intent) async {
    try {
      // Server takes a request lock and waits for an earlier decision. A plain
      // discovery poll is NEVER evidence that an ambiguous write did not land.
      final page = await ref
          .read(onlineOrderInboxRepositoryProvider)
          .fetch(requestId: intent.requestId);
      if (!_current(gen)) return;
      if (page.requests.length != 1 ||
          page.requests.single.id != intent.requestId) {
        throw const OnlineInboxException(OnlineInboxFailure.malformed);
      }
      _sample(page.serverTime);
      final request = page.requests.single;
      if (request.status == OnlineOrderStatus.pending &&
          !request.expiredAt(now())) {
        // Lookup has confirmed pending after the request lock. Retry only the
        // ORIGINAL id, action and reason, bounded to one attempt per recovery.
        await _send(gen, intent, reconcileOnFailure: false);
      } else {
        await _finish(
          gen,
          request.id,
          request.status,
          request.canonicalOrderId,
        );
      }
    } on OnlineInboxException catch (error) {
      if (!_current(gen)) return;
      // not_found / transient / missing RPC cannot prove the original write's
      // result. Keep its intent and block both opposite actions indefinitely.
      _fail(error.failure);
      if (!_securityBlocked) {
        state = state.copyWith(deciding: false, uncertain: true);
      }
    } catch (_) {
      if (!_current(gen)) return;
      state = state.copyWith(
        deciding: false,
        uncertain: true,
        failure: OnlineInboxFailure.transport,
      );
    }
  }

  Future<void> _finish(
    int gen,
    String requestId,
    OnlineOrderStatus status,
    String? canonicalOrderId,
  ) async {
    if (!_current(gen)) return;
    _revision++;
    state = state.copyWith(
      requests: state.requests.where((r) => r.id != requestId).toList(),
      deciding: false,
      uncertain: false,
      clearIntent: true,
      clearFailure: status != OnlineOrderStatus.expired,
      serverTime: now(),
      failure: status == OnlineOrderStatus.expired
          ? OnlineInboxFailure.requestExpired
          : null,
    );
    if (status == OnlineOrderStatus.accepted && canonicalOrderId != null) {
      // The server ALREADY submitted it. Only the existing snapshot pipeline
      // imports canonical truth; no second submit, dispatch or print here.
      try {
        await ref.read(onlineInboxCanonicalRefreshProvider)(canonicalOrderId);
      } catch (_) {
        // Acceptance is already confirmed. A snapshot-refresh failure must
        // never turn it back into an uncertain write or submit it again.
      }
      if (!_current(gen) ||
          !_foreground ||
          _securityBlocked ||
          ref.read(posOfflineModeProvider).phase != PosOfflinePhase.online)
        return;
      try {
        final outcome = await ref.read(onlineInboxAcceptedPrintProvider)(
          requestId,
          canonicalOrderId,
        );
        if (_current(gen) && _foreground && !_securityBlocked) {
          state = state.copyWith(printOutcome: outcome);
        }
      } catch (_) {
        if (_current(gen))
          state = state.copyWith(
            printOutcome: WebOrderPrintOutcome.reconciliationRequired,
          );
      }
    }
  }
}

final onlineOrderInboxControllerProvider =
    NotifierProvider<OnlineOrderInboxController, OnlineOrderInboxState>(
      OnlineOrderInboxController.new,
    );
final onlineOrderInboxPollIntervalProvider = Provider<Duration?>((ref) => null);
// Reuse the production periodic-work seam. Existing timer-free widget tests
// and browser roots that disable polling keep notification scheduling off;
// focused alert tests can inject a cadence independently of discovery polling.
final onlineOrderInboxAlertIntervalProvider = Provider<Duration?>(
  (ref) => ref.watch(onlineOrderInboxPollIntervalProvider) == null
      ? null
      : const Duration(seconds: 10),
);
final onlineInboxCanonicalRefreshProvider =
    Provider<Future<void> Function(String)>(
      (ref) =>
          (id) => ref
              .read(posOrderSyncControllerProvider.notifier)
              .refreshOrders([id]),
    );
