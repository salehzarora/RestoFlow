import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_money/restoflow_money.dart';

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
  SubmittedOrderView copyWith({
    int? subtotalMinor,
    int? discountTotalMinor,
    int? taxTotalMinor,
  }) => SubmittedOrderView(
    orderNumber: orderNumber,
    orderType: orderType,
    currencyCode: currencyCode,
    subtotalMinor: subtotalMinor ?? this.subtotalMinor,
    lines: lines,
    discountTotalMinor: discountTotalMinor ?? this.discountTotalMinor,
    taxTotalMinor: taxTotalMinor ?? this.taxTotalMinor,
    taxRateBp: taxRateBp,
    tableLabel: tableLabel,
    customerName: customerName,
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

  /// Non-authoritative subtotal preview as [Money] (no tax/discounts).
  Money get subtotal => Money(subtotalMinor, currencyCode);

  int get itemCount => lines.fold(0, (count, line) => count + line.quantity);
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
  });

  final String name;
  final int quantity;
  final int lineTotalMinor;
  final String currencyCode;

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
