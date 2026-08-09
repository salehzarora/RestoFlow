import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/order_type_analytics.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-D) — aggregating the dine-in /
/// takeaway split across a window.
///
/// The property that matters most is that the rows keep ADDING UP. A future
/// server that persists a new order type must not have its orders quietly
/// dropped, because a breakdown whose parts no longer sum to the whole is a
/// breakdown an owner would reconcile against and lose.

OwnerSalesSeriesBucket _bucket(
  String day, {
  int? dineInCount,
  int dineInNet = 0,
  int? takeawayCount,
  int takeawayNet = 0,
  List<OwnerSalesSeriesOrderType> extra = const [],
}) {
  final types = <OwnerSalesSeriesOrderType>[
    if (dineInCount != null)
      OwnerSalesSeriesOrderType(
        orderType: 'dine_in',
        orderCount: dineInCount,
        netMinor: dineInNet,
      ),
    if (takeawayCount != null)
      OwnerSalesSeriesOrderType(
        orderType: 'takeaway',
        orderCount: takeawayCount,
        netMinor: takeawayNet,
      ),
    ...extra,
  ];
  return OwnerSalesSeriesBucket(
    day: BusinessDay.tryParse(day)!,
    orderCount: types.fold<int>(0, (s, t) => s + t.orderCount),
    grossMinor: 0,
    discountMinor: 0,
    netMinor: types.fold<int>(0, (s, t) => s + t.netMinor),
    voidCount: 0,
    voidTotalMinor: 0,
    collectedMinor: 0,
    cashMinor: 0,
    byOrderType: types,
  );
}

