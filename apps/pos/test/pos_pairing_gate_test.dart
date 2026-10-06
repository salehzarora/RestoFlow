import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_auth/testing.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_pairing_gate.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';

class _HeartbeatWire implements SyncRpcTransport {
  bool revoked = false;
  bool malformed = false;
  bool offline = false;
  int revocations = 0;
  int heartbeats = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'revoke_device_session') revocations++;
    if (offline)
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    if (malformed) return {'ok': true};
    if (function == 'heartbeat_device_session') heartbeats++;
    if (revoked)
      return {'ok': false, 'error': 'invalid_session', 'reason': 'revoked'};
    return {
      'ok': true,
      'device_id': 'd',
      'device_session_id': 'ds-1',
      'organization_id': 'o',
      'restaurant_id': 'r',
      'branch_id': 'b',
      'device_type': 'pos',
    };
  }
}

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
class _FakeOutcome extends _FakeRestorable
    implements DeviceSessionOutcomeManager {
  _FakeOutcome(this.outcome) : super(null);
  DeviceRestoreOutcome outcome;
  Future<DeviceRestoreOutcome>? pending;
  int calls = 0;
  @override
  Future<DeviceRestoreOutcome> restoreOutcome({
    String? expectedDeviceType,
  }) async {
    calls++;
    lastExpectedDeviceType = expectedDeviceType;
    if (pending != null) return await pending!;
    return outcome;
  }
}

