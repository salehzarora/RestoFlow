import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// RF-131: the POS session provider establishes a REAL
/// `SyncSession(pinSessionId, deviceId)` by calling `public.start_pin_session`
/// (via [PinSessionService]) only when real mode + a Supabase transport + a
/// complete operator-supplied [PosRealSessionConfig] are all present. Every other
/// case (demo mode, missing transport/config, wrong PIN, lockout, transient
/// error) fails closed to `null` - no fake session, no backend contact. No
/// SupabaseClient, no network: a hand-written fake transport (house style) is
/// injected via [posAuthTransportProvider].
class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);

  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;

  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    functions.add(function);
    params.add(p);
    return _handler(function, p);
  }
}

PosRealSessionConfig _ctx() => PosRealSessionConfig.fromValues(
  deviceId: 'device-abc',
  deviceSessionId: 'devsess-1',
  employeeProfileId: 'emp-1',
  pinVerifier: 'verifier-xyz',
)!;

void main() {
  ProviderContainer containerFor({
    required bool isDemoMode,
    SyncRpcTransport? transport,
    PosRealSessionConfig? config,
  }) {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: isDemoMode),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posRealSessionConfigProvider.overrideWithValue(config),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('PosRealSessionConfig (operator-supplied context)', () {
    test('fromValues returns null when ANY field is blank (fail closed)', () {
      expect(
        PosRealSessionConfig.fromValues(
          deviceId: '',
          deviceSessionId: 'ds',
          employeeProfileId: 'e',
          pinVerifier: 'p',
        ),
        isNull,
      );
      expect(
        PosRealSessionConfig.fromValues(
          deviceId: 'd',
          deviceSessionId: '   ',
          employeeProfileId: 'e',
          pinVerifier: 'p',
        ),
        isNull,
      );
      expect(
        PosRealSessionConfig.fromValues(
          deviceId: 'd',
          deviceSessionId: 'ds',
          employeeProfileId: 'e',
          pinVerifier: '',
        ),
        isNull,
      );
    });

    test('fromValues trims and builds when complete', () {
      final config = PosRealSessionConfig.fromValues(
        deviceId: ' device-abc ',
        deviceSessionId: 'devsess-1',
        employeeProfileId: 'emp-1',
        pinVerifier: 'verifier-xyz',
      );
      expect(config, isNotNull);
      expect(config!.deviceId, 'device-abc');
      expect(config.deviceSessionId, 'devsess-1');
      expect(config.employeeProfileId, 'emp-1');
      expect(config.pinVerifier, 'verifier-xyz');
    });

    test('fromEnvironment reads the four dart-define names', () {
      final env = <String, String>{
        PosRealSessionConfig.deviceIdEnvName: 'dev',
        PosRealSessionConfig.deviceSessionIdEnvName: 'ds',
        PosRealSessionConfig.employeeProfileIdEnvName: 'emp',
        PosRealSessionConfig.pinVerifierEnvName: 'pv',
      };
      final config = PosRealSessionConfig.fromEnvironment(
        readEnv: (name) => env[name] ?? '',
      );
      expect(config, isNotNull);
      expect(config!.deviceSessionId, 'ds');
    });

    test('fromEnvironment fails closed when a define is missing', () {
      final config = PosRealSessionConfig.fromEnvironment(
        readEnv: (name) =>
            name == PosRealSessionConfig.pinVerifierEnvName ? '' : 'x',
      );
      expect(config, isNull);
    });
  });

  group('posSyncSessionProvider (RF-131 fail-closed session)', () {
    test('demo mode: no session, start_pin_session is never called', () async {
      final transport = _RecordingTransport(
        (_, _) async => fail('demo mode must not contact a backend'),
      );
      final container = containerFor(
        isDemoMode: true,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(posSessionControllerProvider.future), isNull);
      expect(container.read(posSyncSessionProvider), isNull);
      expect(transport.functions, isEmpty);
    });

    test('real mode: a started PIN session yields SyncSession(pinSessionId, '
        'deviceId) and calls public.start_pin_session (never app.*)', () async {
      // start_pin_session yields the pin-session id; the best-effort shift.open
      // push APPLIES (a fresh shift), so no sync_pull recovery is needed (RF-113).
      final transport = _RecordingTransport((function, _) async {
        if (function == 'sync_push') {
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
        return 'pin-session-id';
      });
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      final session = await container.read(posSessionControllerProvider.future);
      expect(session, isNotNull);
      expect(session!.pinSessionId, 'pin-session-id');
      expect(session.deviceId, 'device-abc');
      expect(container.read(posSyncSessionProvider), session);

      // Let the fire-and-forget shift bootstrap (RF-055 sprint fix) settle.
      await pumpEventQueue();

      // The sign-in call hits the PUBLIC wrapper - never the app schema - and
      // is followed by the best-effort shift.open push (payments require an
      // open shift since RF-055; the POS has no shift UI yet).
      expect(transport.functions.first, 'start_pin_session');
      expect(transport.functions, <String>['start_pin_session', 'sync_push']);
      expect(transport.functions.any((f) => f.contains('app.')), isFalse);

      final params = transport.params.first;
      expect(params['p_device_session_id'], 'devsess-1');
      expect(params['p_employee_profile_id'], 'emp-1');
      expect(params['p_pin_verifier'], 'verifier-xyz');
      // the idempotency key (D-022) is generated and forwarded.
      expect(params['p_local_operation_id'], isA<String>());
      expect((params['p_local_operation_id'] as String).isNotEmpty, isTrue);

      final shiftOp =
          ((transport.params[1]['p_operations'] as List).single as Map);
      expect(shiftOp['operation_type'], 'shift.open');
      expect((shiftOp['payload'] as Map)['opening_float_minor'], 0);
    });

    test('real mode: a wrong PIN (NULL) fails closed', () async {
      final transport = _RecordingTransport((_, _) async => null);
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(posSessionControllerProvider.future), isNull);
      expect(container.read(posSyncSessionProvider), isNull);
      expect(transport.functions, <String>['start_pin_session']);
    });

    test('real mode: a 42501 lockout/precondition fails closed', () async {
      final transport = _RecordingTransport(
        (_, _) async => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'locked / precondition',
        ),
      );
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(posSessionControllerProvider.future), isNull);
      expect(container.read(posSyncSessionProvider), isNull);
    });

    test('real mode: a transient transport error fails closed', () async {
      final transport = _RecordingTransport(
        (_, _) async => throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '503',
          message: 'unavailable',
        ),
      );
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(posSessionControllerProvider.future), isNull);
      expect(container.read(posSyncSessionProvider), isNull);
    });

    test(
      'real mode without a transport (missing/invalid Supabase config) fails '
      'closed',
      () async {
        final container = containerFor(
          isDemoMode: false,
          transport: null,
          config: _ctx(),
        );

        expect(
          await container.read(posSessionControllerProvider.future),
          isNull,
        );
        expect(container.read(posSyncSessionProvider), isNull);
      },
    );

    test(
      'real mode without device/PIN context fails closed and makes no call',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => fail('no PIN attempt without an operator context'),
        );
        final container = containerFor(
          isDemoMode: false,
          transport: transport,
          config: null,
        );

        expect(
          await container.read(posSessionControllerProvider.future),
          isNull,
        );
        expect(container.read(posSyncSessionProvider), isNull);
        expect(transport.functions, isEmpty);
      },
    );

    test(
      'a real session unlocks the real outbox (no longer fails closed)',
      () async {
        final transport = _RecordingTransport(
          (function, _) async =>
              function == 'start_pin_session' ? 'pin-session-id' : null,
        );
        final container = containerFor(
          isDemoMode: false,
          transport: transport,
          config: _ctx(),
        );

        await container.read(posSessionControllerProvider.future);

        final outbox = container.read(outboxRepositoryProvider);
        expect(outbox, isA<RealOutboxRepository>());
        // With a transport + a session, the real outbox is ready: reading recent
        // entries no longer throws OrderSubmissionException (fail-closed) and
        // contacts no backend for an empty store.
        expect(await outbox.recentEntries(), isEmpty);
      },
    );
  });

  // RF-118 blocking-fix parity: the POS staff PIN-session expiry (the same shared
  // PinSessionExpiryPolicy the KDS now mirrors). Uses a CONTROLLABLE clock so the
  // real 30-min / 8-h boundaries + the idle-anchor correctness are deterministic.
  group('PosSessionController staff PIN-session expiry (RF-118)', () {
    final t0 = DateTime.utc(2026, 7, 4, 9);
    const policy = PinSessionExpiryPolicy(); // 30-min idle / 8-h max age

    Future<(ProviderContainer, PosSessionController)> signedIn(
      DateTime signInAt,
    ) async {
      final container = containerFor(
        isDemoMode: false,
        transport: _RecordingTransport((function, _) async {
          // The best-effort shift.open push is fire-and-forget; return an applied
          // result so it settles cleanly (not under test here).
          if (function == 'sync_push') {
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
          return 'pin-session-id';
        }),
        config: null, // no auto-establish: sign in manually under a fixed clock
      );
      final controller = container.read(posSessionControllerProvider.notifier);
      await container.read(
        posSessionControllerProvider.future,
      ); // build() -> null
      controller.clock = () => signInAt;
      final err = await controller.signInWithPin(
        deviceId: 'device-abc',
        deviceSessionId: 'devsess-1',
        employeeProfileId: 'emp-1',
        pin: 'verifier-xyz',
      );
      expect(err, isNull);
      await pumpEventQueue(); // let the fire-and-forget shift bootstrap settle
      expect(container.read(posSyncSessionProvider), isNotNull);
      return (container, controller);
    }

    test('an active session (minutes in) is NOT expired', () async {
      final (container, controller) = await signedIn(t0);
      controller.clock = () => t0.add(const Duration(minutes: 5));
      expect(controller.endSessionIfExpired(policy), isFalse);
      expect(container.read(posSyncSessionProvider), isNotNull);
    });

    test(
      'expires after 30 minutes of inactivity (background then resume)',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0;
        controller.noteAppPaused();
        controller.clock = () => t0.add(const Duration(minutes: 31));
        expect(controller.endSessionIfExpired(policy), isTrue);
        expect(container.read(posSyncSessionProvider), isNull);
      },
    );

    test(
      'expires after the 8-hour absolute max age (even while active)',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0.add(const Duration(hours: 8, minutes: 1));
        expect(controller.endSessionIfExpired(policy), isTrue);
        expect(container.read(posSyncSessionProvider), isNull);
      },
    );

    test(
      'a long-but-active session (never backgrounded) is NOT idle-expired',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0.add(const Duration(minutes: 40));
        expect(
          controller.endSessionIfExpired(policy),
          isFalse,
          reason: 'without a pause, idle is measured from now, not sign-in',
        );
        expect(container.read(posSyncSessionProvider), isNotNull);
      },
    );

    test('the first background moment wins (mobile foreground pass-through '
        'hidden does not reset the idle anchor)', () async {
      final (container, controller) = await signedIn(t0);
      controller.clock = () => t0;
      controller.noteAppPaused();
      controller.clock = () => t0.add(const Duration(minutes: 40));
      controller.noteAppPaused(); // must NOT overwrite
      expect(controller.endSessionIfExpired(policy), isTrue);
      expect(container.read(posSyncSessionProvider), isNull);
    });

    test('endSessionIfExpired is a no-op when there is no session', () async {
      final container = containerFor(
        isDemoMode: false,
        transport: _RecordingTransport((_, _) async => null), // wrong PIN
        config: _ctx(),
      );
      await container.read(posSessionControllerProvider.future);
      final controller = container.read(posSessionControllerProvider.notifier);
      expect(
        controller.endSessionIfExpired(
          const PinSessionExpiryPolicy(maxAge: Duration.zero),
        ),
        isFalse,
      );
    });
  });
}
