import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/durable_outbox_store.dart';
import '../data/ids.dart';
import '../data/order_identity.dart';
import '../data/order_submission.dart';
import '../data/outbox_repository.dart';
import 'cart_controller.dart';
import 'pos_device_context.dart';
import 'pos_menu_provider.dart';
import 'pos_session.dart';
import 'recent_orders_controller.dart';

/// Demo tenant/device scope for submitted orders (DECISION D-001/D-002/D-022).
/// Self-consistent demo values — NOT wired to real auth/org/device context.
const String kDemoOrgId = 'demo-org';
const String kDemoRestaurantId = 'demo-restaurant';
const String kDemoBranchId = 'demo-branch';
const String kDemoDeviceId = 'demo-device';

/// The result of a successful [OutboxController.submit]: the created outbox
/// entry plus the provisional order number to show on the confirmation.
class OrderSubmitResult {
  const OrderSubmitResult({required this.entry, required this.orderNumber});
  final OutboxEntry entry;
  final String orderNumber;
}

/// Owns the client outbox (RF-115): builds a structured order-submission
/// payload from the active cart, enqueues it (real outbox seam), and drives the
/// demo sync lifecycle (push / retry). State is the recent entries, most recent
/// first. In-memory demo only — honestly labelled; no backend.
class OutboxController extends Notifier<List<OutboxEntry>> {
  late OutboxRepository _repo;
  int _seq = 0;
  bool _disposed = false;
  bool _sweeping = false;

  /// Auto-retry cap for a transiently-FAILED entry before it waits for a manual
  /// retry (so a persistently-rejecting backend is not spammed).
  static const int _maxAutoAttempts = 5;

