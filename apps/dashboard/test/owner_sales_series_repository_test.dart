import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_sales_series_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the sales-series repositories.
///
/// The real one is pinned to the EXACT wire contract (RPC name, the four params,
/// and the absence of the custom-window params) because that contract is the
/// whole seam. The demo one is pinned to agreeing with the demo range report,
/// which is the property that stops the demo trend and the demo KPI above it
/// from telling an owner two different stories.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String function, Map<String, dynamic> params) _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  String? get lastFunction => functions.isEmpty ? null : functions.last;
  Map<String, dynamic>? get lastParams => params.isEmpty ? null : params.last;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(args);
    return _handler(function, args);
  }
}

MembershipContext _scope({
  String? restaurantId = 'rest-1',
  String? branchId = 'branch-1',
}) => MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: restaurantId,
  restaurantName: 'Rest 1',
  branchId: branchId,
  branchName: 'Branch 1',
  role: MembershipRole.orgOwner,
  status: 'active',
);

Map<String, dynamic> _payload({String range = 'last7'}) => <String, dynamic>{
  'ok': true,
  'entity': 'owner_sales_series',
  'currency_code': 'ILS',
  'range': range,
  'buckets': <Map<String, dynamic>>[
    {
      'day': '2026-08-07',
      'order_count': 4,
      'gross_minor': 12000,
      'discount_minor': 500,
      'net_minor': 11500,
      'void_count': 0,
      'void_total_minor': 0,
      'collected_minor': 9000,
      'cash_minor': 6000,
      'by_method': <Map<String, dynamic>>[
        {'method': 'card', 'count': 1, 'total_minor': 3000},
      ],
      'by_order_type': <Map<String, dynamic>>[
        {'order_type': 'takeaway', 'order_count': 1, 'net_minor': 2000},
      ],
    },
  ],
};

/// A pinned 'now' so the demo day labels are deterministic: a real clock would
/// make these assertions rot the next time the suite ran across midnight.
DateTime fixedNow() => DateTime(2026, 8, 8, 14, 30);

