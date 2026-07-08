import 'package:restoflow_domain/restoflow_domain.dart';

/// ORDER-CUSTOMER-001: the max stored length of the OPTIONAL customer display
/// name — mirrors the server's 80-char cap (`left(..., 80)` in app.sync_push).
/// The POS input field also caps typing at this length.
const int kCustomerNameMaxLength = 80;

/// Normalizes a raw customer-name input to what is stored + sent: trims, treats
/// an empty/whitespace-only value as null, and clamps to [kCustomerNameMaxLength].
/// The server re-applies the same trim/empty->null/cap, so this is defence in
/// depth. Non-money display text (never a phone number or other PII).
String? normalizeCustomerName(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.length <= kCustomerNameMaxLength
      ? trimmed
      : trimmed.substring(0, kCustomerNameMaxLength);
}

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

/// A selected modifier on an [OrderSubmissionItem] — mirrors an element of the
/// per-item `modifiers[]` array `app.submit_order` validates and snapshots
/// into `order_item_modifiers` (RF-052, D-008). [priceMinorSnapshot] is a
/// SIGNED integer minor-unit UNIT delta; the server counts it × [quantity]
/// once per line in its total formula (`Σ delta × modifier_qty`).
class OrderSubmissionModifier {
  const OrderSubmissionModifier({
    required this.modifierOptionId,
    required this.optionNameSnapshot,
    this.modifierNameSnapshot,
    required this.priceMinorSnapshot,
    this.quantity = 1,
  });

  final String modifierOptionId;
  final String optionNameSnapshot;
  final String? modifierNameSnapshot;
  final int priceMinorSnapshot;

  /// Units of this option (>= 1) — `order_item_modifiers.quantity`.
  final int quantity;

  Map<String, Object?> toJson() => <String, Object?>{
    'modifier_option_id': modifierOptionId,
    'option_name_snapshot': optionNameSnapshot,
    'modifier_name_snapshot': modifierNameSnapshot,
    'price_minor_snapshot': priceMinorSnapshot,
    'quantity': quantity,
  };
}

/// A single line on an [OrderSubmissionPayload]. Money is integer minor units
/// only (DECISION D-007); the name + unit price are snapshots captured at order
/// time (DECISION D-008), never recomputed from a live menu. [lineTotalMinor]
/// follows the RF-052 server formula `qty × unit + Σmodifiers` (the server
/// recomputes and rejects any mismatch).
class OrderSubmissionItem {
  const OrderSubmissionItem({
    required this.menuItemId,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitPriceMinorSnapshot,
    required this.lineTotalMinor,
    this.modifiers = const <OrderSubmissionModifier>[],
    this.notes,
    this.prepComponents = const <KitchenPrepComponent>[],
  });

  final String menuItemId;
  final String nameSnapshot;
  final int quantity;
  final int unitPriceMinorSnapshot;
  final int lineTotalMinor;
  final List<OrderSubmissionModifier> modifiers;

  /// Optional cashier note for this item — `order_items.notes` (non-money;
  /// flows through to the kitchen display unredacted).
  final String? notes;

  /// KITCHEN-PREP-001: the item's configured PER-UNIT kitchen prep components
  /// (from `menu_items.attributes.prep_components`), snapshotted at order time
  /// (D-008) into `order_items.prep_snapshot`. NON-money ({name,quantity,unit});
  /// the KDS multiplies each by [quantity] and aggregates the whole order.
  final List<KitchenPrepComponent> prepComponents;