  @override
  List<OutboxEntry> build() {
    _repo = ref.watch(outboxRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    // RF-114: load any orders queued before a refresh / tab close / app restart
    // (the durable outbox) and best-effort deliver them. Fire-and-forget so
    // build() stays synchronous; state updates when the async load completes.
    _recover();
    // Optional periodic sweep so queued / transiently-failed orders sync once
    // connectivity/backend recovers (no connectivity dependency). OFF unless an
    // interval is provided — main.dart enables it for the real app; tests leave
    // it null so `pumpAndSettle` terminates (a periodic timer never settles).
    final interval = ref.read(outboxAutoSweepIntervalProvider);
    if (interval != null) {
      final timer = Timer.periodic(interval, (_) => _sweep());
      ref.onDispose(timer.cancel);
    }
    return const <OutboxEntry>[];
  }

  /// Loads the durable queue on start and delivers whatever is not yet applied.
  /// Fail-closed: if the real outbox has no session/transport yet it throws, so
  /// we simply skip — a later rebuild (after PIN sign-in) re-runs this.
  Future<void> _recover() async {
    final List<OutboxEntry> loaded;
    try {
      loaded = await _repo.recentEntries();
    } catch (_) {
      return;
    }
    if (_disposed || loaded.isEmpty) return;
    state = loaded;
    await _sweep();
  }

  /// Best-effort delivery of queued orders: re-queue + push transiently-FAILED
  /// entries (up to [_maxAutoAttempts]) and push still-PENDING ones. Retries are
  /// idempotent (`(deviceId, localOperationId)`, D-022) so a re-push after a
  /// restart never creates a duplicate. Single-flight; aborts on session loss.
  Future<void> _sweep() async {
    if (_sweeping || _disposed) return;
    _sweeping = true;
    try {
      final failed = <String>[
        for (final e in state)
          // REVIEW B2: a permanent business rejection replays its stored
          // verdict forever — sweeping it would burn attempts on a foregone
          // conclusion and imply the order might still go through.
          if (e.syncState.isFailed &&
              !e.isPermanentBusinessRejection &&
              e.attemptCount < _maxAutoAttempts)
            e.id,
      ];
      final pending = <String>[
        for (final e in state)
          if (e.syncState.isPending) e.id,
      ];
      for (final id in failed) {
        if (_disposed) return;
        try {
          await retryEntry(id);
        } catch (_) {
          return; // session/transport lost — stop; a later sweep resumes.
        }
      }
      for (final id in pending) {
        if (_disposed) return;
        final cur = entryById(id);
        if (cur == null || !cur.syncState.isPending) continue;
        try {
          await pushEntry(id);
        } catch (_) {
          return;
        }
      }
    } finally {
      _sweeping = false;
    }
  }

  /// POS-OPERATIONS-SYNC-001: push whatever is queued, now.
  ///
  /// The reconnect/startup sequence is PUSH-then-PULL: queued work is delivered and
  /// its acknowledgements/rejections processed BEFORE an authoritative pull, so the
  /// pull observes a server that has already seen this device's writes. Pulling
  /// first would hand us a snapshot that predates our own queued payment and invite
  /// the UI to "correct" itself back to a state we are in the middle of changing.
  ///
  /// Re-entrancy is already guarded inside [_sweep]; a second caller is a no-op
  /// rather than a second concurrent push.
  Future<void> pushQueued() => _sweep();

  /// Manually re-queues + pushes every RETRYABLE failed entry ("Sync failed —
  /// retry all"). REVIEW B2: permanently-rejected business operations are
  /// excluded — their verdict is ledgered and replay cannot change it.
  Future<void> retryAllFailed() async {
    final failed = <String>[
      for (final e in state)
        if (e.syncState.isFailed && !e.isPermanentBusinessRejection) e.id,
    ];
    for (final id in failed) {
      try {
        await retryEntry(id);
      } catch (_) {
        break;
      }
    }
  }

  /// POS-SUBMIT-GUARD-001: a submit already running on THIS controller. The
  /// controller (a Notifier) outlives any cart widget, so this lock holds even
  /// when the phone cart sheet is dismissed and reopened mid-submit — the case
  /// that would otherwise drop [CartPanelContent]'s widget-local guard and let a
  /// second Send tap mint a duplicate order with fresh idempotency keys.
  Future<OrderSubmitResult>? _inFlightSubmit;

  /// Builds + enqueues an order submission from the current cart snapshot.
  /// Throws [OrderSubmissionException] for an empty cart or a dine-in order
  /// without a table (defence-in-depth — the Send button is also gated).
  ///
  /// POS-SUBMIT-GUARD-001: while a submit is in flight, a repeat call JOINS it
  /// (returns the same future / the same order) instead of enqueuing a second
  /// `order.submit` op. This is the correctness boundary; the Send-button
  /// spinner is the UX layer on top.
  Future<OrderSubmitResult> submit({
    required List<CartLineView> lines,
    required int subtotalMinor,
    required String currencyCode,
    required OrderType orderType,
    String? tableId,
    String? tableLabel,
    int taxTotalMinor = 0,
    String? customerName,
  }) {
    final existing = _inFlightSubmit;
    if (existing != null) return existing;
    final future = _runSubmit(
      lines: lines,
      subtotalMinor: subtotalMinor,
      currencyCode: currencyCode,
      orderType: orderType,
      tableId: tableId,
      tableLabel: tableLabel,
      taxTotalMinor: taxTotalMinor,
      customerName: customerName,
    );
    _inFlightSubmit = future;
    // Release the lock once the submit settles (success OR failure) so the next
    // order can go; clear only if a newer submit has not already replaced it.
    // `.ignore()` (not the returned original `future`, which the caller handles)
    // keeps a rejected submit from surfacing as an unhandled async error here.
    future.whenComplete(() {
      if (identical(_inFlightSubmit, future)) _inFlightSubmit = null;
    }).ignore();
    return future;
  }

  Future<OrderSubmitResult> _runSubmit({
    required List<CartLineView> lines,
    required int subtotalMinor,
    required String currencyCode,
    required OrderType orderType,
    String? tableId,
    String? tableLabel,
    int taxTotalMinor = 0,
    String? customerName,
  }) async {
    if (lines.isEmpty) {
      throw const OrderSubmissionException('cannot submit an empty cart');
    }
    if (orderType == OrderType.dineIn &&
        (tableId == null || tableId.trim().isEmpty)) {
      throw const OrderSubmissionException('dine-in order requires a table');
    }
    // ORDER-CUSTOMER-001: normalize the OPTIONAL customer name at this single
    // choke point (covers demo + real). Trim + empty->null + 80-char cap; never
    // gates submit. The server re-normalizes identically.
    final normalizedCustomerName = normalizeCustomerName(customerName);

    _seq++;
    final n = _seq.toString().padLeft(4, '0');
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    // A REAL submission carries CLIENT-GENERATED UUIDs (DECISION D-010 / D-022):
    // the [orderId] and [localOperationId] are sent to `public.sync_push` and
    // MUST be valid UUIDs, never the demo `demo-order-*` / `demo-op-*` labels.
    // Demo mode keeps its deterministic, clearly-labelled ids (no backend - the
    // ids are never transmitted). The [orderNumber] stays a provisional display
    // label (`DEMO-$n`); it is NOT part of the transport body.
    final ids = isDemo ? null : ref.read(clientIdGeneratorProvider);
    final orderId = isDemo ? 'demo-order-$n' : ids!.newId();
    final localOperationId = isDemo ? 'demo-op-$n' : ids!.newId();
    final entryId = isDemo ? 'demo-outbox-$n' : ids!.newId();
    // Demo keeps the honest DEMO-nnnn label; a REAL order shows the shared
    // display code derived from its uuid — the KDS derives the SAME code from
    // the pulled order id, so cashier and kitchen talk about one number.
    final orderNumber = isDemo ? 'DEMO-$n' : displayOrderCode(orderId);
    final createdAt = DateTime.now();

    // RF-114 scope binding: a REAL order is bound to the CURRENT paired device +
    // tenant scope (never a demo placeholder). deviceId comes from the active
    // sync session (the authoritative device identity, also used as the durable
    // store key); org/restaurant/branch come from the paired device context (for
    // defensive replay metadata). On replay the outbox refuses to submit an order
    // whose deviceId != the current session's device (survives unpair/re-pair).
    final session = isDemo ? null : ref.read(posSyncSessionProvider);
    final ctx = isDemo ? null : ref.read(posDeviceContextProvider);
    final deviceId = isDemo
        ? kDemoDeviceId
        : (session?.deviceId ?? ctx?.deviceId ?? kDemoDeviceId);
    final organizationId = isDemo
        ? kDemoOrgId
        : (ctx?.organizationId ?? kDemoOrgId);
    final restaurantId = isDemo
        ? kDemoRestaurantId
        : (ctx?.restaurantId ?? kDemoRestaurantId);
    final branchId = isDemo ? kDemoBranchId : (ctx?.branchId ?? kDemoBranchId);

    // KITCHEN-PREP-001: the ORDER-TIME (D-008) prep snapshot. Each line carries
    // its menu item's configured PER-UNIT prep components, looked up by
    // menuItemId from the live menu the POS is selling from. Non-money; empty
    // for unconfigured items. Snapshotted into the payload so the outbox
    // preserves it and the KDS can aggregate a prep summary offline.
    final menuData = ref.read(posMenuProvider).valueOrNull;
    final prepByItemId = <String, List<KitchenPrepComponent>>{
      if (menuData != null)
        for (final item in menuData.items)
          if (item.prepComponents.isNotEmpty) item.id: item.prepComponents,
    };

    final items = lines
        .map(
          (l) => OrderSubmissionItem(
            menuItemId: l.menuItemId,
            nameSnapshot: l.name,
            quantity: l.quantity,
            unitPriceMinorSnapshot: l.unitPriceMinor,
            // Already includes the line's modifier deltas × quantities
            // (RF-052 formula) — the server recomputes
            // qty×unit + Σ(delta × modifier_qty) and must match.
            lineTotalMinor: l.lineTotalMinor,
            notes: l.note,
            prepComponents:
                prepByItemId[l.menuItemId] ?? const <KitchenPrepComponent>[],
            modifiers: [
              for (final m in l.modifiers)
                OrderSubmissionModifier(
                  modifierOptionId: m.optionId,
                  optionNameSnapshot: m.optionName,
                  modifierNameSnapshot: m.groupName,
                  priceMinorSnapshot: m.priceDeltaMinor,
                  quantity: m.quantity,
                  // KITCHEN-MEAT-001: snapshot the option's meat contribution.
                  meatSnapshot: m.kitchenMeat,
                ),
            ],
          ),
        )
        .toList(growable: false);
    final itemCount = lines.fold<int>(0, (sum, l) => sum + l.quantity);

    final payload = OrderSubmissionPayload(
      orderId: orderId,
      localOperationId: localOperationId,
      deviceId: deviceId,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      orderType: orderType,
      tableId: tableId,
      currencyCode: currencyCode,
      subtotalMinor: subtotalMinor,
      // RF-117: tax computed client-side from the owner's per-branch setting
      // (0 when disabled). Discount stays 0 at submit (it is applied post-submit,
      // server-authoritative). The server validates grand = subtotal − discount
      // + tax and grand >= 0 (integer minor units, D-007).
      taxTotalMinor: taxTotalMinor,
      grandTotalMinor: subtotalMinor + taxTotalMinor,
      items: items,
      clientCreatedAt: createdAt,
      customerName: normalizedCustomerName,
    );

    final entry = OutboxEntry(
      id: entryId,
      deviceId: deviceId,
      organizationId: organizationId,
      restaurantId: restaurantId,
      branchId: branchId,
      localOperationId: localOperationId,
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: orderId,
      payloadJson: jsonEncode(payload.toJson()),
      summary: OrderSummary(
        orderNumber: orderNumber,
        orderType: orderType,
        tableLabel: tableLabel,
        itemCount: itemCount,
        subtotalMinor: subtotalMinor,
        currencyCode: currencyCode,
        customerName: normalizedCustomerName,
      ),
      syncState: OutboxSyncState.pending,
      clientCreatedAt: createdAt,
    );

    final stored = await _repo.enqueue(entry);
    state = await _repo.recentEntries();
    if (!isDemo) {
      // REAL mode sends immediately (no manual "sync now"): push the entry so
      // the backend has the order — the KDS poll then picks it up on its own,
      // and a cash payment can reference the order server-side. A failed push
      // stays visible on the confirmation with an honest error + Retry; the
      // order itself is never lost (it remains queued in the outbox).
      await pushEntry(stored.id);
    }
    return OrderSubmitResult(entry: stored, orderNumber: orderNumber);
  }

  /// Demo-pushes [entryId]: shows "Sending…" then the delivered/failed result.
  Future<void> pushEntry(String entryId) async {
    state = [
      for (final e in state)
        if (e.id == entryId)
          e.copyWith(syncState: OutboxSyncState.inFlight)
        else
          e,
    ];
    await _repo.push(entryId);
    state = await _repo.recentEntries();
    // RESTAURANT-OPERATIONS-V1-001: the server refusing an item as unavailable
    // means OUR menu is stale — a manager flipped availability after our last
    // load. Reload it so the grid greys the item out before the cashier
    // re-enters the corrected order. Availability only travels with the menu
    // (there is no realtime push), so this is the honest refresh point.
    for (final e in state) {
      if (e.id == entryId && e.isPermanentBusinessRejection) {
        if (e.lastErrorCode == 'item_unavailable') {
          ref.invalidate(posMenuProvider);
        }
        // PILOT-OPERATIONS-CORRECTIONS-001 (A3): the submit created NO server order.
        // Retire the phantom recent-order row to a non-actionable rejected shell so it
        // never offers payment/void/receipt for an order that does not exist. Matched
        // by the SAME identity the submit row was recorded under (target order id).
        ref
            .read(posRecentOrdersControllerProvider.notifier)
            .markLocallyRejected(
              PosOrderIdentity.of(
                orderId: e.targetId,
                localOperationId: e.localOperationId,
                outboxEntryId: e.id,
                orderNumber: e.summary.orderNumber,
              ),
            );
      }
    }
  }

  /// Re-queues a failed [entryId] and pushes it again.
  Future<void> retryEntry(String entryId) async {
    await _repo.retry(entryId);
    state = await _repo.recentEntries();
    await pushEntry(entryId);
  }

  /// The current entry for [entryId], or null if it is unknown.
  OutboxEntry? entryById(String? entryId) {
    if (entryId == null) return null;
    for (final e in state) {
      if (e.id == entryId) return e;
    }
    return null;
  }

  /// Count of entries still queued locally (pending / created).
  int get pendingCount => state.where((e) => e.syncState.isPending).length;
}

/// The client outbox repository. Selects by client runtime mode (M7): the
/// in-memory [DemoOutboxStore] in demo mode (the DEFAULT), or the real
/// [RealOutboxRepository] in real mode, which posts `order.submit` ops to the
/// RF-126 `public.sync_push` wrapper. The real repo is built from the shared
/// validated anon-key transport ([posAuthTransportProvider]; no service-role key,
/// D-011) and the current [posSyncSessionProvider] session (RF-131); with no
/// transport (missing/invalid config) or no session it fails closed (no backend
/// contact). Tests can override this provider, [runtimeConfigProvider],
/// [posAuthTransportProvider], or [posSyncSessionProvider] to force a mode.
final outboxRepositoryProvider = Provider<OutboxRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoOutboxStore();
  final transport = ref.watch(posAuthTransportProvider);
  return RealOutboxRepository(
    transport,
    ref.watch(posSyncSessionProvider),
    // RF-114: durable persistence so queued orders survive refresh/restart.
    store: ref.watch(durableOutboxStoreProvider),
  );
});

/// RF-114: the durable outbox store (localStorage-backed on web). Null by
/// default => in-memory only (demo mode / tests). Overridden in `main.dart` for
/// the real app with a [SharedPrefsOutboxStore] built on the shared
/// SharedPreferences instance.
final durableOutboxStoreProvider = Provider<DurableOutboxStore?>((ref) => null);

/// RF-114: the periodic auto-sweep interval that re-delivers queued/failed
/// orders once the backend recovers. Null by default => NO periodic timer (so
/// widget-test `pumpAndSettle` terminates). `main.dart` enables it for the real
/// app; recovery-on-start + manual retry work regardless of this.
final outboxAutoSweepIntervalProvider = Provider<Duration?>((ref) => null);

/// The POS outbox controller (recent entries, most recent first).
final outboxControllerProvider =
    NotifierProvider<OutboxController, List<OutboxEntry>>(OutboxController.new);
