import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/demo_report.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_sales_series_repository.dart';
import 'package:restoflow_dashboard/src/state/dashboard_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Verifies the M7 demo/real DI selection at the ownerReportsRepositoryProvider
/// seam. No SupabaseClient and no network are involved: the choice is driven
/// purely by [runtimeConfigProvider], and the Real* path is a throwing skeleton
/// - so this test also proves the real surface never contacts a backend yet.
void main() {
  late ProviderContainer container;

  tearDown(() => container.dispose());

  test(
    'demo mode (default) selects the Demo repo and yields the demo report',
    () async {
      container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );

      final repo = container.read(ownerReportsRepositoryProvider);
      expect(repo, isA<DemoOwnerReportsRepository>());

      // The demo dataset is preserved and computed locally (no backend): a
      // non-empty report with integer-minor money (no float introduced).
      final report = await container.read(dashboardReportProvider.future);
      expect(report.isEmpty, isFalse);
      expect(report.orderCount, greaterThan(0));
      expect(report.netSalesMinor, isA<int>());
    },
  );

  test(
    'real mode selects the Real skeleton and loadReport fails closed',
    () async {
      container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );

      final repo = container.read(ownerReportsRepositoryProvider);
      expect(repo, isA<RealOwnerReportsRepository>());

      // No backend contact: the skeleton throws rather than fabricating data,
      // surfaced through the existing FutureProvider error state.
      await expectLater(
        container.read(dashboardReportProvider.future),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    },
  );

  // CLIENT-A: the daily sales series is a SECOND seam on the same mode switch.
  // It gets the same guard, because the failure it prevents is the same one and
  // is worse when only half the Overview flips: a real report beside a demo
  // trend would look completely plausible.
  test('demo mode selects the Demo sales-series repo', () async {
    container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
      ],
    );

    expect(
      container.read(ownerSalesSeriesRepositoryProvider),
      isA<DemoOwnerSalesSeriesRepository>(),
    );

    final key = container.read(currentOwnerSalesSeriesKeyProvider);
    expect(key, isNull, reason: 'today (the default) needs no daily series');
  });

  test('real mode selects the Real sales-series repo and fails closed with no '
      'transport/scope', () async {
    container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
      ],
    );

    expect(
      container.read(ownerSalesSeriesRepositoryProvider),
      isA<RealOwnerSalesSeriesRepository>(),
    );

    container.read(reportRangeProvider.notifier).state = ReportRange.last7;
    final key = container.read(currentOwnerSalesSeriesKeyProvider)!;
    expect(key.isDemoMode, isFalse);

    await expectLater(
      container.read(ownerSalesSeriesForKeyProvider(key).future),
      throwsA(isA<RealRepoNotWiredError>()),
    );
  });

  test('the two seams agree on the mode — a real report can never sit beside a '
      'demo trend', () {
    for (final demo in const [true, false]) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: demo),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(ownerReportsRepositoryProvider) is DemoOwnerReportsRepository,
        c.read(ownerSalesSeriesRepositoryProvider)
            is DemoOwnerSalesSeriesRepository,
        reason: 'both seams must resolve to the same data source (demo=$demo)',
      );
    }
  });
}
