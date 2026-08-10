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

import '../analytics/dashboard_analytics_scope.dart';
import 'order_history_models.dart';
import 'order_history_repository.dart';
import '../analytics/analytics_range.dart';
import '../analytics/analytics_window.dart';

/// Reads order history + detail from the ORDERS-HISTORY-001 RPCs.
class RealOrderHistoryRepository implements OrderHistoryRepository {
  const RealOrderHistoryRepository(
    this.config, {
    this.scope,
    this.transport,
    this.analyticsScope,
  });

  /// The validated client runtime config (anon key only). Null when real mode
  /// was selected but the Supabase config was missing/invalid (fail-closed
  /// upstream in `RuntimeConfig`).
  final SupabaseBootstrapConfig? config;

  /// The active membership (org/restaurant/branch) the reads are scoped to.
  final MembershipContext? scope;

  /// The AUTHENTICATED transport. Null => not wired (fail-closed).
  final SyncRpcTransport? transport;

  /// CLIENT-E2 — the owner's selected analytics scope, or null to use whatever
  /// the membership COVERS.
  ///
  /// A business filter, never an authorization claim: the server derives its
  /// own scope from the caller and intersects whatever arrives here, so this
  /// can only narrow what is returned.
  final DashboardAnalyticsScope? analyticsScope;

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
    // CLIENT-E2: the scope the owner actually selected — NOT the membership's
    // ids. `resolveTenantContext` pins a concrete first-restaurant and
    // first-branch onto every resolved membership, so reading them here showed
    // an org owner ONE branch's orders while calling it their history. Falling
    // back to the membership's COVERAGE (role-derived, exactly as the active
    // board and the audit log already do) means even an unwired caller stops
    // narrowing silently.
    final selected = analyticsScope ?? DashboardAnalyticsScope.coveredBy(m);

