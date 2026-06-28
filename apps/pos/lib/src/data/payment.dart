/// Payment tender method (RF-116). Only cash in this milestone (RF-054 limits
/// `payments.method` to `cash`; card/online are deferred).
enum PaymentMethod {
  cash('cash');

  const PaymentMethod(this.wire);
  final String wire;
}

/// Payment lifecycle status (RF-116). Mirrors the frozen `payments.status`
/// vocabulary (DECISION D-018 / RF-054 / STATE_MACHINES.md §5): pending →
/// tendered → completed (terminal), plus voided / failed (terminal). The demo
/// cash flow records a [completed] payment directly on confirm.
enum PaymentStatus {
  pending('pending'),
  tendered('tendered'),
  completed('completed'),
  voided('voided'),
  failed('failed');

  const PaymentStatus(this.wire);
  final String wire;

  bool get isPaid => this == completed;
}

/// A recorded cash payment (RF-116). Field-for-field this mirrors a `payments`
/// row (RF-054): the `(deviceId, localOperationId)` idempotency key (D-022),
/// integer-minor [amountMinor] / [tenderedMinor] / [changeMinor] with
/// `change = tendered - amount` (never negative), the tender [method], the
/// [status], and the [receiptNumber]. In the demo the receipt number is a
/// PROVISIONAL local id (DECISION D-021) — reconciled to a server per-branch
/// number on sync; it is NOT server-assigned.
class CashPayment {
  const CashPayment({
    required this.paymentId,
    required this.orderNumber,
    required this.deviceId,
    required this.localOperationId,
    required this.method,
    required this.status,
    required this.amountMinor,
    required this.tenderedMinor,
    required this.changeMinor,
    required this.currencyCode,
    required this.receiptNumber,
    required this.paidAt,
  });

  final String paymentId;

  /// The order this payment settles (the provisional order number, e.g.
  /// `DEMO-0001`).
  final String orderNumber;

  final String deviceId;
  final String localOperationId;
  final PaymentMethod method;
  final PaymentStatus status;

  /// Amount applied to the order (= order grand total), integer minor units.
  final int amountMinor;

  /// Cash handed over by the customer, integer minor units.
  final int tenderedMinor;

  /// Change given back: `tenderedMinor - amountMinor`, never negative.
  final int changeMinor;

  final String currencyCode;

  /// Provisional demo receipt id (DECISION D-021); not a server receipt number.
  final String receiptNumber;
  final DateTime paidAt;
}

/// A compact, immutable snapshot of the demo shift + cash-drawer context
/// (RF-116 / RF-037). Backed by the real domain `Shift` + `CashDrawerSession`
/// for status + opening float; the running [cashInDrawerMinor] is derived as
/// `openingFloat + sum(completed cash payments.amountMinor)` (MONEY_AND_TAX_SPEC
/// §14). In-memory demo only — not synced.
class ShiftContext {
  const ShiftContext({
    required this.shiftOpen,
    required this.drawerOpen,
    required this.openingFloatMinor,
    required this.cashInDrawerMinor,
    required this.lastPaymentMinor,
    required this.currencyCode,
  });

  final bool shiftOpen;
  final bool drawerOpen;
  final int openingFloatMinor;
  final int cashInDrawerMinor;

  /// The amount of the most recent completed cash payment, or null if none yet.
  final int? lastPaymentMinor;
  final String currencyCode;
}
