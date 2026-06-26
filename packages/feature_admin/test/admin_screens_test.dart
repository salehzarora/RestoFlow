import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> pumpAdmin(
  WidgetTester tester,
  Widget screen, {
  MembershipRole role = MembershipRole.orgOwner,
  Locale locale = const Locale('en'),
}) async {
  // A tall surface so the demo lists are fully laid out (no off-screen items).
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final scope = AdminScope.demo.copyWith(actingRole: role);
  await tester.pumpWidget(
    ProviderScope(
      overrides: adminFeatureOverrides(
        scope: scope,
        repository: DemoAdminStore(scope: scope),
      ),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings screen renders the three section cards', (
    tester,
  ) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminSettingsScreen());
    expect(find.text(l10n.adminSectionOrg), findsOneWidget);
    expect(find.text(l10n.adminSectionRestaurant), findsOneWidget);
    expect(find.text(l10n.adminSectionBranch), findsOneWidget);
    expect(find.text(l10n.adminFieldDefaultCurrency), findsOneWidget);
  });

  testWidgets('settings is read-only for a manager (role-rank guard)', (
    tester,
  ) async {
    final l10n = await en();
    await pumpAdmin(
      tester,
      const AdminSettingsScreen(),
      role: MembershipRole.manager,
    );
    expect(find.text(l10n.adminSettingsReadOnly), findsOneWidget);
    // No Save buttons in the read-only view.
    expect(find.text(l10n.adminSave), findsNothing);
  });

  testWidgets('settings validation: a bad currency blocks save', (
    tester,
  ) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminSettingsScreen());
    final currency = find.widgetWithText(
      TextFormField,
      l10n.adminFieldDefaultCurrency,
    );
    await tester.enterText(currency, 'US'); // too short
    await tester.pump();
    // Save the org section (the first Save button).
    await tester.tap(find.text(l10n.adminSave).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminErrCurrency), findsWidgets);
  });

  testWidgets('users screen lists members with role chips', (tester) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminUsersScreen());
    expect(find.text('Dana Reyes'), findsOneWidget); // a seeded member
    expect(find.text(l10n.authRoleRestaurantOwner), findsWidgets); // role chip
    expect(find.text(l10n.adminSelf), findsOneWidget); // the acting user chip
  });

  testWidgets('grant dialog opens with a role field', (tester) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminUsersScreen());
    await tester.tap(find.text(l10n.adminGrantUser));
    await tester.pumpAndSettle();
    // The display-name + email + role fields are unique to the grant dialog.
    expect(find.text(l10n.adminFieldDisplayName), findsWidgets);
    expect(find.text(l10n.adminFieldRole), findsWidgets);
    expect(find.text(l10n.adminFieldEmail), findsWidgets);
  });

  testWidgets('devices screen lists devices and the active device can start a '
      'session', (tester) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminDevicesScreen());
    expect(find.text('Front Counter POS'), findsOneWidget); // active, seeded
    expect(find.text('Backup POS'), findsOneWidget); // unpaired, seeded
    // Per-status actions render (active → start session, unpaired → issue code).
    expect(find.text(l10n.adminStartSession), findsOneWidget);
    expect(find.text(l10n.adminIssueCode), findsOneWidget);
  });

  testWidgets('issuing an enrollment code shows the one-time secret dialog', (
    tester,
  ) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminDevicesScreen());
    await tester.tap(find.text(l10n.adminIssueCode));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminCodeIssuedTitle), findsOneWidget);
    expect(
      find.text(l10n.adminShownOnce),
      findsOneWidget,
    ); // shown-once warning
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('starting a session shows the one-time token dialog', (
    tester,
  ) async {
    final l10n = await en();
    await pumpAdmin(tester, const AdminDevicesScreen());
    await tester.tap(find.text(l10n.adminStartSession));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminTokenStartedTitle), findsOneWidget);
    expect(find.text(l10n.adminShownOnce), findsOneWidget);
  });
}
