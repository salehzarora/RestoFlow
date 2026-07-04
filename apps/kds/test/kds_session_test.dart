import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// RF-136: the KDS session provider establishes a REAL
/// `SyncSession(pinSessionId, deviceId)` by calling `public.start_pin_session`
/// (via [PinSessionService]) only when real mode + a Supabase transport + a
/// complete operator-supplied [KdsRealSessionConfig] are all present. Every other
/// case (demo mode, missing transport/config, wrong PIN, lockout, transient
/// error) fails closed to `null` - no fake session, no backend contact, and the
/// KDS stays on the demo/auth board. A real session yields a money-free
/// `KdsSyncCoordinator` (the polling-first `sync_pull` source). No SupabaseClient,
/// no network: a hand-written fake transport (house style) is injected via
/// [kdsAuthTransportProvider].
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

KdsRealSessionConfig _ctx() => KdsRealSessionConfig.fromValues(
  deviceId: 'device-abc',
  deviceSessionId: 'devsess-1',
  employeeProfileId: 'emp-1',
  pinVerifier: 'verifier-xyz',
)!;

void main() {
  ProviderContainer containerFor({
    required bool isDemoMode,
    SyncRpcTransport? transport,
    KdsRealSessionConfig? config,
  }) {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: isDemoMode),
        ),
        kdsAuthTransportProvider.overrideWithValue(transport),
        kdsRealSessionConfigProvider.overrideWithValue(config),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('KdsRealSessionConfig (operator-supplied context)', () {
    test('fromValues returns null when ANY field is blank (fail closed)', () {
      expect(
        KdsRealSessionConfig.fromValues(
          deviceId: '',
          deviceSessionId: 'ds',
          employeeProfileId: 'e',
          pinVerifier: 'p',
        ),
        isNull,
      );
      expect(
        KdsRealSessionConfig.fromValues(
          deviceId: 'd',
          deviceSessionId: '   ',
          employeeProfileId: 'e',
          pinVerifier: 'p',
        ),
        isNull,
      );
      expect(
        KdsRealSessionConfig.fromValues(
          deviceId: 'd',
          deviceSessionId: 'ds',
          employeeProfileId: 'e',
          pinVerifier: '',
        ),
        isNull,
      );
    });

    test('fromValues trims and builds when complete', () {
      final config = KdsRealSessionConfig.fromValues(
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
        KdsRealSessionConfig.deviceIdEnvName: 'dev',
        KdsRealSessionConfig.deviceSessionIdEnvName: 'ds',
        KdsRealSessionConfig.employeeProfileIdEnvName: 'emp',
        KdsRealSessionConfig.pinVerifierEnvName: 'pv',
      };
      final config = KdsRealSessionConfig.fromEnvironment(
        readEnv: (name) => env[name] ?? '',
      );
      expect(config, isNotNull);
      expect(config!.deviceSessionId, 'ds');
    });

    test('fromEnvironment fails closed when a define is missing', () {
      final config = KdsRealSessionConfig.fromEnvironment(
        readEnv: (name) =>
            name == KdsRealSessionConfig.pinVerifierEnvName ? '' : 'x',
      );
      expect(config, isNull);
    });
  });

  group('kdsSyncSessionProvider (RF-136 fail-closed session)', () {
    test('demo mode: no session, start_pin_session is never called, no '
        'real source', () async {
      final transport = _RecordingTransport(
        (_, _) async => fail('demo mode must not contact a backend'),
      );
      final container = containerFor(
        isDemoMode: true,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(kdsSessionControllerProvider.future), isNull);
      expect(container.read(kdsSyncSessionProvider), isNull);
      // Demo keeps the local board: no real coordinator is built.
      expect(container.read(kdsRealSyncSourceProvider), isNull);
      expect(transport.functions, isEmpty);
    });

    test('real mode: a started PIN session yields SyncSession(pinSessionId, '
        'deviceId) and calls public.start_pin_session (never app.*)', () async {
      final transport = _RecordingTransport((_, _) async => 'pin-session-id');
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      final session = await container.read(kdsSessionControllerProvider.future);
      expect(session, isNotNull);
      expect(session!.pinSessionId, 'pin-session-id');
      expect(session.deviceId, 'device-abc');
      expect(container.read(kdsSyncSessionProvider), session);

      // exactly one call, to the PUBLIC wrapper - never the app schema.
      expect(transport.functions, <String>['start_pin_session']);
      expect(transport.functions.any((f) => f.contains('app.')), isFalse);

      final params = transport.params.single;
      expect(params['p_device_session_id'], 'devsess-1');
      expect(params['p_employee_profile_id'], 'emp-1');
      expect(params['p_pin_verifier'], 'verifier-xyz');
      // the idempotency key (D-022) is generated and forwarded.
      expect(params['p_local_operation_id'], isA<String>());
      expect((params['p_local_operation_id'] as String).isNotEmpty, isTrue);
    });

    test('real mode: a real session builds the polling-first KdsSyncCoordinator '
        '(money-free sync_pull source)', () async {
      final transport = _RecordingTransport(
        (function, _) async =>
            function == 'start_pin_session' ? 'pin-session-id' : null,
      );
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      await container.read(kdsSessionControllerProvider.future);

      final source = container.read(kdsRealSyncSourceProvider);
      expect(source, isA<KdsSyncCoordinator>());
      // The coordinator is built but NOT started here (no poll/network until the
      // live board mounts). Dispose it so the broadcast controller is closed.
      addTearDown(() => source?.dispose());
    });

    test('real mode: a wrong PIN (NULL) fails closed', () async {
      final transport = _RecordingTransport((_, _) async => null);
      final container = containerFor(
        isDemoMode: false,
        transport: transport,
        config: _ctx(),
      );

      expect(await container.read(kdsSessionControllerProvider.future), isNull);
      expect(container.read(kdsSyncSessionProvider), isNull);
      expect(container.read(kdsRealSyncSourceProvider), isNull);
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

      expect(await container.read(kdsSessionControllerProvider.future), isNull);
      expect(container.read(kdsSyncSessionProvider), isNull);
      expect(container.read(kdsRealSyncSourceProvider), isNull);
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

      expect(await container.read(kdsSessionControllerProvider.future), isNull);
      expect(container.read(kdsSyncSessionProvider), isNull);
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
          await container.read(kdsSessionControllerProvider.future),
          isNull,
        );
        expect(container.read(kdsSyncSessionProvider), isNull);
        expect(container.read(kdsRealSyncSourceProvider), isNull);
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
          await container.read(kdsSessionControllerProvider.future),
          isNull,
        );
        expect(container.read(kdsSyncSessionProvider), isNull);
        expect(container.read(kdsRealSyncSourceProvider), isNull);
        expect(transport.functions, isEmpty);
      },
    );
  });

  group('KdsSessionController staff PIN-session expiry (RF-118)', () {
    final t0 = DateTime.utc(2026, 7, 4, 9);
    const policy = PinSessionExpiryPolicy(); // 30-min idle / 8-h max age

    // Signs in through the INTERACTIVE path under a CONTROLLABLE clock (config is
    // null so build() does not auto-establish first), stamping the expiry
    // window's start at [signInAt] so later checks can advance time precisely.
    Future<(ProviderContainer, KdsSessionController)> signedIn(
      DateTime signInAt,
    ) async {
      final container = containerFor(
        isDemoMode: false,
        transport: _RecordingTransport((_, _) async => 'pin-session-id'),
        config: null,
      );
      final controller = container.read(kdsSessionControllerProvider.notifier);
      await container.read(
        kdsSessionControllerProvider.future,
      ); // build() -> null
      controller.clock = () => signInAt;
      final err = await controller.signInWithPin(
        deviceId: 'device-abc',
        deviceSessionId: 'devsess-1',
        employeeProfileId: 'emp-1',
        pin: 'verifier-xyz',
      );
      expect(err, isNull);
      expect(container.read(kdsSyncSessionProvider), isNotNull);
      return (container, controller);
    }

    test('an active session (minutes in) is NOT expired', () async {
      final (container, controller) = await signedIn(t0);
      controller.clock = () => t0.add(const Duration(minutes: 5));
      expect(controller.endSessionIfExpired(policy), isFalse);
      expect(container.read(kdsSyncSessionProvider), isNotNull);
    });

    test(
      'expires after 30 minutes of inactivity (background then resume)',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0; // background at sign-in time
        controller.noteAppPaused();
        controller.clock = () =>
            t0.add(const Duration(minutes: 31)); // resume 31m
        expect(controller.endSessionIfExpired(policy), isTrue);
        expect(
          container.read(kdsSyncSessionProvider),
          isNull,
          reason: 'expiry clears the staff session -> back to the PIN gate',
        );
      },
    );

    test(
      'does NOT expire on resume when idle < the inactivity window',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0;
        controller.noteAppPaused();
        controller.clock = () =>
            t0.add(const Duration(minutes: 20)); // 20m < 30m
        expect(controller.endSessionIfExpired(policy), isFalse);
        expect(container.read(kdsSyncSessionProvider), isNotNull);
      },
    );

    test(
      'expires after the 8-hour absolute max age (even while active)',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0.add(const Duration(hours: 8, minutes: 1));
        expect(controller.endSessionIfExpired(policy), isTrue);
        expect(container.read(kdsSyncSessionProvider), isNull);
      },
    );

    test('a long-but-active session (never backgrounded) is NOT idle-expired '
        '(the idle anchor is now, not the sign-in time)', () async {
      final (container, controller) = await signedIn(t0);
      // 40 minutes since sign-in, but NEVER backgrounded -> active, not idle.
      controller.clock = () => t0.add(const Duration(minutes: 40));
      expect(
        controller.endSessionIfExpired(policy),
        isFalse,
        reason: 'without a pause, idle is measured from now (fixes ?? started)',
      );
      expect(container.read(kdsSyncSessionProvider), isNotNull);
    });

    test(
      'the first background moment wins: a foreground pass through hidden '
      'does NOT reset the idle anchor (mobile-lifecycle correctness)',
      () async {
        final (container, controller) = await signedIn(t0);
        controller.clock = () => t0;
        controller.noteAppPaused(); // real background at t0
        // Foregrounding re-fires noteAppPaused (hidden on the way up) 40m later:
        controller.clock = () => t0.add(const Duration(minutes: 40));
        controller.noteAppPaused(); // ??= : must NOT overwrite the t0 anchor
        expect(
          controller.endSessionIfExpired(policy),
          isTrue,
          reason: 'idle measured from the true background (t0), not the resume',
        );
        expect(container.read(kdsSyncSessionProvider), isNull);
      },
    );

    test('the pause anchor is consumed on resume (no phantom idle expiry on a '
        'later resume with no new background)', () async {
      final (container, controller) = await signedIn(t0);
      controller.clock = () => t0;
      controller.noteAppPaused();
      controller.clock = () => t0.add(const Duration(minutes: 10));
      expect(
        controller.endSessionIfExpired(policy),
        isFalse,
      ); // consumes anchor
      controller.clock = () => t0.add(const Duration(minutes: 50));
      expect(
        controller.endSessionIfExpired(policy),
        isFalse,
        reason: 'anchor was consumed -> active, not idle-expired',
      );
      expect(container.read(kdsSyncSessionProvider), isNotNull);
    });

    test('endSessionIfExpired is a no-op when there is no session', () async {
      final container = containerFor(
        isDemoMode: false,
        transport: _RecordingTransport((_, _) async => null), // wrong PIN
        config: _ctx(),
      );
      await container.read(kdsSessionControllerProvider.future); // null session
      final controller = container.read(kdsSessionControllerProvider.notifier);
      expect(
        controller.endSessionIfExpired(
          const PinSessionExpiryPolicy(maxAge: Duration.zero),
        ),
        isFalse,
      );
    });
  });
}
