import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/online_order_inbox.dart';
import 'package:restoflow_pos/src/media/background_order_alert_bridge.dart';
import 'package:restoflow_pos/src/state/background_order_alerts.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'online_order_inbox_fixtures.dart';

final _identity = StateProvider<String?>(
  (ref) => 'synthetic-scope|device-session|pin',
);

class _Bridge implements BackgroundOrderAlertBridge {
  Future<Map<String, dynamic>> Function(bool)? prepareHandler;
  Future<bool> Function(Map<String, dynamic>)? bindHandler;
  bool available = true;
  bool enabled = true;
  bool bindsAllowed = true;
  bool cleanupThrows = false;
  final retainedOptIns = <bool>[];
  int prepares = 0;
  int permissionPrompts = 0;
  int suspends = 0;
  int disables = 0;
  int taps = 0;
  final bindings = <Map<String, dynamic>>[];
  final snapshots = <Map<String, dynamic>>[];
  void Function()? tokenChanged;
  void Function()? pendingHint;
  @override
  Future<Map<String, dynamic>> prepare({bool requestPermission = false}) async {
    prepares++;
    if (prepareHandler != null) {
      if (requestPermission) permissionPrompts++;
      final result = await prepareHandler!(requestPermission);
      enabled = result['enabled'] == true;
      return result;
    }
    if (requestPermission) {
      permissionPrompts++;
      enabled = true;
    }
    return {
      'available': available,
      'enabled': enabled,
      'installation_id': '11111111-1111-4111-8111-111111111111',
      'fcm_token': 'synthetic-token',
      'status_secret': '0' * 64,
      'generation': prepares,
    };
  }

  @override
  Future<bool> bind(Map<String, dynamic> binding) async {
    bindings.add(binding);
    final allowed =
        await (bindHandler?.call(binding) ?? Future.value(bindsAllowed));
    if (allowed) enabled = true;
    return allowed;
  }

  @override
  Future<void> pending(Map<String, dynamic> snapshot) async =>
      snapshots.add(snapshot);
  @override
  Future<void> suspend({bool retainOptIn = false}) async {
    suspends++;
    if (cleanupThrows) throw StateError("synthetic cleanup failure");
    retainedOptIns.add(retainOptIn);
  }

  @override
  Future<void> disable() async {
    disables++;
    if (cleanupThrows) throw StateError("synthetic cleanup failure");
    enabled = false;
  }

  @override
  Future<bool> consumeInboxTap() async {
    taps++;
    return true;
  }

  @override
  void setHints({
    required void Function() tokenChanged,
    required void Function() pendingHint,
  }) {
    this.tokenChanged = tokenChanged;
    this.pendingHint = pendingHint;
  }

  @override
  Future<void> dispose() async {}
}

class _Transport extends SyncRpcTransport {
  _Transport(this.handler);
  final Future<Object?> Function() handler;
  final calls = <String>[];
  final parameters = <Map<String, dynamic>>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    calls.add(function);
    parameters.add(Map<String, dynamic>.from(params));
    return handler();
  }
}

class _GatedStore extends InMemoryDeviceSessionSecretStore {
  final gate = Completer<DeviceSessionCredential?>();
  @override
  Future<DeviceSessionCredential?> read() => gate.future;
}

Map<String, dynamic> _registered() => {
  'ok': true,
  'registration_id': '22222222-2222-4222-8222-222222222222',
  'generation': '33333333-3333-4333-8333-333333333333',
  'authority_expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 15))
      .toIso8601String(),
};

Future<void> _run(
  WidgetTester tester,
  Future<void> Function(
    ProviderContainer,
    _Bridge,
    FakeInboxRepository,
    List<Map<String, dynamic>>,
  )
  body, {
  bool enabledBuild = true,
  bool nativeEnabled = true,
  bool nativeAvailable = true,
  bool bindsAllowed = true,
  Future<Map> Function(Map<String, dynamic>)? register,
  Future<Map<String, dynamic>> Function(bool)? prepare,
  Future<bool> Function(Map<String, dynamic>)? bind,
  _Transport? transport,
  DeviceSessionSecretStore? store,
  DateTime Function()? clock,
}) async {
  final bridge = _Bridge()
    ..prepareHandler = prepare
    ..bindHandler = bind
    ..enabled = nativeEnabled
    ..available = nativeAvailable
    ..bindsAllowed = bindsAllowed;
  final repo = FakeInboxRepository();
  final registrations = <Map<String, dynamic>>[];
  final container = ProviderContainer(
    overrides: [
      backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(enabledBuild),
      backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
      if (clock != null)
        backgroundOrderAlertClockProvider.overrideWithValue(clock),
      backgroundOrderAlertEndpointProvider.overrideWithValue(
        'https://synthetic.invalid/functions/v1/pos-order-alert-status',
      ),
      if (transport != null) ...[
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(deviceId: deviceId, pinSessionId: pinId),
        ),
        onlineOrderInboxSecretStoreProvider.overrideWithValue(store),
      ],
      if (transport == null)
        backgroundOrderAlertRegisterProvider.overrideWithValue((
          params, {
          authorize,
          isCurrent,
        }) async {
          registrations.add(params);
          return register?.call(params) ??
              {
                'ok': true,
                'registration_id': '22222222-2222-4222-8222-222222222222',
                'generation': '33333333-3333-4333-8333-333333333333',
                'authority_expires_at': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
              };
        }),
      onlineOrderInboxIdentityProvider.overrideWith(
        (ref) => ref.watch(_identity),
      ),
      onlineOrderInboxRepositoryProvider.overrideWithValue(repo),
      onlineOrderInboxPollIntervalProvider.overrideWithValue(null),
      onlineOrderInboxAlertIntervalProvider.overrideWithValue(null),
      onlineInboxCancelPrintProvider.overrideWithValue(() {}),
      onlineInboxAcceptedPrintProvider.overrideWithValue(
        (_, __) async => throw StateError('printing must not be called'),
      ),
    ],
  );
  final subscription = container.listen(
    backgroundOrderAlertsProvider,
    (_, __) {},
    fireImmediately: true,
  );
  try {
    await tester.pump();
    await body(container, bridge, repo, registrations);
  } finally {
    subscription.close();
    container.dispose();
    // Flush Riverpod's zero-duration refresh task; pump() without a duration
    // flushes microtasks only in this standalone ProviderContainer harness.
    await tester.pump(Duration.zero);
  }
}

