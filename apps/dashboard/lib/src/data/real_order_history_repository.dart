/// Real-mode order-history repository (ORDERS-HISTORY-001).
///
/// Reads the `public.owner_order_history` (paginated LIST) and
/// `public.owner_order_detail` (single-order DETAIL) RPCs — GUC-free,
/// financial-read gated, RLS-safe, integer-minor money (D-007/D-008) — over the
/// SAME authenticated anon-key transport the rest of the real dashboard uses
/// (the GoTrue session rides the client; identity is server-derived).
///
/// FAIL-CLOSED: with no transport/scope it throws [RealRepoNotWiredError]; a
/// transport failure or a rejected (`ok != true`) body throws
/// [OrderHistoryException] — never fabricated data, never a silent demo
/// fallback. A permission / tenant / auth denial stays fail-closed (it is NOT
/// treated as "missing" and never falls back).
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_history_models.dart';
import 'order_history_repository.dart';

/// Reads order history + detail from the ORDERS-HISTORY-001 RPCs.
class RealOrderHistoryRepository implements OrderHistoryRepository {
  const RealOrderHistoryRepository(this.config, {this.scope, this.transport});

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the reads are scoped to.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  @override
  Future<OrderHistoryPage> loadHistory(
    OrderHistoryQuery query, {
    String? cursor,
  }) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'order-history: no authenticated transport/scope - real read not wired',
      );
    }
    final Object? raw;
    try {
      raw = await t.invoke('owner_order_history', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': m.restaurantId,
        'p_branch_id': m.branchId,
        'p_range': query.range.wire,
        'p_search': query.searchOrNull,
        'p_status': query.status.wire,
        'p_order_type': query.orderType.wire,
        'p_payment': query.payment.wire,
        'p_limit': 25,
        'p_cursor': cursor,
      });
    } on SyncTransportException {
      throw const OrderHistoryException(
        'owner_order_history transport failure',
      );
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const OrderHistoryException('owner_order_history rejected');
    }
    final currency = (raw['currency_code'] ?? '').toString();
    final ordersRaw = raw['orders'];
    final rows = <OrderHistoryRow>[];
    if (ordersRaw is List) {
      for (final row in ordersRaw) {
        if (row is! Map) continue;
        rows.add(_row(row, currency));
      }
    }
    return OrderHistoryPage(
      rows: rows,
      hasMore: raw['has_more'] == true,
      nextCursor: _strOrNull(raw['next_cursor']),
    );
  }

  @override
  Future<OrderDetail> loadDetail(String orderId) async {
    final t = transport;
    final m = scope;
    if (t == null || m == null) {
      throw const RealRepoNotWiredError(
        'order-history: no authenticated transport/scope - real read not wired',
      );
    }
    final Object? raw;
    try {
      raw = await t.invoke('owner_order_detail', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': m.restaurantId,
        'p_branch_id': m.branchId,
        'p_order_id': orderId,
      });
    } on SyncTransportException {
      throw const OrderHistoryException('owner_order_detail transport failure');
    }
    if (raw is! Map || raw['ok'] != true) {
      throw const OrderHistoryException('owner_order_detail rejected');
    }
    final order = raw['order'];
    if (order is! Map) {
      throw const OrderHistoryException('owner_order_detail empty');
    }
    final currency = (order['currency_code'] ?? raw['currency_code'] ?? '')
        .toString();
    return _detail(order.cast<String, dynamic>(), currency);
  }

  OrderHistoryRow _row(Map row, String currency) {
    final method = _strOrNull(row['payment_method']);
    return OrderHistoryRow(
      orderId: (row['order_id'] ?? '').toString(),
      orderCode: (row['order_code'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      orderType: (row['order_type'] ?? '').toString(),
      createdAtLabel: (row['created_at'] ?? '').toString(),
      itemCount: _int(row['item_count']),
      grandTotalMinor: _int(row['grand_total_minor']),
      currencyCode: currency,
      paid: (row['payment_status'] ?? '').toString() == 'paid',
      receiptNumber: _strOrNull(row['receipt_number']),
      customerName: _strOrNull(row['customer_name']),
      tableLabel: _strOrNull(row['table_label']),
      staffName: _strOrNull(row['staff_name']),
      paymentMethod: method,
      paidAmountMinor: _intOrNull(row['paid_amount_minor']),
    );
  }

  OrderDetail _detail(Map<String, dynamic> order, String currency) {
    final itemsRaw = order['items'];
    final paymentsRaw = order['payments'];
    return OrderDetail(
      orderId: (order['order_id'] ?? '').toString(),
      orderCode: (order['order_code'] ?? '').toString(),
      status: (order['status'] ?? '').toString(),
      orderType: (order['order_type'] ?? '').toString(),
      currencyCode: currency,
      subtotalMinor: _int(order['subtotal_minor']),
      discountTotalMinor: _int(order['discount_total_minor']),
      taxTotalMinor: _int(order['tax_total_minor']),
      grandTotalMinor: _int(order['grand_total_minor']),
      createdAtLabel: _strOrNull(order['created_at']),
      customerName: _strOrNull(order['customer_name']),
      tableLabel: _strOrNull(order['table_label']),
      branchName: _strOrNull(order['branch_name']),
      staffName: _strOrNull(order['staff_name']),
      receiptNumber: _strOrNull(order['receipt_number']),
      notes: _strOrNull(order['notes']),
      items: itemsRaw is List
          ? itemsRaw.whereType<Map>().map(_item).toList(growable: false)
          : const [],
      payments: paymentsRaw is List
          ? paymentsRaw.whereType<Map>().map(_payment).toList(growable: false)
          : const [],
    );
  }

  OrderDetailItem _item(Map raw) {
    final modsRaw = raw['modifiers'];
    final prepRaw = raw['prep_snapshot'];
    return OrderDetailItem(
      name: (raw['name'] ?? '').toString(),
      quantity: _int(raw['quantity']),
      unitPriceMinor: _int(raw['unit_price_minor']),
      lineDiscountMinor: _int(raw['line_discount_minor']),
      lineTotalMinor: _int(raw['line_total_minor']),
      notes: _strOrNull(raw['notes']),
      modifiers: modsRaw is List
          ? modsRaw.whereType<Map>().map(_modifier).toList(growable: false)
          : const [],
      prepComponents: prepRaw is List
          ? prepRaw
                .whereType<Map>()
                .map(_prep)
                .whereType<OrderPrepComponent>()
                .toList(growable: false)
          : const [],
    );
  }

  OrderDetailModifier _modifier(Map raw) {
    final meat = raw['meat_snapshot'];
    num? meatQty;
    String? meatUnit;
    if (meat is Map) {
      meatQty = _numOrNull(meat['quantity']);
      meatUnit = _strOrNull(meat['unit']);
    }
    return OrderDetailModifier(
      optionName: (raw['option_name'] ?? '').toString(),
      modifierName: _strOrNull(raw['modifier_name']),
      quantity: _int(raw['quantity'], fallback: 1),
      priceMinor: _int(raw['price_minor']),
      meatQuantity: (meatUnit == null) ? null : meatQty,
      meatUnit: (meatQty == null) ? null : meatUnit,
    );
  }

  static OrderPrepComponent? _prep(Map raw) {
    final name = _strOrNull(raw['name']);
    if (name == null) return null;
    final qty = _numOrNull(raw['quantity']);
    if (qty == null) return null;
    return OrderPrepComponent(
      name: name,
      quantity: qty,
      unit: _strOrNull(raw['unit']),
    );
  }

  OrderPayment _payment(Map raw) => OrderPayment(
    method: (raw['method'] ?? '').toString(),
    status: (raw['status'] ?? '').toString(),
    amountMinor: _int(raw['amount_minor']),
    tenderedMinor: _int(raw['tendered_minor']),
    changeMinor: _int(raw['change_minor']),
    receiptNumber: _strOrNull(raw['receipt_number']),
    createdAtLabel: _strOrNull(raw['created_at']),
  );

  static int _int(Object? value, {int fallback = 0}) =>
      value is int ? value : int.tryParse('$value') ?? fallback;

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    return value is int ? value : int.tryParse('$value');
  }

  static num? _numOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse('$value');
  }

  static String? _strOrNull(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
