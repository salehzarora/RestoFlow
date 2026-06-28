import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_reports_repository.dart';
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
}
