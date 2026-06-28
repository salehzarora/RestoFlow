import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';
import 'package:restoflow_admin/src/data/platform_overview_calculator.dart';

void main() {
  group('computePlatformOverview over the demo dataset', () {
    final overview = computePlatformOverview(demoPlatformDataset());

    test('KPI counts derive from the dataset', () {
      expect(overview.organizationCount, 3);
      expect(overview.activeOrganizationCount, 2); // Pizza Plaza is suspended
      expect(overview.restaurantCount, 4); // 2 + 1 + 1
      expect(overview.branchCount, 6); // 3 + 2 + 1
      expect(overview.activeBranchCount, 5); // all active except Noor Airport
      expect(overview.deviceCount, 10); // 3+2+2 + 2+0 + 1
      expect(
        overview.warningCount,
        2,
      ); // Noor Airport inactive, Plaza HQ org suspended
      expect(overview.todayOrderCount, 215); // 87+41+33 + 54+0 + 0
    });

    test('counts are plain integers (no money on the platform overview)', () {
      expect(overview.organizationCount, isA<int>());
      expect(overview.deviceCount, isA<int>());
      expect(overview.todayOrderCount, isA<int>());
    });

    test('organizations: sorted by name, with exact counts/status/plan', () {
      expect(overview.organizations.map((o) => o.organizationName).toList(), [
        'Bistro Group',
        'Cafe Noor',
        'Pizza Plaza',
      ]);
      // Strictly ascending by name (a reversed or other sort would fail).
      for (var i = 1; i < overview.organizations.length; i++) {
        expect(
          overview.organizations[i].organizationName.compareTo(
                overview.organizations[i - 1].organizationName,
              ) >
              0,
          isTrue,
        );
      }

      final bistro = overview.organizations.first;
      expect(bistro.restaurantCount, 2);
      expect(bistro.branchCount, 3);
      expect(bistro.status, 'active');
      expect(bistro.plan, 'pro');

      final plaza = overview.organizations.last;
      expect(plaza.status, 'suspended');
      expect(plaza.branchCount, 1);
      // Exactly two organizations are active (Bistro Group, Cafe Noor).
      expect(
        overview.organizations.where((o) => o.status == 'active').length,
        2,
      );

      // Org branch/restaurant counts reconcile to the KPI totals.
      final branchSum = overview.organizations.fold<int>(
        0,
        (s, o) => s + o.branchCount,
      );
      expect(branchSum, overview.branchCount);
      final restaurantSum = overview.organizations.fold<int>(
        0,
        (s, o) => s + o.restaurantCount,
      );
      expect(restaurantSum, overview.restaurantCount);
    });

    test('branch health: sorted by name, with warnings flagged', () {
      expect(overview.branchHealth.map((b) => b.branchName).toList(), [
        'Downtown Express',
        'Downtown Main',
        'Noor Airport',
        'Noor Central',
        'Plaza HQ',
        'Seaside',
      ]);
      // Strictly ascending by name (a reversed or other sort would fail).
      for (var i = 1; i < overview.branchHealth.length; i++) {
        expect(
          overview.branchHealth[i].branchName.compareTo(
                overview.branchHealth[i - 1].branchName,
              ) >
              0,
          isTrue,
        );
      }

      final warned = overview.branchHealth
          .where((b) => b.hasWarning)
          .map((b) => b.branchName)
          .toList();
      expect(warned, [
        'Noor Airport',
        'Plaza HQ',
      ]); // inactive branch / suspended org
      expect(warned.length, 2); // pinned independently of warningCount

      final airport = overview.branchHealth.firstWhere(
        (b) => b.branchName == 'Noor Airport',
      );
      expect(airport.status, 'inactive');
      expect(airport.deviceCount, 0);
      expect(airport.todayOrderCount, 0);

      final downtownMain = overview.branchHealth.firstWhere(
        (b) => b.branchName == 'Downtown Main',
      );
      expect(downtownMain.status, 'active');
      expect(downtownMain.deviceCount, 3);
      expect(downtownMain.todayOrderCount, 87);
      expect(downtownMain.hasWarning, isFalse);

      // Plaza HQ is an ACTIVE branch but warns because its org is suspended.
      final plazaHq = overview.branchHealth.firstWhere(
        (b) => b.branchName == 'Plaza HQ',
      );
      expect(plazaHq.status, 'active');
      expect(plazaHq.hasWarning, isTrue);

      final noorCentral = overview.branchHealth.firstWhere(
        (b) => b.branchName == 'Noor Central',
      );
      expect(noorCentral.status, 'active');
      expect(noorCentral.todayOrderCount, 54);
    });

    test('recent activity: newest first', () {
      // The full order is pinned, so a reversed/other sort fails immediately.
      expect(overview.activity.map((e) => e.action).toList(), [
        'sync_warning', // 2026-06-28 14:05
        'report_generated', // 2026-06-28 13:20
        'device_paired', // 2026-06-28 10:12
        'branch_opened', // 2026-06-27 16:40
        'organization_created', // 2026-05-20 11:30
      ]);
      expect(overview.activity.first.timestampLabel, '2026-06-28 14:05');
      // Timestamps strictly descending.
      for (var i = 1; i < overview.activity.length; i++) {
        expect(
          overview.activity[i].timestampLabel.compareTo(
                overview.activity[i - 1].timestampLabel,
              ) <=
              0,
          isTrue,
        );
      }
    });
  });

  group('computePlatformOverview over an empty platform', () {
    final overview = computePlatformOverview(emptyPlatformDataset());

    test('every count is zero and lists are empty', () {
      expect(overview.isEmpty, isTrue);
      expect(overview.organizationCount, 0);
      expect(overview.restaurantCount, 0);
      expect(overview.branchCount, 0);
      expect(overview.activeBranchCount, 0);
      expect(overview.deviceCount, 0);
      expect(overview.warningCount, 0);
      expect(overview.todayOrderCount, 0);
      expect(overview.organizations, isEmpty);
      expect(overview.branchHealth, isEmpty);
      expect(overview.activity, isEmpty);
    });
  });
}
