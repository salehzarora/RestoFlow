import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// In REAL mode the Users/Settings tabs must never render the demo store's
/// fabricated people ("Dana Reyes" et al.) or demo values under a demo banner.
/// Without a real users repository injected the Users tab shows the honest
/// not-connected state. The Settings tab shows the REAL resolved workspace
/// values; for an owner it ALSO exposes the RF-116 owner-only editable section
/// (branch/restaurant name + receipt prefix) with real Save affordances.

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
    if (function == 'get_branch_pos_shift_close_enabled') {
      // RF-113: the Settings tab reads the branch policy (enabled here).
      return {
        'ok': true,
        'entity': 'branch',
        'branch_id': 'branch-1',
        'pos_shift_close_enabled': true,
      };
    }
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

  testWidgets('real-mode Settings shows the RESOLVED workspace values plus the '
      'owner editable section — no demo banner, no demo values', (
    tester,
  ) async {
    final l10n = await en();
    await _pumpReal(tester);
    await tester.tap(find.text(l10n.dashboardNavSettings));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adminDemoBanner), findsNothing);
    // The REAL resolved values (org + first restaurant/branch + currency).
    expect(find.text('Olive Group'), findsWidgets);
    // The restaurant name shows in the read-only workspace card AND the editable
    // field (owner), so it appears more than once — never fabricated, never demo.
    expect(find.text('Olive North'), findsWidgets);
    expect(find.text('Main hall'), findsWidgets);
    expect(
      find.text('ILS'),
      findsOneWidget,
    ); // currency stays read-only (locked)
    expect(find.text('America/New_York'), findsNothing);
    expect(find.text('128 Main Street, Suite 4'), findsNothing);
    // RF-116: the org-wide OWNER (resolved to a concrete branch) gets the
    // editable section — a real Save affordance, no blanket "nothing to save".
    expect(find.text(l10n.dashboardSettingsRealNotice), findsNothing);
    expect(find.text(l10n.dashboardSettingsEditableTitle), findsOneWidget);
    expect(find.byKey(const Key('settings-branch-name')), findsOneWidget);
    expect(find.text(l10n.adminSave), findsWidgets);
    // RF-113: the honest, editable shift-close toggle is also present.
    expect(find.text(l10n.dashboardShiftCloseSectionTitle), findsOneWidget);
    expect(find.byKey(const Key('shift-close-policy-toggle')), findsOneWidget);
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