    final Object? raw;
    try {
      raw = await t.invoke('owner_order_history', <String, dynamic>{
        // The organization stays the membership's — it is the authorization
        // anchor, and the selected scope is only ever a filter inside it.
        'p_organization_id': m.organizationId,
        'p_restaurant_id': selected.restaurantId,
        'p_branch_id': selected.branchId,
        'p_search': query.searchOrNull,
        'p_status': query.status.wire,
        'p_order_type': query.orderType.wire,
        'p_payment': query.payment.wire,
        // F3 — the committed window reaches the wire. Before this the call
        // sent only `p_range`, so a CUSTOM window silently fell back to
        // whatever preset token the query still carried: the Orders list
        // answered a different question from the one the owner asked.
        ...analyticsWindowParams(
          query.customWindow ??
              AnalyticsWindow.preset(
                AnalyticsRange.fromOrderHistoryRange(query.range),
              ),
        ),
        'p_limit': query.limit,
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
    // CLIENT-E2: the DETAIL call must be scoped exactly like the LIST that
    // produced the row. Leaving it pinned to the membership would mean an
    // org-wide list could show an order from the second restaurant that then
    // failed to open, because the detail lookup was still narrowed to the
    // first — a row you can see but not read.
    final selected = analyticsScope ?? DashboardAnalyticsScope.coveredBy(m);

    final Object? raw;
    try {
      raw = await t.invoke('owner_order_detail', <String, dynamic>{
        'p_organization_id': m.organizationId,
        'p_restaurant_id': selected.restaurantId,
        'p_branch_id': selected.branchId,
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
      itemCount: _count(row['item_count']),
      grandTotalMinor: _money(
        row['grand_total_minor'],
        'row',
        'grand_total_minor',
      ),
      currencyCode: currency,
      // paid | unpaid | not_chargeable, straight from the ONE server predicate.
      settlement: SettlementState.fromWire(row['payment_status']),
      receiptNumber: _strOrNull(row['receipt_number']),
      customerName: _strOrNull(row['customer_name']),
      customerPhone: _strOrNull(row['customer_phone']),
      tableLabel: _strOrNull(row['table_label']),
      staffName: _strOrNull(row['staff_name']),
      paymentMethod: method,
      paidAmountMinor: _moneyOrNull(
        row['paid_amount_minor'],
        'row',
        'paid_amount_minor',
      ),
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
      subtotalMinor: _money(
        order['subtotal_minor'],
        'detail',
        'subtotal_minor',
      ),
      discountTotalMinor: _money(
        order['discount_total_minor'],
        'detail',
        'discount_total_minor',
      ),
      taxTotalMinor: _money(
        order['tax_total_minor'],
        'detail',
        'tax_total_minor',
      ),
      grandTotalMinor: _money(
        order['grand_total_minor'],
        'detail',
        'grand_total_minor',
      ),
      createdAtLabel: _strOrNull(order['created_at']),
      customerName: _strOrNull(order['customer_name']),
      customerPhone: _strOrNull(order['customer_phone']),
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
      // The quantity MULTIPLIES the line (002A formula B:
      // line = qty x (unit + Σ mods)), so it is read as strictly as the money.
      quantity: _money(raw['quantity'], 'item', 'quantity'),
      unitPriceMinor: _money(
        raw['unit_price_minor'],
        'item',
        'unit_price_minor',
      ),
      lineDiscountMinor: _money(
        raw['line_discount_minor'],
        'item',
        'line_discount_minor',
      ),
      lineTotalMinor: _money(
        raw['line_total_minor'],
        'item',
        'line_total_minor',
      ),
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
      // Absent keeps its documented default of 1; a PRESENT value that cannot
      // be read is corruption, not a 1.
      quantity: raw['quantity'] == null
          ? 1
          : _money(raw['quantity'], 'modifier', 'quantity'),
      priceMinor: _money(raw['price_minor'], 'modifier', 'price_minor'),
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
    amountMinor: _money(raw['amount_minor'], 'payment', 'amount_minor'),
    tenderedMinor: _money(raw['tendered_minor'], 'payment', 'tendered_minor'),
    changeMinor: _money(raw['change_minor'], 'payment', 'change_minor'),
    receiptNumber: _strOrNull(raw['receipt_number']),
    createdAtLabel: _strOrNull(raw['created_at']),
  );

  /// MONEY-CODEX-FINAL-CORRECTIONS-004 (F5): read a money / quantity field
  /// EXACTLY, or fail the whole read.
  ///
  /// This replaced
  ///
  ///     static int _int(Object? value, {int fallback = 0}) =>
  ///         value is int ? value : int.tryParse('$value') ?? fallback;
  ///
  /// which was used for twelve money fields. A value this build could not read
  /// became **0**, and on a money screen 0 is not an error — it is a NUMBER.
  /// The owner saw a real order, with a real code, customer and timestamp,
  /// priced at 0.00, with nothing anywhere saying the figure was invented. It
  /// is indistinguishable from a genuinely comped order and it is the basis
  /// for decisions about staff, pricing and takings.
  ///
  /// MONEY-CODEX-FINAL-CLOSURE-005 (F5): the value must be an actual Dart `int`.
  /// Nothing is parsed, converted, rounded or stringified.
  ///
  /// The 004 version accepted a numeric String, on the theory that "PostgREST
  /// can render a bigint that way". Not on THIS path:
  /// `app.owner_order_history` / `app.owner_order_detail` return ONE jsonb
  /// document whose money keys are built by
  /// `jsonb_build_object(…, 'grand_total_minor', o.grand_total_minor, …)` from
  /// bigint columns, so they arrive as JSON numbers and decode as `int`. A
  /// String in a money field is not a wire form — it is evidence that something
  /// between the column and here reshaped the value, and a reshaped money value
  /// is precisely what must not be trusted.
  ///
  /// Accepting it also re-opened the coercion door: `int.tryParse` silently
  /// takes `'0012000'`, `' 12000'`, `'+12000'` and `'-12000'`, so a padded or
  /// sign-flipped figure would have read as a clean total. A double is refused
  /// for the same reason plus D-007 — money is integer minor units and no float
  /// may enter.
  ///
  /// Throwing is not a regression in availability: this repository's stated
  /// contract is already "never fabricated data, never a silent demo
  /// fallback", and [OrderHistoryException] is the signal it already uses. A
  /// screen that says "could not load" is honest; a screen showing 0.00 is not.
  static int _money(Object? value, String what, String key) {
    if (value is int) return value;
    throw OrderHistoryException(
      'owner order $what: $key is not an exact integer '
      '(${value == null ? 'absent/null' : value.runtimeType})',
    );
  }

  /// The optional form: absent stays absent (an unpaid order has no payment to
  /// sum), but a PRESENT value that cannot be read is still a failed read.
  static int? _moneyOrNull(Object? value, String what, String key) =>
      value == null ? null : _money(value, what, key);

  /// A count shown next to money but never multiplied into it. Kept tolerant
  /// deliberately — a wrong item count misreads a badge, it does not misstate
  /// a bill.
  static int _count(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

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
