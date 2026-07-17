import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../state/pos_session.dart';
import '../state/submitted_order_view.dart';
import 'payment.dart';

/// PSC-001C — the AUTHORITATIVE POS order detail (`public.pos_order_detail`).
///
/// The single server source for opening an existing order, entering Add items,
/// the post-addition refresh, payment review, and the COMBINED itemized
/// receipt — on ANY authorized POS device of the branch, not just the one that
/// placed the order. Header totals are integer minor units (D-007); items are
/// the order-time snapshots (D-008) with their service-round membership; the
/// at-most-one completed payment rides along for faithful reprints.
///
/// FAIL-CLOSED parse: a malformed envelope throws — pending LOCAL additions
/// must never merge into an "authoritative" view built from a guess.
class PosOrderDetail {
  const PosOrderDetail({
    required this.orderId,
    required this.orderCode,
    required this.orderType,
    required this.status,
    required this.revision,
    required this.currencyCode,
    required this.subtotalMinor,
    required this.discountTotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    required this.items,
    required this.rounds,
    this.tableLabel,
    this.customerName,
    this.receiptNumber,
    this.payment,
  });

  final String orderId;
  final String orderCode;
  final String? orderType;
  final String status;
  final int revision;
  final String currencyCode;
  final int subtotalMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;
  final String? tableLabel;
  final String? customerName;
  final String? receiptNumber;
  final List<PosOrderDetailItem> items;
  final List<PosOrderDetailRound> rounds;
  final PosOrderDetailPayment? payment;

  static PosOrderDetail? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final order = raw['order'];
    if (order is! Map) return null;
    final orderId = order['order_id'];
    final orderCode = order['order_code'];
    final status = order['status'];
    final currency = order['currency_code'];
    if (orderId is! String ||
        orderCode is! String ||
        status is! String ||
        currency is! String) {
      return null;
    }
    final items = <PosOrderDetailItem>[];
    final itemsRaw = raw['items'];
    if (itemsRaw is! List) return null;
    for (final e in itemsRaw) {
      final item = PosOrderDetailItem.fromJson(e);
      if (item == null) return null; // atomic — never a half-parsed order
      items.add(item);
    }
    final rounds = <PosOrderDetailRound>[];
    final roundsRaw = raw['rounds'];
    if (roundsRaw is! List) return null;
    for (final e in roundsRaw) {
      final round = PosOrderDetailRound.fromJson(e);
      if (round == null) return null;
      rounds.add(round);
    }
    return PosOrderDetail(
      orderId: orderId,
      orderCode: orderCode,
      orderType: order['order_type'] is String
          ? order['order_type'] as String
          : null,
      status: status,
      revision: _int(order['revision']) ?? 0,
      currencyCode: currency,
      subtotalMinor: _int(order['subtotal_minor']) ?? 0,
      discountTotalMinor: _int(order['discount_total_minor']) ?? 0,
      taxTotalMinor: _int(order['tax_total_minor']) ?? 0,
      grandTotalMinor: _int(order['grand_total_minor']) ?? 0,
      tableLabel: order['table_label'] is String
          ? order['table_label'] as String
          : null,
      customerName: order['customer_name'] is String
          ? order['customer_name'] as String
          : null,
      receiptNumber: order['receipt_number'] is String
          ? order['receipt_number'] as String
          : null,
      items: items,
      rounds: rounds,
      payment: PosOrderDetailPayment.fromJson(raw['payment']),
    );
  }
}

/// One active customer-visible item of the order (original OR added).
class PosOrderDetailItem {
  const PosOrderDetailItem({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineDiscountMinor,
    required this.lineTotalMinor,
    required this.modifiers,
    this.notes,
    this.serviceRoundId,
    this.roundNumber,
  });

  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int lineDiscountMinor;
  final int lineTotalMinor;
  final List<PosOrderDetailModifier> modifiers;
  final String? notes;

  /// Null for the ORIGINAL submission; the owning round otherwise.
  final String? serviceRoundId;
  final int? roundNumber;

