import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/main.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

MembershipContext mem(MembershipRole role) => MembershipContext(
  id: 'a',
  organizationId: 'org-a',
  organizationName: 'Org A',
  restaurantId: null,
  restaurantName: null,
  branchId: null,
  branchName: null,
  role: role,
  status: 'active',
);

MyContext ctx({
  bool admin = false,
  List<MembershipContext> memberships = const [],
}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'u@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: admin,
  memberships: memberships,
);

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Pumps [app] under a ProviderScope (the platform overview uses Riverpod; in
/// production main() supplies the scope around AdminApp) on a wide surface.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('demo mode renders the platform overview', (tester) async {
    await _pump(tester, const AdminApp(demoMode: true));
    final l10n = await en();
    expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
  });

  testWidgets('auth mode: a platform admin reaches the platform overview', (
    tester,
  ) async {
    await _pump(
      tester,
      AdminApp(
        demoMode: false,
        fetchContext: fetcherForContext(ctx(admin: true)),
      ),
    );
    final l10n = await en();
    expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
  });

  testWidgets(
    'auth mode: a tenant role without the platform flag is denied (even org_owner)',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(
            ctx(memberships: [mem(MembershipRole.orgOwner)]),
          ),
        ),
      );
      final l10n = await en();
      expect(find.text(l10n.adminOverviewTitle), findsNothing);
      expect(find.text(l10n.authWrongRole), findsOneWidget);
    },
  );

  testWidgets(
    'auth mode: a platform admin with zero memberships still reaches the overview',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(ctx(admin: true)),
        ),
      );
      final l10n = await en();
      expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
    },
  );
}
