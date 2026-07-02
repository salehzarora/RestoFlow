import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';

class _FakePairing implements DevicePairingRepository {
  _FakePairing(this.result);
  Result<DeviceContext, PairingFailure> result;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async => result;
}

/// A real-style repo that also restores a session on launch (RF-161). It
/// IGNORES [expectedDeviceType] (recording it only), so wrong-type tests prove
/// the GATE itself rejects a mismatched restored context (belt-and-suspenders
/// on top of the repo-level enforcement, which has its own unit tests).
class _FakeRestorable implements DevicePairingRepository, DeviceSessionManager {
  _FakeRestorable(this._restored);
  final DeviceContext? _restored;
  String? lastExpectedDeviceType;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async => const Failure(PairingFailure(PairingFailureKind.invalidCode));

  @override
  Future<DeviceContext?> restore({String? expectedDeviceType}) async {
    lastExpectedDeviceType = expectedDeviceType;
    return _restored;
  }

  @override
  Future<void> unpair() async {}
}

MyContext _kitchenCtx() => const MyContext(
  appUser: AppUserContext(
    id: 'u',
    email: 'k@x.test',
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
      role: MembershipRole.kitchenStaff,
      status: 'active',
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('DEMO mode is unchanged — the kitchen board, no pairing screen', (
    tester,
  ) async {
    await _pump(tester, const KdsApp(demoMode: true));
    expect(find.byType(KitchenOrdersHome), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('real mode with a pairing repo + no device shows the pairing '
      'screen, and it is money-FREE', (tester) async {
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: _FakePairing(
          const Failure(PairingFailure(PairingFailureKind.invalidCode)),
        ),
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(KitchenOrdersHome), findsNothing);
    // Kitchen device: no money on the pairing screen (SECURITY T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('a successful pairing enters the kitchen board', (tester) async {
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: _FakePairing(
          const Success(
            DeviceContext(
              organizationId: 'o',
              branchId: 'b',
              deviceId: 'd',
              deviceType: 'kds',
            ),
          ),
        ),
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pairing-code')), 'KDS-CODE');
    await tester.tap(find.byKey(const Key('pairing-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(KitchenOrdersHome), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('with NO pairing repo the gate is dormant (existing behaviour)', (
    tester,
  ) async {
    await _pump(
      tester,
      KdsApp(demoMode: false, fetchContext: fetcherForContext(_kitchenCtx())),
    );
    expect(find.byType(KitchenOrdersHome), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('a restored device session enters the kitchen board on launch', (
    tester,
  ) async {
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(
          const DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            deviceId: 'd',
            deviceType: 'kds',
          ),
        ),
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    expect(find.byType(KitchenOrdersHome), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('no restorable session falls back to the pairing screen', (
    tester,
  ) async {
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(null),
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(KitchenOrdersHome), findsNothing);
  });

  testWidgets('a restored POS session must NOT unlock the kitchen board — '
      'fail closed to the (money-free) pairing screen', (tester) async {
    final repo = _FakeRestorable(
      const DeviceContext(
        organizationId: 'o',
        branchId: 'b',
        deviceId: 'd',
        deviceType: 'pos',
      ),
    );
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: repo,
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    // The gate asked the repo for a KDS session...
    expect(repo.lastExpectedDeviceType, 'kds');
    // ...and rejects the mismatched context itself even when the repo (this
    // fake) fails to enforce it.
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(KitchenOrdersHome), findsNothing);
    // Kitchen device: still no money anywhere (SECURITY T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('a restored session with NO device type must NOT unlock the '
      'kitchen board', (tester) async {
    await _pump(
      tester,
      KdsApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(
          const DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            deviceId: 'd',
          ),
        ),
        fetchContext: fetcherForContext(_kitchenCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(KitchenOrdersHome), findsNothing);
  });
}
