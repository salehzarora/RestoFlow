import 'package:flutter/material.dart';
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

void main() {
  testWidgets('demo mode renders the existing admin shell', (tester) async {
    await tester.pumpWidget(const AdminApp(demoMode: true));
    await tester.pumpAndSettle();
    final l10n = await en();
    // the minimal admin shell shows the welcome message
    expect(find.text(l10n.welcomeMessage), findsOneWidget);
  });

  testWidgets('auth mode: a platform admin reaches the admin shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      AdminApp(
        demoMode: false,
        fetchContext: fetcherForContext(ctx(admin: true)),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await en();
    expect(find.text(l10n.welcomeMessage), findsOneWidget);
  });

  testWidgets(
    'auth mode: a tenant role without the platform flag is denied (even org_owner)',
    (tester) async {
      await tester.pumpWidget(
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(
            ctx(memberships: [mem(MembershipRole.orgOwner)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await en();
      expect(find.text(l10n.welcomeMessage), findsNothing);
      expect(find.text(l10n.authWrongRole), findsOneWidget);
    },
  );

  testWidgets(
    'auth mode: a platform admin with zero memberships still reaches admin',
    (tester) async {
      await tester.pumpWidget(
        AdminApp(
          demoMode: false,
          fetchContext: fetcherForContext(ctx(admin: true)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await en();
      expect(find.text(l10n.welcomeMessage), findsOneWidget);
    },
  );
}
