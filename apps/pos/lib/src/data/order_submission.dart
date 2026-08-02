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

  /// A failed delivery. Whether a RETRY of the SAME operation identity is
  /// meaningful additionally depends on the entry's error code — see
  /// [OutboxEntry.isPermanentBusinessRejection].
  bool get isFailed => this == rejected || this == dead;
}

/// REVIEW B2 — error codes for which the server RECORDED a permanent business
/// verdict under this operation's `(device_id, local_operation_id)` identity.
/// sync_push replays a terminal ledger result verbatim, so re-pushing the SAME
/// identity can never turn these into an acceptance — even if the underlying
/// obstacle (a sold-out item, a vanished table) is later resolved. A new
/// business attempt must be a DELIBERATE new order, never a "Retry" button.
///
///   * the four typed submit refusals (RESTAURANT-OPERATIONS-V1-001);
///   * 'rejected' — the server's generic permanent collapse of a raised
///     validation/auth failure (RF-056/MONEY-VOID-001), equally ledgered.
///
/// Client-side parse codes (malformed_response, missing_results, …) and `dead`
/// entries stay retryable: no server verdict was positively recorded, so an
/// idempotent re-push is both safe and meaningful.
const Set<String> kPermanentRejectionCodes = {
  'item_unavailable',
  'table_required',
  'table_not_allowed',
  'table_not_available',
  // KITCHEN-DISPATCH-ENFORCE-001: the server refused a `direct_print` submit
  // because the branch's authoritative kitchen_workflow_mode is not
  // `printer_only`. Re-sending the SAME op can never succeed (the op's
  // dispatch mode is part of its stored identity), so this is TERMINAL: no
  // auto-resweep, no Retry, the phantom recent-order row is retired and the
  // kitchen print is suppressed. The cashier re-submits and the fresh op
  // resolves the correct mode.
  'dispatch_mode_not_allowed',
  // MONEY-SERVER-MODIFIER-SCOPE-003D: the server refused a modifier whose
  // option does not belong to the submitted item within this organization —
  // nonexistent, foreign-tenant, wrong-item, or a broken ownership chain, all
  // reported under one code so the refusal is not an existence oracle.
  //
  // TERMINAL: the payload names an option that cannot legitimately price that
  // line, and re-sending the SAME frozen operation can only be refused again.
  // Retrying would be a loop; printing would send the kitchen food nobody can
  // be charged for correctly. The cashier re-picks the modifier from the live
  // menu, which produces a fresh operation.
  //
  // Deliberately NOT a cue to reprice or to drop the offending modifier and
  // send the rest — that would silently turn a paid option into a free one.
  'modifier_option_not_in_scope',
  // KITCHEN-MODIFIER-PREP-CLASSIFIER-STALE-SNAPSHOT-FIX-021: the frozen KITCHEN
  // PREPARATION snapshot on a modifier (a 240g size option contributing 2 Meat
  // pieces, split by Cheese) no longer matches the menu the server holds, so the
  // server refused the operation rather than storing a different answer than the
  // one this device confirmed and will print.
  //
  // TERMINAL, and for a stronger reason than the codes above: the refusal is a
  // pure function of the FROZEN payload and the live menu. Re-sending the same
  // operation cannot succeed unless the owner happens to edit the menu back, so
  // a retry is a loop by construction. Printing would send the kitchen a
  // preparation instruction the server never accepted.
  //
  // The recovery is deliberately a HUMAN one: refresh the menu, re-pick the
  // affected line, and send a NEW operation with a freshly frozen snapshot. It
  // is NOT a cue to re-derive the snapshot locally and resend the same identity
  // — that would put back exactly the silent divergence this closes.
  'modifier_prep_snapshot_stale',
  'rejected',
};

