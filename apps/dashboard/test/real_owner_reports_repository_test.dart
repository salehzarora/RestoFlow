import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// RF-REPORT-001 Slice 1 — maps `public.owner_daily_report` into the Overview's
/// [DashboardReport]: billed sales SPLIT from collected payments, tender
/// breakdown, prior-day deltas; fail-closed with no transport/scope or on a
/// rejected/failed RPC; NO fabricated hourly/branch/shift data in real mode.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastFunction = function;
    lastParams = params;
    return _handler(function, params);
  }
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

// A realistic owner_daily_report payload: billed gross 3900 / discount 200 /
// net 3700; voids 1x5000; collected 3200 (cash 1400 + card 1800); prior day 1200.
Map<String, dynamic> _payload() => <String, dynamic>{
  'ok': true,
  'entity': 'owner_daily_report',
  'currency_code': 'ILS',
  'business_date': '2026-07-05',
  'today': <String, dynamic>{
    'order_count': 4,
    'completed_count': 2,
    'open_count': 2,
    'unpaid_count': 1,
    'gross_minor': 3900,
    'discount_minor': 200,
    'net_minor': 3700,
    'void_count': 1,
    'void_total_minor': 5000,
    'collected_minor': 3200,
    'cash_minor': 1400,
    'last_cash_payment_minor': 400,
    'tenders': <Map<String, dynamic>>[
      {'method': 'card', 'count': 1, 'total_minor': 1800},
      {'method': 'cash', 'count': 2, 'total_minor': 1400},
    ],
  },
  'prior_day': <String, dynamic>{
    'order_count': 1,
    'gross_minor': 1200,
    'net_minor': 1200,
    'cash_minor': 1200,
  },
};

void main() {
  test('maps the owner_daily_report payload into DashboardReport (billed vs '
      'collected SPLIT, integer minor)', () async {
    final transport = _FakeTransport((_, _) => _payload());
    final repo = RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    );

    final report = await repo.loadReport();

    // Calls the RIGHT RPC with the membership scope.
    expect(transport.lastFunction, 'owner_daily_report');
    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
    });

    // Billed sales.
    expect(report.currencyCode, 'ILS');
    expect(report.businessDateLabel, '2026-07-05');
    expect(report.grossSalesMinor, 3900);
    expect(report.discountTotalMinor, 200);
    expect(report.netSalesMinor, 3700);
    expect(report.voidCount, 1);
    expect(report.voidTotalMinor, 5000);
    expect(report.orderCount, 4);
    expect(report.completedOrderCount, 2);
    expect(report.openOrderCount, 2);
    expect(report.unpaidOrderCount, 1);

    // Collected is SPLIT from billed (never conflated).
    expect(report.collectedMinor, 3200);
    expect(report.cashSalesMinor, 1400);
    expect(report.lastCashPaymentMinor, 400);
    expect(
      report.grossSalesMinor == report.collectedMinor,
      isFalse,
      reason: 'billed gross must not equal collected',
    );

    // avg ticket = net // orderCount (integer, no float).
    expect(report.avgOrderValueMinor, 3700 ~/ 4);
    expect(report.netSalesMinor, isA<int>());

    // Tender breakdown -> payment methods, order preserved.
    expect(report.paymentMethods.map((p) => p.method).toList(), [
      'card',
      'cash',
    ]);
    expect(report.paymentMethods[1].count, 2);
    expect(report.paymentMethods[1].totalMinor, 1400);
    expect(report.paymentMethods[0].currencyCode, 'ILS');

    // Prior-day -> comparison; "vs yesterday" deltas compute (net +208%).
    expect(report.comparison, isNotNull);
    expect(report.comparison!.netSalesMinor, 1200);
    expect(
      deltaPercent(report.netSalesMinor, report.comparison!.netSalesMinor),
      (3700 - 1200) * 100 ~/ 1200,
    );
  });

  test(
    'Slice 1 does NOT fabricate hourly / branch / shift data in real mode',
    () async {
      final transport = _FakeTransport((_, _) => _payload());
      final report = await RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: transport,
      ).loadReport();

      expect(report.hourlyNetSales, isEmpty); // chart stays hidden (data-gated)
      expect(report.branches, isEmpty);
      expect(report.topItems, isEmpty);
      expect(report.recentOrders, isEmpty);
      expect(report.shiftStatus, 'none');
      expect(report.openingFloatMinor, 0);
      expect(report.expectedCashMinor, 0);
      expect(report.countedCashMinor, 0);
    },
  );

  test(
    'an empty real day maps to zeros / empty (honest, not fabricated)',
    () async {
      final transport = _FakeTransport(
        (_, _) => <String, dynamic>{
          'ok': true,
          'entity': 'owner_daily_report',
          'currency_code': 'ILS',
          'business_date': '2026-07-05',
          'today': <String, dynamic>{'tenders': <dynamic>[]},
          'prior_day': <String, dynamic>{},
        },
      );
      final report = await RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: transport,
      ).loadReport();

      expect(report.isEmpty, isTrue);
      expect(report.orderCount, 0);
      expect(report.grossSalesMinor, 0);
      expect(report.collectedMinor, 0);
      expect(report.paymentMethods, isEmpty);
    },
  );

  test('fail-closed: no transport/scope -> RealRepoNotWiredError', () async {
    expect(
      RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: null,
      ).loadReport(),
      throwsA(isA<RealRepoNotWiredError>()),
    );
    final transport = _FakeTransport((_, _) => _payload());
    expect(
      RealOwnerReportsRepository(
        null,
        scope: null,
        transport: transport,
      ).loadReport(),
      throwsA(isA<RealRepoNotWiredError>()),
    );
  });

  test(
    'fail-closed: ok!=true -> OwnerReportsException (never demo fallback)',
    () async {
      final transport = _FakeTransport(
        (_, _) => <String, dynamic>{'ok': false, 'error': 'permission_denied'},
      );
      expect(
        RealOwnerReportsRepository(
          null,
          scope: _scope(),
          transport: transport,
        ).loadReport(),
        throwsA(isA<OwnerReportsException>()),
      );
    },
  );

  test('fail-closed: a transport failure -> OwnerReportsException', () async {
    final transport = _FakeTransport(
      (_, _) => throw const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
      ),
    );
    expect(
      RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: transport,
      ).loadReport(),
      throwsA(isA<OwnerReportsException>()),
    );
  });
}
