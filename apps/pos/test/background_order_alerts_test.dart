import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool available = true;
  bool enabled = true;
  bool bindsAllowed = true;
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
    return bindsAllowed;
  }

  @override
  Future<void> pending(Map<String, dynamic> snapshot) async =>
      snapshots.add(snapshot);
  @override
  Future<void> suspend({bool retainOptIn = false}) async {
    suspends++;
  }

  @override
  Future<void> disable() async {
    disables++;
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
}) async {
  final bridge = _Bridge()
    ..enabled = nativeEnabled
    ..available = nativeAvailable
    ..bindsAllowed = bindsAllowed;
  final repo = FakeInboxRepository();
  final registrations = <Map<String, dynamic>>[];
  final container = ProviderContainer(
    overrides: [
      backgroundOrderAlertsBuildEnabledProvider.overrideWithValue(enabledBuild),
      backgroundOrderAlertBridgeProvider.overrideWithValue(bridge),
      backgroundOrderAlertEndpointProvider.overrideWithValue(
        'https://synthetic.invalid/functions/v1/pos-order-alert-status',
      ),
      backgroundOrderAlertRegisterProvider.overrideWithValue((params) async {
        registrations.add(params);
        return register?.call(params) ??
            {
              'ok': true,
              'registration_id': '22222222-2222-4222-8222-222222222222',
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
    'pause does not duplicate registration/polling; resume discovers existing pending',
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
        expect(reg, hasLength(1));
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
