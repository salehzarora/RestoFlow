import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/active_orders_models.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/data/currency_breakdown_repository.dart';
import 'package:restoflow_dashboard/src/data/real_active_orders_repository.dart';
import 'package:restoflow_dashboard/src/data/real_order_history_repository.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// OPS-043 Phase 2 — the Dashboard half of "historical money is never
/// relabelled" and "unlike currencies are never summed".
///
/// The fixture everywhere below is the one that matters: a restaurant that has
/// SWITCHED its operating currency, holding an old order stored in ILS beside a
/// new one stored in USD. Before this phase both list surfaces stamped a single
/// envelope code onto every row, so the old order was rendered as USD — real
/// money, relabelled by a settings change.
void main() {
  group('A. order history: the ROW currency wins', () {
    test(
      'A1. an old ILS order stays ILS while the restaurant now reports USD',
      () async {
        final page = await _history(_mixedHistoryEnvelope());
        final old = page.rows.firstWhere((r) => r.customerName == 'Old ILS');
        final fresh = page.rows.firstWhere((r) => r.customerName == 'New USD');

        expect(old.currencyCode, 'ILS');
        expect(fresh.currencyCode, 'USD');
        expect(
          MoneyFormatter.formatMinor(old.grandTotalMinor, old.currencyCode),
          '₪10.00',
          reason: 'the stored amount and its own currency, unconverted',
        );
        expect(
          MoneyFormatter.formatMinor(fresh.grandTotalMinor, fresh.currencyCode),
          r'$7.00',
        );
      },
    );

    test('A2. NO conversion: the stored minor amount is passed through '
        'untouched', () async {
      final page = await _history(_mixedHistoryEnvelope());
      expect(page.rows.map((r) => r.grandTotalMinor), containsAll([1000, 700]));
    });

    test('A3. a server that predates the migration still works — the row falls '
        'back to the envelope code', () async {
      final page = await _history(_legacyHistoryEnvelope());
      expect(page.rows.single.currencyCode, 'ILS');
    });

    test(
      'A4. an empty per-row code is treated as absent, not as a currency',
      () async {
        final page = await _history(_legacyHistoryEnvelope(rowCurrency: ''));
        expect(page.rows.single.currencyCode, 'ILS');
      },
    );
  });

  group('B. the active board: same rule', () {
    test('B1. an open ILS order on a USD restaurant renders ILS', () async {
      final snapshot = await _active();
      expect(snapshot.rows.single.currencyCode, 'ILS');
      expect(
        MoneyFormatter.formatMinor(
          snapshot.rows.single.grandTotalMinor,
          snapshot.rows.single.currencyCode,
        ),
        '₪4.00',
      );
    });
  });

  group('C. the per-currency breakdown', () {
    test('C1. a mixed window is reported as mixed, with each currency kept '
        'apart', () async {
      final breakdown = await _breakdown((fn, p) => _breakdownEnvelope);
      expect(breakdown.available, isTrue);
      expect(breakdown.isMixed, isTrue);
      expect(breakdown.singleCurrency, isNull);
      final ils = breakdown.totals.firstWhere((t) => t.currencyCode == 'ILS');
      final usd = breakdown.totals.firstWhere((t) => t.currencyCode == 'USD');
      expect(ils.netMinor, 1400);
      expect(usd.netMinor, 700);
      expect(
        ils.netMinor + usd.netMinor,
        2100,
        reason:
            'the arithmetic is possible but MEANINGLESS — nothing in the app '
            'may present it, which is what isMixed exists to prevent',
      );
    });

    test('C2. a single-currency window behaves exactly as before', () async {
      final breakdown = await _breakdown(
        (fn, p) => {
          'ok': true,
          'by_currency': [
            {'currency_code': 'ILS', 'net_minor': 1400, 'order_count': 2},
          ],
        },
      );
      expect(breakdown.isMixed, isFalse);
      expect(breakdown.singleCurrency, 'ILS');
    });

    test('C3. it passes the window it was given, so the split always describes '
        'the same range as the headline', () async {
      final calls = <Map<String, dynamic>>[];
      await _breakdown(
        (fn, p) {
          calls.add(p);
          return _breakdownEnvelope;
        },
        start: '2026-08-01',
        end: '2026-08-07',
      );
      expect(calls.single['p_start'], '2026-08-01');
      expect(calls.single['p_end'], '2026-08-07');
      expect(calls.single['p_organization_id'], 'org-1');
      expect(calls.single['p_restaurant_id'], 'rest-1');
    });

    group('C4. UNAVAILABLE is never "one currency"', () {
      test('an undeployed RPC', () async {
        final breakdown = await _breakdown(
          (fn, p) => throw StateError('PGRST202 function not found'),
        );
        expect(breakdown.available, isFalse);
        expect(breakdown.isMixed, isFalse);
        expect(breakdown.singleCurrency, isNull);
      });

      test('a denial', () async {
        final breakdown = await _breakdown(
          (fn, p) => {'ok': false, 'error': 'permission_denied'},
        );
        expect(breakdown.available, isFalse);
      });

      test('a malformed payload', () async {
        final breakdown = await _breakdown((fn, p) => {'ok': true});
        expect(breakdown.available, isFalse);
      });
    });
  });

  group('D. the shared formatter reached the dashboard', () {
    test('D1. ILS is unchanged to the character', () {
      expect(MoneyFormatter.formatMinor(4242, 'ILS'), '₪42.42');
      expect(MoneyFormatter.formatMinor(-500, 'ILS'), '-₪5.00');
    });

    test('D2. a 0-decimal currency no longer renders 100x wrong', () {
      expect(MoneyFormatter.formatMinor(1500, 'JPY'), 'JPY 1500');
    });

    test('D3. a 3-decimal currency keeps three digits', () {
      expect(MoneyFormatter.formatMinor(1500, 'KWD'), 'KWD 1.500');
    });

    test('D4. an ambiguous-symbol currency shows its CODE, never a bare '
        'unlabelled number', () {
      expect(MoneyFormatter.formatMinor(2500, 'CHF'), 'CHF 25.00');
    });
  });
}

