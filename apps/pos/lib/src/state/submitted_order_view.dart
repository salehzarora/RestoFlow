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
    this.tableLabel,
    this.outboxEntryId,
    this.localOperationId,
    this.orderId,
  });

  final String orderNumber;
  final OrderType orderType;
  final String currencyCode;
  final int subtotalMinor;
  final List<SubmittedLineView> lines;

  /// The assigned dine-in table label, or null for takeaway / unassigned.
  final String? tableLabel;

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
