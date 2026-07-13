import 'package:restoflow_domain/restoflow_domain.dart';

import 'payment.dart';
import '../state/submitted_order_view.dart';

/// POS-ORDERS-AND-PAYMENT-001: one recent order in the cashier's local
/// recent/unpaid-orders surface.
///
/// A faithful snapshot of what THIS device submitted — the [SubmittedOrderView]
/// (order lines + integer-minor totals, D-007/D-008) plus the [CashPayment] once
/// it is settled (null while unpaid) and the local [submittedAt] time. It carries
/// no live fulfillment status (the POS does not pull orders back), so the surface
/// shows only what the device honestly knows: paid/unpaid + the order snapshot.
/// Money is never recomputed — the stored snapshot is the source of truth for
/// display and receipt reprint.
class PosRecentOrder {
  const PosRecentOrder({
    required this.order,
    required this.submittedAt,
    this.payment,
    this.voidedAt,
    this.voidReason,
    this.status,
  });

  final SubmittedOrderView order;

  /// MONEY-SETTLEMENT-CONSISTENCY-001: the last CANONICAL order status this device
  /// heard from the SERVER (`submitted` on submit, then whatever a server envelope
  /// reports — e.g. `record_payment` returns `order_status`, which is `completed` when
  /// the served+settled rule auto-closed the order).
  ///
  /// NULL means "this device has not been told" — the POS does not pull orders back, so
  /// a status change driven purely by the KDS (a bump that auto-completes a comped
  /// order) never reaches this device. We therefore treat null as NOT-known-terminal and
  /// let the SERVER be the authority: it refuses the write and the UI explains why. What
  /// we must never do is infer terminality from the payment marker.
  final String? status;

  /// The recorded payment once the order is settled, or null while unpaid.
  final CashPayment? payment;

  /// When this device submitted the order (local time; drives the window +
  /// newest-first ordering).
  final DateTime submittedAt;

  /// MONEY-VOID-001: when this order was CANCELLED (voided), or null. Set once
  /// the server confirms the void; persisted so a cancelled order stays
  /// cancelled across a restart. A cancelled order carries no payment and cannot
  /// be paid or reprinted as a receipt.
  final DateTime? voidedAt;

  /// MONEY-VOID-001: the cancellation reason (as entered by the cashier), or
  /// null. Display only — never money.
  final String? voidReason;

  String get orderNumber => order.orderNumber;
  String? get orderId => order.orderId;

  /// True once a COMPLETED payment row is attached. This is a MARKER — "was money
  /// taken?" — NOT the settlement question. It is the right test for "can we reprint a
  /// receipt?" and for the server's void guard (which blocks on a live completed
  /// payment), and the WRONG test for "does this order still owe money?".
  bool get isPaid => payment != null && payment!.status.isPaid;

  /// MONEY-SETTLEMENT-CONSISTENCY-001 — the client mirror of `app.order_is_fully_settled`:
  /// does this order still owe money?
  ///
  ///   total == 0 -> SETTLED (non-chargeable: it owes nothing and carries no payment)
  ///   total  > 0 -> settled only when the completed payment COVERS the current total
  ///   total  < 0 -> FAIL CLOSED
  ///
  /// A payment-row marker is wrong in both directions: it calls a comped order "unpaid"
  /// forever, and an UNDER-COVERED order "paid".
  bool get isFullySettled {
    if (grandTotalMinor < 0) return false;
    if (grandTotalMinor == 0) return true;
    final p = payment;
    if (p == null || !p.status.isPaid) return false;
    return p.amountMinor >= grandTotalMinor;
  }

  /// A ZERO-TOTAL (comped / 100%-discounted) order: it owes nothing, and the server
  /// REFUSES to take a payment for it (no zero-value payment, no burned receipt number).
  ///
  /// EXACTLY zero — never `<= 0`. A NEGATIVE total is not "nothing to pay", it is a MONEY
  /// DEFECT (the DB CHECK forbids it, so it should be unreachable). Treating it as
  /// non-chargeable would label a corrupt order "No charge" and hide its payment and
  /// cancel controls — silently swallowing the very thing an operator needs to see. It
  /// therefore falls through to [isFullySettled], which FAILS CLOSED on a negative total:
  /// the order reads UNPAID and keeps every control.
  bool get isNonChargeable => grandTotalMinor == 0;

