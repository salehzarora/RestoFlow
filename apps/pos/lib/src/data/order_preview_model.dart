/// ORDER-DETAIL-PREVIEW-001 — the READ-ONLY order preview model.
///
/// A preview is a window onto what the server already stored, so this model
/// carries ORDER-TIME SNAPSHOTS and nothing else. Two rules govern every field:
///
///  * NEVER consult the live catalog. A historical order shows the name and the
///    price it was sold at, not today's. The mappers below are pure functions of
///    their input — they take no menu, no repository and no provider, so a
///    catalog substitution is structurally impossible rather than merely
///    avoided.
///  * NEVER fabricate. An absent fact is absent: no zero-valued payment that
///    would read as "paid 0", no invented method, table or timestamp. Optional
///    fields are nullable precisely so the UI can omit them honestly.
library;

import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import 'order_actions.dart' show PosPendingKind;
import 'order_detail_repository.dart';
import 'order_snapshot.dart' show PosSettlement;
import 'payment.dart';
import 'recent_order.dart';

/// Where a preview's contents came from — and therefore how much it may claim.
enum OrderPreviewSource {
  /// `public.pos_order_detail`: the server's own record, with structured
  /// modifiers, per-line unit prices, service-round membership and the
  /// authoritative header totals.
  authoritative,

  /// This device's local copy (demo, or a server read that failed). It shows
  /// what it genuinely has and OMITS the rest; it never claims to be complete.
  localCopy,
}

/// One selected modifier as the preview shows it.
class OrderPreviewModifier {
  const OrderPreviewModifier({
    required this.name,
    this.groupName,
    this.quantity,
    this.priceDeltaMinor,
  });

  /// The stored option-name snapshot (authoritative), or the already-rendered
  /// display string (local copy — where the "×N" rides inside the text).
  final String name;

  /// The stored modifier-group name, when the source knows it.
  final String? groupName;

  /// Null on a local copy: the quantity is not separable from the display text
  /// there, and guessing it by parsing the string would be inventing data.
  final int? quantity;

  /// The stored per-unit price delta in integer minor units (D-007). Null when
  /// the source does not carry it.
  final int? priceDeltaMinor;
}

/// One order line as the preview shows it.
class OrderPreviewLine {
  const OrderPreviewLine({
    required this.name,
    required this.quantity,
    required this.modifiers,
    this.unitPriceMinor,
    this.lineTotalMinor,
    this.lineDiscountMinor,
    this.note,
    this.roundNumber,
  });

  /// The stored item-name snapshot — never a current catalog name.
  final String name;
  final int quantity;
  final List<OrderPreviewModifier> modifiers;

  /// The stored per-unit price. Null on a local copy, which records only the
  /// line total.
  final int? unitPriceMinor;
  final int? lineTotalMinor;
  final int? lineDiscountMinor;
  final String? note;

  /// PSC-001C: the service round this line was added in (2+), or null for the
  /// original order. Only the authoritative source knows it.
  final int? roundNumber;

  /// Whether this line arrived as a later ADDITION rather than with the
  /// original order.
  bool get isAddition => roundNumber != null;
}

/// A REAL completed payment. This object exists only when one does.
class OrderPreviewPayment {
  const OrderPreviewPayment({
    required this.method,
    required this.amountMinor,
    required this.paidAt,
    this.tenderedMinor,
    this.changeMinor,
    this.receiptNumber,
  });

  final PaymentMethod method;
  final int amountMinor;

  /// When the money was actually taken — never the time of viewing.
  final DateTime paidAt;
  final int? tenderedMinor;
  final int? changeMinor;
  final String? receiptNumber;
}

/// Everything the read-only preview renders.
class OrderDetailPreviewModel {
  const OrderDetailPreviewModel({
    required this.source,
    required this.orderCode,
    required this.status,
    required this.currencyCode,
    required this.lines,
    this.orderId,
    this.orderType,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.createdAt,
    this.updatedAt,
    this.voidedAt,
    this.settlement,
    this.pendingKind,
    this.subtotalMinor,
    this.discountTotalMinor,
    this.taxTotalMinor,
    this.grandTotalMinor,
    this.amountDueMinor,
    this.payment,
  });

  final OrderPreviewSource source;

  /// The server order id, when this order has one.
  final String? orderId;

  /// The public order code the cashier reads aloud.
  final String orderCode;

  final OrderType? orderType;
  final String? tableLabel;
  final String? customerName;

  /// Preview-only. It is deliberately not surfaced in the Orders list.
  final String? customerPhone;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? voidedAt;

  /// The lifecycle status as the source reports it (a wire token — the UI maps
  /// it through the shared localized vocabulary, never renders it raw).
  final String status;

  final PosSettlement? settlement;

  /// THIS device's queued work for the order, reported separately from the
  /// lifecycle.
  final PosPendingKind? pendingKind;

  final String currencyCode;
  final List<OrderPreviewLine> lines;

  final int? subtotalMinor;
  final int? discountTotalMinor;
  final int? taxTotalMinor;
  final int? grandTotalMinor;

  /// What is still owed. Only ever set from an AUTHORITATIVE source, and only
  /// while money is genuinely outstanding.
  final int? amountDueMinor;

  /// Present only when a real completed payment exists.
  final OrderPreviewPayment? payment;

  bool get isAuthoritative => source == OrderPreviewSource.authoritative;
  bool get isPaid => payment != null;

  /// When the money was taken, or null when it has not been.
  DateTime? get paidAt => payment?.paidAt;

  bool get hasCustomer =>
      (customerName?.trim().isNotEmpty ?? false) ||
      (customerPhone?.trim().isNotEmpty ?? false);

