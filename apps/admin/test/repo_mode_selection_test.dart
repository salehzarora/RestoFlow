import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/real_platform_admin_repository.dart';
import 'package:restoflow_admin/src/state/platform_admin_providers.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// Verifies the M7 demo/real DI selection at platformAdminRepositoryProvider.
/// No SupabaseClient and no network: the choice is driven purely by
/// [runtimeConfigProvider]. Platform admin stays READ-ONLY (D-026); the RF-125
/// public.platform_admin_* wrappers now exist, but real client wiring is
/// intentionally deferred, so the real repo stays fail-closed - real mode never
/// contacts a backend and demo stays the default.
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

    test(
      'real mode resolves the stub repo that throws without a backend',
      () async {
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

        // Real wiring intentionally deferred: the real repo NEVER contacts a
        // backend - it stays fail-closed and throws.
        await expectLater(
          repo.loadOverview(),
          throwsA(isA<RealRepoNotWiredError>()),
        );
      },
    );
  });
}
