import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

class _FakePairing implements DevicePairingRepository {
  _FakePairing(this.result);
  Result<DeviceContext, PairingFailure> result;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async => result;
}

MyContext _managerCtx() => const MyContext(
  appUser: AppUserContext(
    id: 'u',
    email: 'e@x.test',
    displayName: null,
    isActive: true,
  ),
  isPlatformAdmin: false,
  memberships: [
    MembershipContext(
      id: 'm',
      organizationId: 'o',
      organizationName: 'Org',
      restaurantId: null,
      restaurantName: null,
      branchId: 'b',
      branchName: null,
      role: MembershipRole.manager,
      status: 'active',
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  // A roomy surface so the POS menu/cart lays out without overflow in tests.
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(child: app));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('DEMO mode is unchanged — the menu, never the pairing screen', (
    tester,
  ) async {
    await _pump(tester, const PosApp(demoMode: true));
    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('real mode with a pairing repo + no device shows the pairing '
      'screen (not the POS menu)', (tester) async {
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: _FakePairing(
          const Failure(PairingFailure(PairingFailureKind.invalidCode)),
        ),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
  });

  testWidgets('a successful pairing enters the POS surface', (tester) async {
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: _FakePairing(
          const Success(
            DeviceContext(
              organizationId: 'o',
              branchId: 'b',
              deviceId: 'd',
              deviceType: 'pos',
            ),
          ),
        ),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pairing-code')), 'POS-CODE');
    await tester.tap(find.byKey(const Key('pairing-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('with NO pairing repo the gate is dormant (existing behaviour)', (
    tester,
  ) async {
    await _pump(
      tester,
      PosApp(demoMode: false, fetchContext: fetcherForContext(_managerCtx())),
    );
    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });
}