  /// The AUTHORITATIVE mapper.
  ///
  /// [localPayment] is consulted ONLY when the server named no payment — the
  /// server's record always wins, matching the existing receipt precedence.
  /// [createdAt] / [updatedAt] / [settlement] are supplied by the caller
  /// because `pos_order_detail` does not carry them; they come from this
  /// device's snapshot of the same order, and stay null when it has none.
  static OrderDetailPreviewModel fromDetail(
    PosOrderDetail detail, {
    CashPayment? localPayment,
    PosPendingKind? pendingKind,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? voidedAt,
    PosSettlement? settlement,
  }) {
    final payment = _paymentOf(detail.payment, localPayment);
    return OrderDetailPreviewModel(
      source: OrderPreviewSource.authoritative,
      orderId: detail.orderId,
      orderCode: detail.orderCode,
      orderType: _orderTypeOf(detail.orderType),
      tableLabel: _clean(detail.tableLabel),
      customerName: _clean(detail.customerName),
      customerPhone: _clean(detail.customerPhone),
      createdAt: createdAt,
      updatedAt: updatedAt,
      voidedAt: voidedAt,
      status: detail.status,
      settlement: settlement,
      pendingKind: pendingKind,
      currencyCode: detail.currencyCode,
      lines: [
        for (final item in detail.items)
          OrderPreviewLine(
            // The STORED snapshots, verbatim.
            name: item.name,
            quantity: item.quantity,
            unitPriceMinor: item.unitPriceMinor,
            lineTotalMinor: item.lineTotalMinor,
            lineDiscountMinor: item.lineDiscountMinor,
            note: _clean(item.notes),
            roundNumber: item.roundNumber,
            modifiers: [
              for (final modifier in item.modifiers)
                OrderPreviewModifier(
                  name: modifier.optionName,
                  groupName: _clean(modifier.modifierName),
                  quantity: modifier.quantity,
                  priceDeltaMinor: modifier.priceMinor,
                ),
            ],
          ),
      ],
      // The header is the authority on money; the preview never re-sums lines.
      subtotalMinor: detail.subtotalMinor,
      discountTotalMinor: detail.discountTotalMinor,
      taxTotalMinor: detail.taxTotalMinor,
      grandTotalMinor: detail.grandTotalMinor,
      amountDueMinor: payment == null && detail.grandTotalMinor > 0
          ? detail.grandTotalMinor
          : null,
      payment: payment,
    );
  }

  /// The LOCAL fallback mapper — demo, or a server read that failed.
  ///
  /// It shows what this device genuinely recorded and omits the rest. It is
  /// never presented as authoritative: [source] says so, and every field a
  /// local record cannot know stays null.
  static OrderDetailPreviewModel fromLocal(PosRecentOrder order) {
    final view = order.order;
    final payment = _localPaymentOf(order.payment);
    return OrderDetailPreviewModel(
      source: OrderPreviewSource.localCopy,
      orderId: order.orderId,
      orderCode: order.orderNumber,
      orderType: order.orderType,
      tableLabel: _clean(order.tableLabel),
      customerName: _clean(view?.customerName),
      // A local row does not reliably carry the order-time phone; omit it
      // rather than showing a stale or absent value as fact.
      customerPhone: null,
      createdAt: order.snapshot?.createdAt,
      updatedAt: order.snapshot?.updatedAt,
      voidedAt: order.voidedAt,
      status: order.serverStatus ?? order.snapshot?.status ?? '',
      settlement: order.settlement,
      currencyCode: order.currencyCode,
      lines: [
        for (final line in view?.lines ?? const [])
          OrderPreviewLine(
            name: line.name,
            quantity: line.quantity,
            lineTotalMinor: line.lineTotalMinor,
            // A local line records no per-unit price and no structured
            // modifier: its modifiers are already-rendered display strings.
            note: _clean(line.note),
            modifiers: [
              for (final modifier in line.modifiers)
                OrderPreviewModifier(name: modifier),
            ],
          ),
      ],
      subtotalMinor: order.subtotalMinor,
      discountTotalMinor: order.snapshot?.discountTotalMinor,
      taxTotalMinor: order.taxTotalMinor,
      grandTotalMinor: order.grandTotalMinor,
      // Amount due is an AUTHORITATIVE claim about what is still owed; a local
      // copy is not entitled to make it.
      amountDueMinor: null,
      payment: payment,
    );
  }

  /// The server's payment wins; a local one is used only in its absence.
  static OrderPreviewPayment? _paymentOf(
    PosOrderDetailPayment? server,
    CashPayment? local,
  ) {
    if (server != null) {
      return OrderPreviewPayment(
        method: server.method,
        amountMinor: server.amountMinor,
        tenderedMinor: server.tenderedMinor,
        changeMinor: server.changeMinor,
        receiptNumber: _clean(server.receiptNumber),
        paidAt: server.paidAt,
      );
    }
    return _localPaymentOf(local);
  }

  static OrderPreviewPayment? _localPaymentOf(CashPayment? local) {
    if (local == null) return null;
    return OrderPreviewPayment(
      method: local.method,
      amountMinor: local.amountMinor,
      tenderedMinor: local.tenderedMinor,
      changeMinor: local.changeMinor,
      receiptNumber: _clean(local.receiptNumber),
      paidAt: local.paidAt,
    );
  }

  static OrderType? _orderTypeOf(String? wire) => switch (wire) {
    'dine_in' => OrderType.dineIn,
    'takeaway' => OrderType.takeaway,
    // FAIL CLOSED: an unrecognized type is omitted, never coerced into one the
    // order does not actually have.
    _ => null,
  };

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
