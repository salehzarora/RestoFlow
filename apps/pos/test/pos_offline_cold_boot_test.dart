// [POS-OFFLINE-OPERATIONS-002] Pass A — THE missing proof: a REAL Android-style
// cold start with the network fully down reaches the offline cached menu.
//
// Reproduced as close to main.dart's real root as testable: the REAL
// buildPosBootRoot -> DeviceBootGate -> PosBootCoordinator composition (only
// the anonymous sign-in and the timer knobs are injected), the REAL secure
// storage channel (mocked at the MethodChannel), the REAL operational
// snapshot store over mocked prefs, the REAL pairing gate / PIN gate / menu
// provider chain.
//
// Pins:
//  (a) with durable pairing evidence, the app tree mounts (NOT OfflineBootView);
//  (b) the PIN gate's offline restore engages and PosMenuScreen renders the
//      cached menu + the offline banner;
//  (c) kitchen readiness ends in a bounded state (never a stuck spinner);
//  (d) ZERO network IO from the degraded tree (the hold transport counts
//      refused calls; the real wire sees nothing);
//  (e) with NO cached pairing scope, OfflineBootView still shows (existing
//      behaviour pinned) — same for a scope naming another device;
//  (f) when the boot retry succeeds, the transport upgrades IN PLACE: the
//      SAME tree stays mounted (state/element identity survives) and calls
//      now reach the real transport.
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart'
    show DemoCategory, DemoMenuItem;
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/pos_pin_gate.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart'
    show PosMenuData, kPosCategoryPalette;
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posSyncSessionProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

const _pinSessionKey =
    'restoflow.pos.pin_session.v1.org-1.rest-1.branch-1.dev-1';

const _cachedContext = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
  displayName: 'Till 1',
);

/// The real transport the coordinator receives once "the network returns".
/// Nothing may reach it while the boot is degraded (assert (d)).
final class _ScriptedRealTransport implements SyncRpcTransport {
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (function == 'restore_device_session') {
      // The SAME pairing scope the cached context carries — the gate's
      // post-upgrade re-verify must keep the live tree untouched.
      return <String, dynamic>{
        'ok': true,
        'device_session_id': 'ds-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': 'branch-1',
        'device_id': 'dev-1',
        'device_type': 'pos',
      };
    }
    if (function == 'list_device_staff') {
      return <String, dynamic>{
        'ok': true,
        'staff': <dynamic>[
          <String, dynamic>{
            'employee_profile_id': 'emp-1',
            'display_name': 'Amira K.',
            'role': 'cashier',
          },
        ],
      };
    }
    return <String, dynamic>{'ok': false};
  }
}

final class _NullLogoReader implements DeviceReceiptLogoReader {
  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async => null;
}

/// A minimal-but-complete operational snapshot (the same shape the snapshot
/// suite pins), with DYNAMIC times so the 8h session window and the 2h
/// kitchen trust window never rot on a calendar boundary.
PosOperationalSnapshot _snapshot(DateTime now) {
  final (icon0, color0) = kPosCategoryPalette[0];
  final fetchedAt = now.subtract(const Duration(minutes: 30));
  return PosOperationalSnapshot(
    organizationId: _scope.organizationId,
    restaurantId: _scope.restaurantId,
    branchId: _scope.branchId,
    deviceId: _scope.deviceId,
    menu: PosMenuData(
      currencyCode: 'ILS',
      categories: <DemoCategory>[
        DemoCategory(
          id: 'cat-burgers',
          name: 'Burgers',
          icon: icon0,
          color: color0,
        ),
      ],
      items: const <DemoMenuItem>[
        DemoMenuItem(
          id: 'item-burger',
          name: 'Burger',
          priceMinor: 4200,
          categoryId: 'cat-burgers',
          categoryName: 'Burgers',
          categoryDisplayOrder: 1,
          itemDisplayOrder: 1,
        ),
        DemoMenuItem(
          id: 'item-cola',
          name: 'Cola',
          priceMinor: 900,
          categoryId: 'cat-burgers',
          categoryName: 'Burgers',
          categoryDisplayOrder: 1,
          itemDisplayOrder: 2,
        ),
      ],
    ),
    fetchedAt: fetchedAt,
    restaurantName: 'Shawarma HaCarmel',
    branchName: 'Downtown',
    stationName: 'Till 1',
    employeeProfileId: 'emp-1',
    employeeDisplayName: 'Amira K.',
    capabilities: const <String, Object?>{'role': 'cashier'},
    kitchenMode: PosSnapshotKitchenMode(
      mode: 'printer_only',
      revision: 4,
      verifiedAt: fetchedAt,
    ),
  );
}

