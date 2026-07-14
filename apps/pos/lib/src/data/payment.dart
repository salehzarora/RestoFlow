/// Payment tender method (RF-116 / RF-117). Cash plus the non-cash tenders the
/// server records as EXTERNAL — `card`, `bit`, `external` (RF-117 extends
/// `payments.method` from `cash` to `cash|card|bit|external`). A non-cash tender
/// is "record external tender" only: RestoFlow processes NO card charge, so the
/// server stamps amount = tendered = grand total, change = 0, and `close_shift`
/// sums ONLY `cash`, meaning non-cash never inflates expected cash (MONEY §14).
enum PaymentMethod {
  cash('cash'),
  card('card'),
  bit('bit'),
  externalTender('external');

  const PaymentMethod(this.wire);

  /// The DB `payments.method` string (matches the RF-117 CHECK constraint).
  final String wire;

  /// Whether this tender is physical cash (drawer movement, change due). All
  /// other tenders are externally-recorded with no change and no drawer cash.
  bool get isCash => this == PaymentMethod.cash;

  /// The [PaymentMethod] for a DB wire string, or null when unknown. Used to
  /// read the server-echoed `method` back from a `record_payment` result.
  static PaymentMethod? fromWire(Object? wire) {
    for (final m in PaymentMethod.values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
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
    this.orderId,
    this.orderStatus,
  });

  /// MONEY-SETTLEMENT-CONSISTENCY-001: the order's CANONICAL status as the SERVER
  /// reported it in this payment's envelope (`record_payment` returns `order_status`,
  /// which is `completed` when the served + fully-settled rule auto-closed the order).
  ///
  /// This is how the POS learns an order became TERMINAL, so it stops offering Cancel on
  /// it. Null on an older server (or in demo) — and null means "not told", never
  /// "not terminal": the server remains the authority.
  final String? orderStatus;

  final String paymentId;

  /// THE AUTHORITATIVE ORDER THIS PAYMENT SETTLES (`orders.id`), or null when the
  /// server has not named the order (demo / the RF-101 in-memory path) or when the
  /// record was persisted by a build that did not store it.
  ///
  /// POS-OPERATIONS-SYNC-001 (second review correction): a payment used to identify
  /// its order ONLY by [orderNumber], which is a display code and not unique. Two
  /// orders sharing a code therefore shared one payment marker — money filed against
  /// the wrong order. Association is now by [PosOrderIdentity]; this field is what
  /// makes that identity authoritative and durable.
  final String? orderId;

  /// The order's DISPLAY code (e.g. `DEMO-0001`, `#A1B2C3`) — printed on the receipt
  /// and read out to the customer. NEVER an identity: see [orderId].
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
