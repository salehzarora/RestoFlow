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

/// A minimal PIN-pad staff directory (the PIN gate needs one to render).
class _FakeStaffDirectory implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success([
    DeviceStaffMember(
      employeeProfileId: 'emp-1',
      displayName: 'Amira K.',
      role: 'cashier',
    ),
  ]);
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

  testWidgets('a successful pairing advances to the staff PIN gate (D-006 — '
      'never straight into the POS)', (tester) async {
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
              deviceSessionId: 'ds-1',
            ),
          ),
        ),
        deviceStaffRepository: _FakeStaffDirectory(),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pairing-code')), 'POS-CODE');
    await tester.tap(find.byKey(const Key('pairing-submit')));
    await tester.pumpAndSettle();

    // Paired -> the staff PIN sign-in, NOT the POS surface (no session yet).
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
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

  testWidgets('a restored device session advances to the staff PIN gate on '
      'launch (D-006 — never straight into the POS)', (tester) async {
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(
          const DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            deviceId: 'd',
            deviceType: 'pos',
            deviceSessionId: 'ds-1',
          ),
        ),
        deviceStaffRepository: _FakeStaffDirectory(),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    // Restored automatically -> the PIN sign-in (a session is still required);
    // never the pairing screen, never the POS surface without a session.
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('no restorable session falls back to the pairing screen', (
    tester,
  ) async {
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(null),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
  });

  testWidgets('a restored KDS session must NOT unlock the POS — fail closed '
      'to the pairing screen', (tester) async {
    final repo = _FakeRestorable(
      const DeviceContext(
        organizationId: 'o',
        branchId: 'b',
        deviceId: 'd',
        deviceType: 'kds',
      ),
    );
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: repo,
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    // The gate asked the repo for a POS session...
    expect(repo.lastExpectedDeviceType, 'pos');
    // ...and rejects the mismatched context itself even when the repo (this
    // fake) fails to enforce it.
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
  });

  testWidgets('a restored session with NO device type must NOT unlock the '
      'POS', (tester) async {
    await _pump(
      tester,
      PosApp(
        demoMode: false,
        devicePairingRepository: _FakeRestorable(
          const DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            deviceId: 'd',
          ),
        ),
        fetchContext: fetcherForContext(_managerCtx()),
      ),
    );
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(PosMenuScreen), findsNothing);
  });
}