// ---------------------------------------------------------------------------

const Map<String, dynamic> _breakdownEnvelope = {
  'ok': true,
  'entity': 'owner_report_currency_breakdown',
  'range_start': '2026-08-18',
  'range_end': '2026-08-18',
  'by_currency': [
    {
      'currency_code': 'ILS',
      'order_count': 2,
      'gross_minor': 1400,
      'discount_minor': 0,
      'net_minor': 1400,
      'collected_minor': 1000,
      'cash_minor': 1000,
    },
    {
      'currency_code': 'USD',
      'order_count': 1,
      'gross_minor': 700,
      'discount_minor': 0,
      'net_minor': 700,
      'collected_minor': 700,
      'cash_minor': 0,
    },
  ],
};

Map<String, dynamic> _order({
  required String id,
  required String customer,
  required int totalMinor,
  String? currencyCode,
  String status = 'completed',
  String payment = 'paid',
}) => {
  'order_id': id,
  'order_code': '#$id',
  'status': status,
  'order_type': 'dine_in',
  'customer_name': customer,
  'created_at': '2026-08-18 10:00',
  'created_at_utc': '2026-08-18T10:00:00Z',
  'item_count': 1,
  'subtotal_minor': totalMinor,
  'discount_total_minor': 0,
  'tax_total_minor': 0,
  'grand_total_minor': totalMinor,
  'payment_status': payment,
  'paid_amount_minor': payment == 'paid' ? totalMinor : null,
  if (currencyCode != null) 'currency_code': currencyCode,
};

/// A post-migration envelope: the restaurant now operates in USD, and the rows
/// carry the currency each order was actually taken in.
Map<String, dynamic> _mixedHistoryEnvelope() => {
  'ok': true,
  'entity': 'owner_order_history',
  'currency_code': 'USD',
  'range': 'today',
  'limit': 50,
  'orders': [
    _order(
      id: 'o1',
      customer: 'Old ILS',
      totalMinor: 1000,
      currencyCode: 'ILS',
    ),
    _order(id: 'o2', customer: 'New USD', totalMinor: 700, currencyCode: 'USD'),
  ],
  'has_more': false,
  'next_cursor': null,
  'count': 2,
};

/// A PRE-migration envelope: no per-row currency at all.
Map<String, dynamic> _legacyHistoryEnvelope({String? rowCurrency}) => {
  'ok': true,
  'entity': 'owner_order_history',
  'currency_code': 'ILS',
  'range': 'today',
  'limit': 50,
  'orders': [
    _order(
      id: 'o1',
      customer: 'Legacy',
      totalMinor: 1000,
      currencyCode: rowCurrency,
    ),
  ],
  'has_more': false,
  'next_cursor': null,
  'count': 1,
};

const _membership = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest One',
  branchId: 'branch-1',
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Future<OrderHistoryPage> _history(Map<String, dynamic> envelope) =>
    RealOrderHistoryRepository(
      null,
      scope: _membership,
      transport: _Transport((fn, p) => envelope),
    ).loadHistory(const OrderHistoryQuery());

Future<ActiveOrdersSnapshot> _active() => RealActiveOrdersRepository(
  null,
  scope: _membership,
  transport: _Transport(
    (fn, p) => {
      'ok': true,
      'entity': 'owner_active_orders',
      'currency_code': 'USD',
      'queue': p['p_queue'],
      'sort': p['p_sort'],
      'limit': 100,
      'count': 1,
      'matching': 1,
      'has_more': false,
      'truncated': false,
      'next_cursor': null,
      'summary': {'total': 1, 'unpaid': 1},
      'orders': [
        _order(
          id: 'o3',
          customer: 'Open ILS',
          totalMinor: 400,
          currencyCode: 'ILS',
          status: 'submitted',
          payment: 'unpaid',
        ),
      ],
    },
  ),
).loadActive(const ActiveOrdersQuery());

Future<CurrencyBreakdown> _breakdown(
  Object? Function(String fn, Map<String, dynamic> params) handler, {
  String start = '2026-08-18',
  String end = '2026-08-18',
}) => SupabaseCurrencyBreakdownRepository(
  transport: _Transport(handler),
  organizationId: 'org-1',
  restaurantId: 'rest-1',
).load(start: start, end: end);

class _Transport implements SyncRpcTransport {
  _Transport(this._handler);

  final Object? Function(String fn, Map<String, dynamic> params) _handler;

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> params) async =>
      _handler(fn, params);
}
