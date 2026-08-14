import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        DisabledInvalidationSource,
        InvalidationHint,
        InvalidationSource,
        RealtimeScope;

import 'order_sync_controller.dart';
import 'pos_sync_scope_provider.dart';

/// POS-OPEN-ORDERS-REALTIME-GATE-013 — the POS branch-hint bridge:
/// PRIVATE BROADCAST INVALIDATION HINT → EXISTING AUTHORITATIVE REFRESH.
///
/// Mirrors the proven [KdsRealtimeBridge] semantics (250ms leading-edge
/// coalesce, error-tolerant stream, dispose-owns-source) without importing the
/// KDS coordinator types. The bridge OWNS NO business state and NEVER applies
/// hint payload data anywhere:
///  * only parsed [InvalidationHint]s arrive (the source's tryParse already
///    dropped anything malformed/forged — extra keys are never even read);
///  * only `entity == 'orders'` hints are consumed. `order_items` hints are
///    DELIBERATELY IGNORED for the strip: their entity_id is the ITEM id (not
///    an order id, so it cannot target the refresh), and every strip-relevant
///    flow — submit, amendment, table move, status transition, void,
///    completion — also touches the orders row and fires its own hint. No
///    payload change is made to add order_id in this ticket.
///  * consumed ids are collected into a pending set (duplicates/replays
///    dedupe for free) and, after one debounce window, flushed as a single
///    `refreshOrders(ids)` — the EXISTING targeted authoritative snapshot
///    read, fully gated server-side (a revoked device 42501s regardless of
///    any hint it heard). Ids are clamped to the repository's 100-id limit.
///
/// Payment-only settlement changes bump no orders row and therefore emit no
/// hint — settlement freshness honestly remains on the polling/refresh-after-
/// write paths (documented limitation, unchanged by this ticket).
class PosOrdersRealtimeBridge {
  PosOrdersRealtimeBridge({
    required InvalidationSource Function() createSource,
    required Future<void> Function(List<String> orderIds) refreshOrders,
    Duration debounce = const Duration(milliseconds: 250),
    Future<void> Function(Duration)? delay,
  }) : _createSource = createSource,
       _refreshOrders = refreshOrders,
       _debounce = debounce,
       _delay = delay ?? Future<void>.delayed;

  /// The repository clamp for one targeted snapshot call.
  static const int maxIdsPerRefresh = 100;

  /// Each [start] builds a FRESH source (a disposed realtime channel is
  /// deliberately not restartable), so pause→resume yields a fresh authorized
  /// subscription rather than resurrecting a dead socket.
  final InvalidationSource Function() _createSource;
  final Future<void> Function(List<String> orderIds) _refreshOrders;
  final Duration _debounce;
  final Future<void> Function(Duration) _delay;

  InvalidationSource? _source;
  StreamSubscription<InvalidationHint>? _hintSub;
  final Set<String> _pendingOrderIds = <String>{};
  bool _flushScheduled = false;
  bool _disposed = false;

  /// The number of authoritative refreshes issued (test-observable).
  int refreshCount = 0;

  /// Whether a subscription is currently live (test-observable).
  bool get isListening => _source != null;

  /// Opens a fresh subscription. Idempotent while one is live; inert after
  /// [dispose].
  Future<void> start() async {
    if (_disposed || _source != null) return;
    final source = _createSource();
    _source = source;
    await source.start();
    _hintSub = source.hints.listen(
      _onHint,
      // A realtime error never breaks anything: polling remains the floor.
      onError: (_) {},
    );
  }

  /// Closes the current subscription (background pause). Restartable via
  /// [start]; pending un-flushed ids survive a stop/start cycle.
  ///
  /// Teardown is FIRE-AND-FORGET on purpose: the source's dispose is
  /// best-effort by contract (never throws, harmless twice), the state flags
  /// flip synchronously, and awaiting stream teardown inside the widget-test
  /// zone can park forever — nothing downstream depends on its completion.
  void stop() {
    final source = _source;
    if (source == null) return;
    _source = null;
    unawaited(_hintSub?.cancel());
    _hintSub = null;
    unawaited(source.dispose());
  }

  void _onHint(InvalidationHint hint) {
    if (_disposed) return;
    // Orders only — see the class doc for why item hints are ignored.
    if (hint.entity != 'orders') return;
    final id = hint.entityId.trim();
    if (id.isEmpty) return;
    _pendingOrderIds.add(id);
    if (_flushScheduled) return;
    _flushScheduled = true;
    _delay(_debounce).then((_) {
      _flushScheduled = false;
      if (_disposed || _pendingOrderIds.isEmpty) return;
      final ids = _pendingOrderIds.take(maxIdsPerRefresh).toList();
      _pendingOrderIds.clear();
      refreshCount++;
      // Fire-and-forget: a slow/failing refresh must not delay the next
      // window; the refresh path owns its own error surface.
      unawaited(_refreshOrders(ids));
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingOrderIds.clear();
    stop();
  }
}

/// The factory seam the boot composition overrides with the authenticated
/// session's factory ([PosDeviceSeams.invalidationSourceFactory]). The default
/// is DISABLED — demo mode, tests, and any un-overridden composition get a
/// silent no-op source and therefore zero sockets.
final posInvalidationSourceFactoryProvider =
    Provider<InvalidationSource Function(RealtimeScope scope)>(
      (ref) =>
          (_) => const DisabledInvalidationSource(),
    );

/// The live bridge for the CURRENT sync scope, or null when no valid scope
/// exists (unpaired / no PIN session / demo short-circuits to a disabled
/// source anyway). Riverpod owns the lifecycle exactly like the KDS wiring:
///  * scope change / re-pair / logout → this provider rebuilds → the old
///    bridge (and its channel) is disposed via ref.onDispose, the new scope
///    gets a fresh authorized subscription;
///  * provider tear-down (app disposal) → same path.
/// The bridge is started fire-and-forget; a failed subscribe leaves polling
/// as the source of truth (the source itself swallows channel errors).
final posOrdersRealtimeBridgeProvider = Provider<PosOrdersRealtimeBridge?>((
  ref,
) {
  final scope = ref.watch(posSyncScopeProvider);
  if (scope == null) return null;
  final factory = ref.watch(posInvalidationSourceFactoryProvider);
  final realtimeScope = RealtimeScope(
    organizationId: scope.organizationId,
    branchId: scope.branchId,
  );
  final bridge = PosOrdersRealtimeBridge(
    createSource: () => factory(realtimeScope),
    refreshOrders: (ids) =>
        ref.read(posOrderSyncControllerProvider.notifier).refreshOrders(ids),
  );
  ref.onDispose(bridge.dispose);
  return bridge;
});
