import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — parsing the `owner_sales_series`
/// payload.
///
/// Two properties carry the weight here: money stays INTEGER minor at every hop,
/// and a `day` stays the SERVER's branch-local calendar label rather than being
/// reinterpreted as an instant in the device's timezone.

/// A realistic two-day payload. Deliberately asymmetric — every number differs
/// from every other — so a test cannot pass by reading the wrong field.
Map<String, dynamic> _payload() => <String, dynamic>{
  'ok': true,
  'entity': 'owner_sales_series',
  'currency_code': 'ILS',
  'range': 'last7',
  'buckets': <Map<String, dynamic>>[
    {
      'day': '2026-08-07',
      'order_count': 4,
      'gross_minor': 12000,
      'discount_minor': 500,
      'net_minor': 11500,
      'void_count': 1,
      'void_total_minor': 700,
      'collected_minor': 9000,
      'cash_minor': 6000,
      'by_method': <Map<String, dynamic>>[
        {'method': 'cash', 'count': 2, 'total_minor': 6000},
        {'method': 'card', 'count': 1, 'total_minor': 2000},
        {'method': 'bit', 'count': 1, 'total_minor': 700},
        {'method': 'external', 'count': 1, 'total_minor': 300},
      ],
      'by_order_type': <Map<String, dynamic>>[
        {'order_type': 'dine_in', 'order_count': 3, 'net_minor': 9500},
        {'order_type': 'takeaway', 'order_count': 1, 'net_minor': 2000},
      ],
    },
    {
      'day': '2026-08-08',
      'order_count': 2,
      'gross_minor': 5000,
      'discount_minor': 0,
      'net_minor': 5000,
      'void_count': 0,
      'void_total_minor': 0,
      'collected_minor': 5000,
      'cash_minor': 1000,
      'by_method': <Map<String, dynamic>>[
        {'method': 'cash', 'count': 1, 'total_minor': 1000},
        {'method': 'card', 'count': 1, 'total_minor': 4000},
      ],
      'by_order_type': <Map<String, dynamic>>[
        {'order_type': 'dine_in', 'order_count': 2, 'net_minor': 5000},
      ],
    },
  ],
};