  static PosOrderDetailItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['menu_item_name_snapshot'];
    final quantity = _int(raw['quantity']);
    final unit = _int(raw['unit_price_minor_snapshot']);
    if (name is! String || quantity == null || unit == null) return null;
    final mods = <PosOrderDetailModifier>[];
    final modsRaw = raw['modifiers'];
    if (modsRaw is List) {
      for (final m in modsRaw) {
        final mod = PosOrderDetailModifier.fromJson(m);
        if (mod == null) return null;
        mods.add(mod);
      }
    }
    return PosOrderDetailItem(
      name: name,
      quantity: quantity,
      unitPriceMinor: unit,
      lineDiscountMinor: _int(raw['line_discount_minor']) ?? 0,
      lineTotalMinor: _int(raw['line_total_minor']) ?? 0,
      modifiers: mods,
      notes: raw['notes'] is String ? raw['notes'] as String : null,
      serviceRoundId: raw['service_round_id'] is String
          ? raw['service_round_id'] as String
          : null,
      roundNumber: _int(raw['round_number']),
    );
  }
}

class PosOrderDetailModifier {
  const PosOrderDetailModifier({
    required this.optionName,
    required this.priceMinor,
    required this.quantity,
    this.modifierName,
  });

  final String optionName;
  final int priceMinor;
  final int quantity;
  final String? modifierName;

  static PosOrderDetailModifier? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final option = raw['option_name_snapshot'];
    if (option is! String) return null;
    return PosOrderDetailModifier(
      optionName: option,
      priceMinor: _int(raw['price_minor_snapshot']) ?? 0,
      quantity: _int(raw['quantity']) ?? 1,
      modifierName: raw['modifier_name_snapshot'] is String
          ? raw['modifier_name_snapshot'] as String
          : null,
    );
  }
}

/// One service round of the order (voided rounds included — status says so).
class PosOrderDetailRound {
  const PosOrderDetailRound({
    required this.roundId,
    required this.roundNumber,
    required this.status,
  });

  final String roundId;
  final int roundNumber;
  final String status;

  static PosOrderDetailRound? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['round_id'];
    final number = _int(raw['round_number']);
    final status = raw['status'];
    if (id is! String || number == null || status is! String) return null;
    return PosOrderDetailRound(
      roundId: id,
      roundNumber: number,
      status: status,
    );
  }
}

/// The at-most-one completed payment (enough for a faithful reprint).
class PosOrderDetailPayment {
  const PosOrderDetailPayment({
    required this.method,
    required this.amountMinor,
    required this.tenderedMinor,
    required this.changeMinor,
    this.receiptNumber,
  });

  final String method;
  final int amountMinor;
  final int tenderedMinor;
  final int changeMinor;
  final String? receiptNumber;

  static PosOrderDetailPayment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final method = raw['method'];
    if (method is! String) return null;
    return PosOrderDetailPayment(
      method: method,
      amountMinor: _int(raw['amount_minor']) ?? 0,
      tenderedMinor: _int(raw['tendered_minor']) ?? 0,
      changeMinor: _int(raw['change_minor']) ?? 0,
      receiptNumber: raw['receipt_number'] is String
          ? raw['receipt_number'] as String
          : null,
    );
  }
}

/// STRICT integer parse (D-007): ints only — a double or string is refused.
int? _int(Object? v) => v is int ? v : null;

/// Why a detail read failed — mirrors the snapshot repository's taxonomy.
enum PosOrderDetailFailure { session, transport, notFound, malformed }

class PosOrderDetailException implements Exception {
  const PosOrderDetailException(this.failure, [this.detail]);
  final PosOrderDetailFailure failure;
  final String? detail;
  @override
  String toString() => 'PosOrderDetailException(${failure.name}, $detail)';
}

abstract class OrderDetailRepository {
  Future<PosOrderDetail> fetch(String orderId);
}

