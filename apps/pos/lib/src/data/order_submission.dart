import 'package:restoflow_domain/restoflow_domain.dart';

/// Sync-operation lifecycle state for a POS outbox entry (RF-115).
///
/// This MIRRORS the frozen `SyncOperationState` vocabulary (DECISION D-018),
/// owned by `packages/data_local` and `docs/STATE_MACHINES.md` §10 — same member
/// names and snake_case [wire] values, same terminal set. It is re-declared here
/// (rather than depending on `data_local`) only so the demo POS does not pull the
/// Drift/SQLite + RF-021 encrypted-DB foundation in just to label a state: when
/// the device/PIN-session auth bridge + real outbox land, the [OutboxRepository]
/// seam swaps to the `data_local`-backed store and this mirror is replaced by the
/// canonical enum. It does NOT add, rename, or repurpose any state.
enum OutboxSyncState {
  created('created'),
  pending('pending'),
  inFlight('in_flight'),
  applied('applied'),
  rejected('rejected'),
  dead('dead'),
  conflict('conflict'),
  resolved('resolved');

  const OutboxSyncState(this.wire);

  final String wire;

  static const Set<OutboxSyncState> terminals = {applied, rejected, dead};

  bool get isTerminal => terminals.contains(this);

  /// Queued locally, not yet (demo-)sent.
  bool get isPending => this == created || this == pending;

  /// A failed delivery the cashier can retry.
  bool get isFailed => this == rejected || this == dead;
}

/// A single line on an [OrderSubmissionPayload]. Money is integer minor units
/// only (DECISION D-007); the name + unit price are snapshots captured at order
/// time (DECISION D-008), never recomputed from a live menu.
class OrderSubmissionItem {
  const OrderSubmissionItem({
    required this.menuItemId,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitPriceMinorSnapshot,
    required this.lineTotalMinor,
  });

  final String menuItemId;
  final String nameSnapshot;
  final int quantity;
  final int unitPriceMinorSnapshot;
  final int lineTotalMinor;

  /// Mirrors an element of the `submit_order` RPC `order_items[]` (RF-052).
  Map<String, Object?> toJson() => <String, Object?>{
    'menu_item_id': menuItemId,
    'menu_item_name_snapshot': nameSnapshot,
    'quantity': quantity,
    'unit_price_minor_snapshot': unitPriceMinorSnapshot,
    'line_total_minor': lineTotalMinor,
  };
}

/// The structured order-submission payload (RF-115). Its JSON shape mirrors the
/// real `app.submit_order` RPC request (RF-052 / API_CONTRACT §4.1) so the same
/// body can later be POSTed by the real push engine. All money is integer minor
/// units (DECISION D-007). Idempotency is `(deviceId, localOperationId)`
/// (DECISION D-022).
class OrderSubmissionPayload {
  const OrderSubmissionPayload({
    required this.orderId,
    required this.localOperationId,
    required this.deviceId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    this.stationId,
    required this.orderType,
    this.tableId,
    required this.currencyCode,
    required this.subtotalMinor,
    this.discountTotalMinor = 0,
    this.taxTotalMinor = 0,
    required this.grandTotalMinor,
    required this.items,
    required this.clientCreatedAt,
    this.notes,
  });

  final String orderId;
  final String localOperationId;
  final String deviceId;

  // Tenant + operational scope (DECISION D-001/D-002).
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String? stationId;

  final OrderType orderType;
  final String? tableId;
  final String currencyCode;

  final int subtotalMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;

  final List<OrderSubmissionItem> items;
  final DateTime clientCreatedAt;
  final String? notes;

  String get orderTypeWire =>
      orderType == OrderType.dineIn ? 'dine_in' : 'takeaway';

  /// The transport body, shaped like the `submit_order` RPC request (RF-052).
  Map<String, Object?> toJson() => <String, Object?>{
    'order_id': orderId,
    'local_operation_id': localOperationId,
    'device_id': deviceId,
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'station_id': stationId,
    'order_type': orderTypeWire,
    'table_id': tableId,
    'currency_code': currencyCode,
    'subtotal_minor': subtotalMinor,
    'discount_total_minor': discountTotalMinor,
    'tax_total_minor': taxTotalMinor,
    'grand_total_minor': grandTotalMinor,
    'notes': notes,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'order_items': items.map((i) => i.toJson()).toList(growable: false),
  };
}

/// A small, human-readable snapshot of a submitted order, used to render the
/// outbox/confirmation UI WITHOUT showing the raw JSON payload or a UUID wall.
class OrderSummary {
  const OrderSummary({
    required this.orderNumber,
    required this.orderType,
    required this.tableLabel,
    required this.itemCount,
    required this.subtotalMinor,
    required this.currencyCode,
  });

  /// Local/provisional demo number (e.g. `DEMO-0001`) — NOT a server receipt
  /// number (DECISION D-021).
  final String orderNumber;
  final OrderType orderType;
  final String? tableLabel;
  final int itemCount;
  final int subtotalMinor;
  final String currencyCode;
}

/// One client outbox entry (RF-115): a queued order submission plus its sync
/// lifecycle. Field-for-field this mirrors the production `OutboxOperations`
/// row (`packages/data_local`): id, `(deviceId, localOperationId)` idempotency
/// key, operationType/targetEntity/targetId, the JSON [payloadJson], the
/// [syncState], retry bookkeeping, and client timestamp. [summary] is a UI
/// convenience snapshot and is not part of the transport body.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.deviceId,
    required this.localOperationId,
    required this.operationType,
    required this.targetEntity,
    required this.targetId,
    required this.payloadJson,
    required this.summary,
    required this.syncState,
    required this.clientCreatedAt,
    this.attemptCount = 0,
    this.lastErrorCode,
  });

  final String id;
  final String deviceId;
  final String localOperationId;
  final String operationType; // 'order.submit'
  final String targetEntity; // 'order'
  final String targetId; // orderId
  final String payloadJson;
  final OrderSummary summary;
  final OutboxSyncState syncState;
  final DateTime clientCreatedAt;
  final int attemptCount;
  final String? lastErrorCode;

  OutboxEntry copyWith({
    OutboxSyncState? syncState,
    int? attemptCount,
    String? lastErrorCode,
    bool clearError = false,
  }) => OutboxEntry(
    id: id,
    deviceId: deviceId,
    localOperationId: localOperationId,
    operationType: operationType,
    targetEntity: targetEntity,
    targetId: targetId,
    payloadJson: payloadJson,
    summary: summary,
    syncState: syncState ?? this.syncState,
    clientCreatedAt: clientCreatedAt,
    attemptCount: attemptCount ?? this.attemptCount,
    lastErrorCode: clearError ? null : (lastErrorCode ?? this.lastErrorCode),
  );
}