void main() {
  group('BusinessDay — a calendar LABEL, never an instant', () {
    test('keeps the server token verbatim and exposes its parts', () {
      final day = BusinessDay.tryParse('2026-08-08')!;
      expect(day.label, '2026-08-08');
      expect(day.year, 2026);
      expect(day.month, 8);
      expect(day.dayOfMonth, 8);
      expect(day.dayOfMonthLabel, '08');
      expect(day.toString(), '2026-08-08');
    });

    test('a day is the SAME day regardless of what the device timezone would '
        'have made of it', () {
      // This is the bug the type exists to prevent. `DateTime.parse` on a
      // date-only token yields a LOCAL midnight, and the UTC reading a naive
      // client would take (`...T00:00:00Z`) lands on the PREVIOUS calendar day
      // for every device west of UTC. BusinessDay never builds a DateTime, so
      // its answer cannot depend on where the laptop is.
      for (final token in const [
        '2026-01-01',
        '2026-03-29', // a European DST transition
        '2026-08-08',
        '2026-12-31',
      ]) {
        final day = BusinessDay.tryParse(token)!;
        expect(day.label, token);
        expect(
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.dayOfMonth.toString().padLeft(2, '0')}',
          token,
          reason: 'the parts must round-trip to the SERVER token exactly',
        );
      }
    });

    test(
      'ordering is chronological (lexicographic on a zero-padded label)',
      () {
        final a = BusinessDay.tryParse('2026-08-09')!;
        final b = BusinessDay.tryParse('2026-09-01')!;
        final c = BusinessDay.tryParse('2027-01-01')!;
        expect(a.compareTo(b), lessThan(0));
        expect(b.compareTo(c), lessThan(0));
        expect(a.compareTo(BusinessDay.tryParse('2026-08-09')!), 0);
      },
    );

    test('value equality makes it usable as a map key', () {
      final a = BusinessDay.tryParse('2026-08-08')!;
      final b = BusinessDay.tryParse('2026-08-08')!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a: 1}[b], 1);
      expect(a, isNot(BusinessDay.tryParse('2026-08-09')));
    });

    test('rejects anything that is not a YYYY-MM-DD token', () {
      for (final bad in const [
        null,
        '',
        '2026-8-8', // not zero-padded
        '2026-08-08T00:00:00Z', // an instant, not a day
        '08/08/2026',
        '2026-13-01', // month out of range
        '2026-01-32', // day out of range
        '2026-00-10',
        '2026-01-00',
        'not-a-date',
        '2026-+1-08', // int.tryParse would accept the sign; we must not
        '2026- 1-08',
      ]) {
        expect(
          BusinessDay.tryParse(bad),
          isNull,
          reason: 'must reject ${bad ?? 'null'}',
        );
      }
    });
  });

  group('OwnerSalesSeries.fromPayload', () {
    test('parses the full response with integer money throughout', () {
      final series = OwnerSalesSeries.fromPayload(_payload());

      expect(series.currencyCode, 'ILS');
      expect(series.rangeWire, 'last7');
      expect(series.supported, isTrue);
      expect(series.buckets, hasLength(2));

      final first = series.buckets.first;
      expect(first.day.label, '2026-08-07');
      expect(first.orderCount, 4);
      expect(first.grossMinor, 12000);
      expect(first.discountMinor, 500);
      expect(first.netMinor, 11500);
      expect(first.voidCount, 1);
      expect(first.voidTotalMinor, 700);
      expect(first.collectedMinor, 9000);
      expect(first.cashMinor, 6000);

      // Every money field is an int — no double reaches the client (D-007).
      for (final value in <Object>[
        first.grossMinor,
        first.discountMinor,
        first.netMinor,
        first.voidTotalMinor,
        first.collectedMinor,
        first.cashMinor,
      ]) {
        expect(value, isA<int>());
        expect(value, isNot(isA<double>()));
      }
    });

    test('keeps the server ordering (ascending by day)', () {
      final series = OwnerSalesSeries.fromPayload(_payload());
      expect(series.buckets.map((b) => b.day.label), [
        '2026-08-07',
        '2026-08-08',
      ]);
    });

    test('parses cash / card / bit / external, preserving the WIRE tokens', () {
      final series = OwnerSalesSeries.fromPayload(_payload());
      final methods = series.buckets.first.byMethod;
      expect(methods.map((m) => m.method), ['cash', 'card', 'bit', 'external']);
      expect(methods.map((m) => m.count), [2, 1, 1, 1]);
      expect(methods.map((m) => m.totalMinor), [6000, 2000, 700, 300]);
      // The breakdown still sums to the day's collected total.
      expect(
        methods.fold<int>(0, (s, m) => s + m.totalMinor),
        series.buckets.first.collectedMinor,
      );
    });

    test('parses dine_in / takeaway, preserving the WIRE tokens', () {
      final series = OwnerSalesSeries.fromPayload(_payload());
      final types = series.buckets.first.byOrderType;
      expect(types.map((t) => t.orderType), ['dine_in', 'takeaway']);
      expect(types.map((t) => t.orderCount), [3, 1]);
      expect(types.map((t) => t.netMinor), [9500, 2000]);
    });

    test('an UNKNOWN method/order type is kept verbatim, not dropped — a money '
        'breakdown must keep summing to its own total', () {
      final raw = _payload();
      (raw['buckets'] as List)[1]['by_method'] = <Map<String, dynamic>>[
        {'method': 'crypto', 'count': 1, 'total_minor': 5000},
      ];
      (raw['buckets'] as List)[1]['by_order_type'] = <Map<String, dynamic>>[
        {'order_type': 'drive_through', 'order_count': 2, 'net_minor': 5000},
      ];
      final series = OwnerSalesSeries.fromPayload(raw);
      expect(series.buckets[1].byMethod.single.method, 'crypto');
      expect(series.buckets[1].byMethod.single.totalMinor, 5000);
      expect(series.buckets[1].byOrderType.single.orderType, 'drive_through');
    });

    test('an EMPTY bucket list parses to a stable empty series', () {
      final series = OwnerSalesSeries.fromPayload(<String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': 'last30',
        'buckets': <dynamic>[],
      });
      expect(series.buckets, isEmpty);
      expect(series.isEmpty, isTrue);
      expect(series.supported, isTrue);
      expect(series.netSalesMinor, 0);
      expect(series.orderCount, 0);
      expect(series.peakByNet, isNull);
    });

    test('a MISSING or malformed buckets field is empty, never null', () {
      for (final raw in <Map<String, dynamic>>[
        {'ok': true, 'currency_code': 'ILS', 'range': 'last7'},
        {
          'ok': true,
          'currency_code': 'ILS',
          'range': 'last7',
          'buckets': 'nope',
        },
      ]) {
        expect(OwnerSalesSeries.fromPayload(raw).buckets, isEmpty);
      }
    });

    test('a bucket with an unusable day is DROPPED, not repositioned or '
        'zero-filled', () {
      final raw = _payload();
      (raw['buckets'] as List).insert(1, <String, dynamic>{
        'day': 'not-a-day',
        'net_minor': 999999,
        'order_count': 42,
      });
      final series = OwnerSalesSeries.fromPayload(raw);

      expect(series.buckets, hasLength(2));
      expect(series.buckets.map((b) => b.day.label), [
        '2026-08-07',
        '2026-08-08',
      ]);
      // Critically: its money did NOT leak into the totals under some other day.
      expect(series.netSalesMinor, 11500 + 5000);
      expect(series.orderCount, 4 + 2);
    });

    test('a malformed NUMERIC field degrades to 0 — the row survives, the '
        'value is never invented', () {
      final raw = _payload();
      (raw['buckets'] as List)[1]['net_minor'] = 'oops';
      (raw['buckets'] as List)[1]['order_count'] = null;
      final series = OwnerSalesSeries.fromPayload(raw);
      expect(series.buckets, hasLength(2));
      expect(series.buckets[1].netMinor, 0);
      expect(series.buckets[1].orderCount, 0);
    });

    test('a non-map row inside by_method / by_order_type is skipped', () {
      final raw = _payload();
      (raw['buckets'] as List)[1]['by_method'] = <dynamic>[
        'nonsense',
        {'method': 'cash', 'count': 1, 'total_minor': 1000},
      ];
      final series = OwnerSalesSeries.fromPayload(raw);
      expect(series.buckets[1].byMethod, hasLength(1));
      expect(series.buckets[1].byMethod.single.method, 'cash');
    });

    test('currency and range metadata are preserved verbatim — an unmodelled '
        'range echo (custom) is NOT silently rewritten to today', () {
      final series = OwnerSalesSeries.fromPayload(<String, dynamic>{
        'ok': true,
        'currency_code': 'EUR',
        'range': 'custom',
        'buckets': <dynamic>[],
      });
      expect(series.currencyCode, 'EUR');
      expect(series.rangeWire, 'custom');
    });

    test(
      'window totals and the peak day are computed from the real buckets',
      () {
        final series = OwnerSalesSeries.fromPayload(_payload());
        expect(series.netSalesMinor, 16500);
        expect(series.orderCount, 6);
        expect(series.peakByNet!.day.label, '2026-08-07');
        expect(series.peakByNet!.netMinor, 11500);
      },
    );

    test('billed and collected stay DIFFERENT facts', () {
      final series = OwnerSalesSeries.fromPayload(_payload());
      final first = series.buckets.first;
      expect(first.netMinor, isNot(first.collectedMinor));
      expect(first.collectedMinor, isNot(first.cashMinor));
    });

    test('the unavailable series is distinguishable from an empty one', () {
      const missing = OwnerSalesSeries.unavailable('last7');
      expect(missing.supported, isFalse);
      expect(missing.isEmpty, isTrue);
      expect(missing.rangeWire, 'last7');

      final empty = OwnerSalesSeries.fromPayload(<String, dynamic>{
        'ok': true,
        'currency_code': 'ILS',
        'range': 'last7',
        'buckets': <dynamic>[],
      });
      expect(empty.supported, isTrue);
      expect(
        empty.supported,
        isNot(missing.supported),
        reason: '"not deployed" and "no sales" must never look alike',
      );
    });
  });
}