  /// MONEY-VOID-001: true once the order has been cancelled (voided).
  bool get isVoided => voidedAt != null;

  /// The order is in a CANONICAL TERMINAL state as far as this device knows, so no
  /// mutation (payment, cancel/void) can succeed. `completed` is terminal and stays
  /// terminal — there is no completed -> void path (human decision).
  bool get isTerminal =>
      isVoided ||
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'voided';

  int get grandTotalMinor => order.grandTotalMinor;
  String get currencyCode => order.currencyCode;

  PosRecentOrder copyWith({
    CashPayment? payment,
    DateTime? voidedAt,
    String? voidReason,
    String? status,
  }) => PosRecentOrder(
    order: order,
    submittedAt: submittedAt,
    payment: payment ?? this.payment,
    voidedAt: voidedAt ?? this.voidedAt,
    voidReason: voidReason ?? this.voidReason,
    status: status ?? this.status,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'submitted_at': submittedAt.toIso8601String(),
    'order': _orderToJson(order),
    if (payment != null) 'payment': _paymentToJson(payment!),
    if (voidedAt != null) 'voided_at': voidedAt!.toIso8601String(),
    if (voidReason != null) 'void_reason': voidReason,
    if (status != null) 'status': status,
  };

  /// Parses a persisted recent order. Throws [FormatException] on a
  /// missing/foreign shape so a corrupt single entry is dropped on load (never
  /// crashes the POS).
  static PosRecentOrder fromJson(Map<String, Object?> json) {
    final submittedAtRaw = json['submitted_at'];
    final orderRaw = json['order'];
    if (submittedAtRaw is! String || orderRaw is! Map) {
      throw const FormatException('recent order: missing order/submitted_at');
    }
    final submittedAt = DateTime.tryParse(submittedAtRaw);
    if (submittedAt == null) {
      throw const FormatException('recent order: bad submitted_at');
    }
    final paymentRaw = json['payment'];
    final voidedAtRaw = json['voided_at'];
    final voidReasonRaw = json['void_reason'];
    return PosRecentOrder(
      order: _orderFromJson(orderRaw.cast<String, Object?>()),
      submittedAt: submittedAt,
      payment: paymentRaw is Map
          ? _paymentFromJson(paymentRaw.cast<String, Object?>())
          : null,
      voidedAt: voidedAtRaw is String ? DateTime.tryParse(voidedAtRaw) : null,
      voidReason: _strOrNull(voidReasonRaw),
      status: _strOrNull(json['status']),
    );
  }
}

// --- SubmittedOrderView (+ lines) serialization -----------------------------

Map<String, Object?> _orderToJson(SubmittedOrderView o) => <String, Object?>{
  'order_number': o.orderNumber,
  'order_type': o.orderType.name,
  'currency_code': o.currencyCode,
  'subtotal_minor': o.subtotalMinor,
  'discount_total_minor': o.discountTotalMinor,
  'tax_total_minor': o.taxTotalMinor,
  'tax_rate_bp': o.taxRateBp,
  if (o.tableLabel != null) 'table_label': o.tableLabel,
  if (o.customerName != null) 'customer_name': o.customerName,
  if (o.orderId != null) 'order_id': o.orderId,
  if (o.outboxEntryId != null) 'outbox_entry_id': o.outboxEntryId,
  if (o.localOperationId != null) 'local_operation_id': o.localOperationId,
  'lines': [for (final l in o.lines) _lineToJson(l)],
};

