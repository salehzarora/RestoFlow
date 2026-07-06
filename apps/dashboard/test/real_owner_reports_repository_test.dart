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

  // --- LIVE-DASHBOARD-001: owner_daily_report -> sales_summary fallback -------

  // A deployed sales_summary payload (today + a zero-filled last-7-days tail).
  Map<String, dynamic> salesSummary() => <String, dynamic>{
    'ok': true,
    'entity': 'sales_summary',
    'currency_code': 'ILS',
    'today': <String, dynamic>{
      'orders_count': 5,
      'payments_count': 3,
      'gross_minor': 12000,
    },
    'last_7_days': <Map<String, dynamic>>[
      {'day': '2026-06-29', 'orders_count': 0, 'gross_minor': 0},
      {'day': '2026-07-05', 'orders_count': 5, 'gross_minor': 12000},
    ],
  };

  test('missing owner_daily_report RPC (PGRST202) -> falls back to '
      'sales_summary and maps its LIMITED figures', () async {
    final calls = <String>[];
    final transport = _FakeTransport((fn, _) {
      calls.add(fn);
      if (fn == 'owner_daily_report') {
        throw const SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'PGRST202',
          message:
              'Could not find the function public.owner_daily_report'
              '(p_branch_id, p_organization_id, p_restaurant_id) in the '
              'schema cache',
        );
      }
      return salesSummary();
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    // Tried the new RPC FIRST, then fell back to the deployed one — same scope.
    expect(calls, ['owner_daily_report', 'sales_summary']);
    expect(transport.lastParams, {
      'p_organization_id': 'org-1',
      'p_restaurant_id': 'rest-1',
      'p_branch_id': 'branch-1',
    });

    // The figures sales_summary actually provides (integer minor, D-007).
    expect(report.currencyCode, 'ILS');
    expect(report.businessDateLabel, '2026-07-05');
    expect(report.orderCount, 5);
    expect(report.completedOrderCount, 3);
    expect(report.grossSalesMinor, 12000);
    // net/collected/cash mirror gross in the limited build (no discount/tenders).
    expect(report.netSalesMinor, 12000);
    expect(report.collectedMinor, 12000);
    expect(report.cashSalesMinor, 12000);
    // orders - completed payments = open/unpaid approximation.
    expect(report.openOrderCount, 2);
    expect(report.unpaidOrderCount, 2);
  });

  test('the sales_summary fallback keeps UNSUPPORTED fields honest / empty '
      '(never fabricated)', () async {
    final transport = _FakeTransport((fn, _) {
      if (fn == 'owner_daily_report') {
        throw const SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'PGRST202',
          message: 'Could not find the function public.owner_daily_report',
        );
      }
      return salesSummary();
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.discountTotalMinor, 0);
    expect(report.voidCount, 0);
    expect(report.voidTotalMinor, 0);
    expect(report.lastCashPaymentMinor, 0);
    expect(report.paymentMethods, isEmpty); // no tender breakdown
    // LIVE-UX-001: a comparison IS now derived from last_7_days, but this
    // fixture's yesterday is zero, so deltaPercent guards it -> NO visible
    // "vs yesterday" delta (honest, never a fabricated jump).
    expect(report.comparison?.grossSalesMinor, 0);
    expect(
      deltaPercent(report.netSalesMinor, report.comparison?.netSalesMinor),
      isNull,
    );
    expect(report.hourlyNetSales, isEmpty); // chart stays hidden
    expect(report.branches, isEmpty);
    expect(report.topItems, isEmpty);
    expect(report.recentOrders, isEmpty);
    expect(report.shiftStatus, 'none');
    expect(report.openingFloatMinor, 0);
    expect(report.expectedCashMinor, 0);
    expect(report.countedCashMinor, 0);
  });

  test('permission-denied (42501) NEVER falls back -> OwnerReportsException '
      '(sales_summary is not even attempted)', () async {
    final calls = <String>[];
    final transport = _FakeTransport((fn, _) {
      calls.add(fn);
      throw const SyncTransportException(
        SyncTransportErrorKind.auth,
        code: '42501',
        message: 'permission denied',
      );
    });

    await expectLater(
      RealOwnerReportsRepository(
        null,
        scope: _scope(),
        transport: transport,
      ).loadReport(),
      throwsA(isA<OwnerReportsException>()),
    );
    // Fail-closed: the auth denial must NOT be converted into fallback data.
    expect(calls, ['owner_daily_report']);
  });

  test(
    'a NON-missing server error does not fall back -> OwnerReportsException',
    () async {
      final calls = <String>[];
      final transport = _FakeTransport((fn, _) {
        calls.add(fn);
        throw const SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'P0001', // a real server-side raise, not a missing function
          message: 'boom',
        );
      });

      await expectLater(
        RealOwnerReportsRepository(
          null,
          scope: _scope(),
          transport: transport,
        ).loadReport(),
        throwsA(isA<OwnerReportsException>()),
      );
      expect(calls, ['owner_daily_report']);
    },
  );

  // --- LIVE-UX-001: a SAFE "vs yesterday" comparison from last_7_days ----------

  SyncTransportException missingOwnerReport() => const SyncTransportException(
    SyncTransportErrorKind.server,
    code: 'PGRST202',
    message: 'Could not find the function public.owner_daily_report',
  );

  test('LIVE-UX-001: the sales_summary fallback derives a SAFE "vs yesterday" '
      'comparison from last_7_days[len-2] (net/cash mirror gross, no '
      'fabrication)', () async {
    final transport = _FakeTransport((fn, _) {
      if (fn == 'owner_daily_report') throw missingOwnerReport();
      return <String, dynamic>{
        'ok': true,
        'entity': 'sales_summary',
        'currency_code': 'ILS',
        'today': {'orders_count': 5, 'payments_count': 3, 'gross_minor': 12000},
        'last_7_days': <Map<String, dynamic>>[
          {'day': '2026-07-03', 'orders_count': 2, 'gross_minor': 4000},
          {'day': '2026-07-04', 'orders_count': 4, 'gross_minor': 8000}, // ytd
          {'day': '2026-07-05', 'orders_count': 5, 'gross_minor': 12000}, // now
        ],
      };
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    final c = report.comparison;
    expect(c, isNotNull);
    // yesterday = last_7_days[len-2] = {orders:4, gross:8000}; the limited build
    // mirrors net/cash onto gross, so all three carry yesterday's gross_minor.
    expect(c!.grossSalesMinor, 8000);
    expect(c.netSalesMinor, 8000);
    expect(c.cashSalesMinor, 8000);
    expect(c.orderCount, 4);
    // The KPI deltas now compute (today 12000 vs yesterday 8000 = +50%).
    expect(
      deltaPercent(report.netSalesMinor, c.netSalesMinor),
      (12000 - 8000) * 100 ~/ 8000,
    );
    // Still NO fabricated hourly curve — the chart must stay hidden.
    expect(report.hourlyNetSales, isEmpty);
  });

  test('LIVE-UX-001: a short / malformed last_7_days yields NO comparison '
      '(never a fabricated delta)', () async {
    final transport = _FakeTransport((fn, _) {
      if (fn == 'owner_daily_report') throw missingOwnerReport();
      return <String, dynamic>{
        'ok': true,
        'entity': 'sales_summary',
        'currency_code': 'ILS',
        'today': {'orders_count': 5, 'payments_count': 3, 'gross_minor': 12000},
        // Only today -> no prior day to compare against.
        'last_7_days': <Map<String, dynamic>>[
          {'day': '2026-07-05', 'orders_count': 5, 'gross_minor': 12000},
        ],
      };
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.comparison, isNull);
  });

  // --- RF-REPORT-002: TODAY sales-by-hour mapping ------------------------------

  test('RF-REPORT-002: owner_daily_report hourly maps into the chart data '
      '(HH:00 labels, integer minor)', () async {
    final transport = _FakeTransport((_, _) {
      final p = _payload();
      p['hourly'] = <Map<String, dynamic>>[
        {'hour': 0, 'net_minor': 0},
        {'hour': 9, 'net_minor': 1000},
        {'hour': 14, 'net_minor': 2000},
      ];
      return p;
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.hourlyNetSales.length, 3);
    expect(report.hourlyNetSales[0].hourLabel, '00:00');
    expect(report.hourlyNetSales[1].hourLabel, '09:00');
    expect(report.hourlyNetSales[1].netSalesMinor, 1000);
    expect(report.hourlyNetSales[2].hourLabel, '14:00');
    expect(report.hourlyNetSales[2].netSalesMinor, 2000);
    expect(report.hourlyNetSales[2].netSalesMinor, isA<int>());
  });

  test('RF-REPORT-002: an ALL-ZERO hourly maps to EMPTY (chart hidden, never a '
      'flat-zero curve)', () async {
    final transport = _FakeTransport((_, _) {
      final p = _payload();
      p['hourly'] = [
        for (var h = 0; h < 24; h++) {'hour': h, 'net_minor': 0},
      ];
      return p;
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.hourlyNetSales, isEmpty);
  });

  test(
    'RF-REPORT-002: a malformed / missing hourly is handled safely (empty)',
    () async {
      for (final bad in <Object?>['not-a-list', 42, null]) {
        final transport = _FakeTransport((_, _) {
          final p = _payload();
          if (bad != null) p['hourly'] = bad;
          return p;
        });
        final report = await RealOwnerReportsRepository(
          null,
          scope: _scope(),
          transport: transport,
        ).loadReport();
        expect(report.hourlyNetSales, isEmpty);
      }
    },
  );

  test('RF-REPORT-002: hourly SKIPS non-map rows and out-of-range hours '
      '(defensive, keeps only valid buckets)', () async {
    final transport = _FakeTransport((_, _) {
      final p = _payload();
      p['hourly'] = <Object?>[
        'not-a-map', // skipped: row is not a Map
        42, // skipped: row is not a Map
        {'hour': -1, 'net_minor': 9999}, // skipped: hour < 0
        {'hour': 24, 'net_minor': 9999}, // skipped: hour > 23
        {'hour': 9, 'net_minor': 1000}, // kept
      ];
      return p;
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.hourlyNetSales.length, 1);
    expect(report.hourlyNetSales.single.hourLabel, '09:00');
    expect(report.hourlyNetSales.single.netSalesMinor, 1000);
  });

  test('RF-REPORT-002: the sales_summary fallback still has NO hourly (chart '
      'stays hidden in fallback)', () async {
    final transport = _FakeTransport((fn, _) {
      if (fn == 'owner_daily_report') throw missingOwnerReport();
      return <String, dynamic>{
        'ok': true,
        'entity': 'sales_summary',
        'currency_code': 'ILS',
        'today': {'orders_count': 5, 'payments_count': 3, 'gross_minor': 12000},
        'last_7_days': <Map<String, dynamic>>[
          {'day': '2026-07-04', 'orders_count': 4, 'gross_minor': 8000},
          {'day': '2026-07-05', 'orders_count': 5, 'gross_minor': 12000},
        ],
      };
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.hourlyNetSales, isEmpty);
  });

  // --- RF-REPORT-003: TODAY shift / cash reconciliation mapping ---------------

  Future<DashboardReport> loadWith(void Function(Map<String, dynamic>) mut) {
    final transport = _FakeTransport((_, _) {
      final p = _payload();
      mut(p);
      return p;
    });
    return RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();
  }

  test('RF-REPORT-003: owner_daily_report shift_cash maps into ShiftCash '
      '(counts, expected/counted/SIGNED variance, last + recent)', () async {
    final report = await loadWith((p) {
      p['shift_cash'] = <String, dynamic>{
        'closed_shift_count': 2,
        'open_shift_count': 1,
        'expected_cash_minor': 3500,
        'counted_cash_minor': 3490,
        'cash_variance_minor': -10, // negative (shortage) supported
        'last_closed_shift': {
          'shift_id': 's2',
          'branch_id': 'b1',
          'branch_name': 'Main',
          'opened_at': '2026-07-06T09:00:00Z',
          'closed_at': '2026-07-06T18:00:00Z',
          'closed_by_name': 'Amira K.',
          'expected_cash_minor': 2000,
          'counted_cash_minor': 2050,
          'cash_variance_minor': 50,
        },
        'recent_closed_shifts': [
          {
            'shift_id': 's2',
            'branch_name': 'Main',
            'closed_at': '2026-07-06T18:00:00Z',
            'closed_by_name': 'Amira K.',
            'expected_cash_minor': 2000,
            'counted_cash_minor': 2050,
            'cash_variance_minor': 50,
          },
          {
            'shift_id': 's1',
            'branch_name': 'Main',
            'closed_at': '2026-07-06T10:00:00Z',
            'closed_by_name': 'Amira K.',
            'expected_cash_minor': 1500,
            'counted_cash_minor': 1440,
            'cash_variance_minor': -60,
          },
        ],
      };
    });

    final sc = report.shiftCash;
    expect(sc, isNotNull);
    expect(sc!.closedShiftCount, 2);
    expect(sc.openShiftCount, 1);
    expect(sc.expectedCashMinor, 3500);
    expect(sc.countedCashMinor, 3490);
    expect(sc.varianceMinor, -10);
    expect(sc.varianceMinor, isA<int>());
    expect(sc.hasClosedShifts, isTrue);
    expect(sc.lastClosedShift, isNotNull);
    expect(sc.lastClosedShift!.shiftId, 's2');
    expect(sc.lastClosedShift!.branchName, 'Main');
    expect(sc.lastClosedShift!.closedByName, 'Amira K.');
    expect(sc.lastClosedShift!.varianceMinor, 50);
    expect(sc.recentClosedShifts.length, 2);
    expect(sc.recentClosedShifts.first.shiftId, 's2'); // newest first
    expect(sc.recentClosedShifts.last.varianceMinor, -60);
  });

  test(
    'RF-REPORT-003: NO shift_cash -> null (card hides, never fabricated)',
    () async {
      // _payload() carries no shift_cash key.
      final report = await loadWith((_) {});
      expect(report.shiftCash, isNull);
    },
  );

  test('RF-REPORT-003: a malformed shift_cash is handled safely', () async {
    // Non-map top-level -> null.
    var report = await loadWith((p) => p['shift_cash'] = 'nope');
    expect(report.shiftCash, isNull);

    // Malformed nested rows are DROPPED, not crashed.
    report = await loadWith((p) {
      p['shift_cash'] = <String, dynamic>{
        'closed_shift_count': 1,
        'open_shift_count': 0,
        'expected_cash_minor': 100,
        'counted_cash_minor': 100,
        'cash_variance_minor': 0,
        'last_closed_shift': 'not-a-map', // -> null
        'recent_closed_shifts': [
          'not-a-map',
          42,
          {
            'shift_id': 'ok',
            'branch_name': 'B',
            'closed_at': 't',
            'closed_by_name': 'X',
            'expected_cash_minor': 100,
            'counted_cash_minor': 100,
            'cash_variance_minor': 0,
          },
        ],
      };
    });
    expect(report.shiftCash, isNotNull);
    expect(report.shiftCash!.lastClosedShift, isNull);
    expect(
      report.shiftCash!.recentClosedShifts.length,
      1,
    ); // only the valid row
  });

  test('RF-REPORT-003: the sales_summary fallback has NO shift_cash', () async {
    final transport = _FakeTransport((fn, _) {
      if (fn == 'owner_daily_report') throw missingOwnerReport();
      return <String, dynamic>{
        'ok': true,
        'entity': 'sales_summary',
        'currency_code': 'ILS',
        'today': {'orders_count': 5, 'payments_count': 3, 'gross_minor': 12000},
        'last_7_days': <Map<String, dynamic>>[
          {'day': '2026-07-06', 'orders_count': 5, 'gross_minor': 12000},
        ],
      };
    });

    final report = await RealOwnerReportsRepository(
      null,
      scope: _scope(),
      transport: transport,
    ).loadReport();

    expect(report.shiftCash, isNull);
  });
}
