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
  });

  final String orderNumber;
  final OrderType orderType;
  final String currencyCode;
  final int subtotalMinor;
  final List<SubmittedLineView> lines;

  /// The assigned dine-in table label, or null for takeaway / unassigned.
  final String? tableLabel;

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
  });

  final String name;
  final int quantity;
  final int lineTotalMinor;
  final String currencyCode;

  Money get lineTotal => Money(lineTotalMinor, currencyCode);
}
