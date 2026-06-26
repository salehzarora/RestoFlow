import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/main.dart';
import 'package:restoflow_dashboard/src/dashboard_shell.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

MembershipContext mem({
  String? restaurantId,
  String? branchId,
  required MembershipRole role,
}) => MembershipContext(
  id: 'm',
  organizationId: 'org-1',
  organizationName: 'Org One',
  restaurantId: restaurantId,
  restaurantName: restaurantId == null ? null : 'Rest One',
  branchId: branchId,
  branchName: branchId == null ? null : 'Branch One',
  role: role,
  status: 'active',
);

MyContext ctx(MembershipContext membership) => MyContext(
  appUser: const AppUserContext(
    id: 'u',
    email: 'u@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: [membership],
);

Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('dashboardMenuScopeFor (derivation)', () {
    test('null membership (demo mode) returns the demo scope', () {
      expect(dashboardMenuScopeFor(null), demoMenuScope);
    });

    test('branch membership returns the exact org/restaurant/branch scope', () {
      final scope = dashboardMenuScopeFor(
        mem(
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          role: MembershipRole.manager,
        ),
      );
      expect(scope, isNotNull);
      expect(scope!.organizationId, 'org-1');
      expect(scope.restaurantId, 'rest-1');
      expect(scope.branchId, 'branch-1');
    });

    test(
      'restaurant-scoped (branch-null) membership returns a global scope',
      () {
        final scope = dashboardMenuScopeFor(
          mem(restaurantId: 'rest-1', role: MembershipRole.restaurantOwner),
        );
        expect(scope, isNotNull);
        expect(scope!.restaurantId, 'rest-1');
        expect(scope.branchId, isNull);
        expect(scope.isGlobal, isTrue);
      },
    );

    test('org-wide membership with no restaurant returns null (blocked)', () {
      expect(dashboardMenuScopeFor(mem(role: MembershipRole.orgOwner)), isNull);
    });
  });

  group('dashboard menu surface (auth mode)', () {
    testWidgets(
      'branch membership scopes the menu to its org/restaurant/branch',
      (tester) async {
        final l10n = await en();
        await tester.pumpWidget(
          ProviderScope(
            child: DashboardApp(
              demoMode: false,
              fetchContext: fetcherForContext(
                ctx(
                  mem(
                    restaurantId: 'rest-1',
                    branchId: 'branch-1',
                    role: MembershipRole.manager,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dashboardNavMenu));
        await tester.pumpAndSettle();

        expect(find.byType(MenuManagementScreen), findsOneWidget);
        expect(find.text(l10n.menuScopeUnavailableTitle), findsNothing);
        // Demo data is seeded under the REAL membership scope, so it renders.
        expect(find.text('Hot Drinks'), findsOneWidget);
      },
    );

    testWidgets('org-wide membership (no restaurant) shows the blocked state', (
      tester,
    ) async {
      final l10n = await en();
      await tester.pumpWidget(
        ProviderScope(
          child: DashboardApp(
            demoMode: false,
            fetchContext: fetcherForContext(
              ctx(mem(role: MembershipRole.orgOwner)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dashboardNavMenu));
      await tester.pumpAndSettle();

      expect(find.text(l10n.menuScopeUnavailableTitle), findsOneWidget);
      expect(find.byType(MenuManagementScreen), findsNothing);
    });
  });
}