/// KITCHEN-MODIFIER-PREP-CLASSIFIER-REJECTION-UX-AUDIT-FIX-022 — THE ONE menu
/// staleness policy, for every submission surface.
///
/// A refusal belongs here when the server's reason IS that our cached menu no
/// longer matches its own, so the recovery instruction we show ("re-enter the
/// order without these items" / "refresh the menu and select the item options
/// again") is only actionable once the menu has actually been reloaded.
/// Availability and preparation configuration travel ONLY with the menu — there
/// is no realtime push — so this refusal is the honest refresh point.
///
///   * `item_unavailable` (RESTAURANT-OPERATIONS-V1-001) — a manager flipped
///     availability after our last load; reload so the grid greys the item out.
///   * `modifier_prep_snapshot_stale` (021) — the owner changed a modifier's
///     preparation contribution or its classifier after the line was frozen.
///     Without a reload the cashier re-picks the SAME stale option from the
///     SAME cached menu and is refused again, forever: the message would be
///     advice the app itself makes impossible to follow.
///
/// Deliberately NOT here: transport failures and timeouts (nothing says the
/// menu moved), `table_*` refusals (table state is not menu data),
/// `dispatch_mode_not_allowed` (branch configuration), `modifier_option_not_in_scope`
/// (an ownership violation, not a stale copy), payment/printer failures, and an
/// accepted idempotency replay (nothing was refused at all). Reloading on those
/// would spend a round trip and reset the grid for no reason.
///
/// One predicate rather than a condition per widget: the two surfaces that can
/// receive these codes (the initial outbox push and the Add-items terminal
/// refusal) must not be able to disagree about what "stale menu" means.
bool shouldRefreshMenuForSubmissionError(String? errorCode) =>
    errorCode == 'item_unavailable' ||
    errorCode == 'modifier_prep_snapshot_stale';

/// A selected modifier on an [OrderSubmissionItem] — mirrors an element of the
/// per-item `modifiers[]` array `app.submit_order` validates and snapshots
/// into `order_item_modifiers` (RF-052, D-008). [priceMinorSnapshot] is a
/// SIGNED integer minor-unit UNIT delta.
///
/// MONEY-CODEX-FINAL-CLOSURE-005 (F9): this said the server counts the delta
/// "once per line", which is the superseded formula A. It does not.
/// `app.submit_order` computes
///
///     line_total = item_quantity × (unit_price_snapshot
///                                   + Σ(price_minor_snapshot × modifier_qty))
///                  − line_discount
///
/// so the delta is counted once per MODIFIER unit and then again per ITEM unit.
/// A cart line of 2 burgers each with 1 paid 240g upgrade is charged the
/// upgrade twice, not once (MONEY-PRICING-FORMULA-002A).
class OrderSubmissionModifier {
  const OrderSubmissionModifier({
    required this.modifierOptionId,
    required this.optionNameSnapshot,
    this.modifierNameSnapshot,
    required this.priceMinorSnapshot,
    this.quantity = 1,
    this.meatSnapshot,
  });

  final String modifierOptionId;
  final String optionNameSnapshot;
  final String? modifierNameSnapshot;
  final int priceMinorSnapshot;

  /// Units of this option (>= 1) — `order_item_modifiers.quantity`.
  final int quantity;

  /// KITCHEN-MEAT-001: the ORDER-TIME (D-008) snapshot of the option's meat
  /// contribution (`order_item_modifiers.meat_snapshot`). Non-money
  /// ({quantity,unit}); the KDS multiplies it by this modifier's [quantity] and
  /// the item quantity to build the whole-order meat total. Null when the option
  /// carries no meat.
  final KitchenMeat? meatSnapshot;

  Map<String, Object?> toJson() => <String, Object?>{
    'modifier_option_id': modifierOptionId,
    'option_name_snapshot': optionNameSnapshot,
    'modifier_name_snapshot': modifierNameSnapshot,
    'price_minor_snapshot': priceMinorSnapshot,
    'quantity': quantity,
    // Emitted ONLY when present so the pre-feature wire shape (+ the server's
    // idempotency fingerprint) is unchanged for meat-less options.
    if (meatSnapshot != null) 'meat_snapshot': meatSnapshot!.toJson(),
  };
}

