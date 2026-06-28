import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';
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
  // A tall, narrow surface so the demo KDS board lays out without overflow.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(880, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('auth mode: an allowed kitchen_staff reaches the KDS board', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      KdsApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.kitchenStaff)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KitchenOrdersHome), findsOneWidget);
  });

  testWidgets('auth mode: a cashier is denied (wrong role) on KDS', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      KdsApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.cashier)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await en();
    expect(find.byType(KitchenOrdersHome), findsNothing);
    expect(find.text(l10n.authWrongRole), findsOneWidget);
  });

  testWidgets('auth mode: zero memberships shows no-access on KDS', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      KdsApp(demoMode: false, fetchContext: fetcherForContext(ctx())),
    );
    await tester.pumpAndSettle();
    final l10n = await en();
    expect(find.text(l10n.authNoAccess), findsOneWidget);
  });
}
