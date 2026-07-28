import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

import '../data/order_identity.dart';

/// Immutable UI snapshot of a locally-submitted demo order (RF-101 + RF-114).
///
/// Built from the domain `LocalOrder` at submit time so the confirmation panel
/// stays stable after the cart is cleared. Money is integer minor units
/// (DECISION D-007). [orderNumber] is a **local/provisional demo** value only
/// (e.g. `DEMO-0001`) — it is NOT a real server-assigned per-branch receipt
/// number (that is owned downstream, DECISION D-021). [orderType] and the
/// optional dine-in [tableLabel] capture the RF-114 service-mode selection.
class SubmittedOrderView {
  const SubmittedOrderView({
    required this.orderNumber,
    required this.orderType,
    required this.currencyCode,
    required this.subtotalMinor,
    required this.lines,
    this.discountTotalMinor = 0,
    this.taxTotalMinor = 0,
    this.taxRateBp = 0,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.outboxEntryId,
    this.localOperationId,
    this.orderId,
  });

  final String orderNumber;
  final OrderType orderType;
  final String currencyCode;
  final int subtotalMinor;
  final List<SubmittedLineView> lines;

  /// Order-level discount (integer minor units, D-007). 0 until a discount is
  /// applied post-submit (RF-117 part C). In real mode this is the
  /// SERVER-AUTHORITATIVE value read back from `apply_discount`; in demo mode it
  /// is computed locally with the same clamp (discount <= subtotal).
  final int discountTotalMinor;

  /// Tax (integer minor units, D-007) computed at submit from the branch tax
  /// setting (RF-117 part B), exclusive mode. 0 when tax is disabled (the
  /// default), keeping grand == subtotal for the existing demo/e2e flows.
  final int taxTotalMinor;

  /// The tax rate in integer BASIS POINTS captured at submit (0 when disabled),
  /// so the confirmation/receipt can render a "Tax (17.00%)"-style line. No
  /// float — the percent is formatted from this integer.
  final int taxRateBp;

  /// The authoritative order total: `subtotal − discount + tax`, integer minor
  /// units, never negative (the discount is clamped to the subtotal server-side
  /// and demo-side). This is the amount the customer pays.
  int get grandTotalMinor {
    final grand = subtotalMinor - discountTotalMinor + taxTotalMinor;
    return grand < 0 ? 0 : grand;
  }

  /// Copies the view, overriding the post-submit money lines (used when an
  /// order-level discount is applied and the totals must reflect the result).
  ///
  /// POS-OPERATIONS-SYNC-001 adds [subtotalMinor]: the SERVER is authoritative for
  /// the order's money after submit, and its subtotal can move (an item voided on
  /// another till, a re-rolled line). Without this the view's subtotal was
  /// structurally frozen at submit time and `grandTotalMinor` — a getter derived
  /// from it — could never tell the truth again. The order LINES are untouched:
  /// they are the order-time price snapshot (D-008) and are never recomputed.
  ///
  /// RESTAURANT-OPERATIONS-V1-001 adds [tableLabel]: a table MOVE on any till
  /// changes where the order sits, and a receipt reprinted afterwards must name
  /// the CURRENT table (the lines and prices stay order-time, D-008 — a table
  /// is service state, not money).
  SubmittedOrderView copyWith({
    int? subtotalMinor,
    int? discountTotalMinor,
    int? taxTotalMinor,
    String? tableLabel,
  }) => SubmittedOrderView(
    orderNumber: orderNumber,
    orderType: orderType,
    currencyCode: currencyCode,
    subtotalMinor: subtotalMinor ?? this.subtotalMinor,
    lines: lines,
    discountTotalMinor: discountTotalMinor ?? this.discountTotalMinor,
    taxTotalMinor: taxTotalMinor ?? this.taxTotalMinor,
    taxRateBp: taxRateBp,
    tableLabel: tableLabel ?? this.tableLabel,
    customerName: customerName,
    customerPhone: customerPhone,
    outboxEntryId: outboxEntryId,
    localOperationId: localOperationId,
    orderId: orderId,
  );

