/// The platform-console data SEAM: the demo repository answers every page from
/// the structured dataset, honours an injected dataset, and fails the way the
/// UI expects.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/console_models.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

void main() {
  test('the demo repository answers all five console reads', () async {
    const repo = DemoPlatformAdminRepository();

    final overview = await repo.loadConsoleOverview();
    expect(overview.organizationsTotal, 5);
    expect(overview.branchesTotal, 8);

    final subscribers = await repo.loadSubscribers(const SubscriberQuery());
    expect(subscribers.totalCount, 5);
    expect(subscribers.rows.first.organizationId, isNotEmpty);

    final detail = await repo.loadSubscriberDetail(
      subscribers.rows.first.organizationId,
    );
    expect(detail.organization.name, subscribers.rows.first.organizationName);

    final restaurants = await repo.loadRestaurants(const RestaurantQuery());
    expect(restaurants.totalCount, 6);

    final audit = await repo.loadAuditPage(const AuditQuery());
    expect(audit.rows, isNotEmpty);
  });

  test('an injected dataset is used (empty platform -> empty pages)', () async {
    final repo = DemoPlatformAdminRepository(dataset: emptyPlatformDataset());
    expect((await repo.loadConsoleOverview()).isEmpty, isTrue);
    expect(
      (await repo.loadSubscribers(const SubscriberQuery())).isEmpty,
      isTrue,
    );
    expect(
      (await repo.loadRestaurants(const RestaurantQuery())).isEmpty,
      isTrue,
    );
    expect((await repo.loadAuditPage(const AuditQuery())).isEmpty, isTrue);
  });

  test('a configured failure surfaces on EVERY read', () async {
    const repo = DemoPlatformAdminRepository(failureMessage: 'boom');
    expect(repo.loadConsoleOverview(), throwsA(isA<PlatformAdminException>()));
    expect(
      repo.loadSubscribers(const SubscriberQuery()),
      throwsA(isA<PlatformAdminException>()),
    );
    expect(
      repo.loadSubscriberDetail('anything'),
      throwsA(isA<PlatformAdminException>()),
    );
    expect(
      repo.loadRestaurants(const RestaurantQuery()),
      throwsA(isA<PlatformAdminException>()),
    );
    expect(
      repo.loadAuditPage(const AuditQuery()),
      throwsA(isA<PlatformAdminException>()),
    );
  });

  test('an unknown tenant is DENIED, not "not found" — the console must not '
      'reveal which organization ids exist', () async {
    const repo = DemoPlatformAdminRepository();
    await expectLater(
      repo.loadSubscriberDetail('d0000000-0000-4000-8000-00000000dead'),
      throwsA(
        isA<PlatformAdminException>().having(
          (e) => e.kind,
          'kind',
          PlatformAdminErrorKind.accessDenied,
        ),
      ),
    );
  });
}
