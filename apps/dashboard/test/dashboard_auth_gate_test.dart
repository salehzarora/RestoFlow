import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/dashboard_home_screen.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Pumps the dashboard app under a ProviderScope (the demo report screen uses
/// Riverpod; in production main() supplies the scope around DashboardApp).
Future<void> pumpDashboard(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

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

MyContext ctx({List<MembershipContext> memberships = const []}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'u@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: memberships,
);

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('demo mode renders the existing dashboard demo screen', (
    tester,
  ) async {
    await pumpDashboard(tester, const DashboardApp(demoMode: true));
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
  });

  testWidgets('auth mode: a manager reaches the dashboard', (tester) async {
    await pumpDashboard(
      tester,
      DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.manager)]),
        ),
      ),
    );
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
  });

  testWidgets('auth mode: an org_owner reaches the dashboard', (tester) async {
    await pumpDashboard(
      tester,
      DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.orgOwner)]),
        ),
      ),
    );
    expect(find.byType(DashboardHomeScreen), findsOneWidget);
  });

  testWidgets('auth mode: a cashier is denied (wrong role)', (tester) async {
    await pumpDashboard(
      tester,
      DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.cashier)]),
        ),
      ),
    );
    final l10n = await en();
    expect(find.byType(DashboardHomeScreen), findsNothing);
    expect(find.text(l10n.authWrongRole), findsOneWidget);
  });

  testWidgets('auth mode: accountant shows the deferred (coming soon) state', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      DashboardApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.accountant)]),
        ),
      ),
    );
    final l10n = await en();
    expect(find.text(l10n.authComingSoon), findsOneWidget);
    expect(find.byType(DashboardHomeScreen), findsNothing);
  });
}