/// The real read over `public.pos_order_detail` (SECURITY INVOKER wrapper of
/// the SECURITY DEFINER app fn; anon key + PIN/device session, D-011).
class RealOrderDetailRepository implements OrderDetailRepository {
  const RealOrderDetailRepository(this._transport, this._session);

  final SyncRpcTransport? _transport;
  final SyncSession? _session;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.session,
        'no authenticated PIN session on a paired device',
      );
    }
    final Object? raw;
    try {
      raw = await transport.invoke('pos_order_detail', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_order_id': orderId,
      });
    } on SyncTransportException catch (e) {
      throw PosOrderDetailException(
        PosOrderDetailFailure.transport,
        e.code ?? e.kind.name,
      );
    }
    if (raw is! Map) {
      throw const PosOrderDetailException(PosOrderDetailFailure.malformed);
    }
    if (raw['ok'] != true) {
      final error = raw['error'];
      throw PosOrderDetailException(
        error == 'order_not_found'
            ? PosOrderDetailFailure.notFound
            : PosOrderDetailFailure.session,
        error is String ? error : null,
      );
    }
    final detail = PosOrderDetail.fromJson(raw);
    if (detail == null) {
      throw const PosOrderDetailException(PosOrderDetailFailure.malformed);
    }
    return detail;
  }
}

/// Demo mode has no server orders to detail; the flow simply isn't offered
/// (the demo board never surfaces an Add-items action on a server order).
class UnavailableOrderDetailRepository implements OrderDetailRepository {
  const UnavailableOrderDetailRepository();
  @override
  Future<PosOrderDetail> fetch(String orderId) async =>
      throw const PosOrderDetailException(
        PosOrderDetailFailure.session,
        'order detail is unavailable in demo mode',
      );
}

final orderDetailRepositoryProvider = Provider<OrderDetailRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return const UnavailableOrderDetailRepository();
  return RealOrderDetailRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
  );
});

/// Builds the COMBINED receipt/order view from the AUTHORITATIVE server
/// detail — original AND added items as ONE list (locked: the customer
/// receipt never shows round sections). This is what lets a DIFFERENT POS
/// device of the branch review/reprint the complete order.
SubmittedOrderView submittedOrderViewFromDetail(
  PosOrderDetail d,
) => SubmittedOrderView(
  orderNumber: d.orderCode,
  orderType: d.orderType == 'takeaway' ? OrderType.takeaway : OrderType.dineIn,
  currencyCode: d.currencyCode,
  subtotalMinor: d.subtotalMinor,
  discountTotalMinor: d.discountTotalMinor,
  taxTotalMinor: d.taxTotalMinor,
  tableLabel: d.tableLabel,
  customerName: d.customerName,
  orderId: d.orderId,
  lines: [
    for (final i in d.items)
      SubmittedLineView(
        name: i.name,
        quantity: i.quantity,
        lineTotalMinor: i.lineTotalMinor,
        currencyCode: d.currencyCode,
        modifiers: [
          for (final m in i.modifiers)
            m.quantity > 1 ? '${m.optionName} ×${m.quantity}' : m.optionName,
        ],
        note: i.notes,
      ),
  ],
);

/// The completed payment as the receipt's [CashPayment], or null when the
/// order is unpaid. Identity fields the server detail deliberately does not
/// expose (payment id, recording device/op) are stamped with an explicit
/// 'authoritative' placeholder — the printed receipt never renders them.
CashPayment? cashPaymentFromDetail(PosOrderDetail d) {
  final p = d.payment;
  if (p == null) return null;
  return CashPayment(
    paymentId: 'authoritative',
    orderNumber: d.orderCode,
    deviceId: 'authoritative',
    localOperationId: 'authoritative',
    method: PaymentMethod.fromWire(p.method) ?? PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: p.amountMinor,
    tenderedMinor: p.tenderedMinor,
    changeMinor: p.changeMinor,
    currencyCode: d.currencyCode,
    receiptNumber: p.receiptNumber ?? d.receiptNumber ?? '',
    paidAt: DateTime.now(),
    orderId: d.orderId,
    orderStatus: d.status,
  );
}