void main() {
  testWidgets(
    'token change during prepare re-reads latest token before one registration',
    (tester) async {
      final oldLookup = Completer<Map<String, dynamic>>();
      var lookups = 0;
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          bridge.tokenChanged!();
          oldLookup.complete({
            ..._prepared(),
            'fcm_token': 'synthetic-old-token',
          });
          await tester.pump();
          expect(lookups, 2);
          expect(registrations, hasLength(1));
          expect(
            registrations.single['p_fcm_token'],
            'synthetic-current-token',
          );
          expect(bridge.permissionPrompts, 0);
          expect(bridge.bindings, hasLength(1));
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
          expect(repository.decisions, isEmpty);
        },
        prepare: (_) => ++lookups == 1
            ? oldLookup.future
            : Future.value({
                ..._prepared(),
                'fcm_token': 'synthetic-current-token',
              }),
      );
    },
  );
  testWidgets(
    'token hints during an issued registration reconcile once after its native lane',
    (tester) async {
      final first = Completer<Map>();
      var issued = 0;
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          expect(registrations, hasLength(1));
          for (var i = 0; i < 5; i++) {
            bridge.tokenChanged!();
          }
          expect(registrations, hasLength(1));
          first.complete(_registered());
          await tester.pump();
          expect(registrations, hasLength(2));
          expect(bridge.bindings, hasLength(2));
          expect(bridge.permissionPrompts, 0);
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
          expect(repository.decisions, isEmpty);
        },
        register: (_) =>
            ++issued == 1 ? first.future : Future.value(_registered()),
      );
    },
  );
  testWidgets(
    'paused registration retains token hints and binds the latest server generation after resume',
    (tester) async {
      final firstRegistration = Completer<Map>();
      var calls = 0;
      const latestGeneration = '44444444-4444-4444-8444-444444444444';
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          final controller = container.read(
            backgroundOrderAlertsProvider.notifier,
          );
          expect(registrations, hasLength(1));
          controller.onPaused();
          bridge.tokenChanged!();
          firstRegistration.complete(_registered());
          await tester.pump();
          expect(bridge.bindings, isEmpty);
          expect(registrations, hasLength(1));
          controller.onResume();
          await tester.pump();
          expect(registrations, hasLength(2));
          expect(bridge.bindings, hasLength(2));
          expect(
            bridge.bindings.last['registration_generation'],
            latestGeneration,
          );
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
          expect(bridge.permissionPrompts, 0);
          expect(repository.decisions, isEmpty);
        },
        register: (_) => ++calls == 1
            ? firstRegistration.future
            : Future.value({..._registered(), 'generation': latestGeneration}),
      );
    },
  );
  testWidgets(
    'foreground renewal never extends an unchanged server authorization deadline',
    (tester) async {
      var clock = DateTime.utc(2026, 10, 20, 12);
      final expiry = clock.add(const Duration(minutes: 5));
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          for (final minutes in [3, 1, 1]) {
            clock = clock.add(Duration(minutes: minutes));
            await tester.pump(Duration(minutes: minutes));
          }
          expect(registrations, hasLength(3));
          expect(
            container.read(backgroundOrderAlertsProvider).enabled,
            isFalse,
          );
          expect(
            container.read(backgroundOrderAlertsProvider).authorizationExpired,
            isTrue,
          );
          expect(bridge.permissionPrompts, 0);
          expect(repository.decisions, isEmpty);
        },
        clock: () => clock,
        register: (_) async => {
          'ok': true,
          'registration_id': '22222222-2222-4222-8222-222222222222',
          'generation': '33333333-3333-4333-8333-333333333333',
          'authority_expires_at': expiry.toIso8601String(),
        },
      );
    },
  );
  testWidgets(
    'foreground opt-in renews before expiry without another permission prompt',
    (tester) async {
      var clock = DateTime.utc(2026, 10, 20, 12);
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          expect(registrations, hasLength(1));
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
          clock = clock.add(const Duration(minutes: 2, seconds: 59));
          await tester.pump(const Duration(minutes: 2, seconds: 59));
          expect(registrations, hasLength(1));
          clock = clock.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(registrations, hasLength(2));
          expect(bridge.bindings, hasLength(2));
          expect(bridge.permissionPrompts, 0);
          expect(repository.decisions, isEmpty);
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
        },
        clock: () => clock,
        register: (_) async => {
          'ok': true,
          'registration_id': '22222222-2222-4222-8222-222222222222',
          'generation': '33333333-3333-4333-8333-333333333333',
          'authority_expires_at': clock
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        },
      );
    },
  );
  testWidgets(
    'expired background delegation needs a fresh authenticated identity',
    (tester) async {
      var clock = DateTime.utc(2026, 10, 20, 12);
      await _run(
        tester,
        (container, bridge, repository, registrations) async {
          final controller = container.read(
            backgroundOrderAlertsProvider.notifier,
          );
          controller.onPaused();
          clock = clock.add(const Duration(hours: 9));
          await tester.pump(const Duration(hours: 9));
          expect(registrations, hasLength(1));
          controller.onResume();
          await tester.pump();
          expect(registrations, hasLength(1));
          expect(
            container.read(backgroundOrderAlertsProvider).enabled,
            isFalse,
          );
          expect(
            container.read(backgroundOrderAlertsProvider).authorizationExpired,
            isTrue,
          );
          expect(bridge.permissionPrompts, 0);
          // Existing PIN authentication publishes a new identity. Re-enabling
          // under that real identity uses the existing consent flow; this
          // notification controller never manufactures a PIN session.
          container.read(_identity.notifier).state =
              'synthetic-scope|device-session|new-real-pin';
          await tester.pump();
          await container
              .read(backgroundOrderAlertsProvider.notifier)
              .setEnabled(true);
          expect(registrations, hasLength(2));
          expect(container.read(backgroundOrderAlertsProvider).enabled, isTrue);
          expect(repository.decisions, isEmpty);
        },
        clock: () => clock,
        register: (_) async => {
          'ok': true,
          'registration_id': '22222222-2222-4222-8222-222222222222',
          'generation': '33333333-3333-4333-8333-333333333333',
          'authority_expires_at': clock
              .add(const Duration(hours: 8))
              .toIso8601String(),
        },
      );
    },
  );
  for (final missingPlugin in [false, true]) {
    testWidgets(
      'real MethodChannel ${missingPlugin ? 'missing plugin' : 'platform error'} cleanup fails closed without throwing legacy writers',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        const channel = MethodChannel('restoflow.pos/background_order_alert');
        var failing = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (failing) {
              if (missingPlugin) throw MissingPluginException();
              throw PlatformException(code: 'synthetic-error');
            }
            return null;
          },
        );
        final bridge = MethodChannelBackgroundOrderAlertBridge(
          channel: channel,
        );
        var registrations = 0;
        final container = ProviderContainer(
          overrides: [
            backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(true),
            backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
            backgroundOrderAlertRegisterProvider.overrideWithValue((
              params, {
              authorize,
              isCurrent,
            }) async {
              registrations++;
              return _registered();
            }),
            onlineOrderInboxIdentityProvider.overrideWithValue(
              'synthetic-identity',
            ),
            onlineOrderInboxRepositoryProvider.overrideWithValue(
              FakeInboxRepository(),
            ),
            onlineOrderInboxPollIntervalProvider.overrideWithValue(null),
            onlineOrderInboxAlertIntervalProvider.overrideWithValue(null),
          ],
        );
        container.listen(backgroundOrderAlertsProvider, (_, __) {});
        try {
          await tester.pump();
          await bridge.disable(); // existing logout/unpair writers never throw
          await bridge.suspend();
          expect(await bridge.revoke(), false);
          final controller = container.read(
            backgroundOrderAlertsProvider.notifier,
          );
          await controller.setEnabled(false);
          expect(container.read(backgroundOrderAlertsProvider).failed, true);
          await controller.setEnabled(true);
          expect(container.read(backgroundOrderAlertsProvider).enabled, false);
          expect(registrations, 0);
          await bridge.dispose();
          expect(await bridge.revoke(), false);
          failing = false;
          await controller.setEnabled(false); // successful observed revocation
          expect(await bridge.revoke(), true); // native void success is null
          expect(await bridge.bind({}), false); // still disposed: cannot enable
        } finally {
          failing = false;
          container.dispose();
          await tester.pump(Duration.zero);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  testWidgets(
    'repeated consent, resume and token hints share one native lane',
    (tester) async {
      final automatic = Completer<Map<String, dynamic>>();
      final permission = Completer<Map<String, dynamic>>();
      final registration = Completer<Map>();
      final binding = Completer<bool>();
      await _run(
        tester,
        (c, b, r, reg) async {
          final controller = c.read(backgroundOrderAlertsProvider.notifier);
          final first = controller.setEnabled(true);
          final second = controller.setEnabled(true);
          for (var i = 0; i < 5; i++) {
            controller.onResume();
            b.tokenChanged!();
          }
          expect(identical(first, second), true);
          expect(b.prepares, 1);
          automatic.complete(_prepared(enabled: false));
          await tester.pump();
          expect(b.prepares, 2);
          expect(b.permissionPrompts, 1);
          permission.complete(_prepared());
          await tester.pump();
          expect(reg, hasLength(1));
          expect(c.read(backgroundOrderAlertsProvider).enabled, false);
          registration.complete(_registered());
          await tester.pump();
          expect(b.bindings, hasLength(1));
          expect(c.read(backgroundOrderAlertsProvider).enabled, false);
          binding.complete(true);
          await tester.pump();
          await first;
          await second;
          expect(c.read(backgroundOrderAlertsProvider).enabled, true);
          expect(c.read(backgroundOrderAlertsProvider).busy, false);
          expect(r.decisions, isEmpty);
        },
        prepare: (explicit) => explicit ? permission.future : automatic.future,
        register: (_) => registration.future,
        bind: (_) => binding.future,
      );
    },
  );
  for (final result in ['denied', 'unavailable', 'error', 'bind-refused']) {
    testWidgets(
      'explicit $result stays visibly failed through passive refresh',
      (tester) async {
        await _run(
          tester,
          (c, b, r, reg) async {
            await c
                .read(backgroundOrderAlertsProvider.notifier)
                .setEnabled(true);
            expect(c.read(backgroundOrderAlertsProvider).failed, true);
            expect(c.read(backgroundOrderAlertsProvider).available, true);
            expect(c.read(backgroundOrderAlertsProvider).busy, false);
            final prepares = b.prepares;
            b.tokenChanged!();
            c.read(backgroundOrderAlertsProvider.notifier).onResume();
            await c.read(onlineOrderInboxControllerProvider.notifier).refresh();
            await tester.pump();
            expect(c.read(backgroundOrderAlertsProvider).failed, true);
            expect(b.prepares, prepares);
            expect(r.decisions, isEmpty);
          },
          nativeEnabled: false,
          bindsAllowed: result != 'bind-refused',
          prepare: (explicit) async {
            if (!explicit) return _prepared(enabled: false);
            if (result == 'error') throw StateError('synthetic bridge error');
            return {
              ..._prepared(enabled: result == 'bind-refused'),
              'available': result != 'unavailable',
            };
          },
        );
      },
    );
  }
  testWidgets('permission completion after resume continues exactly once', (
    tester,
  ) async {
    final permission = Completer<Map<String, dynamic>>();
    await _run(
      tester,
      (c, b, r, reg) async {
        final controller = c.read(backgroundOrderAlertsProvider.notifier);
        final enabling = controller.setEnabled(true);
        await tester.pump();
        controller.onPaused();
        controller.onResume();
        permission.complete(_prepared());
        await tester.pump();
        await enabling;
        expect(reg, hasLength(1));
        expect(b.permissionPrompts, 1);
        expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      },
      prepare: (explicit) async =>
          explicit ? permission.future : _prepared(enabled: false),
    );
  });
  testWidgets('completed RPC is parked across pause instead of replayed', (
    tester,
  ) async {
    final registration = Completer<Map>();
    await _run(
      tester,
      (c, b, r, reg) async {
        final controller = c.read(backgroundOrderAlertsProvider.notifier);
        final enabling = controller.setEnabled(true);
        await tester.pump();
        expect(reg, hasLength(1));
        controller.onPaused();
        registration.complete(_registered());
        await tester.pump();
        expect(b.bindings, isEmpty);
        controller.onResume();
        await tester.pump();
        await enabling;
        expect(reg, hasLength(1));
        expect(b.bindings, hasLength(1));
        expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      },
      nativeEnabled: false,
      register: (_) => registration.future,
    );
  });
  for (final stage in ['prepare', 'rpc', 'bind']) {
    for (final cancellation in [
      'off',
      'logout',
      'replacement',
      'dispose',
      'invalid-PIN',
    ]) {
      testWidgets(
        '$cancellation during $stage rejects late obsolete completion',
        (tester) async {
          final gate = Completer<void>();
          await _run(
            tester,
            (c, b, r, reg) async {
              final controller = c.read(backgroundOrderAlertsProvider.notifier);
              final enabling = controller.setEnabled(true);
              await tester.pump();
              if (cancellation == 'off') {
                await controller.setEnabled(false);
              } else if (cancellation == 'logout' ||
                  cancellation == 'replacement') {
                c.read(_identity.notifier).state = cancellation == 'logout'
                    ? null
                    : 'replacement-PIN';
                await tester.pump(Duration.zero);
              } else if (cancellation == 'invalid-PIN') {
                r.onFetch = (_, __) async => throw const OnlineInboxException(
                  OnlineInboxFailure.invalidSession,
                );
                await c
                    .read(onlineOrderInboxControllerProvider.notifier)
                    .refresh();
                await tester.pump();
              } else {
                c.dispose();
              }
              await enabling;
              gate.complete();
              await tester.pump();
              expect(
                b.enabled,
                false,
                reason: 'late native completion must be revoked',
              );
              if (stage == 'prepare') expect(reg, isEmpty);
              if (stage != 'bind') expect(b.bindings, isEmpty);
              if (cancellation == 'off' || cancellation == 'invalid-PIN') {
                expect(c.read(backgroundOrderAlertsProvider).enabled, false);
                expect(c.read(backgroundOrderAlertsProvider).busy, false);
              }
              expect(r.decisions, isEmpty);
            },
            nativeEnabled: false,
            prepare: (explicit) async {
              if (!explicit) return _prepared(enabled: false);
              if (stage == 'prepare') await gate.future;
              return _prepared();
            },
            register: (_) async {
              if (stage == 'rpc') await gate.future;
              return _registered();
            },
            bind: (_) async {
              if (stage == 'bind') await gate.future;
              return true;
            },
          );
        },
      );
    }
  }
  for (final stage in ['prepare', 'rpc', 'bind']) {
    testWidgets('OFF then new intent waits for old $stage cleanup', (
      tester,
    ) async {
      final gate = Completer<void>();
      var held = false;
      await _run(
        tester,
        (c, b, r, reg) async {
          final controller = c.read(backgroundOrderAlertsProvider.notifier);
          final old = controller.setEnabled(true);
          await tester.pump();
          final before = b.prepares;
          await controller.setEnabled(false);
          await old;
          final current = controller.setEnabled(true);
          await tester.pump();
          expect(c.read(backgroundOrderAlertsProvider).busy, true);
          expect(b.prepares, before);
          gate.complete();
          await tester.pump();
          await current;
          expect(c.read(backgroundOrderAlertsProvider).enabled, true);
          expect(c.read(backgroundOrderAlertsProvider).failed, false);
          expect(b.permissionPrompts, 2);
          expect(b.bindings.length, stage == 'bind' ? 2 : 1);
          expect(r.decisions, isEmpty);
        },
        nativeEnabled: false,
        prepare: (explicit) async {
          if (!explicit) return _prepared(enabled: false);
          if (stage == 'prepare' && !held) {
            held = true;
            await gate.future;
          }
          return _prepared();
        },
        register: (_) async {
          if (stage == 'rpc' && !held) {
            held = true;
            await gate.future;
          }
          return _registered();
        },
        bind: (_) async {
          if (stage == 'bind' && !held) {
            held = true;
            await gate.future;
          }
          return true;
        },
      );
    });
  }
  testWidgets(
    'confirmed intent expires without releasing unfinished native work',
    (tester) async {
      final permission = Completer<Map<String, dynamic>>();
      await _run(
        tester,
        (c, b, r, reg) async {
          final controller = c.read(backgroundOrderAlertsProvider.notifier);
          final enabling = controller.setEnabled(true);
          await tester.pump();
          await tester.pump(const Duration(minutes: 2));
          await enabling;
          expect(c.read(backgroundOrderAlertsProvider).failed, true);
          expect(c.read(backgroundOrderAlertsProvider).busy, false);
          permission.complete(_prepared());
          await tester.pump();
          expect(reg, isEmpty);
          expect(b.bindings, isEmpty);
          expect(b.enabled, false);
        },
        prepare: (explicit) async =>
            explicit ? permission.future : _prepared(enabled: false),
      );
    },
  );
  testWidgets('ordinary pause preserves valid native background delegation', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      final suspends = b.suspends;
      final disables = b.disables;
      final controller = c.read(backgroundOrderAlertsProvider.notifier);
      controller.onPaused();
      await tester.pump();
      expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      expect(b.suspends, suspends);
      expect(b.disables, disables);
      controller.onResume();
      await tester.pump();
      expect(reg, hasLength(1));
      controller.onPaused(); // paused disposal also retains the bounded binding
    });
  });
  testWidgets(
    'offline during passive renewal retains opt-in for later online renewal',
    (tester) async {
      final renewal = Completer<Map<String, dynamic>>();
      var passiveCalls = 0;
      await _run(
        tester,
        (c, b, r, reg) async {
          b.tokenChanged!();
          await tester.pump();
          c.read(posOfflineModeProvider.notifier).recordSetupRequired();
          await tester.pump();
          renewal.complete(_prepared());
          await tester.pump();
          expect(b.disables, 0);
          expect(b.retainedOptIns, everyElement(true));
          c.read(posOfflineModeProvider.notifier).recordOnlineFetch();
          b.tokenChanged!();
          await tester.pump();
          expect(c.read(backgroundOrderAlertsProvider).enabled, true);
          expect(reg, hasLength(2));
        },
        prepare: (_) async =>
            ++passiveCalls == 2 ? renewal.future : _prepared(),
      );
    },
  );
  for (final malformed in [
    'refusal',
    'missing-id',
    'bad-id',
    'missing-generation',
    'bad-generation',
    'expired',
    'missing-expiry',
    'non-map',
  ]) {
    testWidgets('actual registration adapter rejects HTTP-success $malformed', (
      tester,
    ) async {
      final transport = _Transport(
        () async => switch (malformed) {
          'refusal' => {'ok': false, 'error': 'disabled'},
          'missing-id' => {..._registered(), 'registration_id': null},
          'bad-id' => {..._registered(), 'registration_id': 'not-an-id'},
          'missing-generation' => {..._registered(), 'generation': null},
          'bad-generation' => {..._registered(), 'generation': 1},
          'expired' => {
            ..._registered(),
            'authority_expires_at': DateTime.utc(2000).toIso8601String(),
          },
          'missing-expiry' => {..._registered(), 'authority_expires_at': null},
          _ => 'not-a-map',
        },
      );
      final store = InMemoryDeviceSessionSecretStore();
      await store.write(
        const DeviceSessionCredential(
          deviceId: deviceId,
          sessionToken: 'synthetic-device-token',
        ),
      );
      await _run(
        tester,
        (c, b, r, reg) async {
          await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(true);
          expect(transport.calls, ['pos_register_order_alert']);
          expect(c.read(backgroundOrderAlertsProvider).failed, true);
          expect(c.read(backgroundOrderAlertsProvider).enabled, false);
          expect(b.bindings, isEmpty);
          expect(r.decisions, isEmpty);
        },
        nativeEnabled: false,
        transport: transport,
        store: store,
      );
    });
  }
  testWidgets('actual adapter binds only valid authenticated registration', (
    tester,
  ) async {
    final transport = _Transport(() async => _registered());
    final store = InMemoryDeviceSessionSecretStore();
    await store.write(
      const DeviceSessionCredential(
        deviceId: deviceId,
        sessionToken: 'synthetic-device-token',
      ),
    );
    await _run(
      tester,
      (c, b, r, reg) async {
        await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(true);
        expect(transport.calls, ['pos_register_order_alert']);
        expect(b.bindings, hasLength(1));
        expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      },
      nativeEnabled: false,
      transport: transport,
      store: store,
    );
  });
  for (final credential in [
    null,
    const DeviceSessionCredential(
      deviceId: 'other-device',
      sessionToken: 'synthetic-device-token',
    ),
    const DeviceSessionCredential(deviceId: deviceId, sessionToken: ''),
  ]) {
    testWidgets(
      'actual adapter refuses absent or mismatched pairing ${credential?.deviceId}',
      (tester) async {
        final transport = _Transport(() async => _registered());
        final store = InMemoryDeviceSessionSecretStore();
        if (credential != null) await store.write(credential);
        await _run(
          tester,
          (c, b, r, reg) async {
            await c
                .read(backgroundOrderAlertsProvider.notifier)
                .setEnabled(true);
            expect(transport.calls, isEmpty);
            expect(c.read(backgroundOrderAlertsProvider).failed, true);
            expect(b.bindings, isEmpty);
          },
          nativeEnabled: false,
          transport: transport,
          store: store,
        );
      },
    );
  }
  for (final cancelled in [true, false]) {
    testWidgets(
      'actual adapter credential wait respects ${cancelled ? 'OFF' : 'pause/resume'} before HTTP',
      (tester) async {
        final transport = _Transport(() async => _registered());
        final store = _GatedStore();
        await _run(
          tester,
          (c, b, r, reg) async {
            final controller = c.read(backgroundOrderAlertsProvider.notifier);
            final enabling = controller.setEnabled(true);
            await tester.pump();
            if (cancelled) {
              await controller.setEnabled(false);
            } else {
              controller.onPaused();
            }
            store.gate.complete(
              const DeviceSessionCredential(
                deviceId: deviceId,
                sessionToken: 'synthetic-device-token',
              ),
            );
            await tester.pump();
            expect(transport.calls, isEmpty);
            if (!cancelled) {
              controller.onResume();
              await tester.pump();
            }
            await enabling;
            expect(transport.calls.length, cancelled ? 0 : 1);
            expect(
              b.bindings.length,
              cancelled ? 0 : 1,
              reason:
                  'failed=${c.read(backgroundOrderAlertsProvider).failed}; suspends=${b.suspends}',
            );
            expect(c.read(backgroundOrderAlertsProvider).enabled, !cancelled);
          },
          nativeEnabled: false,
          transport: transport,
          store: store,
        );
      },
    );
  }
  testWidgets('cleanup error is sanitized and quarantines newer native work', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      b.cleanupThrows = true;
      final controller = c.read(backgroundOrderAlertsProvider.notifier);
      await controller.setEnabled(false);
      expect(c.read(backgroundOrderAlertsProvider).failed, true);
      final before = b.prepares;
      await controller.setEnabled(true);
      expect(b.prepares, before);
      b.cleanupThrows = false;
      await controller.setEnabled(
        false,
      ); // explicit successful cleanup recovers
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets(
    'real disposed MethodChannel bridge revokes late permission before replacement',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('restoflow.pos/background_order_alert');
      final gate = Completer<Map<String, dynamic>>();
      var prepares = 0;
      var disables = 0;
      var nativeOptIn = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'prepare') {
          prepares++;
          if (prepares == 1) {
            final result = await gate.future;
            nativeOptIn = true; // late Android permission grants after disposal
            return result;
          }
          return _prepared(enabled: false);
        }
        if (call.method == 'disable' || call.method == 'suspend') {
          disables++;
          nativeOptIn = false;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      ProviderContainer make() => ProviderContainer(
        overrides: [
          backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(true),
          onlineOrderInboxIdentityProvider.overrideWithValue(
            'synthetic-identity',
          ),
          onlineOrderInboxRepositoryProvider.overrideWithValue(
            FakeInboxRepository(),
          ),
          onlineOrderInboxPollIntervalProvider.overrideWithValue(null),
          onlineOrderInboxAlertIntervalProvider.overrideWithValue(null),
        ],
      );
      final old = make();
      old.listen(backgroundOrderAlertsProvider, (_, __) {});
      await tester.pump();
      old.dispose();
      await tester.pump();
      final replacement = make();
      replacement.listen(backgroundOrderAlertsProvider, (_, __) {});
      await tester.pump();
      expect(prepares, 1);
      gate.complete(_prepared());
      await tester.pump();
      expect(prepares, 2);
      expect(disables, greaterThanOrEqualTo(2));
      expect(nativeOptIn, false);
      expect(replacement.read(backgroundOrderAlertsProvider).enabled, false);
      replacement.dispose();
      await tester.pump(Duration.zero);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('confirmed Enable survives unfinished automatic preparation', (
    tester,
  ) async {
    final automatic = Completer<Map<String, dynamic>>();
    await _run(
      tester,
      (c, b, r, reg) async {
        final enabling = c
            .read(backgroundOrderAlertsProvider.notifier)
            .setEnabled(true);
        await tester.pump();
        expect(c.read(backgroundOrderAlertsProvider).busy, true);
        expect(b.prepares, 1);
        automatic.complete(_prepared(enabled: false));
        await tester.pump();
        await enabling;
        expect(b.permissionPrompts, 1);
        expect(reg, hasLength(1));
        expect(c.read(backgroundOrderAlertsProvider).enabled, true);
        expect(c.read(backgroundOrderAlertsProvider).busy, false);
        expect(r.decisions, isEmpty);
      },
      prepare: (permission) async =>
          permission ? _prepared() : automatic.future,
    );
  });
  testWidgets(
    'permission completion while paused continues on resume without replay',
    (tester) async {
      final permission = Completer<Map<String, dynamic>>();
      await _run(
        tester,
        (c, b, r, reg) async {
          final controller = c.read(backgroundOrderAlertsProvider.notifier);
          final enabling = controller.setEnabled(true);
          await tester.pump();
          controller.onPaused();
          permission.complete(_prepared());
          await tester.pump();
          expect(reg, isEmpty);
          controller.onResume();
          await tester.pump();
          await enabling;
          expect(c.read(backgroundOrderAlertsProvider).busy, false);
          expect(c.read(backgroundOrderAlertsProvider).enabled, true);
          expect(b.permissionPrompts, 1);
          expect(reg, hasLength(1));
          expect(r.decisions, isEmpty);
        },
        prepare: (explicit) async =>
            explicit ? permission.future : _prepared(enabled: false),
      );
    },
  );
  testWidgets('explicit native refusal is visible OFF and recoverable', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(true);
      expect(c.read(backgroundOrderAlertsProvider).failed, true);
      expect(c.read(backgroundOrderAlertsProvider).available, true);
      expect(c.read(backgroundOrderAlertsProvider).enabled, false);
      expect(c.read(backgroundOrderAlertsProvider).busy, false);
      expect(reg, isEmpty);
      expect(r.decisions, isEmpty);
    }, prepare: (_) async => _prepared(enabled: false));
  });
  test(
    'real local logout and unpair writers revoke only notification delegation',
    () async {
      final bridge = _Bridge();
      final c = ProviderContainer(
        overrides: [
          backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
        ],
      );
      c.read(backgroundOrderAlertBridgeProvider);
      c.read(posSessionControllerProvider.notifier).endSession();
      expect(bridge.disables, 1);
      c
          .read(posDeviceContextProvider.notifier)
          .set(
            const DeviceContext(
              organizationId: 'org',
              restaurantId: 'restaurant',
              branchId: 'branch',
              deviceId: deviceId,
              deviceType: 'pos',
              deviceSessionId: 'session',
            ),
          );
      expect(bridge.disables, 1);
      c.read(posDeviceContextProvider.notifier).set(null);
      expect(bridge.disables, 2);
      c.dispose();
    },
  );
  testWidgets('default OFF adds no native work or registration', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      expect(c.read(backgroundOrderAlertsProvider).available, false);
      expect(b.prepares, 0);
      expect(reg, isEmpty);
      await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(true);
      await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(false);
      expect(c.read(backgroundOrderAlertsProvider).available, false);
      expect(b.prepares, 0);
    }, enabledBuild: false);
  });
  testWidgets('opt-in registration delegates no pairing PIN or customer data', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      expect(reg.single.keys.toSet(), {
        'p_installation_id',
        'p_fcm_token',
        'p_status_secret',
      });
      expect(b.permissionPrompts, 0);
      expect(b.bindings.single.keys.toSet(), {
        'identity',
        'generation',
        'registration_id',
        'registration_generation',
        'endpoint',
        'authority_expires_at',
      });
      expect(b.snapshots, isNotEmpty);
      expect(b.snapshots.last.keys.toSet(), {
        'identity',
        'server_time',
        'requests',
      });
      for (final row in b.snapshots.last['requests'] as List) {
        expect((row as Map).keys.toSet(), {'request_id', 'expires_at'});
      }
      expect(r.decisions, isEmpty);
    });
  });
  testWidgets(
    'explicit enable requests permission; disabled install never registers automatically',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        expect(reg, isEmpty);
        await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(true);
        expect(b.permissionPrompts, 1);
        expect(reg, hasLength(1));
        expect(c.read(backgroundOrderAlertsProvider).enabled, true);
      }, nativeEnabled: false);
    },
  );
  testWidgets(
    'missing Firebase/config and refused native binding fail silent',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        expect(reg, isEmpty);
        expect(c.read(backgroundOrderAlertsProvider).enabled, false);
        await c.read(onlineOrderInboxControllerProvider.notifier).refresh();
        expect(r.fetches, isNotEmpty);
        expect(r.decisions, isEmpty);
      }, nativeAvailable: false);
      await _run(tester, (c, b, r, reg) async {
        expect(c.read(backgroundOrderAlertsProvider).failed, true);
        expect(c.read(backgroundOrderAlertsProvider).enabled, false);
        expect(b.suspends, greaterThan(0));
      }, bindsAllowed: false);
    },
  );
  testWidgets('permission denied does not suppress existing Inbox discovery', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      await c.read(onlineOrderInboxControllerProvider.notifier).refresh();
      expect(r.fetches, isNotEmpty);
      expect(reg, isEmpty);
      expect(r.decisions, isEmpty);
    }, nativeEnabled: false);
  });
  testWidgets(
    'token rotation reuses real registration; push hint uses existing refresh only',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        b.tokenChanged!();
        await tester.pump();
        expect(reg, hasLength(2));
        expect(b.permissionPrompts, 0);
        final before = r.fetches.length;
        b.pendingHint!();
        await tester.pump();
        expect(r.fetches.length, before + 1);
        expect(r.decisions, isEmpty);
        expect(reg, hasLength(2));
      });
    },
  );
  testWidgets(
    'pause defers token rotation until authenticated resume without adding polling',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        final controller = c.read(backgroundOrderAlertsProvider.notifier);
        controller.onPaused();
        final fetches = r.fetches.length;
        b.pendingHint!();
        b.tokenChanged!();
        await tester.pump();
        expect(r.fetches.length, fetches);
        expect(reg, hasLength(1));
        controller.onResume();
        await tester.pump();
        expect(reg, hasLength(2));
        b.pendingHint!();
        await tester.pump();
        expect(r.fetches.length, fetches + 1);
      });
    },
  );
  testWidgets('offline clears native authority without touching orders', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      c.read(posOfflineModeProvider.notifier).recordSetupRequired();
      await tester.pump();
      expect(b.suspends, greaterThan(0));
      expect(r.decisions, isEmpty);
    });
  });
  testWidgets(
    'logout clears native authority and blocks notification tap until PIN auth',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        c.read(_identity.notifier).state = null;
        await tester.pump(Duration.zero);
        expect(b.disables, greaterThan(0));
        expect(
          await c
              .read(backgroundOrderAlertsProvider.notifier)
              .consumeInboxTap(),
          false,
        );
        expect(b.taps, 0);
        expect(r.decisions, isEmpty);
      });
    },
  );
  testWidgets('late registration after identity loss cannot bind', (
    tester,
  ) async {
    final pending = Completer<Map>();
    await _run(tester, (c, b, r, reg) async {
      c.read(_identity.notifier).state = null;
      await tester.pump(Duration.zero);
      pending.complete({
        'ok': true,
        'registration_id': '22222222-2222-4222-8222-222222222222',
        'generation': '33333333-3333-4333-8333-333333333333',
        'authority_expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      });
      await tester.pump();
      expect(b.bindings, isEmpty);
      expect(b.disables, greaterThan(0));
    }, register: (_) => pending.future);
  });
  testWidgets('registration errors do not alter Inbox/pending decisions', (
    tester,
  ) async {
    await _run(tester, (c, b, r, reg) async {
      expect(c.read(backgroundOrderAlertsProvider).failed, true);
      await c.read(onlineOrderInboxControllerProvider.notifier).refresh();
      expect(r.fetches, isNotEmpty);
      expect(r.decisions, isEmpty);
    }, register: (_) async => throw StateError('synthetic_failure'));
  });
  testWidgets(
    'off cancels immediately and token hints cannot silently reenable',
    (tester) async {
      await _run(tester, (c, b, r, reg) async {
        await c.read(backgroundOrderAlertsProvider.notifier).setEnabled(false);
        b.tokenChanged!();
        await tester.pump();
        expect(reg, hasLength(1));
        expect(c.read(backgroundOrderAlertsProvider).enabled, false);
      });
    },
  );
}

Map<String, dynamic> _prepared({bool enabled = true}) => {
  'available': true,
  'enabled': enabled,
  'installation_id': '11111111-1111-4111-8111-111111111111',
  'fcm_token': 'synthetic-token',
  'status_secret': '0' * 64,
  'generation': 1,
};
