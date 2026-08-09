import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/comparison_delta.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/report_calculator.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-B) — period comparison v2.
///
/// Two things are pinned here. First the DEPLOYMENT SEAM: SERVER-B's additive
/// `comparison.completed_count` / `comparison.discount_minor` are merged but not
/// applied to every database, so the parser must be able to say "this server did
/// not tell me" — which is a different fact from "the prior window had none",
/// and must never collapse into a measured zero. Second the ARITHMETIC: average
/// order value is integer minor units on both sides, and every delta goes
/// through the one shared [ComparisonDelta].

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      _handler(function, params);
}

MembershipContext _scope() => const MembershipContext(
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

/// An `owner_report_range` body. [comparison] is spliced in verbatim so a test
/// can post the PRE-SERVER-B shape, the new shape, or a malformed one.
Map<String, dynamic> _rangePayload(Map<String, dynamic> comparison) =>
    <String, dynamic>{
      'ok': true,
      'entity': 'owner_report_range',
      'currency_code': 'ILS',
      'range': 'last7',
      'range_start': '2026-08-02',
      'range_end': '2026-08-08',
      'current': <String, dynamic>{
        'order_count': 8,
        'completed_count': 6,
        'open_count': 2,
        'unpaid_count': 1,
        'gross_minor': 24000,
        'discount_minor': 1500,
        'net_minor': 22500,
        'void_count': 1,
        'void_total_minor': 900,
        'collected_minor': 20000,
        'cash_minor': 12000,
        'last_cash_payment_minor': 3000,
        'tenders': <Map<String, dynamic>>[
          {'method': 'cash', 'count': 4, 'total_minor': 12000},
        ],
      },
      'comparison': comparison,
      'hourly': <dynamic>[],
      'shift_cash': null,
    };

/// The five comparison keys that existed BEFORE SERVER-B.
Map<String, dynamic> _legacyComparison() => <String, dynamic>{
  'order_count': 5,
  'gross_minor': 18000,
  'net_minor': 17000,
  'cash_minor': 9000,
  'collected_minor': 15000,
};

Future<DashboardReport> _load(Map<String, dynamic> comparison) {
  final repo = RealOwnerReportsRepository(
    null,
    scope: _scope(),
    transport: _FakeTransport((_, _) => _rangePayload(comparison)),
  );
  return repo.loadReport(range: ReportRange.last7);
}

void main() {
  group('parser — the SERVER-B deployment seam', () {
    test(
      'A. a PRE-SERVER-B payload (only the original five keys) still parses',
      () async {
        final report = await _load(_legacyComparison());
        final cmp = report.comparison!;

        expect(cmp.orderCount, 5);
        expect(cmp.grossSalesMinor, 18000);
        expect(cmp.netSalesMinor, 17000);
        expect(cmp.cashSalesMinor, 9000);
      },
    );

    test(
      'B. a SERVER-B payload parses completed_count and discount_minor',
      () async {
        final report = await _load(
          _legacyComparison()
            ..['completed_count'] = 4
            ..['discount_minor'] = 1200,
        );
        final cmp = report.comparison!;

        expect(cmp.completedOrderCount, 4);
        expect(cmp.discountTotalMinor, 1200);
        expect(cmp.completedOrderCount, isA<int>());
        expect(cmp.discountTotalMinor, isA<int>());
      },
    );

    test(
      'C. ABSENT additive keys are null — never a fabricated zero',
      () async {
        final cmp = (await _load(_legacyComparison())).comparison!;

        expect(cmp.completedOrderCount, isNull);
        expect(cmp.discountTotalMinor, isNull);
        expect(
          cmp.completedOrderCount,
          isNot(0),
          reason:
              '"the server did not send it" is not "the prior window had 0"',
        );
      },
    );

    test('D. a PRESENT zero is a real zero, distinct from absent', () async {
      final cmp = (await _load(
        _legacyComparison()
          ..['completed_count'] = 0
          ..['discount_minor'] = 0,
      )).comparison!;

      expect(cmp.completedOrderCount, 0);
      expect(cmp.discountTotalMinor, 0);
      expect(cmp.completedOrderCount, isNotNull);
      expect(cmp.discountTotalMinor, isNotNull);
    });

    test('E. a MALFORMED additive key degrades to absent, following the '
        'optional-field convention already used for the shift rows', () async {
      final cmp = (await _load(
        _legacyComparison()
          ..['completed_count'] = 'oops'
          ..['discount_minor'] = <String, dynamic>{'nope': 1},
      )).comparison!;

      expect(cmp.completedOrderCount, isNull);
      expect(cmp.discountTotalMinor, isNull);
      // The rest of the comparison is untouched by one bad field.
      expect(cmp.netSalesMinor, 17000);
    });

    test('E2. a NUMERIC STRING is still accepted, like every other field on '
        'this transport', () async {
      final cmp = (await _load(
        _legacyComparison()
          ..['completed_count'] = '4'
          ..['discount_minor'] = '1200',
      )).comparison!;

      expect(cmp.completedOrderCount, 4);
      expect(cmp.discountTotalMinor, 1200);
    });

    test('F. the original five fields are unchanged by the addition', () async {
      final withNew = (await _load(
        _legacyComparison()
          ..['completed_count'] = 4
          ..['discount_minor'] = 1200,
      )).comparison!;
      final withoutNew = (await _load(_legacyComparison())).comparison!;

      expect(withNew.orderCount, withoutNew.orderCount);
      expect(withNew.grossSalesMinor, withoutNew.grossSalesMinor);
      expect(withNew.netSalesMinor, withoutNew.netSalesMinor);
      expect(withNew.cashSalesMinor, withoutNew.cashSalesMinor);
    });

    test('the CURRENT-window primitives the comparison is measured against are '
        'the same server keys', () async {
      final report = await _load(_legacyComparison());
      expect(report.completedOrderCount, 6); // current.completed_count
      expect(report.discountTotalMinor, 1500); // current.discount_minor
      expect(report.orderCount, 8);
      expect(report.netSalesMinor, 22500);
    });

    test('the LEGACY report paths leave the additive fields absent — their '
        'prior blocks genuinely do not carry them', () async {
      // owner_report_range missing -> owner_daily_report (prior_day has only
      // order_count / gross / net / cash).
      final repo = RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: _FakeTransport((function, _) {
          if (function == 'owner_report_range') {
            throw const SyncTransportException(
              SyncTransportErrorKind.server,
              code: 'PGRST202',
              message: 'Could not find the function public.owner_report_range',
            );
          }
          return <String, dynamic>{
            'ok': true,
            'entity': 'owner_daily_report',
            'currency_code': 'ILS',
            'business_date': '2026-08-08',
            'today': <String, dynamic>{
              'order_count': 4,
              'completed_count': 3,
              'net_minor': 12000,
              'discount_minor': 200,
            },
            'prior_day': <String, dynamic>{
              'order_count': 2,
              'gross_minor': 8000,
              'net_minor': 8000,
              'cash_minor': 8000,
            },
          };
        }),
      );

      final cmp = (await repo.loadReport()).comparison!;
      expect(cmp.orderCount, 2);
      expect(cmp.completedOrderCount, isNull);
      expect(cmp.discountTotalMinor, isNull);
    });
  });

  group('average order value — integer minor units on both sides', () {
    test('exact integer division is pinned on the prior side', () {
      // 1000 / 4 = 250 and 900 / 3 = 300 — the brief's worked example.
      expect(
        const ReportComparison(
          grossSalesMinor: 900,
          netSalesMinor: 900,
          orderCount: 3,
          cashSalesMinor: 0,
        ).avgOrderValueMinor,
        300,
      );
      // Truncating, never rounding: 1000 / 3 = 333, not 334.
      expect(
        const ReportComparison(
          grossSalesMinor: 1000,
          netSalesMinor: 1000,
          orderCount: 3,
          cashSalesMinor: 0,
        ).avgOrderValueMinor,
        333,
      );
      expect(
        const ReportComparison(
          grossSalesMinor: 1000,
          netSalesMinor: 1000,
          orderCount: 4,
          cashSalesMinor: 0,
        ).avgOrderValueMinor,
        250,
      );
    });

    test(
      'a prior window with NO orders has no average at all (null), not 0',
      () {
        const cmp = ReportComparison(
          grossSalesMinor: 0,
          netSalesMinor: 0,
          orderCount: 0,
          cashSalesMinor: 0,
        );
        expect(cmp.avgOrderValueMinor, isNull);
        // ...so the delta against it has no basis, rather than looking infinite.
        expect(
          ComparisonDelta.of(250, cmp.avgOrderValueMinor).state,
          ComparisonState.noBasis,
        );
      },
    );

    test('the value stays an int — no double ever enters the money path', () {
      final value = const ReportComparison(
        grossSalesMinor: 1000,
        netSalesMinor: 1000,
        orderCount: 3,
        cashSalesMinor: 0,
      ).avgOrderValueMinor;
      expect(value, isA<int>());
      expect(value, isNot(isA<double>()));
    });

    test('the CURRENT side keeps its existing product behaviour (0 for an '
        'order-less window) — only the comparison basis is nullable', () {
      final report = demoRangeReport(ReportRange.today);
      expect(report.avgOrderValueMinor, isA<int>());
      expect(
        report.avgOrderValueMinor,
        report.netSalesMinor ~/ report.orderCount,
      );
    });

    test('the worked example end to end: 1000/4 vs 900/3 is a decrease', () {
      const prior = ReportComparison(
        grossSalesMinor: 900,
        netSalesMinor: 900,
        orderCount: 3,
        cashSalesMinor: 0,
      );
      final delta = ComparisonDelta.of(1000 ~/ 4, prior.avgOrderValueMinor);
      expect(delta.current, 250);
      expect(delta.prior, 300);
      expect(delta.state, ComparisonState.decrease);
      expect(delta.absolute, -50);
      expect(delta.percent, -16); // -50 * 100 ~/ 300, truncated toward zero
    });
  });

  group('ComparisonDelta integration for the new metrics', () {
    test('a discount that grew is an INCREASE — direction only, no judgement '
        'is encoded in the delta itself', () {
      final delta = ComparisonDelta.of(1500, 1200);
      expect(delta.state, ComparisonState.increase);
      expect(delta.absolute, 300);
      expect(delta.percent, 25);
    });

    test('fewer completed orders is a DECREASE, not an error', () {
      final delta = ComparisonDelta.of(4, 6);
      expect(delta.state, ComparisonState.decrease);
      expect(delta.absolute, -2);
      expect(delta.percent, -33);
    });

    test('an identical value is FLAT — a measured no-change, distinct from no '
        'basis', () {
      final flat = ComparisonDelta.of(6, 6);
      expect(flat.state, ComparisonState.flat);
      expect(flat.absolute, 0);
      expect(flat.percent, 0);
      expect(flat.hasBasis, isTrue);
      expect(flat.state, isNot(ComparisonState.noBasis));
    });

    test('a prior of ZERO yields noBasis, not +100%', () {
      final delta = ComparisonDelta.of(1500, 0);
      expect(delta.state, ComparisonState.noBasis);
      expect(delta.percent, isNull);
      expect(delta.absolute, isNull);
    });

    test('a prior of NULL — the not-deployed server — yields noBasis', () {
      final delta = ComparisonDelta.of(1500, null);
      expect(delta.state, ComparisonState.noBasis);
      expect(delta.percent, isNull);
    });

    test('money values stay int through the delta', () {
      final delta = ComparisonDelta.of(22500, 17000);
      expect(delta.current, isA<int>());
      expect(delta.prior, isA<int>());
      expect(delta.absolute, isA<int>());
      expect(delta.percent, isA<int>());
    });

    test('there is no second percent implementation — the shared delta matches '
        'the legacy deltaPercent exactly', () {
      for (final (current, prior) in const [
        (22500, 17000),
        (4, 6),
        (1500, 1200),
        (0, 5),
        (7, 7),
        (-100, 250),
      ]) {
        expect(
          ComparisonDelta.of(current, prior).percent,
          deltaPercent(current, prior),
          reason: 'ComparisonDelta.of($current, $prior)',
        );
      }
    });
  });

  group('demo comparison data is internally consistent', () {
    test('the demo prior window carries both additive primitives', () {
      final report = demoRangeReport(ReportRange.today);
      final cmp = report.comparison!;
      expect(cmp.completedOrderCount, isNotNull);
      expect(cmp.discountTotalMinor, isNotNull);
    });

    test("the today fixture's prior discount equals its own gross - net", () {
      final cmp = demoRangeReport(ReportRange.today).comparison!;
      expect(cmp.discountTotalMinor, cmp.grossSalesMinor - cmp.netSalesMinor);
    });

    test('the prior completed count never exceeds the prior order count', () {
      for (final range in ReportRange.values) {
        final cmp = demoRangeReport(range).comparison!;
        expect(
          cmp.completedOrderCount!,
          lessThanOrEqualTo(cmp.orderCount),
          reason: 'range $range',
        );
      }
    });
  });
}