SubmittedOrderView _orderFromJson(Map<String, Object?> j) {
  final orderNumber = j['order_number'];
  final currencyCode = j['currency_code'];
  if (orderNumber is! String || currencyCode is! String) {
    throw const FormatException('recent order: bad order header');
  }
  final linesRaw = j['lines'];
  return SubmittedOrderView(
    orderNumber: orderNumber,
    orderType: _orderTypeFromName(j['order_type']),
    currencyCode: currencyCode,
    subtotalMinor: _int(j['subtotal_minor']),
    discountTotalMinor: _int(j['discount_total_minor']),
    taxTotalMinor: _int(j['tax_total_minor']),
    taxRateBp: _int(j['tax_rate_bp']),
    tableLabel: _strOrNull(j['table_label']),
    customerName: _strOrNull(j['customer_name']),
    orderId: _strOrNull(j['order_id']),
    outboxEntryId: _strOrNull(j['outbox_entry_id']),
    localOperationId: _strOrNull(j['local_operation_id']),
    lines: linesRaw is List
        ? [
            for (final l in linesRaw)
              if (l is Map) _lineFromJson(l.cast<String, Object?>()),
          ]
        : const <SubmittedLineView>[],
  );
}

Map<String, Object?> _lineToJson(SubmittedLineView l) => <String, Object?>{
  'name': l.name,
  'quantity': l.quantity,
  'line_total_minor': l.lineTotalMinor,
  'currency_code': l.currencyCode,
  'modifiers': l.modifiers,
  if (l.note != null) 'note': l.note,
};

SubmittedLineView _lineFromJson(Map<String, Object?> j) {
  final name = j['name'];
  final currencyCode = j['currency_code'];
  if (name is! String || currencyCode is! String) {
    throw const FormatException('recent order: bad line');
  }
  final modsRaw = j['modifiers'];
  return SubmittedLineView(
    name: name,
    quantity: _int(j['quantity']),
    lineTotalMinor: _int(j['line_total_minor']),
    currencyCode: currencyCode,
    modifiers: modsRaw is List
        ? [for (final m in modsRaw) '$m']
        : const <String>[],
    note: _strOrNull(j['note']),
  );
}

// --- CashPayment serialization ----------------------------------------------

Map<String, Object?> _paymentToJson(CashPayment p) => <String, Object?>{
  'payment_id': p.paymentId,
  'order_number': p.orderNumber,
  'device_id': p.deviceId,
  'local_operation_id': p.localOperationId,
  'method': p.method.wire,
  'status': p.status.wire,
  'amount_minor': p.amountMinor,
  'tendered_minor': p.tenderedMinor,
  'change_minor': p.changeMinor,
  'currency_code': p.currencyCode,
  'receipt_number': p.receiptNumber,
  'paid_at': p.paidAt.toIso8601String(),
  if (p.orderStatus != null) 'order_status': p.orderStatus,
};

CashPayment _paymentFromJson(Map<String, Object?> j) {
  final paidAt = DateTime.tryParse('${j['paid_at']}');
  if (paidAt == null) {
    throw const FormatException('recent order: bad payment paid_at');
  }
  return CashPayment(
    paymentId: '${j['payment_id'] ?? ''}',
    orderNumber: '${j['order_number'] ?? ''}',
    deviceId: '${j['device_id'] ?? ''}',
    localOperationId: '${j['local_operation_id'] ?? ''}',
    method: PaymentMethod.fromWire(j['method']) ?? PaymentMethod.cash,
    status: _statusFromWire(j['status']),
    amountMinor: _int(j['amount_minor']),
    tenderedMinor: _int(j['tendered_minor']),
    changeMinor: _int(j['change_minor']),
    currencyCode: '${j['currency_code'] ?? ''}',
    receiptNumber: '${j['receipt_number'] ?? ''}',
    paidAt: paidAt,
    orderStatus: _strOrNull(j['order_status']),
  );
}

OrderType _orderTypeFromName(Object? name) {
  for (final t in OrderType.values) {
    if (t.name == name) return t;
  }
  return OrderType.takeaway;
}

PaymentStatus _statusFromWire(Object? wire) {
  for (final s in PaymentStatus.values) {
    if (s.wire == wire) return s;
  }
  return PaymentStatus.completed;
}

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}
