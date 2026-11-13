/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION — request §3: one
/// authoritative completed CARD payment (`method = 'card'`,
/// `status = 'completed'`, `deleted_at` null) is represented as Card, never as
/// Cash, on every Dashboard reporting surface it is meant to reach.
///
/// Tests only — no production file changes. Every group and test name starts
/// with its matrix ID:
///
///  * R1 the Overview "Payment & cash summary" card, the Cash sales KPI and the
///    last cash payment, mapped by the REAL `RealOwnerReportsRepository` from an
///    `owner_report_range` payload, in real mode;
///  * R2 the payment-mix amount, meta line and donut segment;
///  * R3 the per-method daily trend strip;
///  * R4 the Shift & cash card (Collected vs Cash sales vs the drawer figures);
///  * R5 the Orders history card filter (demo repository and the real wire);
///  * R6 the order drawer's payment row;
///  * R7 the receipt preview (pure builder + HTML);
///  * R8 the shared labels, filter labels and tender colours;
///  * X1 a provider-recorded card is indistinguishable from a hand-recorded one
///    (same mapped models, same rendered text);
///  * X2 no provider marker reaches a mapped model or the screen;
///  * X3 no source under lib names a provider field (every injected wire key,
///    in snake_case and camelCase);
///  * X4 cash, Bit and external keep their labels, amounts and colours.
///
/// What the client proves and what the server computes: R1 to R4 render
/// payment figures the server has already aggregated from completed,
/// non-deleted payments only, and their fixtures hold no non-completed card
/// row; the real-wire R5 list is filtered by its fake transport, standing in
/// for `owner_order_history`. So none of them proves that pending, tendered,
/// failed, voided or deleted card rows are left out: that rests on the
/// server. Only R5 (demo repository), R6 and R7 exercise the client's own
/// completed-only selection (`completedPayment` / `isCompleted`); a deleted
/// card row is modelled as an absent payment.
///
/// Deliberately NOT asserted anywhere: the Overview Daily-summary "Cash
/// collected" row, the mixed-currency split and the `sales_summary` fallback.
/// They are the known defect DASHBOARD-COLLECTED-LABEL-001, recorded
/// separately; no test here drives the fallback path, and none may read as
/// proof that those surfaces are right.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_labels.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/dashboard_analytics_scope.dart';
import 'package:restoflow_dashboard/src/analytics/payment_tender_colors.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/orders/order_history_screen.dart';
import 'package:restoflow_dashboard/src/overview/overview_visuals.dart';
import 'package:restoflow_dashboard/src/print/order_preview_builders.dart';
import 'package:restoflow_dashboard/src/print/print_document.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_dashboard/src/state/order_history_providers.dart';
import 'package:restoflow_dashboard/src/widgets/section_card.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

// ---------------------------------------------------------------------------
// Locales, modes, palette and scope.
// ---------------------------------------------------------------------------

const List<String> _locales = ['en', 'ar', 'he'];

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

/// One instance per mode: RuntimeConfig has no `==`, so a fresh instance per
/// pump would read as a configuration change to every repository seam.
final RuntimeConfig _realMode = RuntimeConfig.test(isDemoMode: false);
final RuntimeConfig _demoMode = RuntimeConfig.test(isDemoMode: true);

/// The palette the brand theme carries — what the tender colours resolve
/// against on screen (every harness below uses this same theme).
final RestoflowBrandPalette _palette = restoflowBaseTheme()
    .extension<RestoflowBrandPalette>()!;

/// An organization owner. Its COVERAGE is the whole organization, so the real
/// repositories send no restaurant/branch filter.
MembershipContext _owner() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

// ---------------------------------------------------------------------------
// The report window, in integer minor units (ILS). The constants below are
// pairwise distinct, so a figure that lands under the wrong label cannot hide
// behind a tie.
// ---------------------------------------------------------------------------

/// ₪120.00 over 4 completed cash payments.
const int _cashMinor = 12000;

/// ₪50.00 over 2 completed card payments.
const int _cardMinor = 5000;

/// ₪20.00 over 1 completed Bit payment.
const int _bitMinor = 2000;

/// ₪10.00 over 1 completed external payment.
const int _externalMinor = 1000;

/// ₪200.00 — the server's ALL-tender collected total. Never asserted as a
/// displayed figure (the Daily-summary row it renders in is
/// DASHBOARD-COLLECTED-LABEL-001): it is an input, the payment-mix share
/// denominator, and a value that must NOT sit beside a cash label.
const int _collectedMinor =
    _cashMinor + _cardMinor + _bitMinor + _externalMinor;

/// ₪30.00 — the last CASH payment (`method = 'cash'` server-side).
const int _lastCashMinor = 3000;

/// ₪170.00 — the last closed shift's tender-neutral collected: cash + card.
const int _shiftCollectedMinor = _cashMinor + _cardMinor;

/// ₪160.00 — the shift's stored expected drawer: opening 4000 + cash 12000.
/// close_shift sums cash only, so no card amount can ever be in it.
const int _expectedCashMinor = 16000;

/// ₪159.50 counted, so the stored variance is -50 (rendered -₪0.50).
const int _countedCashMinor = 15950;
const int _varianceMinor = _countedCashMinor - _expectedCashMinor;

// ---------------------------------------------------------------------------
// Provider-like markers (X1 / X2). Synthetic: letters and hyphens only — never
// a digit run, a key-shaped string or a real provider value.
// ---------------------------------------------------------------------------

/// The keys a card integration COULD attach to a wire row, with marker values.
/// X3 hunts lib for every leaf key here and in [_markerPayload], so a key
/// added to either is scanned for too.
const Map<String, String> _markers = <String, String>{
  'provider_reference': 'MARKER-PROVIDER-REFERENCE',
  'attempt_id': 'MARKER-ATTEMPT-ID',
  'terminal_ref': 'MARKER-TERMINAL-REF',
  'credential_ref': 'MARKER-CREDENTIAL-REF',
  'local_operation_id': 'MARKER-LOCAL-OPERATION-ID',
  'approval_number': 'MARKER-APPROVAL-NUMBER',
  'voucher_number': 'MARKER-VOUCHER-NUMBER',
  'card_last4': 'MARKER-LAST-FOUR',
  'card_brand_code': 'MARKER-CARD-BRAND',
  'provider_status_code': 'MARKER-PROVIDER-STATUS',
};

/// A nested raw provider payload, as an integration might forward it.
Map<String, Object?> _markerPayload() => <String, Object?>{
  'merchant_key': 'MARKER-MERCHANT-KEY',
  'terminal_ref': 'MARKER-NESTED-TERMINAL-REF',
  'credential_ref': 'MARKER-NESTED-CREDENTIAL-REF',
  'attempt': <String, Object?>{'attempt_id': 'MARKER-NESTED-ATTEMPT-ID'},
};

/// Every marker VALUE — what X2 hunts for in models and on screen.
final List<String> _markerValues = <String>[
  ..._markers.values,
  'MARKER-MERCHANT-KEY',
  'MARKER-NESTED-TERMINAL-REF',
  'MARKER-NESTED-CREDENTIAL-REF',
  'MARKER-NESTED-ATTEMPT-ID',
];

/// [row], plus every marker key and the nested payload when [provider]. The
/// hand-recorded variant is the row exactly as given.
Map<String, dynamic> _mark(
  Map<String, dynamic> row, {
  required bool provider,
}) => provider
    ? <String, dynamic>{...row, ..._markers, 'payload': _markerPayload()}
    : row;

// ---------------------------------------------------------------------------
// owner_report_range wire payloads (the shape the RF-REPORT-004 mapping tests
// in real_owner_reports_repository_test.dart use).
// ---------------------------------------------------------------------------

Map<String, dynamic> _tender(
  String method,
  int count,
  int totalMinor, {
  required bool provider,
}) => _mark(<String, dynamic>{
  'method': method,
  'count': count,
  'total_minor': totalMinor,
}, provider: provider);

/// The window's tenders in the server's order: cash, card, bit, external.
List<Map<String, dynamic>> _tenders({
  required bool provider,
  bool withCard = true,
}) => [
  _tender('cash', 4, _cashMinor, provider: provider),
  if (withCard) _tender('card', 2, _cardMinor, provider: provider),
  _tender('bit', 1, _bitMinor, provider: provider),
  _tender('external', 1, _externalMinor, provider: provider),
];

Map<String, dynamic> _closedShift({
  required int collectedMinor,
  required bool provider,
}) => _mark(<String, dynamic>{
  'shift_id': 'shift-last',
  'branch_id': 'branch-1',
  'branch_name': 'Main',
  'opened_at': '2026-10-30 08:00',
  'closed_at': '2026-10-30 17:00',
  'opened_by_name': 'Staff A',
  'closed_by_name': 'Staff B',
  'opening_float_minor': 4000,
  'duration_minutes': 540,
  'order_count': 6,
  'collected_minor': collectedMinor,
  'cash_sales_minor': _cashMinor,
  'expected_cash_minor': _expectedCashMinor,
  'counted_cash_minor': _countedCashMinor,
  'cash_variance_minor': _varianceMinor,
}, provider: provider);

/// One `owner_report_range` answer. The comparison block carries BOTH SERVER-B
/// keys (`completed_count`, `discount_minor`), so the report proves the
/// card / bit / external history filters exist.
Map<String, dynamic> _rangePayload({
  String range = 'today',
  List<Map<String, dynamic>>? tenders,
  int collectedMinor = _collectedMinor,
  int cashMinor = _cashMinor,
  int lastCashMinor = _lastCashMinor,
  int shiftCollectedMinor = _shiftCollectedMinor,
  bool provider = false,
}) => _mark(<String, dynamic>{
  'ok': true,
  'entity': 'owner_report_range',
  'currency_code': 'ILS',
  'range': range,
  'range_start': range == 'today' ? '2026-10-30' : '2026-10-24',
  'range_end': '2026-10-30',
  'current': _mark(<String, dynamic>{
    'order_count': 8,
    'completed_count': 6,
    'open_count': 2,
    'unpaid_count': 1,
    'gross_minor': 24000,
    'discount_minor': 1500,
    'net_minor': 22500,
    'void_count': 0,
    'void_total_minor': 0,
    'collected_minor': collectedMinor,
    'cash_minor': cashMinor,
    'last_cash_payment_minor': lastCashMinor,
    'tenders': tenders ?? _tenders(provider: provider),
  }, provider: provider),
  'comparison': <String, dynamic>{
    'order_count': 5,
    'gross_minor': 18000,
    'net_minor': 17000,
    'cash_minor': 9000,
    'collected_minor': 15000,
    'completed_count': 4,
    'discount_minor': 1200,
  },
  'hourly': <dynamic>[],
  'shift_cash': _mark(<String, dynamic>{
    'closed_shift_count': 1,
    'open_shift_count': 0,
    'expected_cash_minor': _expectedCashMinor,
    'counted_cash_minor': _countedCashMinor,
    'cash_variance_minor': _varianceMinor,
    'last_closed_shift': _closedShift(
      collectedMinor: shiftCollectedMinor,
      provider: provider,
    ),
    'recent_closed_shifts': [
      _closedShift(collectedMinor: shiftCollectedMinor, provider: provider),
    ],
  }, provider: provider),
}, provider: provider);

/// A fake AUTHENTICATED transport for the Overview. It answers only
/// `owner_report_range` and records every call, so a test can prove the report
/// came through the real range mapping and never through a degrade path.
class _ReportTransport implements SyncRpcTransport {
  _ReportTransport(this._payloadFor);

