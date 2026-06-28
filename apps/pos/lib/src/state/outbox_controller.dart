import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

import '../data/order_submission.dart';
import '../data/outbox_repository.dart';
import 'cart_controller.dart';

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
    final orderId = 'demo-order-$n';
    final localOperationId = 'demo-op-$n';
    final orderNumber = 'DEMO-$n';
    final createdAt = DateTime.now();

    final items = lines
        .map(
          (l) => OrderSubmissionItem(
            menuItemId: l.menuItemId,
            nameSnapshot: l.name,
            quantity: l.quantity,
            unitPriceMinorSnapshot: l.unitPriceMinor,
            lineTotalMinor: l.lineTotalMinor,
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
      // RF-115 carries no tax/discount preview; the authoritative totals are the
      // money engine's job (RF-036). Grand total == subtotal for now.
      grandTotalMinor: subtotalMinor,
      items: items,
      clientCreatedAt: createdAt,
    );

    final entry = OutboxEntry(
      id: 'demo-outbox-$n',
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

/// The client outbox repository. Defaults to the in-memory [DemoOutboxStore];
/// tests / the real data bridge can override this provider.
final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => DemoOutboxStore(),
);

/// The POS outbox controller (recent entries, most recent first).
final outboxControllerProvider =
    NotifierProvider<OutboxController, List<OutboxEntry>>(OutboxController.new);
