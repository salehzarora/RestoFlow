import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kds/main.dart';
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
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kdsAuthTransportProvider.overrideWithValue(transport),
        ...overrides,
      ],
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

/// Replicates the REAL app-root topology (main.dart): the app-level
/// [KdsSessionLifecycleObserver] wraps a session-driven swap between the LIVE
/// board (a stub for KdsSyncedHome — a SIBLING of the gate) and the [KdsPinGate].
/// This is the faithful shape for expiry tests: the observer must survive the
/// board/gate swap (a gate-local observer would be torn down when the board
/// mounts). The gate's own `child` is never rendered here (the board replaces it),
/// so it is a no-op placeholder.
Future<void> _pumpAppLike(
  WidgetTester tester, {
  required SyncRpcTransport transport,
  DeviceStaffRepository? staff,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kdsAuthTransportProvider.overrideWithValue(transport),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsSessionLifecycleObserver(
          child: Consumer(
            builder: (context, ref, _) {
              final session = ref.watch(kdsSyncSessionProvider);
              return session != null
                  ? const Text('KDS-BOARD', key: Key('kds-board'))
                  : KdsPinGate(
                      device: _device,
                      staffRepository: staff ?? _FakeStaff(),
                      child: const SizedBox.shrink(),
                    );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives the app to the background then back to the foreground through the
/// LEGAL lifecycle sequence (mobile-style), so the app-root observer records a
/// pause and then re-checks expiry on resume.
Future<void> _backgroundThenResume(WidgetTester tester) async {
  final binding = tester.binding;
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester, String pin) async {
  await tester.tap(find.byKey(const Key('pin-staff-emp-9')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('pin-input')), pin);
  await tester.tap(find.byKey(const Key('pin-submit')));
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

  group('RF-118 staff PIN-session expiry (KDS parity with POS)', () {
    testWidgets('main.dart wraps home in the app-root '
        'KdsSessionLifecycleObserver (so expiry survives the live/non-live '
        'board swap — the gate is torn down when the board mounts)', (
      tester,
    ) async {
      // The REAL app: the observer must sit ABOVE the home swap, not inside the
      // gate (which is unmounted the instant a session goes live).
      await tester.pumpWidget(const KdsApp(demoMode: true));
      await tester.pumpAndSettle();
      expect(find.byType(KdsSessionLifecycleObserver), findsOneWidget);
    });

    testWidgets('an active session STAYS on the board when it is not expired '
        '(default policy, brief background)', (tester) async {
      await _pumpAppLike(
        tester,
        transport: _FakeTransport(
          (fn, p) => fn == 'start_pin_session' ? 'pin-session-9' : null,
        ),
      );
      await _signIn(tester, '4321');
      expect(find.byKey(const Key('kds-board')), findsOneWidget);

      await _backgroundThenResume(tester); // default 30m/8h -> not expired
      expect(find.byKey(const Key('kds-board')), findsOneWidget);
      expect(find.byType(PinLoginScreen), findsNothing);
    });

    testWidgets(
      'an idle session expires on resume EVEN THOUGH the live board (not the '
      'gate) is mounted, returns to the money-free PIN gate, and shows the '
      'localized "enter PIN again" notice',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pumpAppLike(
          tester,
          transport: _FakeTransport(
            (fn, p) => fn == 'start_pin_session' ? 'pin-session-9' : null,
          ),
          overrides: [
            // Zero inactivity => any background+resume expires the session.
            kdsPinSessionExpiryPolicyProvider.overrideWithValue(
              const PinSessionExpiryPolicy(inactivityTimeout: Duration.zero),
            ),
          ],
        );
        await _signIn(tester, '4321');
        // The gate is now UNMOUNTED (the board is live) — the app-root observer
        // is what enforces expiry.
        expect(find.byKey(const Key('kds-board')), findsOneWidget);
        expect(find.byType(KdsPinGate), findsNothing);

        await _backgroundThenResume(tester);

        expect(find.byKey(const Key('kds-board')), findsNothing);
        expect(find.byType(PinLoginScreen), findsOneWidget);
        expect(find.text(l10n.pinSessionExpired), findsOneWidget);
        // Still money-free after expiry (SECURITY T-003).
        expect(find.textContaining('₪'), findsNothing);
        expect(find.textContaining(r'$'), findsNothing);
      },
    );

    testWidgets('the absolute max age expires the session on resume', (
      tester,
    ) async {
      await _pumpAppLike(
        tester,
        transport: _FakeTransport(
          (fn, p) => fn == 'start_pin_session' ? 'pin-session-9' : null,
        ),
        overrides: [
          kdsPinSessionExpiryPolicyProvider.overrideWithValue(
            const PinSessionExpiryPolicy(maxAge: Duration.zero),
          ),
        ],
      );
      await _signIn(tester, '4321');
      expect(find.byKey(const Key('kds-board')), findsOneWidget);

      await _backgroundThenResume(tester);
      expect(find.byType(PinLoginScreen), findsOneWidget);
      expect(find.byKey(const Key('kds-board')), findsNothing);
    });

    testWidgets('a re-established session clears the expired notice', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await _pumpAppLike(
        tester,
        transport: _FakeTransport(
          (fn, p) => fn == 'start_pin_session' ? 'pin-session-9' : null,
        ),
        overrides: [
          kdsPinSessionExpiryPolicyProvider.overrideWithValue(
            const PinSessionExpiryPolicy(inactivityTimeout: Duration.zero),
          ),
        ],
      );
      await _signIn(tester, '4321'); // session live -> board
      await _backgroundThenResume(tester); // expire -> gate + notice
      expect(find.text(l10n.pinSessionExpired), findsOneWidget);

      await _signIn(tester, '4321'); // sign in again -> board, notice cleared
      expect(find.byKey(const Key('kds-board')), findsOneWidget);
      expect(find.text(l10n.pinSessionExpired), findsNothing);
    });

    testWidgets('the KDS PIN cooldown still works (visible lockout after the '
        'threshold, submit disabled, no more server calls)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      var serverCalls = 0;
      final transport = _FakeTransport((fn, p) {
        if (fn == 'start_pin_session') serverCalls++;
        return null; // always a wrong PIN
      });
      await _pump(
        tester,
        transport: transport,
        overrides: [
          pinAttemptLimiterProvider.overrideWithValue(
            PinAttemptLimiter(store: InMemoryPinAttemptStore(), maxAttempts: 2),
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('pin-staff-emp-9')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.enterText(find.byKey(const Key('pin-input')), '0000');
        await tester.tap(find.byKey(const Key('pin-submit')));
        await tester.pumpAndSettle();
      }
      expect(serverCalls, 2);
      expect(find.text(l10n.pinLoginLocked), findsWidgets);
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('pin-submit')),
      );
      expect(submit.onPressed, isNull);

      // A further attempt is blocked locally (no new server call).
      await tester.enterText(find.byKey(const Key('pin-input')), '0000');
      await tester.tap(find.byKey(const Key('pin-submit')));
      await tester.pumpAndSettle();
      expect(serverCalls, 2);
      // Money-free throughout (kitchen surface, T-003).
      expect(find.textContaining('₪'), findsNothing);
    });
  });
}

class _EmptyStaff implements DeviceStaffRepository {
  @override
  Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>>
  listStaff() async => const Success([]);
}