  final Map<String, dynamic> Function(String range) _payloadFor;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    params.add(Map<String, dynamic>.of(p));
    if (function != 'owner_report_range') {
      throw const SyncTransportException(
        SyncTransportErrorKind.server,
        code: 'XX000',
        message: 'not part of this fixture',
      );
    }
    return _payloadFor('${p['p_range'] ?? 'today'}');
  }
}

// ---------------------------------------------------------------------------
// owner_order_history / owner_order_detail wire payloads.
// ---------------------------------------------------------------------------

Map<String, dynamic> _wireHistoryRow(
  String orderId,
  String orderCode,
  int totalMinor, {
  required bool provider,
}) => _mark(<String, dynamic>{
  'order_id': orderId,
  'order_code': orderCode,
  'receipt_number': null,
  'status': 'completed',
  'order_type': 'dine_in',
  'customer_name': null,
  'table_label': 'T4',
  'staff_name': 'Staff A',
  'created_at': '2026-10-30 12:00',
  'item_count': 1,
  'subtotal_minor': totalMinor,
  'discount_total_minor': 0,
  'tax_total_minor': 0,
  'grand_total_minor': totalMinor,
  'payment_method': 'card',
  'payment_status': 'paid',
  'paid_amount_minor': totalMinor,
}, provider: provider);

/// The server filters on each order's single COMPLETED payment
/// (`pay.method = p_payment`), so the card filter answers the two
/// completed-card orders and nothing else. This fake applies that rule itself,
/// so the real-wire R5 tests prove the request and the rendering, not the
/// server's exclusion of non-completed or deleted rows.
Map<String, dynamic> _historyPayload({
  required Object? payment,
  required bool provider,
}) {
  final rows = <Map<String, dynamic>>[
    if (payment == null || payment == 'card') ...[
      _wireHistoryRow('o-card-ok', '#ORD-A', 5000, provider: provider),
      _wireHistoryRow('o-card-retry', '#ORD-K', 5500, provider: provider),
    ],
  ];
  return _mark(<String, dynamic>{
    'ok': true,
    'entity': 'owner_order_history',
    'currency_code': 'ILS',
    'range': 'today',
    'limit': 25,
    'orders': rows,
    'has_more': false,
    'next_cursor': null,
    'count': rows.length,
  }, provider: provider);
}

Map<String, dynamic> _wireCardPayment(
  String status,
  int amountMinor, {
  required bool provider,
}) => _mark(<String, dynamic>{
  'method': 'card',
  'status': status,
  'amount_minor': amountMinor,
  'tendered_minor': amountMinor,
  'change_minor': 0,
  'receipt_number': null,
  'created_at': '2026-10-30 12:05',
}, provider: provider);

/// `owner_order_detail` returns every NON-deleted payment of any status; the
/// retry order carries the failed card attempt before the completed one.
Map<String, dynamic> _detailPayload(String orderId, {required bool provider}) {
  final retry = orderId == 'o-card-retry';
  final totalMinor = retry ? 5500 : 5000;
  return _mark(<String, dynamic>{
    'ok': true,
    'entity': 'owner_order_detail',
    'currency_code': 'ILS',
    'order': _mark(<String, dynamic>{
      'order_id': orderId,
      'order_code': retry ? '#ORD-K' : '#ORD-A',
      'receipt_number': null,
      'status': 'completed',
      'order_type': 'dine_in',
      'customer_name': null,
      'table_label': 'T4',
      'branch_name': 'Main',
      'staff_name': 'Staff A',
      'notes': null,
      'created_at': '2026-10-30 12:00',
      'currency_code': 'ILS',
      'subtotal_minor': totalMinor,
      'discount_total_minor': 0,
      'tax_total_minor': 0,
      'grand_total_minor': totalMinor,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'order_item_id': 'item-1',
          'name': 'Burger',
          'quantity': 1,
          'station_id': null,
          'notes': null,
          'unit_price_minor': totalMinor,
          'line_discount_minor': 0,
          'line_total_minor': totalMinor,
          'prep_snapshot': <Map<String, dynamic>>[],
          'modifiers': <Map<String, dynamic>>[],
        },
      ],
      'payments': <Map<String, dynamic>>[
        if (retry) _wireCardPayment('failed', totalMinor, provider: provider),
        _wireCardPayment('completed', totalMinor, provider: provider),
      ],
    }, provider: provider),
  }, provider: provider);
}

/// A fake transport for the Orders surfaces: answers `owner_order_history` the
/// way the server filters it, and `owner_order_detail` by `p_order_id`.
class _OrdersTransport implements SyncRpcTransport {
  _OrdersTransport({required this.provider});

  /// Whether every wire row carries the provider markers.
  final bool provider;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    params.add(Map<String, dynamic>.of(p));
    switch (function) {
      case 'owner_order_history':
        return _historyPayload(payment: p['p_payment'], provider: provider);
      case 'owner_order_detail':
        return _detailPayload('${p['p_order_id']}', provider: provider);
    }
    throw const SyncTransportException(
      SyncTransportErrorKind.server,
      code: 'XX000',
      message: 'not part of this fixture',
    );
  }
}

// ---------------------------------------------------------------------------
// The owner_sales_series seam (R3).
// ---------------------------------------------------------------------------

class _SeriesRepository implements OwnerSalesSeriesRepository {
  _SeriesRepository(this.series);

  final OwnerSalesSeries series;
  final List<AnalyticsRange> calls = <AnalyticsRange>[];

  @override
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
  }) async {
    calls.add(range);
    return series;
  }
}

OwnerSalesSeriesBucket _seriesDay(
  String day, {
  int cash = 0,
  int card = 0,
}) => OwnerSalesSeriesBucket(
  day: BusinessDay.tryParse(day)!,
  orderCount: 2,
  grossMinor: cash + card,
  discountMinor: 0,
  netMinor: cash + card,
  voidCount: 0,
  voidTotalMinor: 0,
  collectedMinor: cash + card,
  cashMinor: cash,
  byMethod: [
    if (cash > 0)
      OwnerSalesSeriesPaymentMethod(method: 'cash', count: 1, totalMinor: cash),
    if (card > 0)
      OwnerSalesSeriesPaymentMethod(method: 'card', count: 1, totalMinor: card),
  ],
);

/// Every day's tender breakdown holds card ONLY.
OwnerSalesSeries _cardOnlySeries() => OwnerSalesSeries(
  currencyCode: 'ILS',
  rangeWire: 'last7',
  buckets: [
    _seriesDay('2026-10-28', card: 1000),
    _seriesDay('2026-10-29', card: 3000),
    _seriesDay('2026-10-30', card: 2000),
  ],
);

/// Cash and card on the same days, plus a day with card but no cash: a strip
/// that added card into cash would draw 5000 / 3000 / 9000.
OwnerSalesSeries _cashAndCardSeries() => OwnerSalesSeries(
  currencyCode: 'ILS',
  rangeWire: 'last7',
  buckets: [
    _seriesDay('2026-10-28', cash: 4000, card: 1000),
    _seriesDay('2026-10-29', card: 3000),
    _seriesDay('2026-10-30', cash: 8000, card: 1000),
  ],
);

// ---------------------------------------------------------------------------
// owner_sales_series / owner_report_currency_breakdown wire answers (X2). R3
// and the Overview harness inject a ready-built series and currency guard, so
// these answers are what carries the markers through the REAL mappers.
// ---------------------------------------------------------------------------

/// One `owner_sales_series` answer: one day of cash 1000 and card 5000.
Map<String, dynamic> _seriesPayload({required bool provider}) =>
    _mark(<String, dynamic>{
      'ok': true,
      'currency_code': 'ILS',
      'range': 'last7',
      'buckets': [
        _mark(<String, dynamic>{
          'day': '2026-10-30',
          'order_count': 2,
          'gross_minor': 6000,
          'discount_minor': 0,
          'net_minor': 6000,
          'void_count': 0,
          'void_total_minor': 0,
          'collected_minor': 6000,
          'cash_minor': 1000,
          'by_method': [
            _mark(<String, dynamic>{
              'method': 'cash',
              'count': 1,
              'total_minor': 1000,
            }, provider: provider),
            _mark(<String, dynamic>{
              'method': 'card',
              'count': 1,
              'total_minor': 5000,
            }, provider: provider),
          ],
          'by_order_type': [
            _mark(<String, dynamic>{
              'order_type': 'dine_in',
              'order_count': 2,
              'net_minor': 6000,
            }, provider: provider),
          ],
        }, provider: provider),
      ],
    }, provider: provider);

/// One `owner_report_currency_breakdown` answer: the window is single-ILS.
Map<String, dynamic> _breakdownPayload({required bool provider}) =>
    _mark(<String, dynamic>{
      'ok': true,
      'by_currency': [
        _mark(<String, dynamic>{
          'currency_code': 'ILS',
          'order_count': 8,
          'gross_minor': 24000,
          'discount_minor': 1500,
          'net_minor': 22500,
          'collected_minor': _collectedMinor,
          'cash_minor': _cashMinor,
        }, provider: provider),
      ],
    }, provider: provider);

/// A fake AUTHENTICATED transport for those two reads. It records every call
/// and keeps every answer it served, so a test can inspect the very wire the
/// REAL repositories mapped.
class _AnalyticsTransport implements SyncRpcTransport {
  _AnalyticsTransport({required this.provider});

  /// Whether every wire row carries the provider markers.
  final bool provider;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> answers = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    calls.add(function);
    final Map<String, dynamic> answer;
    switch (function) {
      case 'owner_sales_series':
        answer = _seriesPayload(provider: provider);
      case 'owner_report_currency_breakdown':
        answer = _breakdownPayload(provider: provider);
      default:
        throw const SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'XX000',
          message: 'not part of this fixture',
        );
    }
    answers.add(answer);
    return answer;
  }
}

// ---------------------------------------------------------------------------
// Demo-repository orders (R5 / R6 / R7). The demo filter applies the SAME rule
// as the server: an order matches a method only through its single COMPLETED
// payment.
// ---------------------------------------------------------------------------

OrderPayment _pay(
  String method,
  String status,
  int amountMinor, {
  int? tenderedMinor,
  int changeMinor = 0,
}) => OrderPayment(
  method: method,
  status: status,
  amountMinor: amountMinor,
  tenderedMinor: tenderedMinor ?? amountMinor,
  changeMinor: changeMinor,
);

OrderDetail _order(
  String orderId,
  String orderCode, {
  required String status,
  required int totalMinor,
  List<OrderPayment> payments = const [],
}) => OrderDetail(
  orderId: orderId,
  orderCode: orderCode,
  status: status,
  orderType: 'dine_in',
  currencyCode: 'ILS',
  subtotalMinor: totalMinor,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: totalMinor,
  createdAtLabel: '2026-10-30 12:00',
  tableLabel: 'T4',
  branchName: 'Main',
  items: [
    OrderDetailItem(
      name: 'Burger',
      quantity: 1,
      unitPriceMinor: totalMinor,
      lineTotalMinor: totalMinor,
    ),
  ],
  payments: payments,
);

