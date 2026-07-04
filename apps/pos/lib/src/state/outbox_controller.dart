import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/order_submission.dart';
import '../data/outbox_repository.dart';
import 'cart_controller.dart';
import 'pos_session.dart';

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

  @override
  List<OutboxEntry> build() {
    _repo = ref.watch(outboxRepositoryProvider);
    return const <OutboxEntry>[];
  }

  /// Builds + enqueues an order submission from the current cart snapshot.
  /// Throws [OrderSubmissionException] for an empty cart or a dine-in order
  /// without a table (defence-in-depth — the Send button is also gated).
  Future<OrderSubmitResult> submit({
    required List<CartLineView> lines,
    required int subtotalMinor,
    required String currencyCode,
    required OrderType orderType,
    String? tableId,
    String? tableLabel,
    int taxTotalMinor = 0,
  }) async {
    if (lines.isEmpty) {
      throw const OrderSubmissionException('cannot submit an empty cart');
    }
    if (orderType == OrderType.dineIn &&
        (tableId == null || tableId.trim().isEmpty)) {
      throw const OrderSubmissionException('dine-in order requires a table');
    }

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
            modifiers: [
              for (final m in l.modifiers)
                OrderSubmissionModifier(
                  modifierOptionId: m.optionId,
                  optionNameSnapshot: m.optionName,
                  modifierNameSnapshot: m.groupName,
                  priceMinorSnapshot: m.priceDeltaMinor,
                  quantity: m.quantity,
                ),
            ],
          ),
        )
        .toList(growable: false);
    final itemCount = lines.fold<int>(0, (sum, l) => sum + l.quantity);

    final payload = OrderSubmissionPayload(
      orderId: orderId,
      localOperationId: localOperationId,
      deviceId: kDemoDeviceId,
      organizationId: kDemoOrgId,
      restaurantId: kDemoRestaurantId,
      branchId: kDemoBranchId,
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
    );

    final entry = OutboxEntry(
      id: entryId,
      deviceId: kDemoDeviceId,
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
  return RealOutboxRepository(transport, ref.watch(posSyncSessionProvider));
});

/// The POS outbox controller (recent entries, most recent first).
final outboxControllerProvider =
    NotifierProvider<OutboxController, List<OutboxEntry>>(OutboxController.new);
