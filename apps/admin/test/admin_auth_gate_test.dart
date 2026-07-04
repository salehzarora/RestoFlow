import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/main.dart';
import 'package:restoflow_admin/src/admin_platform_gate.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealModeUnconfiguredView;
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
  bool mfa = false,
  List<MembershipContext> memberships = const [],
}) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'u@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: admin,
  hasMfaAal2: mfa,
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

  testWidgets(
    'auth mode: a platform admin WITH an MFA (aal2) session reaches the '
    'platform overview',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(ctx(admin: true, mfa: true)),
        ),
      );
      final l10n = await en();
      expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
    },
  );

  testWidgets(
    'RF-119 auth mode: a platform admin WITHOUT an MFA session gets the honest '
    'MFA-required state, never the overview and never fake platform data',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          // Active platform grant (admin: true) but NO aal2 session (mfa: false).
          fetchContext: fetcherForContext(ctx(admin: true)),
        ),
      );
      final l10n = await en();
      expect(find.byType(AdminMfaRequiredView), findsOneWidget);
      expect(find.text(l10n.adminMfaRequiredTitle), findsOneWidget);
      expect(find.text(l10n.adminMfaRequiredBody), findsOneWidget);
      expect(find.text(l10n.adminMfaRequiredHint), findsOneWidget);
      // It IS the platform panel (not the restaurant Dashboard), and it is NOT
      // the overview / any fake platform figures.
      expect(find.text(l10n.adminGateNotOwner), findsOneWidget);
      expect(find.text(l10n.adminOverviewTitle), findsNothing);
      expect(find.byKey(const Key('admin-mfa-retry')), findsOneWidget);
      // Not the wrong-account explainer (they ARE a platform admin) or a denial.
      expect(find.text(l10n.adminGateNotAdminAccount), findsNothing);
      expect(find.text(l10n.authAccessDenied), findsNothing);
    },
  );

  testWidgets(
    'auth mode: a tenant role without the platform flag gets the HONEST '
    'platform-panel explainer (even org_owner) — never the overview',
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
      // Sprint (admin access clarification): the explainer replaces the
      // dead-end wrong-role state — what this app is, where owners go, and
      // that this signed-in account is not a platform admin.
      expect(find.text(l10n.adminGateTitle), findsOneWidget);
      expect(find.text(l10n.adminGateNotOwner), findsOneWidget);
      expect(find.text(l10n.adminGateUseDashboard), findsOneWidget);
      expect(find.text(l10n.adminGateNotAdminAccount), findsOneWidget);
      expect(
        find.byKey(const Key('admin-gate-open-dashboard')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-gate-retry')), findsOneWidget);
      // No scary generic denial.
      expect(find.text(l10n.authWrongRole), findsNothing);
      expect(find.text(l10n.authAccessDenied), findsNothing);
    },
  );

  testWidgets(
    'auth mode: an unauthenticated visitor gets the explainer (this app has '
    'no sign-in by design), not "Account access denied"',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForFailure(const AuthDeniedFailure()),
        ),
      );
      final l10n = await en();
      expect(find.text(l10n.adminGateTitle), findsOneWidget);
      expect(find.text(l10n.adminGateNotOwner), findsOneWidget);
      // Unauthenticated: the "signed-in account" note must NOT appear.
      expect(find.text(l10n.adminGateNotAdminAccount), findsNothing);
      expect(find.text(l10n.authAccessDenied), findsNothing);
      expect(find.text(l10n.adminOverviewTitle), findsNothing);
    },
  );

  testWidgets('real mode without Supabase config fails closed to the honest '
      'unconfigured help page (mirrors the dashboard)', (tester) async {
    // No fetchContext injected and no dart-defines in tests => config null.
    await _pump(tester, const AdminApp(demoMode: false));
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
  });

  testWidgets('the explainer renders in Arabic (RTL) with the exact copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: AdminGateExplainer(signedIn: false, onRetry: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(AdminGateExplainer))),
      TextDirection.rtl,
    );
    // The Arabic-first copy the sprint prescribed, verbatim.
    expect(
      find.text('هذه لوحة إدارة المنصة، وليست لوحة صاحب المطعم.'),
      findsOneWidget,
    );
    expect(find.text('استخدم Dashboard لإدارة المطعم.'), findsOneWidget);
  });

  testWidgets(
    'auth mode: a platform admin (MFA) with zero memberships still reaches the '
    'overview',
    (tester) async {
      await _pump(
        tester,
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(ctx(admin: true, mfa: true)),
        ),
      );
      final l10n = await en();
      expect(find.text(l10n.adminOverviewTitle), findsOneWidget);
    },
  );

  testWidgets('RF-119 the MFA-required view renders in Arabic (RTL) safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: AdminMfaRequiredView(onRetry: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(AdminMfaRequiredView))),
      TextDirection.rtl,
    );
    expect(find.text('مطلوب مصادقة متعددة العوامل'), findsOneWidget);
  });
}