void main() {
  group('aggregation across days', () {
    test('sums counts and nets per type, exactly', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-06',
          dineInCount: 4,
          dineInNet: 30000,
          takeawayCount: 2,
          takeawayNet: 8000,
        ),
        _bucket(
          '2026-08-07',
          dineInCount: 5,
          dineInNet: 41000,
          takeawayCount: 1,
          takeawayNet: 3500,
        ),
        _bucket(
          '2026-08-08',
          dineInCount: 3,
          dineInNet: 13500,
          takeawayCount: 1,
          takeawayNet: 4000,
        ),
      ]);

      expect(rows.map((r) => r.orderType), ['dine_in', 'takeaway']);
      expect(rows[0].orderCount, 12);
      expect(rows[0].netMinor, 84500);
      expect(rows[1].orderCount, 4);
      expect(rows[1].netMinor, 15500);
    });

    test('a type MISSING on one day contributes zero for that day and still '
        'appears from the others', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket('2026-08-06', dineInCount: 4, dineInNet: 30000),
        // No takeaway at all on this day — the server omits the row.
        _bucket('2026-08-07', dineInCount: 2, dineInNet: 10000),
        _bucket('2026-08-08', takeawayCount: 3, takeawayNet: 9000),
      ]);

      expect(rows.map((r) => r.orderType), ['dine_in', 'takeaway']);
      expect(rows[0].orderCount, 6);
      expect(rows[1].orderCount, 3);
      expect(rows[1].netMinor, 9000);
    });

    test('a window with no typed rows at all aggregates to nothing — never a '
        'pair of zero rows', () {
      expect(aggregateOrderTypeAnalytics(const []), isEmpty);
      expect(aggregateOrderTypeAnalytics([_bucket('2026-08-08')]), isEmpty);
    });

    test('money and counts stay ints', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket('2026-08-08', dineInCount: 3, dineInNet: 12345),
      ]);
      expect(rows.single.netMinor, isA<int>());
      expect(rows.single.netMinor, isNot(isA<double>()));
      expect(rows.single.orderCount, isA<int>());
    });
  });

  group('share of ORDERS, in basis points', () {
    test("the brief's worked example: 3 dine-in and 1 takeaway", () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-08',
          dineInCount: 3,
          dineInNet: 30000,
          takeawayCount: 1,
          takeawayNet: 5000,
        ),
      ]);
      expect(rows[0].shareBps, 7500);
      expect(rows[1].shareBps, 2500);
    });

    test('truncating integer division, never rounding up', () {
      // 1 of 3 = 33.33% -> 3333 bps, and 2 of 3 -> 6666.
      final rows = aggregateOrderTypeAnalytics([
        _bucket('2026-08-08', dineInCount: 2, takeawayCount: 1),
      ]);
      expect(rows[0].shareBps, 6666);
      expect(rows[1].shareBps, 3333);
    });

    test('the DENOMINATOR is the returned order count — the shares of a '
        'complete breakdown account for the whole window', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-08',
          dineInCount: 12,
          dineInNet: 84500,
          takeawayCount: 4,
          takeawayNet: 15500,
        ),
      ]);
      final totalCount = rows.fold<int>(0, (s, r) => s + r.orderCount);
      expect(totalCount, 16);
      expect(rows[0].shareBps, (12 * 10000) ~/ 16);
      expect(rows[1].shareBps, (4 * 10000) ~/ 16);
      expect(rows.fold<int>(0, (s, r) => s + r.shareBps!), 10000);
    });

    test('a zero order count yields NULL, not 0%', () {
      expect(orderShareBasisPoints(0, 0), isNull);
      expect(orderShareBasisPoints(5, 0), isNull);
      expect(orderShareBasisPoints(5, -1), isNull);

      // A window whose only rows carry zero orders: money may exist from an
      // earlier day's settlement, but there is no order population to share.
      final rows = aggregateOrderTypeAnalytics([
        _bucket('2026-08-08', dineInCount: 0, dineInNet: 0),
      ]);
      expect(rows.single.shareBps, isNull);
      expect(rows.single.hasShare, isFalse);
    });
  });

  group('unknown future order types', () {
    test('are PRESERVED, and counted in the denominator so the rows keep '
        'summing to the window', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-08',
          dineInCount: 6,
          dineInNet: 60000,
          takeawayCount: 2,
          takeawayNet: 20000,
          extra: const [
            OwnerSalesSeriesOrderType(
              orderType: 'delivery',
              orderCount: 2,
              netMinor: 20000,
            ),
          ],
        ),
      ]);

      expect(rows.map((r) => r.orderType), ['dine_in', 'takeaway', 'delivery']);
      expect(rows.last.orderCount, 2);
      expect(rows.last.netMinor, 20000);
      // 6 / 10, 2 / 10, 2 / 10 — the unknown type is in the denominator.
      expect(rows.map((r) => r.shareBps), [6000, 2000, 2000]);
      expect(rows.fold<int>(0, (s, r) => s + r.shareBps!), 10000);
    });

    test('several unknown types sort alphabetically after the known ones', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-08',
          takeawayCount: 1,
          dineInCount: 1,
          extra: const [
            OwnerSalesSeriesOrderType(
              orderType: 'zeta',
              orderCount: 1,
              netMinor: 0,
            ),
            OwnerSalesSeriesOrderType(
              orderType: 'delivery',
              orderCount: 1,
              netMinor: 0,
            ),
          ],
        ),
      ]);
      expect(rows.map((r) => r.orderType), [
        'dine_in',
        'takeaway',
        'delivery',
        'zeta',
      ]);
    });

    test('ordering is fixed, not by size — a card that reorders itself as the '
        'day goes on has to be re-read every time', () {
      // Takeaway dominates, and still sorts second.
      final rows = aggregateOrderTypeAnalytics([
        _bucket(
          '2026-08-08',
          dineInCount: 1,
          dineInNet: 1000,
          takeawayCount: 99,
          takeawayNet: 990000,
        ),
      ]);
      expect(rows.map((r) => r.orderType), ['dine_in', 'takeaway']);
    });

    test('a type present only in later days keeps its position', () {
      final rows = aggregateOrderTypeAnalytics([
        _bucket('2026-08-06', takeawayCount: 2, takeawayNet: 8000),
        _bucket('2026-08-07', dineInCount: 1, dineInNet: 5000),
      ]);
      expect(rows.map((r) => r.orderType), ['dine_in', 'takeaway']);
    });
  });

  group('self-consistency with the bucket the server sent', () {
    test('the typed rows sum EXACTLY to each bucket order_count and net_minor '
        '— the SERVER-A contract (same order_win CTE, same billed predicate, '
        'same net formula, NOT NULL order_type)', () {
      final buckets = [
        _bucket(
          '2026-08-06',
          dineInCount: 4,
          dineInNet: 30000,
          takeawayCount: 2,
          takeawayNet: 8000,
        ),
        _bucket(
          '2026-08-07',
          dineInCount: 5,
          dineInNet: 41000,
          takeawayCount: 1,
          takeawayNet: 3500,
        ),
      ];
      final rows = aggregateOrderTypeAnalytics(buckets);

      expect(
        rows.fold<int>(0, (s, r) => s + r.orderCount),
        buckets.fold<int>(0, (s, b) => s + b.orderCount),
      );
      expect(
        rows.fold<int>(0, (s, r) => s + r.netMinor),
        buckets.fold<int>(0, (s, b) => s + b.netMinor),
      );
    });

    test('an UNKNOWN type does not break that sum', () {
      final buckets = [
        _bucket(
          '2026-08-08',
          dineInCount: 6,
          dineInNet: 60000,
          extra: const [
            OwnerSalesSeriesOrderType(
              orderType: 'delivery',
              orderCount: 2,
              netMinor: 20000,
            ),
          ],
        ),
      ];
      final rows = aggregateOrderTypeAnalytics(buckets);
      expect(rows.fold<int>(0, (s, r) => s + r.orderCount), 8);
      expect(rows.fold<int>(0, (s, r) => s + r.netMinor), 80000);
      expect(
        rows.fold<int>(0, (s, r) => s + r.netMinor),
        buckets.single.netMinor,
      );
    });
  });

  test(
    'rows are value-equal, so a rebuild with identical data is identical',
    () {
      const a = OrderTypeAnalyticsRow(
        orderType: 'dine_in',
        orderCount: 12,
        netMinor: 84500,
        shareBps: 7500,
      );
      const b = OrderTypeAnalyticsRow(
        orderType: 'dine_in',
        orderCount: 12,
        netMinor: 84500,
        shareBps: 7500,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const OrderTypeAnalyticsRow(
            orderType: 'takeaway',
            orderCount: 12,
            netMinor: 84500,
            shareBps: 7500,
          ),
        ),
      );
    },
  );
}