void main() {
  group('RealOwnerSalesSeriesRepository — the wire contract', () {
    test(
      'calls owner_sales_series with exactly the four scope+range params',
      () async {
        final transport = _FakeTransport((_, _) => _payload());
        final repo = RealOwnerSalesSeriesRepository(
          scope: _scope(),
          transport: transport,
        );

        await repo.loadSeries(range: AnalyticsRange.last7);

        expect(transport.lastFunction, 'owner_sales_series');
        expect(transport.lastParams, {
          'p_organization_id': 'org-1',
          // CODEX F-1A: the fixture membership is an ORG owner, so its COVERAGE is
          // the whole organization. rest-1 / branch-1 are what resolveTenantContext
          // pinned onto it, and sending them as the request scope was the defect —
          // the family key said one branch while the RPC asked for another.
          'p_restaurant_id': null,
          'p_branch_id': null,
          'p_range': 'last7',
        });
      },
    );

    test(
      'does NOT send p_start / p_end — there is no custom range yet, and a '
      'client-computed window would re-own the timezone the server owns',
      () async {
        final transport = _FakeTransport((_, _) => _payload());
        final repo = RealOwnerSalesSeriesRepository(
          scope: _scope(),
          transport: transport,
        );

        await repo.loadSeries(range: AnalyticsRange.last30);

        expect(transport.lastParams!.containsKey('p_start'), isFalse);
        expect(transport.lastParams!.containsKey('p_end'), isFalse);
        expect(transport.lastParams, hasLength(4));
      },
    );

    test('sends the EXACT last7 / last30 wire tokens', () async {
      final transport = _FakeTransport((_, _) => _payload());
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(),
        transport: transport,
      );

      await repo.loadSeries(range: AnalyticsRange.last7);
      expect(transport.lastParams!['p_range'], 'last7');

      await repo.loadSeries(range: AnalyticsRange.last30);
      expect(transport.lastParams!['p_range'], 'last30');
    });

    test('sends a NULL restaurant/branch for an org-wide membership rather '
        'than omitting or inventing one', () async {
      final transport = _FakeTransport((_, _) => _payload());
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(restaurantId: null, branchId: null),
        transport: transport,
      );

      await repo.loadSeries(range: AnalyticsRange.last7);

      expect(transport.lastParams!['p_restaurant_id'], isNull);
      expect(transport.lastParams!['p_branch_id'], isNull);
      expect(transport.lastParams!.containsKey('p_branch_id'), isTrue);
    });

    test('runs the response through the series parser', () async {
      final transport = _FakeTransport((_, _) => _payload());
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(),
        transport: transport,
      );

      final series = await repo.loadSeries(range: AnalyticsRange.last7);

      expect(series, isA<OwnerSalesSeries>());
      expect(series.currencyCode, 'ILS');
      expect(series.rangeWire, 'last7');
      expect(series.buckets.single.day.label, '2026-08-07');
      expect(series.buckets.single.netMinor, 11500);
      expect(series.buckets.single.byMethod.single.method, 'card');
    });

    test('fails closed with no transport or no scope', () async {
      await expectLater(
        const RealOwnerSalesSeriesRepository().loadSeries(
          range: AnalyticsRange.last7,
        ),
        throwsA(isA<RealRepoNotWiredError>()),
      );
      await expectLater(
        RealOwnerSalesSeriesRepository(
          transport: _FakeTransport((_, _) => _payload()),
        ).loadSeries(range: AnalyticsRange.last7),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    });

    test('a transport failure surfaces honestly — never empty data', () async {
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(),
        transport: _FakeTransport((_, _) {
          throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            message: 'offline',
          );
        }),
      );

      await expectLater(
        repo.loadSeries(range: AnalyticsRange.last7),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
    });

    test('a REJECTED body (permission_denied) throws — never softened into '
        '"unavailable" and never fabricated', () async {
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(),
        transport: _FakeTransport(
          (_, _) => <String, dynamic>{
            'ok': false,
            'error': 'permission_denied',
            'entity': 'owner_sales_series',
          },
        ),
      );

      await expectLater(
        repo.loadSeries(range: AnalyticsRange.last7),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
    });

    test('a MISSING RPC degrades to the honest unavailable series — the '
        'SERVER-A migration is not applied to every database yet', () async {
      for (final e in const [
        SyncTransportException(
          SyncTransportErrorKind.server,
          code: 'PGRST202',
          message: 'Could not find the function public.owner_sales_series',
        ),
        SyncTransportException(
          SyncTransportErrorKind.server,
          code: '404',
          message: 'not found',
        ),
        SyncTransportException(
          SyncTransportErrorKind.server,
          message: 'function public.owner_sales_series does not exist',
        ),
      ]) {
        final repo = RealOwnerSalesSeriesRepository(
          scope: _scope(),
          transport: _FakeTransport((_, _) => throw e),
        );
        final series = await repo.loadSeries(range: AnalyticsRange.last7);
        expect(series.supported, isFalse);
        expect(series.buckets, isEmpty);
      }
    });

    test('an AUTH denial is never treated as missing — a denied caller must '
        'not be handed a softer story', () async {
      final repo = RealOwnerSalesSeriesRepository(
        scope: _scope(),
        transport: _FakeTransport((_, _) {
          throw const SyncTransportException(
            SyncTransportErrorKind.auth,
            code: 'PGRST202',
            message: 'could not find the function',
          );
        }),
      );

      await expectLater(
        repo.loadSeries(range: AnalyticsRange.last7),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
    });
  });

  group('DemoOwnerSalesSeriesRepository', () {
    test('produces one bucket per day, ascending, ending today', () async {
      const repo = DemoOwnerSalesSeriesRepository(clock: fixedNow);
      final series = await repo.loadSeries(range: AnalyticsRange.last7);

      expect(series.buckets, hasLength(7));
      expect(series.buckets.first.day.label, '2026-08-02');
      expect(series.buckets.last.day.label, '2026-08-08');
      for (var i = 1; i < series.buckets.length; i++) {
        expect(
          series.buckets[i - 1].day.compareTo(series.buckets[i].day),
          lessThan(0),
          reason: 'buckets must be strictly ascending by day',
        );
      }
    });

    test('last30 spans month boundaries without arithmetic drift', () async {
      const repo = DemoOwnerSalesSeriesRepository(clock: fixedNow);
      final series = await repo.loadSeries(range: AnalyticsRange.last30);

      expect(series.buckets, hasLength(30));
      expect(series.buckets.first.day.label, '2026-07-10');
      expect(series.buckets.last.day.label, '2026-08-08');
      expect(
        series.buckets.map((b) => b.day.label).toSet(),
        hasLength(30),
        reason: 'no duplicated day',
      );
    });

    test('the demo trend SUMS to the demo range report — one dataset, two '
        'surfaces, one number', () async {
      const repo = DemoOwnerSalesSeriesRepository(clock: fixedNow);
      for (final (range, reportRange) in const [
        (AnalyticsRange.last7, ReportRange.last7),
        (AnalyticsRange.last30, ReportRange.last30),
      ]) {
        final series = await repo.loadSeries(range: range);
        final report = await const DemoOwnerReportsRepository().loadReport(
          range: reportRange,
        );
        expect(
          series.netSalesMinor,
          report.netSalesMinor,
          reason: 'the daily trend must sum to the Net sales KPI for $range',
        );
        expect(series.orderCount, report.orderCount);
      }
    });

    test(
      'money stays integer minor and the demo currency is the demo one',
      () async {
        const repo = DemoOwnerSalesSeriesRepository(clock: fixedNow);
        final series = await repo.loadSeries(range: AnalyticsRange.last7);

        expect(series.currencyCode, kDemoCurrencyCode);
        expect(series.rangeWire, 'last7');
        for (final b in series.buckets) {
          expect(b.netMinor, isA<int>());
          expect(b.cashMinor, isA<int>());
          expect(b.netMinor, greaterThan(0));
        }
      },
    );

    test(
      'does not invent an order-type split the demo dataset does not model',
      () async {
        const repo = DemoOwnerSalesSeriesRepository(clock: fixedNow);
        final series = await repo.loadSeries(range: AnalyticsRange.last7);
        for (final b in series.buckets) {
          expect(b.byOrderType, isEmpty);
          // The tender breakdown IS modelled (cash), and sums to collected.
          expect(b.byMethod.single.method, 'cash');
          expect(b.byMethod.single.totalMinor, b.collectedMinor);
        }
      },
    );

    test('surfaces an injected failure rather than empty data', () async {
      const repo = DemoOwnerSalesSeriesRepository(
        failureMessage: 'forced failure',
      );
      await expectLater(
        repo.loadSeries(range: AnalyticsRange.last7),
        throwsA(isA<OwnerSalesSeriesException>()),
      );
    });
  });
}