/// R5's fixture: exactly ONE order is paid by a completed card payment.
List<OrderDetail> _historyOrders() => [
  _order(
    'o-card-ok',
    '#ORD-A',
    status: 'completed',
    totalMinor: 5000,
    payments: [_pay('card', 'completed', 5000)],
  ),
  _order(
    'o-card-pending',
    '#ORD-B',
    status: 'served',
    totalMinor: 4500,
    payments: [_pay('card', 'pending', 4500)],
  ),
  _order(
    'o-card-tendered',
    '#ORD-C',
    status: 'served',
    totalMinor: 4400,
    payments: [_pay('card', 'tendered', 4400)],
  ),
  _order(
    'o-card-failed',
    '#ORD-D',
    status: 'served',
    totalMinor: 4300,
    payments: [_pay('card', 'failed', 4300)],
  ),
  _order(
    'o-card-voided',
    '#ORD-E',
    status: 'served',
    totalMinor: 4200,
    payments: [_pay('card', 'voided', 4200)],
  ),
  // The server never returns a payment whose deleted_at is set, so a deleted
  // card payment reaches the client as no payment at all.
  _order('o-card-deleted', '#ORD-F', status: 'served', totalMinor: 4100),
  _order(
    'o-cash-ok',
    '#ORD-G',
    status: 'completed',
    totalMinor: 12000,
    payments: [
      _pay('cash', 'completed', 12000, tenderedMinor: 15000, changeMinor: 3000),
    ],
  ),
  _order(
    'o-bit-ok',
    '#ORD-H',
    status: 'completed',
    totalMinor: 2000,
    payments: [_pay('bit', 'completed', 2000)],
  ),
  _order(
    'o-external-ok',
    '#ORD-J',
    status: 'completed',
    totalMinor: 1000,
    payments: [_pay('external', 'completed', 1000)],
  ),
];

/// R6 / R7: a FAILED card attempt followed by the completed card payment.
OrderDetail _retryOrder() => _order(
  'o-card-retry',
  '#ORD-K',
  status: 'completed',
  totalMinor: 5500,
  payments: [_pay('card', 'failed', 5500), _pay('card', 'completed', 5500)],
);

/// The card orders whose ONLY card row never completed.
const List<String> _neverCompletedCardOrders = [
  'o-card-pending',
  'o-card-tendered',
  'o-card-failed',
  'o-card-voided',
  'o-card-deleted',
];

DemoOrderHistoryRepository _demoOrders(List<OrderDetail> details) =>
    DemoOrderHistoryRepository(
      orders: [for (final d in details) DemoOrder(daysAgo: 0, detail: d)],
    );

// ---------------------------------------------------------------------------
// Harnesses.
// ---------------------------------------------------------------------------

/// The Overview in REAL mode, its report mapped by the real
/// [RealOwnerReportsRepository] from whatever [transport] answers.
Widget _overview({
  required String locale,
  required SyncRpcTransport transport,
  OwnerSalesSeriesRepository? series,
  Key? key,
}) => ProviderScope(
  key: key,
  overrides: [
    runtimeConfigProvider.overrideWithValue(_realMode),
    // Real mode withholds merged money until the window's currency is known.
    // These tests are about tenders, so the window is declared single-ILS.
    dashboardCurrencyGuardProvider.overrideWith(
      (ref) async => const ReportCurrencyGuard.single('ILS'),
    ),
    ownerReportsRepositoryProvider.overrideWithValue(
      RealOwnerReportsRepository(null, scope: _owner(), transport: transport),
    ),
    if (series != null)
      ownerSalesSeriesRepositoryProvider.overrideWithValue(series),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const DashboardHomeScreen(),
  ),
);

/// The Orders history surface over [repository], opened on [payment].
Widget _orders({
  required String locale,
  required RuntimeConfig mode,
  required OrderHistoryRepository repository,
  PaymentFilter payment = PaymentFilter.all,
  Key? key,
}) => ProviderScope(
  key: key,
  overrides: [
    runtimeConfigProvider.overrideWithValue(mode),
    orderHistoryRepositoryProvider.overrideWithValue(repository),
    orderHistoryQueryProvider.overrideWith(
      (ref) => OrderHistoryQuery(payment: payment),
    ),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    theme: restoflowBaseTheme(),
    home: const Scaffold(body: OrderHistoryScreen()),
  ),
);