Map<String, Object?> _pinSessionRecord(DateTime now) => <String, Object?>{
  'v': 1,
  'session_id': 'pin-stored',
  'employee_profile_id': 'emp-1',
  'display_name': 'Amira K.',
  'organization_id': 'org-1',
  'restaurant_id': 'rest-1',
  'branch_id': 'branch-1',
  'device_id': 'dev-1',
  'device_session_id': 'ds-1',
  'last_online_verify': now
      .subtract(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secure;

  setUp(() {
    secure = <String, String>{};
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, Object?>();
          final key = args?['key'] as String?;
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              secure[key!] = args!['value']! as String;
              return null;
            case 'delete':
              secure.remove(key);
              return null;
            case 'containsKey':
              return secure.containsKey(key);
            case 'readAll':
              return Map<String, String>.of(secure);
            case 'deleteAll':
              secure.clear();
              return null;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Seeds the full durable evidence of a till that completed a real online
  /// bootstrap before losing the network: device secret + cached pairing
  /// scope (secure), the bounded PIN-session record (secure, inside its 8h
  /// window), and the scoped operational snapshot (prefs).
  Future<void> seedDurableState(DateTime now) async {
    secure['restoflow.device_id'] = 'dev-1';
    secure['restoflow.device_session_token'] = 'tok-1';
    secure['restoflow.device_context_cache'] = encodeCachedDeviceContext(
      _cachedContext,
    );
    secure[_pinSessionKey] = jsonEncode(_pinSessionRecord(now));
    await SharedPrefsOperationalSnapshotStore().save(_scope, _snapshot(now));
  }

  void sizeTablet(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ({
    PosBootCoordinator coordinator,
    _ScriptedRealTransport realTransport,
    void Function() goOnline,
    int Function() signInAttempts,
  })
  buildCoordinator(SharedPreferences prefs) {
    var online = false;
    var attempts = 0;
    final realTransport = _ScriptedRealTransport();
    final coordinator = PosBootCoordinator(
      prefs: prefs,
      demoMode: false,
      createSession: () async {
        attempts++;
        if (!online) throw const SocketException('venue Wi-Fi down');
        return (
          transport: realTransport,
          imageUrlResolver: FakeDeviceImageUrlResolver(),
          receiptLogoReader: _NullLogoReader(),
        );
      },
    );
    return (
      coordinator: coordinator,
      realTransport: realTransport,
      goOnline: () => online = true,
      signInAttempts: () => attempts,
    );
  }

  Widget root(
    SharedPreferences prefs,
    PosBootCoordinator coordinator, {
    Duration? autoRetryInterval,
  }) => buildPosBootRoot(
    prefs: prefs,
    locale: const Locale('en'),
    coordinator: coordinator,
    autoRetryInterval: autoRetryInterval,
    demoModeOverride: false,
    includePeriodicWork: false,
    extraOverrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posKitchenModeVerificationTimeoutProvider.overrideWithValue(
        const Duration(milliseconds: 300),
      ),
    ],
  );

  Future<void> pumpThrough(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets(
    'cold boot with the network fully down reaches the cached menu behind the '
    'restored offline session — then upgrades IN PLACE when the retry '
    'succeeds (a/b/c/d/f)',
    (tester) async {
      sizeTablet(tester);
      final now = DateTime.now().toUtc();
      await seedDurableState(now);
      final prefs = await SharedPreferences.getInstance();
      final boot = buildCoordinator(prefs);

      await tester.pumpWidget(
        root(
          prefs,
          boot.coordinator,
          autoRetryInterval: const Duration(milliseconds: 400),
        ),
      );
      await pumpThrough(tester);

      // (a) The app tree mounts — never the blocking offline screen.
      expect(find.byType(OfflineBootView), findsNothing);
      expect(find.byType(PosMenuScreen), findsOneWidget);
      expect(find.byType(PinLoginScreen), findsNothing);

      // (b) The PIN gate's offline restore engaged: the restored session is
      // live and the cached menu renders with the offline banner.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PosMenuScreen)),
      );
      final session = container.read(posSyncSessionProvider);
      expect(session, isNotNull);
      expect(session!.pinSessionId, 'pin-stored');
      expect(session.deviceId, 'dev-1');
      expect(find.text('Burger'), findsWidgets);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);

      // (c) Kitchen readiness ended in a BOUNDED state: the offline-trusted
      // resolved mode (the snapshot capture is inside its window) or the
      // explicit retryable Unavailable — never a stuck Loading spinner.
      final readiness = container.read(posKitchenModeReadinessProvider);
      expect(
        readiness is KitchenModeReadinessLoading,
        isFalse,
        reason: 'readiness must be actionable, got: $readiness',
      );

      // (d) ZERO network IO from the degraded tree: every repository call was
      // refused synchronously by the hold transport; the real wire saw
      // nothing. The ONLY network attempts are the boot gate's own retries.
      final upgradable = boot.coordinator.upgradableTransport;
      expect(upgradable, isNotNull);
      expect(upgradable!.isUpgraded, isFalse);
      expect(
        upgradable.heldCallCount,
        greaterThan(0),
        reason: 'the degraded tree exercised the hold transport',
      );
      expect(boot.realTransport.calls, isEmpty);
      expect(boot.signInAttempts(), greaterThanOrEqualTo(1));

      // ---- (f) the network returns: upgrade IN PLACE, no remount ----------
      final pinGateStateBefore = tester.state(find.byType(PosPinGate));
      final menuElementBefore = tester.element(find.byType(PosMenuScreen));
      boot.goOnline();
      // Fire the pending auto-retry (backoff ≤ 400ms × 8 = 3.2s), then let
      // the upgrade + the gate's silent server re-verification settle.
      await tester.pump(const Duration(seconds: 4));
      await pumpThrough(tester);

      expect(upgradable.isUpgraded, isTrue);
      expect(
        boot.realTransport.calls.map((c) => c.$1),
        contains('restore_device_session'),
        reason: 'the pairing gate re-verified against the server on upgrade',
      );
      // The SAME tree is still mounted: state and element identity survived,
      // the restored session is still live, and no boot/offline screen ever
      // interposed.
      expect(find.byType(PosMenuScreen), findsOneWidget);
      expect(
        identical(tester.state(find.byType(PosPinGate)), pinGateStateBefore),
        isTrue,
        reason: 'reconnection must not rebuild the subtree (cart safety)',
      );
      expect(
        identical(
          tester.element(find.byType(PosMenuScreen)),
          menuElementBefore,
        ),
        isTrue,
      );
      expect(
        container.read(posSyncSessionProvider)?.pinSessionId,
        'pin-stored',
      );
      expect(find.byType(OfflineBootView), findsNothing);

      // Tear down explicitly so the gate/watchdog timers are disposed.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    '(e) with NO cached pairing scope the blocked OfflineBootView still shows '
    '(existing behaviour pinned)',
    (tester) async {
      sizeTablet(tester);
      final now = DateTime.now().toUtc();
      await seedDurableState(now);
      // The secret survives, but the cached scope is gone (e.g. pre-Pass-A
      // install): no pairing evidence, no degraded mount.
      secure.remove('restoflow.device_context_cache');
      final prefs = await SharedPreferences.getInstance();
      final boot = buildCoordinator(prefs);

      await tester.pumpWidget(root(prefs, boot.coordinator));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBootView), findsOneWidget);
      expect(find.byType(PosMenuScreen), findsNothing);
      expect(boot.coordinator.upgradableTransport, isNull);
      expect(boot.realTransport.calls, isEmpty);
    },
  );

  testWidgets(
    '(e) a cached scope naming ANOTHER device than the stored secret is '
    'refused — OfflineBootView (fail closed)',
    (tester) async {
      sizeTablet(tester);
      final now = DateTime.now().toUtc();
      await seedDurableState(now);
      secure['restoflow.device_context_cache'] = encodeCachedDeviceContext(
        const DeviceContext(
          organizationId: 'org-1',
          branchId: 'branch-1',
          restaurantId: 'rest-1',
          deviceId: 'dev-OTHER',
          deviceType: 'pos',
          deviceSessionId: 'ds-1',
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final boot = buildCoordinator(prefs);

      await tester.pumpWidget(root(prefs, boot.coordinator));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBootView), findsOneWidget);
      expect(find.byType(PosMenuScreen), findsNothing);
      expect(boot.coordinator.upgradableTransport, isNull);
    },
  );
}