class _RepairOutcome extends _FakeOutcome
    implements DeviceSessionLocalRepairManager {
  _RepairOutcome() : super(const DeviceSessionRestoreUnavailable());
  @override
  int get consecutiveUnavailable => 3;
  @override
  Future<void> clearLocalPairing() async {}
}

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
  testWidgets('H5 POS local repair fences an older in-flight restore reply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RepairOutcome();
    final pending = Completer<DeviceRestoreOutcome>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: PosPairingGate(
            repository: repo,
            signedInChild: const Text('live protected app'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.pending = pending.future;
    await tester.tap(find.byKey(const Key('device-session-retry')));
    await tester.pump();
    expect(repo.calls, 2);
    await tester.tap(find.byKey(const Key('device-session-repair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    pending.complete(
      const DeviceSessionRestored(
        DeviceContext(
          organizationId: 'o',
          restaurantId: 'r',
          branchId: 'b',
          deviceId: 'd',
          deviceSessionId: 's',
          deviceType: 'pos',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.text('live protected app'), findsNothing);
    expect(find.byType(DeviceSessionUnavailableView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'H3 POS ignores superseded cold restore without changing gate verdict',
    (tester) async {
      final repository = _FakeOutcome(const DeviceSessionRestoreSuperseded());
      await tester.pumpWidget(
        ProviderScope(
          child: PosApp(
            demoMode: false,
            devicePairingRepository: repository,
            deviceStaffRepository: _FakeStaffDirectory(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      expect(find.byType(DevicePairingScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'H3 cold unknown then offline recovers to real PIN gate automatically',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd', sessionToken: 'token'),
      );
      final wire = _HeartbeatWire()..malformed = true;
      final repo = SupabaseDevicePairingRepository(
        transport: DeviceSessionGuardedTransport(wire),
        secretStore: store,
      );
      await _pump(
        tester,
        PosApp(
          demoMode: false,
          devicePairingRepository: repo,
          deviceStaffRepository: _FakeStaffDirectory(),
        ),
      );
      expect(repo.activeDevice, isNull);
      expect(repo.consecutiveUnavailable, 2);
      wire.offline = true;
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(repo.consecutiveUnavailable, 0);
      expect(repo.protectedCallsBlocked, isTrue);
      expect(find.byType(PinLoginScreen), findsNothing);
      wire.offline = false;
      wire.malformed = false;
      await tester.pump(const Duration(seconds: 120));
      await tester.pumpAndSettle();
      expect(repo.protectedCallsBlocked, isFalse);
      expect(find.byType(PinLoginScreen), findsOneWidget);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
      expect(find.byType(OfflineBootView), findsNothing);
      expect(await store.read(), isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S4 completed local unpair ignores a late upgrade restore verdict',
    (tester) async {
      final repository = _FakeOutcome(const DeviceSessionRestoreRejected());
      final pending = Completer<DeviceRestoreOutcome>();
      repository.pending = pending.future;
      final upgrade = UpgradableSyncTransport();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: PosPairingGate(
              repository: repository,
              upgradeSignal: upgrade,
              initialDevice: const DeviceContext(
                organizationId: 'o',
                restaurantId: 'r',
                branchId: 'b',
                deviceId: 'd',
                deviceType: 'pos',
                deviceSessionId: 'ds',
              ),
              signedInChild: const Text('live POS'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      upgrade.upgrade(_HeartbeatWire());
      await tester.pump();
      expect(repository.calls, 1);
      await repository.unpair();
      c.read(posDeviceContextProvider.notifier).set(null);
      await tester.pumpAndSettle();
      expect(find.byType(DevicePairingScreen), findsOneWidget);
      pending.complete(const DeviceSessionRestoreUnavailable());
      await tester.pumpAndSettle();
      expect(find.byType(DevicePairingScreen), findsOneWidget);
      expect(find.byType(DeviceSessionUnavailableView), findsNothing);
    },
  );
  testWidgets(
    'S3 cold unknown gate offers confirmed local repair after third automatic verdict',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(deviceId: 'd', sessionToken: 'token'),
      );
      final wire = _HeartbeatWire()..malformed = true;
      final repo = SupabaseDevicePairingRepository(
        transport: DeviceSessionGuardedTransport(wire),
        secretStore: store,
      );
      await _pump(
        tester,
        PosApp(
          demoMode: false,
          devicePairingRepository: repo,
          deviceStaffRepository: _FakeStaffDirectory(),
        ),
      );
      expect(repo.consecutiveUnavailable, 2);
      expect(find.byKey(const Key('device-session-repair')), findsNothing);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(repo.consecutiveUnavailable, 3);
      await tester.tap(find.byKey(const Key('device-session-repair')));
      await tester.pumpAndSettle();
      expect(await store.read(), isNotNull);
      await tester.tap(find.byKey(const Key('device-session-repair-cancel')));
      await tester.pumpAndSettle();
      expect(await store.read(), isNotNull);
      await tester.tap(find.byKey(const Key('device-session-repair')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
      await tester.pumpAndSettle();
      expect(await store.read(), isNull);
      expect(wire.revocations, 0);
      expect(find.byType(DevicePairingScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'BIZBOT real repository heartbeat returns rejected device to activation',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: 'd',
          sessionToken: 'test-token',
        ),
      );
      final wire = _HeartbeatWire();
      final repo = SupabaseDevicePairingRepository(
        transport: DeviceSessionGuardedTransport(wire),
        secretStore: store,
      );
      await _pump(
        tester,
        PosApp(
          demoMode: false,
          devicePairingRepository: repo,
          deviceStaffRepository: _FakeStaffDirectory(),
        ),
      );
      expect(find.byType(PinLoginScreen), findsOneWidget);
      expect(wire.heartbeats, 1);
      wire.revoked = true;
      await tester.pump(const Duration(minutes: 15));
      await tester.pumpAndSettle();
      expect(find.byType(DevicePairingScreen), findsOneWidget);
      expect(find.byType(PinLoginScreen), findsNothing);
      expect(await store.read(), isNull);
      final count = wire.heartbeats;
      await tester.pump(const Duration(minutes: 30));
      expect(wire.heartbeats, count);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final offline in [true, false]) {
    testWidgets(
      'BIZBOT ${offline ? "offline" : "unknown"} restore is retryable without activation',
      (tester) async {
        final pairing = _FakeOutcome(
          offline
              ? const DeviceSessionRestoreOffline()
              : const DeviceSessionRestoreUnavailable(),
        );
        await _pump(
          tester,
          PosApp(
            demoMode: false,
            devicePairingRepository: pairing,
            deviceStaffRepository: _FakeStaffDirectory(),
          ),
        );
        expect(find.byType(DevicePairingScreen), findsNothing);
        expect(
          find.byType(offline ? OfflineBootView : DeviceSessionUnavailableView),
          findsOneWidget,
        );
        pairing.outcome = const DeviceSessionRestored(
          DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            restaurantId: 'r',
            deviceId: 'd',
            deviceType: 'pos',
            deviceSessionId: 'ds-1',
          ),
        );
        await tester.tap(
          find.byKey(
            Key(offline ? 'offline-boot-retry' : 'device-session-retry'),
          ),
        );
        await tester.pumpAndSettle();
        expect(pairing.calls, 2);
        expect(pairing.lastExpectedDeviceType, 'pos');
        expect(find.byType(PinLoginScreen), findsOneWidget);
        expect(find.byType(DevicePairingScreen), findsNothing);
      },
    );
  }
  testWidgets('DEMO mode is unchanged — the menu, never the pairing screen', (
    tester,
  ) async {
    await _pump(tester, const PosApp(demoMode: true));
    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
  });

  testWidgets('PILOT-OFFLINE-BOOT-001: real mode with an offline problem shows '
      'the friendly offline screen, not the dev help page or the menu', (
    tester,
  ) async {
    await _pump(
      tester,
      const PosApp(
        demoMode: false,
        realAuthProblem: RealDeviceAuthProblem.offline,
      ),
    );
    expect(find.byType(OfflineBootView), findsOneWidget);
    expect(find.byType(DeviceSignInUnavailableView), findsNothing);
    expect(find.byType(PosMenuScreen), findsNothing);
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

  testWidgets('Part G: clearing the published device context (what the '
      'settings-sheet Unpair does) returns the gate to the pairing screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: PosApp(
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
      ),
    );
    await tester.pumpAndSettle();
    // Restored -> the staff PIN gate (a paired device is present).
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);

    // Unpair clears the published context; the gate returns to pairing.
    container.read(posDeviceContextProvider.notifier).set(null);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePairingScreen), findsOneWidget);
    expect(find.byType(PinLoginScreen), findsNothing);
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

  // Sprint fix: a POS device never has an owner account, so when the real
  // device bootstrap fails the app must say WHY — never the legacy account
  // gate's misleading "Account access denied".
  group('real mode without seams shows the honest bootstrap problem', () {
    testWidgets('anonymous sign-in unavailable -> the actionable help page, '
        'never "Account access denied"', (tester) async {
      await _pump(
        tester,
        const PosApp(
          demoMode: false,
          realAuthProblem: RealDeviceAuthProblem.signInUnavailable,
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.byType(DeviceSignInUnavailableView), findsOneWidget);
      expect(find.text(l10n.authDeviceSignInUnavailableBody), findsOneWidget);
      expect(find.text(l10n.authAccessDenied), findsNothing);
      expect(find.byType(PosMenuScreen), findsNothing);
      expect(find.byType(DevicePairingScreen), findsNothing);
    });

    testWidgets('missing Supabase config -> the unconfigured help page, '
        'never "Account access denied"', (tester) async {
      await _pump(
        tester,
        const PosApp(
          demoMode: false,
          realAuthProblem: RealDeviceAuthProblem.unconfigured,
        ),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
      expect(find.text(l10n.authAccessDenied), findsNothing);
      expect(find.byType(PosMenuScreen), findsNothing);
    });

    testWidgets('the pairing repo wins over a problem flag (paired flow is '
        'unaffected)', (tester) async {
      await _pump(
        tester,
        PosApp(
          demoMode: false,
          devicePairingRepository: _FakeRestorable(null),
          realAuthProblem: RealDeviceAuthProblem.signInUnavailable,
          fetchContext: fetcherForContext(_managerCtx()),
        ),
      );
      expect(find.byType(DevicePairingScreen), findsOneWidget);
      expect(find.byType(DeviceSignInUnavailableView), findsNothing);
    });
  });
}