/// A tall, wide surface so every card is laid out and on screen.
void _tallView(WidgetTester tester, {Size size = const Size(1400, 3600)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _key(String key) => find.byKey(Key(key));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

TextDirection _direction(String code) =>
    code == 'en' ? TextDirection.ltr : TextDirection.rtl;

/// Every label / value pair an [OverviewValueRow] renders under [scope], in
/// screen order. The pair is ONE row, so a value can be attributed to its
/// label rather than merely found somewhere on the card.
List<(String, String)> _valuePairs(WidgetTester tester, Finder scope) => [
  for (final row in tester.widgetList<OverviewValueRow>(
    find.descendant(of: scope, matching: find.byType(OverviewValueRow)),
  ))
    if (row.label case final Text label)
      if (row.value case final Text value) (label.data ?? '', value.data ?? ''),
];

/// The payment-mix donut's segments.
List<RestoflowDonutSegment> _segments(WidgetTester tester) => tester
    .widget<RestoflowDonutChart>(
      find.descendant(
        of: _key('payment-mix-card'),
        matching: find.byType(RestoflowDonutChart),
      ),
    )
    .segments;

/// The legend swatch colour of one payment-mix row.
Color? _swatch(WidgetTester tester, String method) {
  for (final box in tester.widgetList<Container>(
    find.descendant(
      of: _key('payment-mix-row-$method'),
      matching: find.byType(Container),
    ),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
      return decoration.color;
    }
  }
  return null;
}

/// Every Text and RichText string under [scope] (the whole tree when null),
/// in tree order.
List<String> _renderedText(WidgetTester tester, [Finder? scope]) {
  Finder within(Finder matching) => scope == null
      ? matching
      : find.descendant(of: scope, matching: matching, skipOffstage: false);
  return [
    for (final text in tester.widgetList<Text>(
      within(find.byType(Text, skipOffstage: false)),
    ))
      text.data ?? text.textSpan?.toPlainText() ?? '',
    for (final rich in tester.widgetList<RichText>(
      within(find.byType(RichText, skipOffstage: false)),
    ))
      rich.text.toPlainText(),
  ];
}

/// True when a Text reading exactly [label] under [scope] shares its nearest
/// Row with a Text reading exactly [value] — the two are ONE rendered row.
bool _rowPairs(Finder scope, String label, String value) {
  for (final labelElement
      in find.descendant(of: scope, matching: find.text(label)).evaluate()) {
    Element? row;
    labelElement.visitAncestorElements((ancestor) {
      if (ancestor.widget is Row) {
        row = ancestor;
        return false;
      }
      return true;
    });
    final found = row;
    if (found == null) continue;
    final paired = find.descendant(
      of: find.byElementPredicate((e) => identical(e, found)),
      matching: find.text(value),
    );
    if (paired.evaluate().isNotEmpty) return true;
  }
  return false;
}

Finder get _sheet => _key('order-detail-sheet');

Future<void> _openDrawer(WidgetTester tester, String orderId) async {
  final card = _key('order-card-$orderId');
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget, reason: 'the drawer for $orderId opened');
  expect(
    find.descendant(of: _sheet, matching: _key('order-detail-content')),
    findsOneWidget,
    reason: 'the detail for $orderId loaded',
  );
}

Future<void> _closeDrawer(WidgetTester tester) async {
  await tester.tap(_key('order-detail-close'));
  await tester.pumpAndSettle();
  expect(_sheet, findsNothing);
}

/// The Orders payment filter control is ON [filter] and shows [label].
void _expectPaymentFilterShows(
  WidgetTester tester,
  PaymentFilter filter,
  String label,
) {
  final control = _key('orders-payment-filter');
  expect(control, findsOneWidget);
  expect(
    tester.widget<DropdownButtonFormField<PaymentFilter>>(control).initialValue,
    filter,
  );
  final button = tester.widget<DropdownButton<PaymentFilter>>(
    find.descendant(
      of: control,
      matching: find.byType(DropdownButton<PaymentFilter>),
    ),
  );
  expect(button.value, filter);
  // The selected entry is what the closed control displays.
  final selected = button.items!.singleWhere((item) => item.value == filter);
  expect((selected.child as Text).data, label);
  expect(
    find.descendant(of: control, matching: find.text(label)),
    findsWidgets,
  );
}

/// The receipt's key/value lines as (label, value).
List<(String, String)> _kvLines(PrintDocument doc) => [
  for (final line in doc.lines)
    if (line.kind == PrintLineKind.keyValue)
      (line.left ?? '', line.right ?? ''),
];

/// The receipt's centred lines.
List<String> _centerLines(PrintDocument doc) => [
  for (final line in doc.lines)
    if (line.kind == PrintLineKind.center) line.left ?? '',
];

/// documentToHtml's markup for one plain key/value line.
String _kvHtml(String label, String value) =>
    '<span>$label</span><span class="">$value</span>';

// ---------------------------------------------------------------------------
// Field-by-field views of the mapped models (X1 / X2). The models define no
// `==`, so equality is asserted on every field, nested ones included.
// ---------------------------------------------------------------------------

Map<String, Object?> _closedShiftFields(ClosedShiftSummary s) =>
    <String, Object?>{
      'shiftId': s.shiftId,
      'branchName': s.branchName,
      'closedAtLabel': s.closedAtLabel,
      'openedAtLabel': s.openedAtLabel,
      'closedByName': s.closedByName,
      'openedByName': s.openedByName,
      'expectedCashMinor': s.expectedCashMinor,
      'countedCashMinor': s.countedCashMinor,
      'varianceMinor': s.varianceMinor,
      'openingFloatMinor': s.openingFloatMinor,
      'durationMinutes': s.durationMinutes,
      'orderCount': s.orderCount,
      'collectedMinor': s.collectedMinor,
      'cashSalesMinor': s.cashSalesMinor,
    };

Map<String, Object?> _reportFields(DashboardReport r) {
  final comparison = r.comparison;
  final shift = r.shiftCash;
  final lastShift = shift?.lastClosedShift;
  return <String, Object?>{
    'currencyCode': r.currencyCode,
    'businessDateLabel': r.businessDateLabel,
    'range': r.range.wire,
    'rangeSupported': r.rangeSupported,
    'rangeStartLabel': r.rangeStartLabel,
    'rangeEndLabel': r.rangeEndLabel,
    'grossSalesMinor': r.grossSalesMinor,
    'netSalesMinor': r.netSalesMinor,
    'discountTotalMinor': r.discountTotalMinor,
    'collectedMinor': r.collectedMinor,
    'cashSalesMinor': r.cashSalesMinor,
    'lastCashPaymentMinor': r.lastCashPaymentMinor,
    'voidTotalMinor': r.voidTotalMinor,
    'openingFloatMinor': r.openingFloatMinor,
    'expectedCashMinor': r.expectedCashMinor,
    'countedCashMinor': r.countedCashMinor,
    'orderCount': r.orderCount,
    'completedOrderCount': r.completedOrderCount,
    'openOrderCount': r.openOrderCount,
    'unpaidOrderCount': r.unpaidOrderCount,
    'voidCount': r.voidCount,
    'shiftStatus': r.shiftStatus,
    'branches': [
      for (final b in r.branches)
        [b.branchName, b.orderCount, b.netSalesMinor, b.currencyCode],
    ],
    'topItems': [
      for (final t in r.topItems)
        [
          t.menuItemId,
          t.name,
          t.quantity,
          t.lineRevenueMinor,
          t.currencyCode,
          t.orderCount,
        ],
    ],
    'recentOrders': [
      for (final o in r.recentOrders)
        [
          o.orderNumber,
          o.timeLabel,
          o.isDineIn,
          o.tableLabel,
          o.status,
          o.isPaid,
          o.totalMinor,
          o.currencyCode,
          o.hasActiveRound,
        ],
    ],
    'paymentMethods': [
      for (final p in r.paymentMethods)
        [p.method, p.count, p.totalMinor, p.currencyCode],
    ],
    'hourlyNetSales': [
      for (final h in r.hourlyNetSales) [h.hourLabel, h.netSalesMinor],
    ],
    'comparison': comparison == null
        ? null
        : [
            comparison.grossSalesMinor,
            comparison.netSalesMinor,
            comparison.orderCount,
            comparison.cashSalesMinor,
            comparison.completedOrderCount,
            comparison.discountTotalMinor,
          ],
    'shiftCash': shift == null
        ? null
        : <String, Object?>{
            'closedShiftCount': shift.closedShiftCount,
            'openShiftCount': shift.openShiftCount,
            'expectedCashMinor': shift.expectedCashMinor,
            'countedCashMinor': shift.countedCashMinor,
            'varianceMinor': shift.varianceMinor,
            'lastClosedShift': lastShift == null
                ? null
                : _closedShiftFields(lastShift),
            'recentClosedShifts': [
              for (final s in shift.recentClosedShifts) _closedShiftFields(s),
            ],
          },
    'supportsPaymentMethodHistoryFilters':
        r.supportsPaymentMethodHistoryFilters,
    'isEmpty': r.isEmpty,
  };
}

Map<String, Object?> _historyRowFields(OrderHistoryRow r) => <String, Object?>{
  'orderId': r.orderId,
  'orderCode': r.orderCode,
  'status': r.status,
  'orderType': r.orderType,
  'createdAtLabel': r.createdAtLabel,
  'itemCount': r.itemCount,
  'grandTotalMinor': r.grandTotalMinor,
  'currencyCode': r.currencyCode,
  'settlement': r.settlement.name,
  'receiptNumber': r.receiptNumber,
  'customerName': r.customerName,
  'customerPhone': r.customerPhone,
  'tableLabel': r.tableLabel,
  'staffName': r.staffName,
  'paymentMethod': r.paymentMethod,
  'paidAmountMinor': r.paidAmountMinor,
  'createdAtUtc': r.createdAtUtc?.toIso8601String(),
  'branchName': r.branchName,
  'shiftStatus': r.shiftStatus,
  'kitchenWorkOpen': r.kitchenWorkOpen,
  'editCount': r.editCount,
  'hasActiveRound': r.hasActiveRound,
};

Map<String, Object?> _paymentFields(OrderPayment p) => <String, Object?>{
  'method': p.method,
  'status': p.status,
  'amountMinor': p.amountMinor,
  'tenderedMinor': p.tenderedMinor,
  'changeMinor': p.changeMinor,
  'receiptNumber': p.receiptNumber,
  'createdAtLabel': p.createdAtLabel,
};

Map<String, Object?> _detailFields(OrderDetail d) {
  final completed = d.completedPayment;
  final edits = d.edits;
  return <String, Object?>{
    'orderId': d.orderId,
    'orderCode': d.orderCode,
    'status': d.status,
    'orderType': d.orderType,
    'currencyCode': d.currencyCode,
    'subtotalMinor': d.subtotalMinor,
    'discountTotalMinor': d.discountTotalMinor,
    'taxTotalMinor': d.taxTotalMinor,
    'grandTotalMinor': d.grandTotalMinor,
    'createdAtLabel': d.createdAtLabel,
    'customerName': d.customerName,
    'customerPhone': d.customerPhone,
    'tableLabel': d.tableLabel,
    'branchName': d.branchName,
    'staffName': d.staffName,
    'receiptNumber': d.receiptNumber,
    'notes': d.notes,
    'items': [
      for (final item in d.items)
        <String, Object?>{
          'name': item.name,
          'quantity': item.quantity,
          'unitPriceMinor': item.unitPriceMinor,
          'lineDiscountMinor': item.lineDiscountMinor,
          'lineTotalMinor': item.lineTotalMinor,
          'notes': item.notes,
          'modifiers': [
            for (final m in item.modifiers)
              [
                m.optionName,
                m.modifierName,
                m.quantity,
                m.priceMinor,
                m.meatQuantity,
                m.meatUnit,
              ],
          ],
          'prepComponents': [
            for (final c in item.prepComponents) [c.name, c.quantity, c.unit],
          ],
        },
    ],
    'payments': [for (final p in d.payments) _paymentFields(p)],
    'editCount': d.editCount,
    'hasActiveRound': d.hasActiveRound,
    'activeRoundsReady': d.activeRoundsReady,
    'edits': edits == null
        ? null
        : [
            for (final e in edits)
              [
                e.editNumber,
                e.createdAtLabel,
                e.reasonCode,
                e.reasonText,
                e.kitchenChannel,
                e.kitchenAckRequired,
                e.kitchenAckAtLabel,
                e.kitchenAckPending,
              ],
          ],
    'completedPayment': completed == null ? null : _paymentFields(completed),
    'settlement': d.settlement.name,
  };
}

Map<String, Object?> _seriesFields(OwnerSalesSeries s) => <String, Object?>{
  'currencyCode': s.currencyCode,
  'rangeWire': s.rangeWire,
  'supported': s.supported,
  'buckets': [
    for (final b in s.buckets)
      <String, Object?>{
        'day': b.day.label,
        'orderCount': b.orderCount,
        'grossMinor': b.grossMinor,
        'discountMinor': b.discountMinor,
        'netMinor': b.netMinor,
        'voidCount': b.voidCount,
        'voidTotalMinor': b.voidTotalMinor,
        'collectedMinor': b.collectedMinor,
        'cashMinor': b.cashMinor,
        'byMethod': [
          for (final m in b.byMethod) [m.method, m.count, m.totalMinor],
        ],
        'byOrderType': [
          for (final t in b.byOrderType)
            [t.orderType, t.orderCount, t.netMinor],
        ],
      },
  ],
};

Map<String, Object?> _breakdownFields(CurrencyBreakdown b) => <String, Object?>{
  'available': b.available,
  'failure': b.failure.name,
  'totals': [
    for (final t in b.totals)
      [
        t.currencyCode,
        t.orderCount,
        t.grossMinor,
        t.discountMinor,
        t.netMinor,
        t.collectedMinor,
        t.cashMinor,
      ],
  ],
};

/// The markers found anywhere in [text].
List<String> _markersIn(String text) => [
  for (final marker in _markerValues)
    if (text.contains(marker)) marker,
];

/// True when [row] is a provider-marked wire row: every marker key with its
/// marker value, plus the nested payload map.
bool _carriesMarkers(Object? row) =>
    row is Map &&
    _markers.entries.every((m) => row[m.key] == m.value) &&
    row['payload'] is Map;

// ---------------------------------------------------------------------------
// X3 — the sources scanned for provider field names: every .dart file under
// lib. Each anchored entry below pairs a path (relative to apps/dashboard)
// with an anchor proving it is the file meant.
// ---------------------------------------------------------------------------

const Map<String, String> _scannedSources = <String, String>{
  // The report, order and series models.
  'lib/src/data/demo_report.dart': 'class PaymentMethodLine',
  'lib/src/data/order_history_models.dart': 'class OrderPayment',
  'lib/src/data/owner_sales_series.dart': 'class OwnerSalesSeriesPaymentMethod',
  // The Real* repositories that map the wire into them.
  'lib/src/data/real_owner_reports_repository.dart': "'owner_report_range'",
  'lib/src/data/real_order_history_repository.dart': "'owner_order_detail'",
  'lib/src/data/real_owner_sales_series_repository.dart':
      "'owner_sales_series'",
  // The surfaces and shared mappers this file renders them through.
  'lib/src/dashboard_home_screen.dart': "'payment-summary-card'",
  'lib/src/orders/order_history_screen.dart': "'orders-payment-filter'",
  'lib/src/orders/order_detail_sheet.dart': 'completedPayment',
  'lib/src/print/order_preview_builders.dart': 'posReceiptPaid',
  'lib/src/analytics/analytics_labels.dart': 'posPaymentMethodCard',
  'lib/src/analytics/payment_tender_colors.dart': 'primaryNavy',
};

/// Every injected wire key, in snake_case and camelCase: the LEAF keys of
/// [_markers] and [_markerPayload]. The containers (`payload`, `attempt`) are
/// left out: they are ordinary words across lib.
final List<String> _providerFieldNames = () {
  final leaves = <String>{};
  void walk(Map<String, Object?> map) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (value is Map) {
        walk(value.cast<String, Object?>());
      } else {
        leaves.add(key);
      }
    }
  }

  walk(_markers);
  walk(_markerPayload());
  String camel(String snake) {
    final words = snake.split('_');
    return words.first +
        words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
  }

  return <String>[
    for (final key in leaves) ...[key, camel(key)],
  ];
}();

/// Reads a Dashboard source. The runner's cwd is apps/dashboard for a package
/// run and the repo root for CI's `flutter test apps/dashboard`.
String _readSource(String relative) {
  for (final path in [relative, 'apps/dashboard/$relative']) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('cannot find $relative (cwd: ${Directory.current.path})');
}

/// The Dashboard's lib/, whether the runner's cwd is apps/dashboard or the
/// repository root.
Directory _dashboardLib() {
  for (final path in const ['lib', 'apps/dashboard/lib']) {
    final anchor = File('$path/src/data/real_owner_reports_repository.dart');
    if (anchor.existsSync()) return Directory(path);
  }
  fail('cannot find apps/dashboard/lib (cwd: ${Directory.current.path})');
}

/// lib-relative, forward-slashed path -> content, for every .dart file under
/// lib (the same walk as the isolation suite's T4).
Map<String, String> _dashboardSources() {
  final lib = _dashboardLib();
  final base = lib.path.split(Platform.pathSeparator).join('/');
  final out = <String, String>{};
  for (final entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.split(Platform.pathSeparator).join('/');
    out['lib${path.substring(base.length)}'] = entity.readAsStringSync();
  }
  return out;
}

List<String> _providerFieldsIn(String source) => [
  for (final name in _providerFieldNames)
    if (source.contains(name)) name,
];