/// A single line on an [OrderSubmissionPayload]. Money is integer minor units
/// only (DECISION D-007); the name + unit price are snapshots captured at order
/// time (DECISION D-008), never recomputed from a live menu. [lineTotalMinor]
/// follows the server formula corrected in MONEY-PRICING-FORMULA-002A,
/// `qty × (unit + Σmodifiers)`. [unitPriceMinorSnapshot] stays the BARE unit
/// price and each modifier's `price_minor_snapshot` stays its UNIT delta —
/// neither is pre-multiplied on the wire.
///
/// WHAT THE SERVER ACTUALLY CHECKS, stated accurately (F9). This said "the
/// server recomputes and rejects any mismatch", which overstates the contract.
/// Precisely:
///
///  1. `app.submit_order` recomputes ALL of the item and modifier arithmetic
///     itself, from the order-time snapshots on the wire — each modifier as
///     `price_minor_snapshot × modifier_qty`, summed, added to the bare unit
///     price, and multiplied by the item quantity;
///  2. it validates only the AGGREGATE: `p_client_subtotal_minor` must equal
///     the recomputed subtotal, or the whole submit is refused;
///  3. it never reads this per-line field back for comparison. The stored
///     `order_items.line_total_minor` is the server's own computation.
///
/// So [lineTotalMinor] is NOT independently trusted as authoritative — a wrong
/// value here is caught only when it moves the subtotal, and two compensating
/// line errors would pass. Send the exact 002A figure; do not rely on the
/// server to correct this field.
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

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: how this order is dispatched to the
/// kitchen. [kds] (the default) is the normal KDS active workflow. [directPrint]
/// is used ONLY when the branch is a VERIFIED printer_only branch (no KDS device):
/// the server routes the order OUT of the KDS board and rests it at `served` so it
/// can complete on the UNCHANGED settlement rule and free its table. The wire
/// value is only emitted for [directPrint] — a [kds] order keeps the exact
/// pre-feature op shape (the server defaults a missing dispatch_mode to 'kds').
enum OrderDispatchMode {
  kds('kds'),
  directPrint('direct_print');

  const OrderDispatchMode(this.wire);