  /// The assigned dine-in table label, or null for takeaway / unassigned.
  final String? tableLabel;

  /// ORDER-CUSTOMER-001: the OPTIONAL customer display name captured at order
  /// time (already trimmed + empty->null). Shown on the confirmation + printed
  /// receipt; null when the cashier entered none. Non-money.
  final String? customerName;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: the OPTIONAL customer phone captured at
  /// order time (already trimmed/validated + empty->null). Shown on the
  /// confirmation + printed on the receipt and kitchen ticket. Non-money.
  final String? customerPhone;

  /// The client-generated order id (a UUID in real mode) this order was
  /// submitted with — `OutboxEntry.targetId` (RF-129). A real `payment.create`
  /// references it as `order_id` (RF-130); null for the RF-101 in-memory path.
  final String? orderId;

  /// Link to the client outbox entry this order was enqueued as (RF-115), so the
  /// confirmation can show live sync status. Null for the in-memory RF-101 path.
  final String? outboxEntryId;

  /// The idempotency operation id `(deviceId, localOperationId)` (DECISION
  /// D-022), shown compactly as the outbox reference.
  final String? localOperationId;

  /// THE identity of this order for association — payment, receipt, void, dedupe.
  /// The server id when we have one, this device's own operation id until then, and
  /// NEVER the display code (see [PosOrderIdentity]).
  PosOrderIdentity get identity => PosOrderIdentity.of(
    orderId: orderId,
    localOperationId: localOperationId,
    outboxEntryId: outboxEntryId,
    orderNumber: orderNumber,
  );

  /// Non-authoritative subtotal preview as [Money] (no tax/discounts).
  Money get subtotal => Money(subtotalMinor, currencyCode);

  int get itemCount => lines.fold(0, (count, line) => count + line.quantity);

  /// MENU-ORDER-001: [lines] in the canonical menu-configured PRINT order —
  /// category display order -> item display order -> line_position — used by
  /// EVERY receipt + preview + kitchen surface so they all show the SAME
  /// Dashboard-configured order. Whole line objects move, so each item's
  /// modifiers + note stay attached; legacy 0 snapshots fall back to input order.
  List<SubmittedLineView> get printOrderedLines => sortByMenuPrintOrder(
    lines,
    (l) => [l.categoryDisplayOrder, l.itemDisplayOrder, l.linePosition],
  );
}

/// An immutable single line on a [SubmittedOrderView].
class SubmittedLineView {
  const SubmittedLineView({
    required this.name,
    required this.quantity,
    required this.lineTotalMinor,
    required this.currencyCode,
    this.modifiers = const <String>[],
    this.note,
    this.categoryDisplayOrder = 0,
    this.itemDisplayOrder = 0,
    this.linePosition = 0,
  });

  final String name;
  final int quantity;
  final int lineTotalMinor;
  final String currencyCode;

  /// MENU-ORDER-001: the item's menu-configured PRINT-order keys — the category
  /// rank (order_items.category_display_order_snapshot), the item-within-category
  /// rank (item_display_order_snapshot), and the order line's original position
  /// (line_position) as the tie-breaker. On the client submit path the ranks come
  /// from the menu (via the cart line) and line_position is the 1-based cart
  /// index; on the server-backed reprint they are the immutable submit-time
  /// snapshots from pos_order_detail. 0 = unknown (falls back to input order).
  /// Non-money; used only by the shared canonical print sort.
  final int categoryDisplayOrder;
  final int itemDisplayOrder;
  final int linePosition;

  /// Selected modifier option names (order-time snapshots, D-008; a
  /// quantity-enabled option arrives pre-formatted as `name ×N`), rendered
  /// as sub-lines on the confirmation/receipt. [lineTotalMinor] already
  /// includes their price deltas × quantities (RF-052 formula).
  final List<String> modifiers;

  /// Optional cashier note for this item ("بدون بصل") — rendered under the
  /// modifiers on the confirmation/receipt/print (non-money data).
  final String? note;

  Money get lineTotal => Money(lineTotalMinor, currencyCode);
}
