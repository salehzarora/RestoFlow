import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kds/src/kds_pin_gate.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

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
      employeeProfileId: 'emp-9',
      displayName: 'Yosef L.',
      role: 'kitchen_staff',
    ),
  ]);
}

const _device = DeviceContext(
  organizationId: 'o',
  branchId: 'b',
  deviceId: 'dev-9',
  deviceType: 'kds',
  deviceSessionId: 'ds-9',
);

Future<void> _pump(
  WidgetTester tester, {
  required SyncRpcTransport transport,
  DeviceStaffRepository? staff,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [kdsAuthTransportProvider.overrideWithValue(transport)],
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsPinGate(
          device: _device,
          staffRepository: staff ?? _FakeStaff(),
          child: const Text('KDS-BOARD', key: Key('kds-board')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no session -> the money-free PIN screen, never the board', (
    tester,
  ) async {
    await _pump(tester, transport: _FakeTransport((fn, p) => fail('no call')));
    expect(find.byType(PinLoginScreen), findsOneWidget);
    expect(find.byKey(const Key('kds-board')), findsNothing);
    // Kitchen surface: no money anywhere (SECURITY T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('a valid PIN starts the session and enters the board', (
    tester,
  ) async {
    final transport = _FakeTransport(
      (fn, p) => fn == 'start_pin_session' ? 'pin-session-9' : null,
    );
    await _pump(tester, transport: transport);

    await tester.tap(find.byKey(const Key('pin-staff-emp-9')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '4321');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kds-board')), findsOneWidget);
    final call = transport.calls.single;
    expect(call.$2['p_device_session_id'], 'ds-9');
    expect(call.$2['p_pin_verifier'], '4321');
  });

  testWidgets('a wrong PIN keeps the board locked', (tester) async {
    final transport = _FakeTransport((fn, p) => null);
    await _pump(tester, transport: transport);

    await tester.tap(find.byKey(const Key('pin-staff-emp-9')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-input')), '0000');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kds-board')), findsNothing);
    expect(find.text('Wrong PIN — try again.'), findsOneWidget);
  });

  testWidgets('no staff yet -> the KDS-specific Dashboard -> Staff guidance '
      '(sprint UX fix), money-free, never an account denial', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(
      tester,
      transport: _FakeTransport((fn, p) => fail('no sign-in without staff')),
      staff: _EmptyStaff(),
    );
    expect(find.text(l10n.pinLoginEmptyTitle), findsOneWidget);
    expect(find.text(l10n.pinLoginEmptyBodyKds), findsOneWidget);
    expect(find.textContaining('kitchen staff'), findsOneWidget);
    expect(find.text(l10n.pinLoginStepsTitle), findsOneWidget);
    expect(find.text(l10n.authTryAgain), findsOneWidget);
    expect(find.text(l10n.authAccessDenied), findsNothing);
    expect(find.byKey(const Key('kds-board')), findsNothing);
    // Kitchen device: still no money anywhere (SECURITY T-003).
    expect(find.textContaining('₪'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });
}

class _EmptyStaff implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success([]);
}
