import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Sprint: in REAL mode the Users/Settings tabs must never render the demo
/// store's fabricated people ("Dana Reyes" et al.) or demo values under a
/// demo banner — Users shows the honest not-connected state; Settings shows
/// the REAL resolved workspace values, read-only, with no Save affordance.

const _orgWideOwner = MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Olive Group',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: MembershipRole.orgOwner,
  status: 'active',
);

MyContext _ctx() => const MyContext(
  appUser: AppUserContext(
    id: 'u',
    email: 'owner@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: [_orgWideOwner],
);

class _StructureTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'list_org_structure') {
      return {
        'ok': true,
        'entity': 'org_structure',
        'organization': {
          'id': 'org-1',
          'name': 'Olive Group',
          'default_currency': 'ILS',
        },
        'restaurants': [
          {
            'id': 'rest-1',
            'name': 'Olive North',
            'currency_override': null,
            'timezone': 'UTC',
            'status': 'active',
            'branches': [
              {
                'id': 'branch-1',
                'name': 'Main hall',
                'timezone': 'UTC',
                'status': 'active',
              },
            ],
          },
        ],
        'server_ts': 't',
      };
    }
    throw const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: '503',
      message: 'not under test',
    );
  }
}

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pumpReal(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(_ctx()),
        reportsTransport: _StructureTransport(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('real-mode Users shows the honest not-connected state — no '
      'demo people, no demo banner', (tester) async {
    final l10n = await en();
    await _pumpReal(tester);
    await tester.tap(find.text(l10n.dashboardNavUsers));
    await tester.pumpAndSettle();

    expect(find.text(l10n.dashboardUsersNotConnectedTitle), findsOneWidget);
    expect(find.text(l10n.adminDemoBanner), findsNothing);
    // The seeded demo members must never appear as real people.
    expect(find.text('Dana Reyes'), findsNothing);
    expect(find.textContaining('olivethyme.test'), findsNothing);
    // No grant affordance either — there is no backend read to refresh from.
    expect(find.text(l10n.adminGrantUser), findsNothing);
  });

  testWidgets('real-mode Settings shows the RESOLVED workspace values, '
      'read-only — no demo banner, no Save', (tester) async {
    final l10n = await en();
    await _pumpReal(tester);
    await tester.tap(find.text(l10n.dashboardNavSettings));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminDemoBanner), findsNothing);
    expect(find.text(l10n.dashboardSettingsRealNotice), findsOneWidget);
    // The REAL resolved values (org + first restaurant/branch + currency).
    expect(find.text('Olive Group'), findsWidgets);
    expect(find.text('Olive North'), findsOneWidget);
    expect(find.text('Main hall'), findsWidgets);
    expect(find.text('ILS'), findsOneWidget);
    // Read-only: no Save button, and none of the demo settings values.
    expect(find.text(l10n.adminSave), findsNothing);
    expect(find.text('America/New_York'), findsNothing);
    expect(find.text('128 Main Street, Suite 4'), findsNothing);
  });

  testWidgets('demo mode keeps the labelled demo Users surface (unchanged)', (
    tester,
  ) async {
    final l10n = await en();
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: DashboardApp(demoMode: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dashboardNavUsers));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminDemoBanner), findsOneWidget);
    expect(find.text('Dana Reyes'), findsOneWidget);
  });
}