void main() {
  // =========================================================================
  // R1 — Overview payment summary, through the REAL owner_report_range map.
  // =========================================================================
  group('R1 Overview payment summary', () {
    for (final code in _locales) {
      testWidgets('R1 the card tender is a Card row, while the cash rows, the '
          'Cash sales KPI and the last cash payment carry cash only ($code)', (
        tester,
      ) async {
        _tallView(tester);
        final l10n = await _l10n(code);
        final transport = _ReportTransport(
          (range) => _rangePayload(range: range),
        );
        await tester.pumpWidget(_overview(locale: code, transport: transport));
        await tester.pumpAndSettle();

        // The report came through the REAL range mapping, never through a
        // degrade path (owner_daily_report / sales_summary).
        expect(transport.calls, isNotEmpty);
        expect(transport.calls.toSet(), {'owner_report_range'});
        expect(transport.params.first['p_range'], 'today');

        final summary = _key('payment-summary-card');
        expect(summary, findsOneWidget);
        expect(Directionality.of(tester.element(summary)), _direction(code));
        final pairs = _valuePairs(tester, summary);
        expect(pairs, [
          (l10n.dashboardCashSales, '₪120.00'),
          (l10n.dashboardLastCashPayment, '₪30.00'),
          (l10n.posPaymentMethodCash, '4 · ₪120.00'),
          (l10n.posPaymentMethodCard, '2 · ₪50.00'),
          (l10n.posPaymentMethodBit, '1 · ₪20.00'),
          (l10n.posPaymentMethodExternal, '1 · ₪10.00'),
        ]);

        // The card amount never sits beside a cash label, and no cash figure
        // ever sits beside the Card label.
        final cashLabels = {
          l10n.posPaymentMethodCash,
          l10n.dashboardCashSales,
          l10n.dashboardLastCashPayment,
        };
        for (final (label, value) in pairs) {
          if (cashLabels.contains(label)) {
            expect(value, isNot(contains('₪50.00')), reason: label);
            expect(value, isNot(contains('₪200.00')), reason: label);
          }
          if (label == l10n.posPaymentMethodCard) {
            expect(value, isNot(contains('₪120.00')));
            expect(value, isNot(contains('₪30.00')));
          }
        }
        expect(
          pairs.where((p) => p.$1 == l10n.posPaymentMethodCard),
          hasLength(1),
        );

        // The Cash sales KPI is the cash row alone — never card, never the
        // all-tender collected total.
        final kpi = _key('kpi-cash-sales');
        final card = tester.widget<RestoflowMetricCard>(kpi);
        expect(card.label, l10n.dashboardCashSales);
        expect(card.value, '₪120.00');
        expect(
          find.descendant(of: kpi, matching: find.text('₪120.00')),
          findsOneWidget,
        );
        for (final notCash in const ['₪50.00', '₪200.00', '₪170.00']) {
          expect(
            find.descendant(of: kpi, matching: find.text(notCash)),
            findsNothing,
          );
        }
      });
    }
  });

  // =========================================================================
  // R2 — Payment mix.
  // =========================================================================
  group('R2 Payment mix', () {
    for (final code in _locales) {
      testWidgets('R2 the card slice is labelled Card, valued at the card '
          'minor amount and painted primary navy, not accent orange ($code)', (
        tester,
      ) async {
        _tallView(tester);
        final l10n = await _l10n(code);
        await tester.pumpWidget(
          _overview(
            locale: code,
            transport: _ReportTransport((range) => _rangePayload(range: range)),
          ),
        );
        await tester.pumpAndSettle();

        // The legend row: label, amount and the count / share / average line.
        expect(
          find.descendant(
            of: _key('payment-mix-row-card'),
            matching: find.text(l10n.posPaymentMethodCard),
          ),
          findsOneWidget,
        );
        expect(_text(tester, 'payment-amount-card'), '₪50.00');
        // 5000 of 20000 collected = 25.0%; 5000 over 2 payments = ₪25.00.
        expect(
          _text(tester, 'payment-meta-card'),
          [
            l10n.dashboardRecordedPaymentsCount(2),
            l10n.dashboardShareOfCollected('25.0'),
            l10n.dashboardAvgRecordedPayment('₪25.00'),
          ].join(' · '),
        );
        expect(_swatch(tester, 'card'), _palette.primaryNavy);

        // The donut: one slice per tender, in the server's order.
        final segments = _segments(tester);
        expect(segments.map((s) => s.label).toList(), [
          l10n.posPaymentMethodCash,
          l10n.posPaymentMethodCard,
          l10n.posPaymentMethodBit,
          l10n.posPaymentMethodExternal,
        ]);
        final card = segments[1];
        expect(card.label, l10n.posPaymentMethodCard);
        expect(card.value, _cardMinor);
        expect(card.color, _palette.primaryNavy);
        expect(card.color, isNot(_palette.accentOrange));

        // Cash, Bit and external keep their own slice and colour.
        Color tender(String method) => paymentTenderColor(
          palette: _palette,
          brightness: Brightness.light,
          method: method,
        );
        expect(
          (segments[0].label, segments[0].value, segments[0].color),
          (l10n.posPaymentMethodCash, _cashMinor, _palette.accentOrange),
        );
        expect(
          (segments[2].label, segments[2].value, segments[2].color),
          (l10n.posPaymentMethodBit, _bitMinor, tender('bit')),
        );
        expect(
          (segments[3].label, segments[3].value, segments[3].color),
          (l10n.posPaymentMethodExternal, _externalMinor, tender('external')),
        );
        expect(_text(tester, 'payment-amount-cash'), '₪120.00');
        expect(_text(tester, 'payment-amount-bit'), '₪20.00');
        expect(_text(tester, 'payment-amount-external'), '₪10.00');
        expect(
          _text(tester, 'payment-meta-cash'),
          [
            l10n.dashboardRecordedPaymentsCount(4),
            l10n.dashboardShareOfCollected('60.0'),
            l10n.dashboardAvgRecordedPayment('₪30.00'),
          ].join(' · '),
        );
      });
    }
  });

  // =========================================================================
  // R3 — Per-method daily trend.
  // =========================================================================
  group('R3 Per-method trend', () {
    for (final code in _locales) {
      testWidgets('R3 a window without cash draws the CARD trend from the '
          'card amounts ($code)', (tester) async {
        _tallView(tester);
        final l10n = await _l10n(code);
        // The window recorded card only: no cash tender at all.
        final transport = _ReportTransport(
          (range) => _rangePayload(
            range: range,
            tenders: [_tender('card', 3, 6000, provider: false)],
            collectedMinor: 6000,
            cashMinor: 0,
            lastCashMinor: 0,
          ),
        );
        final series = _SeriesRepository(_cardOnlySeries());
        await tester.pumpWidget(
          _overview(locale: code, transport: transport, series: series),
        );
        await tester.pumpAndSettle();
        // Today keeps its hourly view: no series, no strip.
        expect(series.calls, isEmpty);
        expect(_key('payment-method-trend-title'), findsNothing);

        await tester.tap(_key('range-chip-last7'));
        await tester.pumpAndSettle();

        expect(transport.params.last['p_range'], 'last7');
        expect(series.calls, isNotEmpty);
        expect(series.calls.toSet(), {AnalyticsRange.last7});
        expect(
          _text(tester, 'payment-method-trend-title'),
          l10n.dashboardMethodTrendTitle(l10n.posPaymentMethodCard),
        );
        expect(
          _text(tester, 'payment-method-trend-title'),
          isNot(l10n.dashboardMethodTrendTitle(l10n.posPaymentMethodCash)),
        );
        final chart = tester.widget<RestoflowBarChart>(
          _key('payment-method-trend-chart'),
        );
        expect(chart.bars.map((b) => b.value).toList(), [1000, 3000, 2000]);
        expect(chart.peakValueLabel, '₪30.00');
      });

      testWidgets('R3 with cash in the window the strip names Cash and draws '
          'cash only — card is never added in ($code)', (tester) async {
        _tallView(tester);
        final l10n = await _l10n(code);
        final transport = _ReportTransport(
          (range) => _rangePayload(range: range),
        );
        final series = _SeriesRepository(_cashAndCardSeries());
        await tester.pumpWidget(
          _overview(locale: code, transport: transport, series: series),
        );
        await tester.pumpAndSettle();
        await tester.tap(_key('range-chip-last7'));
        await tester.pumpAndSettle();

        expect(transport.params.last['p_range'], 'last7');
        expect(series.calls.toSet(), {AnalyticsRange.last7});
        expect(
          _text(tester, 'payment-method-trend-title'),
          l10n.dashboardMethodTrendTitle(l10n.posPaymentMethodCash),
        );
        final chart = tester.widget<RestoflowBarChart>(
          _key('payment-method-trend-chart'),
        );
        final bars = chart.bars.map((b) => b.value).toList();
        // Cash per day, including the truthful 0 on the card-only day.
        expect(bars, [4000, 0, 8000]);
        expect(bars, isNot([5000, 3000, 9000]));
        expect(chart.peakValueLabel, '₪80.00');
      });
    }
  });

  // =========================================================================
  // R4 — Shift card.
  // =========================================================================
  group('R4 Shift card', () {
    for (final code in _locales) {
      testWidgets('R4 "Collected" carries every tender, "Cash sales" cash '
          'only, and expected / counted / variance never move with the card '
          'amount ($code)', (tester) async {
        _tallView(tester);
        final l10n = await _l10n(code);

        Future<
          ({
            List<String> chips,
            Map<String, String> rows,
            List<String> variances,
          })
        >
        render(int shiftCollectedMinor) async {
          await tester.pumpWidget(
            _overview(
              key: ValueKey('r4-$shiftCollectedMinor-$code'),
              locale: code,
              transport: _ReportTransport(
                (range) => _rangePayload(
                  range: range,
                  shiftCollectedMinor: shiftCollectedMinor,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final last = _key('shift-cash-last');
          expect(last, findsOneWidget);
          return (
            chips: [
              for (final t in tester.widgetList<Text>(
                find.descendant(of: last, matching: find.byType(Text)),
              ))
                t.data ?? '',
            ],
            rows: <String, String>{
              for (final row in tester.widgetList<SectionRow>(
                find.descendant(
                  of: _key('shift-cash-card'),
                  matching: find.byType(SectionRow),
                ),
              ))
                row.label: row.trailingValue,
            },
            variances: [
              for (final t in tester.widgetList<Text>(
                _key('shift-cash-variance'),
              ))
                t.data ?? '',
            ],
          );
        }

        final collectedLabel = l10n.dashboardShiftCollected;
        final cashSalesLabel = l10n.dashboardCashSales;

        // The last shift collected cash 12000 + card 5000.
        final withCard = await render(_shiftCollectedMinor);
        expect(withCard.chips, contains('$collectedLabel: ₪170.00'));
        expect(withCard.chips, contains('$cashSalesLabel: ₪120.00'));
        expect(withCard.chips, isNot(contains('$cashSalesLabel: ₪170.00')));
        expect(withCard.chips, isNot(contains('$collectedLabel: ₪120.00')));
        expect(withCard.rows, {
          l10n.dashboardShiftExpectedCash: '₪160.00',
          l10n.dashboardCountedCash: '₪159.50',
        });
        // The aggregate and the last shift's variance: stored, cash-only.
        expect(withCard.variances, ['-₪0.50', '-₪0.50']);

        // The same shift with a LARGER card amount (cash unchanged).
        final moreCard = await render(_cashMinor + 7000);
        expect(moreCard.chips, contains('$collectedLabel: ₪190.00'));
        expect(moreCard.chips, contains('$cashSalesLabel: ₪120.00'));
        expect(moreCard.rows, withCard.rows);
        expect(moreCard.variances, withCard.variances);
      });
    }
  });

  // =========================================================================
  // R5 — Orders history card filter.
  // =========================================================================
  group('R5 Orders history card filter', () {
    for (final code in _locales) {
      testWidgets('R5 the card filter keeps ONLY the order paid by a '
          'completed card payment, and the filter reads Card ($code)', (
        tester,
      ) async {
        _tallView(tester, size: const Size(1400, 2600));
        final l10n = await _l10n(code);
        final orders = _historyOrders();

        // Control: unfiltered, every fixture order is listed.
        await tester.pumpWidget(
          _orders(
            key: ValueKey('r5-all-$code'),
            locale: code,
            mode: _demoMode,
            repository: _demoOrders(orders),
          ),
        );
        await tester.pumpAndSettle();
        for (final order in orders) {
          expect(_key('order-card-${order.orderId}'), findsOneWidget);
        }

        await tester.pumpWidget(
          _orders(
            key: ValueKey('r5-card-$code'),
            locale: code,
            mode: _demoMode,
            repository: _demoOrders(orders),
            payment: PaymentFilter.card,
          ),
        );
        await tester.pumpAndSettle();

        expect(_key('orders-error'), findsNothing);
        expect(_key('orders-empty'), findsNothing);
        expect(_key('order-card-o-card-ok'), findsOneWidget);
        for (final order in orders) {
          if (order.orderId == 'o-card-ok') continue;
          expect(
            _key('order-card-${order.orderId}'),
            findsNothing,
            reason: '${order.orderId} has no completed card payment',
          );
        }
        _expectPaymentFilterShows(
          tester,
          PaymentFilter.card,
          l10n.posPaymentMethodCard,
        );
        expect(
          Directionality.of(tester.element(_key('orders-payment-filter'))),
          _direction(code),
        );
      });

      testWidgets('R5 through the real repository the list asks for card on '
          'the wire and lists the completed-card orders ($code)', (
        tester,
      ) async {
        _tallView(tester, size: const Size(1400, 2600));
        final l10n = await _l10n(code);
        final transport = _OrdersTransport(provider: false);
        await tester.pumpWidget(
          _orders(
            locale: code,
            mode: _realMode,
            repository: RealOrderHistoryRepository(
              null,
              scope: _owner(),
              transport: transport,
            ),
            payment: PaymentFilter.card,
          ),
        );
        await tester.pumpAndSettle();

        expect(transport.calls, contains('owner_order_history'));
        for (var i = 0; i < transport.calls.length; i++) {
          if (transport.calls[i] == 'owner_order_history') {
            expect(transport.params[i]['p_payment'], 'card');
          }
        }
        expect(_key('order-card-o-card-ok'), findsOneWidget);
        expect(_key('order-card-o-card-retry'), findsOneWidget);
        _expectPaymentFilterShows(
          tester,
          PaymentFilter.card,
          l10n.posPaymentMethodCard,
        );
      });
    }

    test('R5 RealOrderHistoryRepository sends p_payment = card and maps '
        'payment_method card', () async {
      final transport = _OrdersTransport(provider: false);
      final page = await RealOrderHistoryRepository(
        null,
        scope: _owner(),
        transport: transport,
      ).loadHistory(const OrderHistoryQuery(payment: PaymentFilter.card));

      expect(transport.calls, ['owner_order_history']);
      expect(transport.params.single['p_payment'], 'card');
      expect(page.rows.map((r) => r.orderId).toList(), [
        'o-card-ok',
        'o-card-retry',
      ]);
      for (final row in page.rows) {
        expect(row.paymentMethod, 'card');
        expect(row.settlement, SettlementState.paid);
      }
      expect(page.rows.map((r) => r.paidAmountMinor).toList(), [5000, 5500]);
    });
  });

  // =========================================================================
  // R6 — Order drawer.
  // =========================================================================
  group('R6 Order drawer', () {
    for (final code in _locales) {
      testWidgets('R6 a completed card reads Card + amount; card rows that '
          'never completed fall back to the settlement row; cash, Bit and '
          'external keep their own labels ($code)', (tester) async {
        _tallView(tester, size: const Size(1400, 2800));
        final l10n = await _l10n(code);
        await tester.pumpWidget(
          _orders(
            locale: code,
            mode: _demoMode,
            repository: _demoOrders([..._historyOrders(), _retryOrder()]),
          ),
        );
        await tester.pumpAndSettle();
        final card = l10n.posPaymentMethodCard;

        // A completed card, alone and after a FAILED card attempt.
        for (final (orderId, amount) in const [
          ('o-card-ok', '₪50.00'),
          ('o-card-retry', '₪55.00'),
        ]) {
          await _openDrawer(tester, orderId);
          expect(_rowPairs(_sheet, card, amount), isTrue, reason: orderId);
          expect(
            _rowPairs(_sheet, l10n.ordersFilterPayment, l10n.dashboardUnpaid),
            isFalse,
            reason: orderId,
          );
          expect(
            find.descendant(
              of: _sheet,
              matching: find.text(l10n.posPaymentMethodCash),
            ),
            findsNothing,
          );
          await _closeDrawer(tester);
        }

        // Pending, tendered, failed, voided, deleted: no completed payment.
        for (final orderId in _neverCompletedCardOrders) {
          await _openDrawer(tester, orderId);
          expect(
            _rowPairs(_sheet, l10n.ordersFilterPayment, l10n.dashboardUnpaid),
            isTrue,
            reason: orderId,
          );
          expect(
            find.descendant(of: _sheet, matching: find.text(card)),
            findsNothing,
            reason: '$orderId must not show Card as its payment',
          );
          await _closeDrawer(tester);
        }

        // Cash, Bit and external show their own labels and amounts.
        for (final (orderId, label, amount) in [
          ('o-cash-ok', l10n.posPaymentMethodCash, '₪120.00'),
          ('o-bit-ok', l10n.posPaymentMethodBit, '₪20.00'),
          ('o-external-ok', l10n.posPaymentMethodExternal, '₪10.00'),
        ]) {
          await _openDrawer(tester, orderId);
          expect(_rowPairs(_sheet, label, amount), isTrue, reason: orderId);
          expect(
            find.descendant(of: _sheet, matching: find.text(card)),
            findsNothing,
            reason: orderId,
          );
          await _closeDrawer(tester);
        }
      });
    }
  });

  // =========================================================================
  // R7 — Receipt preview (pure).
  // =========================================================================
  group('R7 Receipt preview', () {
    for (final code in _locales) {
      test('R7 a completed card prints Card + amount with no Paid / Change; '
          'card rows that never completed print Unpaid; cash, Bit and '
          'external keep their lines ($code)', () async {
        final l10n = await _l10n(code);
        final card = l10n.posPaymentMethodCard;
        final paid = l10n.posReceiptPaid;
        final change = l10n.posReceiptChange;
        final orders = {
          for (final o in [..._historyOrders(), _retryOrder()]) o.orderId: o,
        };
        bool isPaidOrChange((String, String) line) =>
            line.$1 == paid || line.$1 == change;

        for (final (orderId, amount) in const [
          ('o-card-ok', '₪50.00'),
          ('o-card-retry', '₪55.00'),
        ]) {
          final doc = buildOrderReceiptPreview(l10n, orders[orderId]!);
          final html = documentToHtml(doc);
          final kv = _kvLines(doc);
          expect(kv.where((l) => l.$1 == card).toList(), [
            (card, amount),
          ], reason: orderId);
          expect(kv.where(isPaidOrChange), isEmpty, reason: orderId);
          expect(_centerLines(doc), isNot(contains(l10n.dashboardUnpaid)));
          expect(html, contains(_kvHtml(card, amount)));
          expect(html, isNot(contains('<span>$paid</span>')));
          expect(html, isNot(contains('<span>$change</span>')));
          expect(
            html,
            isNot(contains('<span>${l10n.posPaymentMethodCash}</span>')),
          );
        }

        for (final orderId in _neverCompletedCardOrders) {
          final doc = buildOrderReceiptPreview(l10n, orders[orderId]!);
          final html = documentToHtml(doc);
          final kv = _kvLines(doc);
          expect(_centerLines(doc), contains(l10n.dashboardUnpaid));
          expect(
            html,
            contains('<div class="c">${l10n.dashboardUnpaid}</div>'),
            reason: orderId,
          );
          expect(kv.where((l) => l.$1 == card), isEmpty, reason: orderId);
          expect(kv.where(isPaidOrChange), isEmpty, reason: orderId);
          expect(html, isNot(contains(card)), reason: orderId);
        }

        // Cash tendered ₪150.00 for ₪120.00: Paid and Change.
        final cash = buildOrderReceiptPreview(l10n, orders['o-cash-ok']!);
        expect(
          _kvLines(cash),
          containsAll([(paid, '₪150.00'), (change, '₪30.00')]),
        );
        expect(_kvLines(cash).where((l) => l.$1 == card), isEmpty);
        expect(documentToHtml(cash), contains(_kvHtml(paid, '₪150.00')));
        expect(documentToHtml(cash), contains(_kvHtml(change, '₪30.00')));

        // Exact cash: Paid, and no Change line.
        final exact = buildOrderReceiptPreview(
          l10n,
          _order(
            'o-cash-exact',
            '#ORD-L',
            status: 'completed',
            totalMinor: 12000,
            payments: [_pay('cash', 'completed', 12000)],
          ),
        );
        expect(_kvLines(exact), contains((paid, '₪120.00')));
        expect(_kvLines(exact).where((l) => l.$1 == change), isEmpty);

        // Bit and external print their own label, never Paid / Change.
        for (final (orderId, label, amount) in [
          ('o-bit-ok', l10n.posPaymentMethodBit, '₪20.00'),
          ('o-external-ok', l10n.posPaymentMethodExternal, '₪10.00'),
        ]) {
          final doc = buildOrderReceiptPreview(l10n, orders[orderId]!);
          expect(_kvLines(doc), contains((label, amount)), reason: orderId);
          expect(_kvLines(doc).where(isPaidOrChange), isEmpty);
          expect(_kvLines(doc).where((l) => l.$1 == card), isEmpty);
          expect(documentToHtml(doc), contains(_kvHtml(label, amount)));
        }
      });
    }
  });

  // =========================================================================
  // R8 — Shared labels and tender colours (pure).
  // =========================================================================
  group('R8 Labels and tender colours', () {
    for (final code in _locales) {
      test('R8 the shared mappers call card Card, distinct from Cash, in '
          'every vocabulary ($code)', () async {
        final l10n = await _l10n(code);
        final labels = {
          for (final m in kPaymentMethodWireTokens)
            m: paymentMethodLabel(l10n, m),
        };
        expect(labels, {
          'cash': l10n.posPaymentMethodCash,
          'card': l10n.posPaymentMethodCard,
          'bit': l10n.posPaymentMethodBit,
          'external': l10n.posPaymentMethodExternal,
        });
        expect(labels.values.toSet(), hasLength(4));
        expect(labels['card'], isNot(labels['cash']));
        for (final m in kPaymentMethodWireTokens) {
          expect(labels[m], isNot(m), reason: 'raw token $m leaked');
          expect(labels[m], isNotEmpty);
        }

        expect(
          paymentFilterLabel(l10n, PaymentFilter.card),
          l10n.posPaymentMethodCard,
        );
        expect(
          paymentFilterLabel(l10n, PaymentFilter.card),
          isNot(l10n.posPaymentMethodCash),
        );
        expect(
          paymentFilterLabel(l10n, PaymentFilter.cash),
          l10n.posPaymentMethodCash,
        );
        expect(
          paymentFilterLabel(l10n, PaymentFilter.bit),
          l10n.posPaymentMethodBit,
        );
        expect(
          paymentFilterLabel(l10n, PaymentFilter.external),
          l10n.posPaymentMethodExternal,
        );

        final options = paymentFilterOptions(l10n, PaymentFilter.card);
        expect(options[PaymentFilter.card], l10n.posPaymentMethodCard);
        expect(options[PaymentFilter.cash], l10n.posPaymentMethodCash);
        expect(
          options.keys,
          containsAll(const [
            PaymentFilter.all,
            PaymentFilter.paid,
            PaymentFilter.unpaid,
            PaymentFilter.cash,
            PaymentFilter.card,
          ]),
        );
        // Card is reachable by drill-down; the free dropdown keeps its set.
        expect(
          paymentFilterOptions(l10n, PaymentFilter.all),
          isNot(contains(PaymentFilter.card)),
        );
      });

      testWidgets('R8 paymentTenderColorOf resolves four distinct tender '
          'colours from the theme: card navy, cash orange ($code)', (
        tester,
      ) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(code),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            theme: restoflowBaseTheme(),
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final colours = {
          for (final m in kPaymentMethodWireTokens)
            m: paymentTenderColorOf(context, m),
        };
        expect(colours.values.toSet(), hasLength(4));
        expect(colours['card'], _palette.primaryNavy);
        expect(colours['cash'], _palette.accentOrange);
        expect(colours['card'], isNot(colours['cash']));
        for (final m in kPaymentMethodWireTokens) {
          expect(
            colours[m],
            paymentTenderColor(
              palette: _palette,
              brightness: Brightness.light,
              method: m,
            ),
          );
        }
      });
    }

    test('R8 paymentTenderColor: four distinct colours in both brightnesses; '
        'card is primary navy and cash accent orange', () {
      for (final brightness in Brightness.values) {
        final palette = restoflowBaseTheme(
          brightness: brightness,
        ).extension<RestoflowBrandPalette>()!;
        final colours = {
          for (final m in kPaymentMethodWireTokens)
            m: paymentTenderColor(
              palette: palette,
              brightness: brightness,
              method: m,
            ),
        };
        expect(colours.values.toSet(), hasLength(4), reason: '$brightness');
        expect(colours['card'], palette.primaryNavy);
        expect(colours['cash'], palette.accentOrange);
        expect(colours['card'], isNot(colours['cash']));
      }
    });
  });

  // =========================================================================
  // X1 — provider-recorded vs hand-recorded: indistinguishable.
  // =========================================================================
  group('X1 Provider-recorded vs hand-recorded', () {
    test('X1 the marked owner_report_range payload maps to the SAME '
        'DashboardReport, field by field', () async {
      final hand = _ReportTransport((range) => _rangePayload(range: range));
      final marked = _ReportTransport(
        (range) => _rangePayload(range: range, provider: true),
      );
      final a = await RealOwnerReportsRepository(
        null,
        scope: _owner(),
        transport: hand,
      ).loadReport();
      final b = await RealOwnerReportsRepository(
        null,
        scope: _owner(),
        transport: marked,
      ).loadReport();

      expect(marked.calls, ['owner_report_range']);
      expect(_reportFields(b), _reportFields(a));
      // The shared mapping is the card-correct one, not two equal wrong ones.
      expect(a.paymentMethods.map((p) => p.method).toList(), [
        'cash',
        'card',
        'bit',
        'external',
      ]);
      expect(a.paymentMethods[1].totalMinor, _cardMinor);
      expect(a.cashSalesMinor, _cashMinor);
      expect(a.lastCashPaymentMinor, _lastCashMinor);
      expect(
        a.shiftCash!.lastClosedShift!.collectedMinor,
        _shiftCollectedMinor,
      );
      expect(a.shiftCash!.lastClosedShift!.cashSalesMinor, _cashMinor);
      expect(a.supportsPaymentMethodHistoryFilters, isTrue);
      // Not vacuous: the marked wire carries the markers on the top level, the
      // current block, every tender row and the shift rows — and the
      // hand-recorded wire carries none.
      final wire = _rangePayload(provider: true);
      final current = wire['current'] as Map;
      final shift = wire['shift_cash'] as Map;
      expect(_carriesMarkers(wire), isTrue);
      expect(_carriesMarkers(current), isTrue);
      expect(current['tenders'] as List, hasLength(4));
      expect((current['tenders'] as List).every(_carriesMarkers), isTrue);
      expect(_carriesMarkers(shift), isTrue);
      expect(_carriesMarkers(shift['last_closed_shift']), isTrue);
      expect(_markersIn(jsonEncode(wire)), _markerValues);
      expect(jsonEncode(_rangePayload()), isNot(contains('MARKER')));
    });

    test('X1 the marked owner_order_history rows map to the SAME rows, '
        'field by field', () async {
      Future<List<Map<String, Object?>>> load(bool provider) async {
        final page = await RealOrderHistoryRepository(
          null,
          scope: _owner(),
          transport: _OrdersTransport(provider: provider),
        ).loadHistory(const OrderHistoryQuery(payment: PaymentFilter.card));
        return [for (final r in page.rows) _historyRowFields(r)];
      }

      final hand = await load(false);
      final marked = await load(true);
      expect(marked, hand);
      expect(hand, hasLength(2));
      expect(hand.map((r) => r['paymentMethod']).toSet(), {'card'});
      // Not vacuous: the top level and every order row are marked.
      final wire = _historyPayload(payment: 'card', provider: true);
      expect(_carriesMarkers(wire), isTrue);
      expect(wire['orders'] as List, hasLength(2));
      expect((wire['orders'] as List).every(_carriesMarkers), isTrue);
      expect(_markersIn(jsonEncode(wire)), _markerValues);
      expect(
        jsonEncode(_historyPayload(payment: 'card', provider: false)),
        isNot(contains('MARKER')),
      );
    });

    test('X1 the marked owner_order_detail maps to the SAME OrderDetail, '
        'field by field', () async {
      Future<Map<String, Object?>> load(bool provider) async {
        final detail = await RealOrderHistoryRepository(
          null,
          scope: _owner(),
          transport: _OrdersTransport(provider: provider),
        ).loadDetail('o-card-retry');
        return _detailFields(detail);
      }

      final hand = await load(false);
      final marked = await load(true);
      expect(marked, hand);
      expect(hand['completedPayment'], {
        'method': 'card',
        'status': 'completed',
        'amountMinor': 5500,
        'tenderedMinor': 5500,
        'changeMinor': 0,
        'receiptNumber': null,
        'createdAtLabel': '2026-10-30 12:05',
      });
      expect(hand['payments'], hasLength(2));
      // Not vacuous: the top level, the order and both payment rows (the
      // failed attempt and the completed card) are marked.
      final wire = _detailPayload('o-card-retry', provider: true);
      final order = wire['order'] as Map;
      expect(_carriesMarkers(wire), isTrue);
      expect(_carriesMarkers(order), isTrue);
      expect(order['payments'] as List, hasLength(2));
      expect((order['payments'] as List).every(_carriesMarkers), isTrue);
      expect(_markersIn(jsonEncode(wire)), _markerValues);
      expect(
        jsonEncode(_detailPayload('o-card-retry', provider: false)),
        isNot(contains('MARKER')),
      );
    });

    for (final code in _locales) {
      testWidgets('X1 the Overview payment summary and payment mix (R1, R2) '
          'render identical text for both variants ($code)', (tester) async {
        _tallView(tester);
        final l10n = await _l10n(code);

        Future<
          ({
            List<String> texts,
            List<(String, String)> summary,
            List<String> mix,
            List<(String, int, Color)> segments,
          })
        >
        render(bool provider) async {
          final transport = _ReportTransport(
            (range) => _rangePayload(range: range, provider: provider),
          );
          await tester.pumpWidget(
            _overview(
              key: ValueKey('x1-overview-$provider-$code'),
              locale: code,
              transport: transport,
            ),
          );
          await tester.pumpAndSettle();
          expect(transport.calls.toSet(), {'owner_report_range'});
          return (
            texts: _renderedText(tester),
            summary: _valuePairs(tester, _key('payment-summary-card')),
            mix: _renderedText(tester, _key('payment-mix-card')),
            segments: [
              for (final s in _segments(tester)) (s.label, s.value, s.color),
            ],
          );
        }

        final hand = await render(false);
        final marked = await render(true);
        expect(marked.texts, hand.texts);
        expect(marked.summary, hand.summary);
        expect(marked.mix, hand.mix);
        expect(marked.segments, hand.segments);
        // Not vacuous: the captures hold the cards being compared...
        expect(hand.texts, contains(l10n.dashboardPaymentSummary));
        expect(hand.mix, contains(l10n.posPaymentMethodCard));
        // ...and what both render is the card-correct picture.
        expect(
          hand.summary,
          contains((l10n.posPaymentMethodCard, '2 · ₪50.00')),
        );
        expect(hand.segments[1], (
          l10n.posPaymentMethodCard,
          _cardMinor,
          _palette.primaryNavy,
        ));
      });

      testWidgets('X1 the Orders list and the order drawer (R5, R6) render '
          'identical text for both variants ($code)', (tester) async {
        _tallView(tester, size: const Size(1400, 2600));
        final l10n = await _l10n(code);

        Future<({List<String> list, List<String> drawer})> render(
          bool provider,
        ) async {
          final transport = _OrdersTransport(provider: provider);
          await tester.pumpWidget(
            _orders(
              key: ValueKey('x1-orders-$provider-$code'),
              locale: code,
              mode: _realMode,
              repository: RealOrderHistoryRepository(
                null,
                scope: _owner(),
                transport: transport,
              ),
              payment: PaymentFilter.card,
            ),
          );
          await tester.pumpAndSettle();
          final list = _renderedText(tester);
          await _openDrawer(tester, 'o-card-retry');
          expect(
            _rowPairs(_sheet, l10n.posPaymentMethodCard, '₪55.00'),
            isTrue,
          );
          final drawer = _renderedText(tester, _sheet);
          await _closeDrawer(tester);
          expect(
            transport.calls,
            containsAll(['owner_order_history', 'owner_order_detail']),
          );
          return (list: list, drawer: drawer);
        }

        final hand = await render(false);
        final marked = await render(true);
        expect(marked.list, hand.list);
        expect(marked.drawer, hand.drawer);
        // Not vacuous: the list capture holds both card rows, and the drawer
        // capture holds the Card payment row.
        expect(hand.list, containsAll(['#ORD-A', '#ORD-K']));
        expect(hand.drawer, contains(l10n.posPaymentMethodCard));
      });
    }
  });

  // =========================================================================
  // X2 — no marker reaches a model or the screen.
  // =========================================================================
  group('X2 No provider marker surfaces', () {
    test('X2 no marker value reaches a mapped report, history row or order '
        'detail', () async {
      final report = await RealOwnerReportsRepository(
        null,
        scope: _owner(),
        transport: _ReportTransport(
          (range) => _rangePayload(range: range, provider: true),
        ),
      ).loadReport();
      final repository = RealOrderHistoryRepository(
        null,
        scope: _owner(),
        transport: _OrdersTransport(provider: true),
      );
      final page = await repository.loadHistory(
        const OrderHistoryQuery(payment: PaymentFilter.card),
      );
      final details = [
        await repository.loadDetail('o-card-ok'),
        await repository.loadDetail('o-card-retry'),
      ];

      final dumps = <String>[
        '${_reportFields(report)}',
        for (final r in page.rows) '${_historyRowFields(r)}',
        for (final d in details) '${_detailFields(d)}',
      ];
      expect(page.rows, hasLength(2));
      for (final dump in dumps) {
        expect(dump, isNotEmpty);
        expect(_markersIn(dump), isEmpty, reason: dump);
        expect(dump, isNot(contains('MARKER')));
      }
    });

    test('X2 no marker value reaches a mapped sales series or currency '
        'breakdown', () async {
      Future<Map<String, Object?>> load(_AnalyticsTransport transport) async {
        final series = await RealOwnerSalesSeriesRepository(
          scope: _owner(),
          transport: transport,
        ).loadSeries(range: AnalyticsRange.last7);
        final breakdown = await SupabaseCurrencyBreakdownRepository(
          transport: transport,
          organizationId: 'org-1',
        ).load(start: '2026-10-24', end: '2026-10-30');
        // Both came through their real wire calls, never a degrade path.
        expect(transport.calls, [
          'owner_sales_series',
          'owner_report_currency_breakdown',
        ]);
        return <String, Object?>{
          'series': _seriesFields(series),
          'breakdown': _breakdownFields(breakdown),
        };
      }

      final handWire = _AnalyticsTransport(provider: false);
      final markedWire = _AnalyticsTransport(provider: true);
      final hand = await load(handWire);
      final marked = await load(markedWire);

      expect(marked, hand);
      for (final dump in ['$hand', '$marked']) {
        expect(_markersIn(dump), isEmpty, reason: dump);
        expect(dump, isNot(contains('MARKER')));
      }
      // Not vacuous: both answers were mapped, not degraded (the series is
      // supported, the breakdown available), and the card row stays card.
      expect(hand, <String, Object?>{
        'series': <String, Object?>{
          'currencyCode': 'ILS',
          'rangeWire': 'last7',
          'supported': true,
          'buckets': [
            <String, Object?>{
              'day': '2026-10-30',
              'orderCount': 2,
              'grossMinor': 6000,
              'discountMinor': 0,
              'netMinor': 6000,
              'voidCount': 0,
              'voidTotalMinor': 0,
              'collectedMinor': 6000,
              'cashMinor': 1000,
              'byMethod': [
                ['cash', 1, 1000],
                ['card', 1, 5000],
              ],
              'byOrderType': [
                ['dine_in', 2, 6000],
              ],
            },
          ],
        },
        'breakdown': <String, Object?>{
          'available': true,
          'failure': 'none',
          'totals': [
            ['ILS', 8, 24000, 1500, 22500, _collectedMinor, _cashMinor],
          ],
        },
      });
      // ...and the marked transport really served the markers: on the top
      // level, the bucket and every by_method, by_order_type and by_currency
      // row. The hand-recorded answers carry none.
      expect(markedWire.answers, hasLength(2));
      final seriesWire = markedWire.answers[0];
      final breakdownWire = markedWire.answers[1];
      final buckets = seriesWire['buckets'] as List;
      expect(buckets, hasLength(1));
      final bucket = buckets.single as Map;
      final methods = bucket['by_method'] as List;
      final orderTypes = bucket['by_order_type'] as List;
      final currencies = breakdownWire['by_currency'] as List;
      expect(_carriesMarkers(seriesWire), isTrue);
      expect(_carriesMarkers(bucket), isTrue);
      expect(methods, hasLength(2));
      expect(methods.every(_carriesMarkers), isTrue);
      expect(orderTypes, hasLength(1));
      expect(orderTypes.every(_carriesMarkers), isTrue);
      expect(_carriesMarkers(breakdownWire), isTrue);
      expect(currencies, hasLength(1));
      expect(currencies.every(_carriesMarkers), isTrue);
      for (final answer in markedWire.answers) {
        expect(_markersIn(jsonEncode(answer)), _markerValues);
      }
      expect(handWire.answers, hasLength(2));
      for (final answer in handWire.answers) {
        expect(jsonEncode(answer), isNot(contains('MARKER')));
      }
    });

    for (final code in _locales) {
      testWidgets('X2 no marker value is rendered on the Overview, the '
          'Orders list or the order drawer ($code)', (tester) async {
        _tallView(tester, size: const Size(1400, 3600));
        final l10n = await _l10n(code);

        await tester.pumpWidget(
          _overview(
            key: ValueKey('x2-overview-$code'),
            locale: code,
            transport: _ReportTransport(
              (range) => _rangePayload(range: range, provider: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final overview = _renderedText(tester);

        final transport = _OrdersTransport(provider: true);
        await tester.pumpWidget(
          _orders(
            key: ValueKey('x2-orders-$code'),
            locale: code,
            mode: _realMode,
            repository: RealOrderHistoryRepository(
              null,
              scope: _owner(),
              transport: transport,
            ),
            payment: PaymentFilter.card,
          ),
        );
        await tester.pumpAndSettle();
        final list = _renderedText(tester);
        final drawers = <String>[];
        for (final orderId in const ['o-card-ok', 'o-card-retry']) {
          await _openDrawer(tester, orderId);
          drawers.addAll(_renderedText(tester, _sheet));
          await _closeDrawer(tester);
        }

        // Not vacuous: each capture holds the card-paid content it should.
        expect(overview, contains(l10n.posPaymentMethodCard));
        expect(list, isNotEmpty);
        expect(drawers, contains(l10n.posPaymentMethodCard));
        expect(transport.calls, contains('owner_order_detail'));
        for (final text in [...overview, ...list, ...drawers]) {
          expect(_markersIn(text), isEmpty, reason: text);
          expect(text, isNot(contains('MARKER')));
        }
      });
    }
  });

  // =========================================================================
  // X3 — static: no source under lib names a provider field.
  // =========================================================================
  group('X3 Static source scan', () {
    test('X3 the report / order / series models, the Real* repositories and '
        'the rendering surfaces name no provider field', () {
      // The names hunted for: 11 leaf keys in two spellings each, the
      // voucher, brand, status and merchant keys and the camelCase approval
      // and last-four spellings among them.
      expect(_providerFieldNames, hasLength(22));
      expect(_providerFieldNames, containsAll(_markers.keys));
      expect(
        _providerFieldNames,
        containsAll(const [
          'approvalNumber',
          'voucher_number',
          'voucherNumber',
          'cardLast4',
          'card_brand_code',
          'cardBrandCode',
          'provider_status_code',
          'providerStatusCode',
          'merchant_key',
          'merchantKey',
        ]),
      );
      for (final MapEntry(key: path, value: anchor)
          in _scannedSources.entries) {
        final source = _readSource(path);
        expect(
          source,
          contains(anchor),
          reason: '$path is not the file this guard means to scan',
        );
        expect(
          _providerFieldsIn(source),
          isEmpty,
          reason: '$path names a provider field',
        );
      }
      // Every .dart file under lib, not only the anchored ones. Not vacuous:
      // the whole library was read, the anchored files, the currency
      // breakdown and the report source among it.
      final sources = _dashboardSources();
      expect(sources.length, greaterThan(100));
      expect(
        sources.keys,
        containsAll([
          'lib/src/data/currency_breakdown_repository.dart',
          'lib/src/data/owner_report_source.dart',
          ..._scannedSources.keys,
        ]),
      );
      final offenders = <String, List<String>>{
        for (final MapEntry(key: path, value: source) in sources.entries)
          if (_providerFieldsIn(source).isNotEmpty)
            path: _providerFieldsIn(source),
      };
      expect(offenders, isEmpty, reason: 'a lib source names a provider field');
      // The scanner is live: it reports every name it is asked about.
      expect(
        _providerFieldsIn(_providerFieldNames.join(' ')),
        _providerFieldNames,
      );
    });
  });

  // =========================================================================
  // X4 — cash, Bit and external are unchanged.
  // =========================================================================
  group('X4 Cash, Bit and external unchanged', () {
    for (final code in _locales) {
      testWidgets('X4 cash, Bit and external keep the same labels, amounts and '
          'colours whether or not a card tender is in the window ($code)', (
        tester,
      ) async {
        _tallView(tester);
        final l10n = await _l10n(code);
        final labels = {
          'cash': l10n.posPaymentMethodCash,
          'bit': l10n.posPaymentMethodBit,
          'external': l10n.posPaymentMethodExternal,
        };

        Future<Map<String, Object?>> render(bool withCard) async {
          await tester.pumpWidget(
            _overview(
              key: ValueKey('x4-$withCard-$code'),
              locale: code,
              transport: _ReportTransport(
                (range) => _rangePayload(
                  range: range,
                  tenders: _tenders(provider: false, withCard: withCard),
                  collectedMinor: withCard
                      ? _collectedMinor
                      : _collectedMinor - _cardMinor,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final pairs = _valuePairs(tester, _key('payment-summary-card'));
          final segments = {
            for (final s in _segments(tester)) s.label: (s.value, s.color),
          };
          expect(
            segments.containsKey(l10n.posPaymentMethodCard),
            withCard,
            reason: 'the card slice is present only with a card tender',
          );
          return {
            for (final MapEntry(key: method, value: label) in labels.entries)
              method: <String, Object?>{
                'summary': [
                  for (final (l, v) in pairs)
                    if (l == label) v,
                ],
                'amount': _text(tester, 'payment-amount-$method'),
                'segment': segments[label],
                'swatch': _swatch(tester, method),
              },
            // The cash-only figures beside the tenders.
            'cashSalesKpi': tester
                .widget<RestoflowMetricCard>(_key('kpi-cash-sales'))
                .value,
            'cashRows': [
              for (final (l, v) in pairs)
                if (l == l10n.dashboardCashSales ||
                    l == l10n.dashboardLastCashPayment)
                  '$l=$v',
            ],
          };
        }

        final withCard = await render(true);
        final withoutCard = await render(false);
        expect(withCard, withoutCard);

        Color tender(String method) => paymentTenderColor(
          palette: _palette,
          brightness: Brightness.light,
          method: method,
        );
        expect(withCard['cash'], {
          'summary': ['4 · ₪120.00'],
          'amount': '₪120.00',
          'segment': (_cashMinor, _palette.accentOrange),
          'swatch': _palette.accentOrange,
        });
        expect(withCard['bit'], {
          'summary': ['1 · ₪20.00'],
          'amount': '₪20.00',
          'segment': (_bitMinor, tender('bit')),
          'swatch': tender('bit'),
        });
        expect(withCard['external'], {
          'summary': ['1 · ₪10.00'],
          'amount': '₪10.00',
          'segment': (_externalMinor, tender('external')),
          'swatch': tender('external'),
        });
        expect(withCard['cashSalesKpi'], '₪120.00');
        expect(withCard['cashRows'], [
          '${l10n.dashboardCashSales}=₪120.00',
          '${l10n.dashboardLastCashPayment}=₪30.00',
        ]);
        for (final method in const ['cash', 'bit', 'external']) {
          expect(tender(method), isNot(_palette.primaryNavy), reason: method);
        }
      });

      testWidgets('X4 the cash, Bit and external history filters each keep '
          'only their own completed order and read their own label ($code)', (
        tester,
      ) async {
        _tallView(tester, size: const Size(1400, 2600));
        final l10n = await _l10n(code);
        final orders = _historyOrders();
        for (final (filter, orderId, label) in [
          (PaymentFilter.cash, 'o-cash-ok', l10n.posPaymentMethodCash),
          (PaymentFilter.bit, 'o-bit-ok', l10n.posPaymentMethodBit),
          (
            PaymentFilter.external,
            'o-external-ok',
            l10n.posPaymentMethodExternal,
          ),
        ]) {
          await tester.pumpWidget(
            _orders(
              key: ValueKey('x4-${filter.wire}-$code'),
              locale: code,
              mode: _demoMode,
              repository: _demoOrders(orders),
              payment: filter,
            ),
          );
          await tester.pumpAndSettle();
          for (final order in orders) {
            expect(
              _key('order-card-${order.orderId}'),
              order.orderId == orderId ? findsOneWidget : findsNothing,
              reason: '${filter.wire}: ${order.orderId}',
            );
          }
          _expectPaymentFilterShows(tester, filter, label);
        }
      });
    }
  });
}
