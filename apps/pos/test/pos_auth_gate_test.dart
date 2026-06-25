import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

/// Pumps the POS app under a ProviderScope (the demo cart screen uses Riverpod;
/// in production main() supplies the scope around PosApp). A wide surface gives
/// the menu+cart layout room (matches the existing POS screen tests).
Future<void> pumpPos(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

MembershipContext mem(
  MembershipRole role, {
  String id = 'a',
  String org = 'Org A',
}) => MembershipContext(
  id: id,
  organizationId: 'org-$id',
  organizationName: org,
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
  testWidgets('demo mode renders the existing POS demo screen (no auth)', (
    tester,
  ) async {
    await pumpPos(tester, const PosApp(demoMode: true));
    expect(find.byType(PosMenuScreen), findsOneWidget);
  });

  testWidgets('auth mode: an allowed cashier reaches the POS screen', (
    tester,
  ) async {
    await pumpPos(
      tester,
      PosApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(memberships: [mem(MembershipRole.cashier)]),
        ),
      ),
    );
    expect(find.byType(PosMenuScreen), findsOneWidget);
  });

  testWidgets(
    'auth mode: a wrong role (kitchen_staff) is denied, not crashed',
    (tester) async {
      await pumpPos(
        tester,
        PosApp(
          demoMode: false,
          fetchContext: fetcherForContext(
            ctx(memberships: [mem(MembershipRole.kitchenStaff)]),
          ),
        ),
      );
      final l10n = await en();
      expect(find.byType(PosMenuScreen), findsNothing);
      expect(find.text(l10n.authWrongRole), findsOneWidget);
    },
  );

  testWidgets('auth mode: multiple memberships show the picker', (
    tester,
  ) async {
    await pumpPos(
      tester,
      PosApp(
        demoMode: false,
        fetchContext: fetcherForContext(
          ctx(
            memberships: [
              mem(MembershipRole.cashier, id: 'a', org: 'Org A'),
              mem(MembershipRole.manager, id: 'b', org: 'Org B'),
            ],
          ),
        ),
      ),
    );
    final l10n = await en();
    expect(find.text(l10n.authChooseLocation), findsOneWidget);
    expect(find.text('Org A'), findsOneWidget);
    expect(find.text('Org B'), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
  });

  testWidgets('auth mode: zero memberships shows no-access', (tester) async {
    await pumpPos(
      tester,
      PosApp(demoMode: false, fetchContext: fetcherForContext(ctx())),
    );
    final l10n = await en();
    expect(find.text(l10n.authNoAccess), findsOneWidget);
  });

  testWidgets('auth mode: a 42501/denied context shows access-denied', (
    tester,
  ) async {
    await pumpPos(
      tester,
      PosApp(
        demoMode: false,
        fetchContext: fetcherForFailure(const AuthDeniedFailure()),
      ),
    );
    final l10n = await en();
    expect(find.text(l10n.authAccessDenied), findsOneWidget);
  });
}
