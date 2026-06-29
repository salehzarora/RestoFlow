import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Verifies the M7 demo/real DI selection at platformAdminRepositoryProvider.
/// No SupabaseClient and no network: the choice is driven purely by
/// [runtimeConfigProvider]. Platform admin stays READ-ONLY (D-026). Real mode
/// now selects the RF-128 [RealPlatformAdminRepository] (wired to the RF-125
/// public.platform_admin_* wrappers); with no Supabase config it fails closed
/// with a [PlatformAdminException] and contacts no backend. Demo stays default.
/// (The real repo's wrapper calls + JSON mapping are covered by
/// real_platform_admin_repository_test.dart.)
void main() {
  group('platformAdminRepositoryProvider mode selection', () {
    test(
      'demo mode (default) resolves the demo repo and loads demo data',
      () async {
        final container = ProviderContainer(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
          ],
        );
        addTearDown(container.dispose);

        final repo = container.read(platformAdminRepositoryProvider);
        expect(repo, isA<DemoPlatformAdminRepository>());

        // The demo overview is computed locally (no backend): a non-empty
        // platform with at least one organization.
        final overview = await repo.loadOverview();
        expect(overview.isEmpty, isFalse);
        expect(overview.organizationCount, greaterThan(0));
      },
    );

    test('real mode resolves RealPlatformAdminRepository; unconfigured it fails '
        'closed without a backend', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(platformAdminRepositoryProvider);
      expect(repo, isA<RealPlatformAdminRepository>());

      // No Supabase config (RuntimeConfig.test supplies none) -> the real repo
      // has no transport and fails closed; it contacts no backend.
      await expectLater(
        repo.loadOverview(),
        throwsA(isA<PlatformAdminException>()),
      );
    });
  });
}
