import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_pin_gate.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

class _FakeStaff implements DeviceStaffRepository {
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

const _device = DeviceContext(
  organizationId: 'o',
  branchId: 'b',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
);

Future<void> _pump(
  WidgetTester tester, {
  required SyncRpcTransport transport,
  DeviceContext device = _device,
  DeviceStaffRepository? staff,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posAuthTransportProvider.overrideWithValue(transport),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: PosPinGate(
          device: device,
          staffRepository: staff ?? _FakeStaff(),
          child: const Text('POS-SURFACE', key: Key('pos-surface')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives the app to the background then back to the foreground through the
/// LEGAL lifecycle sequence, so the gate's WidgetsBindingObserver records a pause
/// and re-checks expiry on resume.
Future<void> _backgroundThenResume(WidgetTester tester) async {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no session -> the PIN screen, never the POS surface', (
    tester,
  ) async {
    await _pump(tester, transport: _FakeTransport((fn, p) => fail('no call')));
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.byKey(const Key('pos-surface')), findsNothing);
  });

  testWidgets('a valid PIN starts the session and enters the POS surface', (
    tester,
  ) async {
    final transport = _FakeTransport(
      (fn, p) => fn == 'start_pin_session' ? 'pin-session-1' : null,
    );
    await _pump(tester, transport: transport);

    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-surface')), findsOneWidget);
    // The RPC got the RESTORED device-session handle + the typed PIN.
    final call = transport.calls.first;
    expect(call.$1, 'start_pin_session');
    expect(call.$2['p_device_session_id'], 'ds-1');
    expect(call.$2['p_employee_profile_id'], 'emp-1');
    expect(call.$2['p_pin_verifier'], '1234');
    // A shift bootstrap followed (RF-055: payments require an open shift).
    final shiftCall = transport.calls[1];
    expect(shiftCall.$1, 'sync_push');
    final op = (shiftCall.$2['p_operations'] as List).single as Map;
    expect(op['operation_type'], 'shift.open');
    expect((op['payload'] as Map)['opening_float_minor'], 0);
  });

  testWidgets('a wrong PIN (NULL) keeps the gate closed with a safe error', (
    tester,
  ) async {
    final transport = _FakeTransport((fn, p) => null); // wrong verifier
    await _pump(tester, transport: transport);

    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '9999');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-surface')), findsNothing);
    expect(find.text('Wrong PIN — try again.'), findsOneWidget);
  });

  testWidgets(
    "a session minted for ANOTHER pairing does not unlock this till — the PIN "
    'screen is shown, not the POS surface',
    (tester) async {
      // The stale-session shape: the till was unpaired (which never ends the
      // in-memory PIN session) and re-paired as a NEW device. The old session is
      // still standing — for a device this pairing has never been.
      await _pump(
        tester,
        transport: _FakeTransport((fn, p) => fail('no call')),
        overrides: [
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(
              pinSessionId: 'stale-pin-A',
              deviceId: 'SOME-OTHER-DEVICE',
            ),
          ),
        ],
      );

      // Rendering the POS here would run every submit and payment under the OLD
      // pairing's server session — orders taken on this till, created on another
      // branch's books.
      expect(find.byKey(const Key('pos-surface')), findsNothing);
      expect(find.byType(PinLoginScreen), findsOneWidget);
    },
  );

  testWidgets('a device context WITHOUT a session handle fails closed', (
    tester,
  ) async {
    await _pump(
      tester,
      transport: _FakeTransport((fn, p) => fail('no call')),
      device: const DeviceContext(
        organizationId: 'o',
        branchId: 'b',
        deviceId: 'dev-1',
        deviceType: 'pos',
        // no deviceSessionId
      ),
    );
    expect(find.byType(RealModeUnconfiguredView), findsOneWidget);
    expect(find.byKey(const Key('pos-surface')), findsNothing);
  });

  testWidgets('no staff yet -> the POS-specific Dashboard -> Staff guidance '
      '(sprint UX fix), never an account denial', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(
      tester,
      transport: _FakeTransport((fn, p) => fail('no sign-in without staff')),
      staff: _EmptyStaff(),
    );
    expect(find.text(l10n.pinLoginEmptyTitle), findsOneWidget);
    expect(find.text(l10n.pinLoginEmptyBodyPos), findsOneWidget);
    expect(find.textContaining('cashier'), findsOneWidget);
    expect(find.text(l10n.pinLoginStepsTitle), findsOneWidget);
    expect(find.text(l10n.authTryAgain), findsOneWidget);
    expect(find.text(l10n.authAccessDenied), findsNothing);
    expect(find.byKey(const Key('pos-surface')), findsNothing);
  });

  testWidgets('RF-118: an idle session expires on resume, returns to the PIN '
      'gate, and shows the localized "enter PIN again" notice', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(
      tester,
      transport: _FakeTransport((fn, p) {
        if (fn == 'sync_push') {
          return <String, dynamic>{
            'ok': true,
            'results': <dynamic>[
              <String, dynamic>{
                'operation_type': 'shift.open',
                'status': 'applied',
                'ok': true,
              },
            ],
          };
        }
        return fn == 'start_pin_session' ? 'pin-session-1' : null;
      }),
      overrides: [
        // Zero inactivity => any background+resume expires the session.
        posPinSessionExpiryPolicyProvider.overrideWithValue(
          const PinSessionExpiryPolicy(inactivityTimeout: Duration.zero),
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('pin-staff-emp-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '1234');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-surface')), findsOneWidget);

    await _backgroundThenResume(tester);

    expect(find.byKey(const Key('pos-surface')), findsNothing);
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.text(l10n.pinSessionExpired), findsOneWidget);
  });
}

class _EmptyStaff implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success([]);
}