  final String wire;
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
    this.customerPhone,
    this.dispatchMode = OrderDispatchMode.kds,
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

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL customer phone (non-money
  /// display string; see [normalizeCustomerPhone]). Trimmed + empty->null +
  /// validated upstream; the server re-validates. Reaches the receipt + the
  /// kitchen ticket. Never an identifier / idempotency key / log value.
  final String? customerPhone;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the kitchen dispatch mode (default
  /// [OrderDispatchMode.kds]). Set to [OrderDispatchMode.directPrint] ONLY for a
  /// VERIFIED printer_only branch so the order closes without a KDS device.
  final OrderDispatchMode dispatchMode;

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
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL phone travels in the
    // durable body; the transport (_buildOrderSubmitOp) forwards it to the server
    // ONLY when present, so a phone-less op keeps the exact pre-feature fingerprint.
    'customer_phone': customerPhone,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'order_items': items.map((i) => i.toJson()).toList(growable: false),
    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: emit dispatch_mode ONLY for a
    // direct_print order (a VERIFIED printer_only branch). A kds order keeps the
    // EXACT pre-feature durable body + transport op shape — no dispatch_mode key at
    // all (the server + the transport both default a missing value to 'kds'). This
    // is what makes a printer_only dine-in order rest at served and close on
    // settlement, while every existing kds order is byte-unchanged.
    if (dispatchMode == OrderDispatchMode.directPrint)
      'dispatch_mode': dispatchMode.wire,
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
    this.customerPhone,
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

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL customer phone (non-money),
  /// so the confirmation/receipt can show it without decoding the raw payload.
  final String? customerPhone;

  /// RF-114 durable-outbox persistence (integer minor money only, D-007).
  Map<String, Object?> toJson() => <String, Object?>{
    'order_number': orderNumber,
    'order_type': orderType == OrderType.dineIn ? 'dine_in' : 'takeaway',
    'table_label': tableLabel,
    'item_count': itemCount,
    'subtotal_minor': subtotalMinor,
    'currency_code': currencyCode,
    'customer_name': customerName,
    'customer_phone': customerPhone,
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
    customerPhone: json['customer_phone'] as String?,
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
    this.lastErrorDetail,
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

  /// RESTAURANT-OPERATIONS-V1-001: SAFE display detail for a typed rejection —
  /// today only `item_unavailable` uses it (the joined blocked-item names the
  /// server echoed back from OUR OWN payload snapshots). Never raw backend
  /// JSON; null for every other outcome.
  final String? lastErrorDetail;

  /// REVIEW B2: TRUE when the server durably rejected THIS operation identity
  /// for a business reason — replaying the same identity returns the SAME
  /// stored rejection forever, so no Retry control may be offered and no
  /// auto-sweep may waste attempts on it. The honest recovery is the typed
  /// explanation already shown plus a deliberate NEW order.
  bool get isPermanentBusinessRejection =>
      syncState == OutboxSyncState.rejected &&
      kPermanentRejectionCodes.contains(lastErrorCode);

  /// KITCHEN-DISPATCH-ENFORCE-001 — TRUE when this entry is a permanently
  /// rejected **`order.submit`**, i.e. the server NEVER created an order for it.
  ///
  /// `app.sync_push` dispatches every operation inside its own `EXCEPTION`
  /// subtransaction and validates `order.submit` (payload shape, customer phone,
  /// dispatch mode, order-type/table rules, item availability) **before**
  /// `app.submit_order` inserts anything. So a PERMANENT rejection of an
  /// `order.submit` means there is no `orders` row — whatever the typed code.
  /// Any surface that would act on a server order (pay, pay later, discount,
  /// void, receipt, kitchen ticket, complete) must therefore be withheld.
  ///
  /// Scoped deliberately to `order.submit`: a permanent rejection of a LATER
  /// operation (a payment, a discount) says nothing about whether the order
  /// itself exists, so it must never be treated as a never-created shell. A
  /// retryable/unknown failure is likewise excluded — it has no durable verdict.
  bool get isNeverCreatedOrderSubmit =>
      operationType == 'order.submit' && isPermanentBusinessRejection;

  /// SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007 — whether this entry
  /// may leave the active retry queue on an explicit operator action.
  ///
  /// DELIBERATELY the narrowest provable class: a permanently-rejected
  /// `order.submit`. `app.sync_push` validates and dispatches every operation
  /// inside its own subtransaction and rejects an `order.submit` BEFORE
  /// `app.submit_order` inserts anything, so a permanent rejection of one is
  /// positive proof that NO `orders` row exists — nothing is orphaned by
  /// removing the local record, and there is no authoritative server order to
  /// reconcile against.
  ///
  /// Everything else stays, on purpose:
  ///   * `pending` / `created` / `in_flight` — the server may be about to own
  ///     it, or already does;
  ///   * `dead`, and a `rejected` carrying an UNRECOGNISED code — no positive
  ///     server verdict was recorded, so a replay is still meaningful;
  ///   * `conflict` / `resolved` — a person has to settle them;
  ///   * a permanent rejection of a LATER operation (a payment, a discount) —
  ///     it says nothing about whether the ORDER exists, which is exactly why
  ///     [isNeverCreatedOrderSubmit] is scoped to `order.submit`;
  ///   * an unreadable record — never decoded, so never in this list at all; it
  ///     is preserved verbatim and counted by the storage-health surface.
  bool get isDismissibleResolvedFailure => isNeverCreatedOrderSubmit;

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
    if (lastErrorDetail != null) 'last_error_detail': lastErrorDetail,
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
      lastErrorDetail: json['last_error_detail'] as String?,
    );
  }

  OutboxEntry copyWith({
    OutboxSyncState? syncState,
    int? attemptCount,
    String? lastErrorCode,
    String? lastErrorDetail,
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
    lastErrorDetail: clearError
        ? null
        : (lastErrorDetail ?? this.lastErrorDetail),
  );
}