  /// Mirrors an element of the `submit_order` RPC `order_items[]` (RF-052).
  Map<String, Object?> toJson() => <String, Object?>{
    'menu_item_id': menuItemId,
    'menu_item_name_snapshot': nameSnapshot,
    'quantity': quantity,
    'unit_price_minor_snapshot': unitPriceMinorSnapshot,
    'line_total_minor': lineTotalMinor,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    if (modifiers.isNotEmpty)
      'modifiers': modifiers.map((m) => m.toJson()).toList(growable: false),
    // Emitted ONLY when present so the pre-feature wire shape (and the server's
    // md5(op_type||payload) idempotency fingerprint) is unchanged for items
    // with no prep — same conditional-emit rule as notes/modifiers.
    if (prepComponents.isNotEmpty)
      'prep_snapshot': [for (final c in prepComponents) c.toJson()],
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
    this.customerName,
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

  /// ORDER-CUSTOMER-001: the OPTIONAL customer display name (non-money, like
  /// [notes]). Trimmed + empty->null upstream; the server re-normalizes
  /// (trim/empty->null/<=80). Reaches the receipt + the kitchen ticket.
  final String? customerName;

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
    'customer_name': customerName,
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
    this.customerName,
  });

  /// Local/provisional demo number (e.g. `DEMO-0001`) — NOT a server receipt
  /// number (DECISION D-021).
  final String orderNumber;
  final OrderType orderType;
  final String? tableLabel;
  final int itemCount;
  final int subtotalMinor;
  final String currencyCode;

  /// ORDER-CUSTOMER-001: the OPTIONAL customer display name (non-money), so the
  /// confirmation/receipt can show it without decoding the raw payload.
  final String? customerName;

  /// RF-114 durable-outbox persistence (integer minor money only, D-007).
  Map<String, Object?> toJson() => <String, Object?>{
    'order_number': orderNumber,
    'order_type': orderType == OrderType.dineIn ? 'dine_in' : 'takeaway',
    'table_label': tableLabel,
    'item_count': itemCount,
    'subtotal_minor': subtotalMinor,
    'currency_code': currencyCode,
    'customer_name': customerName,
  };

  factory OrderSummary.fromJson(Map<String, Object?> json) => OrderSummary(
    orderNumber: json['order_number'] as String? ?? '',
    orderType: json['order_type'] == 'dine_in'
        ? OrderType.dineIn
        : OrderType.takeaway,
    tableLabel: json['table_label'] as String?,
    itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
    subtotalMinor: (json['subtotal_minor'] as num?)?.toInt() ?? 0,
    currencyCode: json['currency_code'] as String? ?? 'ILS',
    customerName: json['customer_name'] as String?,
  );
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
    this.organizationId,
    this.restaurantId,
    this.branchId,
    this.attemptCount = 0,
    this.lastErrorCode,
  });

  final String id;

  /// The ORIGINAL device this order was queued on (DECISION D-022). RF-114 binds
  /// a durable entry to its device: on replay the outbox refuses to submit it
  /// under a session for a DIFFERENT device (survives unpair/re-pair) — see
  /// [RealOutboxRepository]. In real mode this is the real device-session
  /// deviceId, never a demo placeholder.
  final String deviceId;
  final String localOperationId;
  final String operationType; // 'order.submit'
  final String targetEntity; // 'order'
  final String targetId; // orderId
  final String payloadJson;
  final OrderSummary summary;
  final OutboxSyncState syncState;
  final DateTime clientCreatedAt;

  /// RF-114 defensive scope metadata: the ORIGINAL tenant scope this order was
  /// queued under (from the paired device context; null when unknown/demo).
  /// Local-only — never transmitted (the server derives scope from the session).
  final String? organizationId;
  final String? restaurantId;
  final String? branchId;

  final int attemptCount;
  final String? lastErrorCode;

  /// RF-114 durable-outbox persistence. Stores ONLY what a retry needs: the
  /// idempotency identity `(deviceId, localOperationId)`, the op envelope, the
  /// server-shaped [payloadJson] (integer minor money only, D-007; no secrets,
  /// no service-role key), a UI [summary], and the lifecycle. Tenant scope is
  /// server-derived from the session and is NOT part of the transmitted op, so
  /// nothing sensitive is persisted here.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'device_id': deviceId,
    'local_operation_id': localOperationId,
    'operation_type': operationType,
    'target_entity': targetEntity,
    'target_id': targetId,
    'payload_json': payloadJson,
    'summary': summary.toJson(),
    'sync_state': syncState.wire,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'attempt_count': attemptCount,
    'last_error_code': lastErrorCode,
  };

  /// Parses a persisted entry. Fail-safe: an unparseable/foreign-shape entry
  /// throws [FormatException] so the store can drop it rather than crash the
  /// POS on start (schema drift / a corrupt localStorage value).
  factory OutboxEntry.fromJson(Map<String, Object?> json) {
    final wire = json['sync_state'] as String?;
    final state = OutboxSyncState.values.firstWhere(
      (s) => s.wire == wire,
      orElse: () => throw FormatException('unknown sync_state: $wire'),
    );
    final createdRaw = json['client_created_at'] as String?;
    final created = DateTime.tryParse(createdRaw ?? '');
    if (created == null) {
      throw FormatException('bad client_created_at: $createdRaw');
    }
    final summaryRaw = json['summary'];
    if (summaryRaw is! Map) {
      throw const FormatException('missing summary');
    }
    return OutboxEntry(
      id: json['id'] as String? ?? (throw const FormatException('missing id')),
      deviceId: json['device_id'] as String? ?? '',
      localOperationId:
          json['local_operation_id'] as String? ??
          (throw const FormatException('missing local_operation_id')),
      operationType: json['operation_type'] as String? ?? 'order.submit',
      targetEntity: json['target_entity'] as String? ?? 'order',
      targetId: json['target_id'] as String? ?? '',
      payloadJson:
          json['payload_json'] as String? ??
          (throw const FormatException('missing payload_json')),
      summary: OrderSummary.fromJson(summaryRaw.cast<String, Object?>()),
      syncState: state,
      clientCreatedAt: created,
      organizationId: json['organization_id'] as String?,
      restaurantId: json['restaurant_id'] as String?,
      branchId: json['branch_id'] as String?,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      lastErrorCode: json['last_error_code'] as String?,
    );
  }

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
    organizationId: organizationId,
    restaurantId: restaurantId,
    branchId: branchId,
    attemptCount: attemptCount ?? this.attemptCount,
    lastErrorCode: clearError ? null : (lastErrorCode ?? this.lastErrorCode),
  );
}
