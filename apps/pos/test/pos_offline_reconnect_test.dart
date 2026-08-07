// POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A — THE OFFLINE LATCH.
//
// THE DEFECT. `posOfflineModeProvider` is a root notifier whose build watches
// nothing, and its only `online` writer is the `pos_menu` success path. But
// `posMenuProvider` is a non-autoDispose FutureProvider whose offline branch
// RETURNS the cached snapshot instead of throwing, so it settles into AsyncData
// and Riverpod never retries it; its watched dependencies are identity-stable at
// runtime, and the menu screen renders the normal grid (so even the Retry
// buttons are unreachable). The ONLY remaining re-fetch trigger was the
// lifecycle's resume-time invalidation — and an Android Activity `resumed` is
// NOT emitted when the cashier toggles Wi-Fi in the foreground (there is
// deliberately no connectivity plugin in this app).
//
// Consequence: a one-minute outage latched the POS "offline" until the app was
// RESTARTED — banner stuck, payment/discount/void/shift-close refused by
// `blockPosActionWhileOffline`, and the outbox's own reconnect listener (which
// resets the retry backoff on offlineCached -> online) never firing either.
//
// THE FIX UNDER TEST is a TRIGGER, never a new writer: while the phase is
// `offlineCached` and the app is foregrounded, the lifecycle re-invalidates the
// menu provider on a bounded cadence, and THAT FETCH'S OWN OUTCOME still decides
// the phase. Nothing here consults a connectivity API.
//
// Covers the mandated regression list 1-10:
//   1     a real remote failure lands on offlineCached + the offline banner
//   2/3/4 the SAME MOUNTED app recovers with no restart and no lifecycle resume
//   5     it is the FETCH RESULT, not the timer, that flips the phase
//   6     Wi-Fi up / server down never produces a false recovery
//   7     nothing but a successful menu fetch un-gates server-backed actions
//         (a probe in flight does NOT un-gate)
//   8     recovery revalidates the PIN session without an outbox entry
//   9     a failing revalidation leaves a safe, still-blocked auth state
//  10     the recovered edge asks the kitchen readiness seam to re-verify
//
// Synthetic values only. No network, no printer, no orders, no prints.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart'
    show DemoCategory, DemoMenuItem;
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart'
    show DemoOutboxStore;
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart'
    show outboxRepositoryProvider;
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:restoflow_pos/src/widgets/pos_sync_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);
const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
const _device = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
);
const _sessionKey = 'restoflow.pos.pin_session.v1.org-1.rest-1.branch-1.dev-1';

/// The probe cadence used throughout. Long enough that the initial
/// `pumpAndSettle` can never accidentally fire a tick, short enough to drive
/// with one explicit `pump`.
const _probeInterval = Duration(seconds: 10);

/// One clean tick: past the interval, then a few frames for the fetch, the
/// deferred offline-state microtask and the snapshot read to land.
Future<void> _tick(WidgetTester tester, {int ticks = 1}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(_probeInterval + const Duration(milliseconds: 1));
    for (var j = 0; j < 4; j++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }
}

/// A transport whose `pos_menu` answer is switchable MID-TEST — the whole point
/// of this suite is that the app is never rebuilt when the network returns.
/// Every other function is offline throughout: none of them may ever be
/// load-bearing for the offline phase.
final class _ProbeTransport implements SyncRpcTransport {
  _ProbeTransport({this.serverUp = false});

  /// Whether `pos_menu` currently answers (the venue Wi-Fi AND the backend).
  bool serverUp;

  /// "Wi-Fi is connected but the server never answers" — the captive-portal /
  /// LAN-without-internet shape a connectivity flag would report as ONLINE.
  bool hangMenu = false;

  int menuCalls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'pos_menu') {
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    menuCalls++;
    if (hangMenu) return Completer<Object?>().future;
    if (!serverUp) {
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    return _menuEnvelope();
  }
}

/// A `pos_menu` transport that answers with a SESSION REFUSAL — the shape
/// regression 9 needs (the network is back but this PIN session is not valid).
final class _AuthRefusingTransport implements SyncRpcTransport {
  int menuCalls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'pos_menu') menuCalls++;
    throw const SyncTransportException(
      SyncTransportErrorKind.auth,
      code: '42501',
      message: 'pos_menu: PIN session is not valid (inactive/ended/expired)',
    );
  }
}

/// A fake readiness seam over the WEB-SAFE lifecycle surface — the exact
/// interface `posKitchenReadinessHeartbeatProvider` exposes.
final class _FakeReadinessHeartbeat implements PosKitchenReadinessLifecycle {
  int startups = 0;
  int resumes = 0;
  int pauses = 0;

  @override
  void onStartup() => startups++;

  @override
  void onResume() => resumes++;

  @override
  void onPaused() => pauses++;
}

Map<String, dynamic> _menuEnvelope() => <String, dynamic>{
  'ok': true,
  'currency_code': 'ILS',
  'categories': <dynamic>[
    <String, dynamic>{'id': 'cat-1', 'name': 'Burgers', 'display_order': 1},
  ],
  'items': <dynamic>[
    <String, dynamic>{
      'id': 'item-burger',
      'name': 'Burger',
      'base_price_minor': 4200,
      'menu_category_id': 'cat-1',
      'display_order': 1,
    },
  ],
  'modifiers': <dynamic>[],
  'modifier_options': <dynamic>[],
};

PosMenuData _cachedMenu() {
  final (icon, color) = kPosCategoryPalette[0];
  return PosMenuData(
    currencyCode: 'ILS',
    categories: <DemoCategory>[
      DemoCategory(id: 'cat-1', name: 'Burgers', icon: icon, color: color),
    ],
    items: const <DemoMenuItem>[
      DemoMenuItem(
        id: 'item-burger',
        name: 'Burger',
        priceMinor: 4200,
        categoryId: 'cat-1',
        categoryName: 'Burgers',
        categoryDisplayOrder: 1,
        itemDisplayOrder: 1,
      ),
    ],
    modifierGroups: const <PosModifierGroup>[],
  );
}

PosOperationalSnapshot _snapshot({DateTime? fetchedAt}) =>
    PosOperationalSnapshot(
      organizationId: _scope.organizationId,
      restaurantId: _scope.restaurantId,
      branchId: _scope.branchId,
      deviceId: _scope.deviceId,
      menu: _cachedMenu(),
      fetchedAt: fetchedAt ?? DateTime.utc(2026, 8, 6, 9),
    );

Map<String, Object?> _storedSessionRecord({required DateTime lastVerify}) =>
    <String, Object?>{
      'v': 1,
      'session_id': 'pin-stored',
      'employee_profile_id': 'emp-1',
      'display_name': 'Amira K.',
      'organization_id': 'org-1',
      'restaurant_id': 'rest-1',
      'branch_id': 'branch-1',
      'device_id': 'dev-1',
      'device_session_id': 'ds-1',
      'last_online_verify': lastVerify.toUtc().toIso8601String(),
    };

/// A few event-loop turns for the container-level (non-widget) tests.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secure;
  late List<MethodCall> secureCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    secure = <String, String>{};
    secureCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
          secureCalls.add(call);
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
    // Every scenario below starts from a till that HAS completed its one-time
    // online bootstrap: the durable snapshot exists, so a failing fetch serves
    // the cached menu (offlineCached) rather than the setup-required state.
    await SharedPrefsOperationalSnapshotStore().save(_scope, _snapshot());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  int sessionWrites() => secureCalls
      .where(
        (c) =>
            c.method == 'write' &&
            ((c.arguments as Map)['key'] as String).startsWith(
              'restoflow.pos.pin_session.',
            ),
      )
      .length;

  /// The REAL composition under test: the real lifecycle widget (which owns the
  /// probe) over the real menu screen (which owns the banner), in real mode,
  /// with the probe cadence made testable. The kitchen seams are faked/nulled
  /// so the native spool composition never enters these tests.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required SyncRpcTransport transport,
    Locale locale = const Locale('en'),
    PosKitchenReadinessLifecycle? heartbeat,
    Duration? probeInterval = _probeInterval,
    List<Override> extra = const [],
    bool overrideSession = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          if (overrideSession)
            posSyncSessionProvider.overrideWithValue(_session),
          posSyncScopeProvider.overrideWithValue(_scope),
          outboxRepositoryProvider.overrideWithValue(
            DemoOutboxStore(delay: (_) async {}),
          ),
          posKitchenSpoolRuntimeProvider.overrideWithValue(null),
          posKitchenReadinessHeartbeatProvider.overrideWithValue(heartbeat),
          posOfflineReconnectProbeIntervalProvider.overrideWithValue(
            probeInterval,
          ),
          ...extra,
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const PosSyncLifecycle(child: PosMenuScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(PosSyncLifecycle)),
    );
  }

  /// Unmount so the probe timer is cancelled before the test ends — a pending
  /// periodic Timer is a flutter_test failure, which is exactly the assertion
  /// we want on the dispose path.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  PosOfflinePhase phaseOf(ProviderContainer c) =>
      c.read(posOfflineModeProvider).phase;

  // -------------------------------------------------------------------------
  group('1. the outage is entered honestly', () {
    // -----------------------------------------------------------------------
    testWidgets('a real remote failure lands on offlineCached with the '
        'offline banner over the cached grid', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);

      expect(transport.menuCalls, greaterThanOrEqualTo(1));
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      expect(c.read(posOfflineModeProvider).menuFromCache, isTrue);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);
      expect(find.text('Burger'), findsWidgets);
      expect(find.text(l10n.posMenuLoadError), findsNothing);

      await unmount(tester);
    });
  });

  // -------------------------------------------------------------------------
  group('2/3/4. the SAME MOUNTED app recovers — no restart, no resume', () {
    // -----------------------------------------------------------------------
    testWidgets('the transport starts answering and the probe alone restores '
        'the online phase and removes the banner', (tester) async {
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);

      // The identity of the live widget State — proof that recovery below is
      // NOT a remount/restart. Nothing in this test dispatches an
      // AppLifecycleState: `handleAppLifecycleStateChanged` is never called.
      final lifecycleState = tester.state(find.byType(PosSyncLifecycle));
      final callsBefore = transport.menuCalls;

      // The cashier walks back into Wi-Fi range. No user action, no lifecycle
      // event, no rebuild — only the world outside the app changed.
      transport.serverUp = true;
      await _tick(tester);

      expect(
        transport.menuCalls,
        greaterThan(callsBefore),
        reason: 'the probe must have re-attempted the real fetch',
      );
      expect(
        phaseOf(c),
        PosOfflinePhase.online,
        reason:
            'the latch is broken: a mounted app recovers on its own, without '
            'an app restart and without an AppLifecycleState.resumed',
      );
      expect(find.byKey(const Key('pos-offline-banner')), findsNothing);
      expect(
        identical(tester.state(find.byType(PosSyncLifecycle)), lifecycleState),
        isTrue,
        reason: 'the very same mounted State recovered — nothing restarted',
      );
      // The phase left offlineCached, so the probe cancelled itself: this test
      // can end without unmounting and flutter_test still sees no pending
      // timer.
    });

    testWidgets('the recovered phase un-gates the server-backed actions that '
        'were refused during the outage', (tester) async {
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);
      final context = tester.element(find.byType(PosMenuScreen));
      expect(blockPosActionWhileOffline(context), isTrue);
      await tester.pump();

      transport.serverUp = true;
      await _tick(tester);

      expect(phaseOf(c), PosOfflinePhase.online);
      expect(
        blockPosActionWhileOffline(tester.element(find.byType(PosMenuScreen))),
        isFalse,
        reason: 'payment/discount/void/shift-close are available again',
      );
    });
  });

  // -------------------------------------------------------------------------
  group(
    '5/6. the FETCH decides — never the timer, never a connectivity flag',
    () {
      // -----------------------------------------------------------------------
      testWidgets('repeated probes against a dead server keep the phase '
          'offlineCached (the timer is a trigger, not a writer)', (
        tester,
      ) async {
        final transport = _ProbeTransport();
        final c = await pump(tester, transport: transport);
        final callsBefore = transport.menuCalls;

        await _tick(tester, ticks: 4);

        expect(
          transport.menuCalls,
          greaterThan(callsBefore),
          reason: 'the probe really did run repeatedly',
        );
        expect(
          phaseOf(c),
          PosOfflinePhase.offlineCached,
          reason: 'only a SUCCESSFUL fetch may write the online phase',
        );
        expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);

        // ...and the very next successful fetch flips it, proving the phase was
        // waiting on the RESULT, not on the number of attempts.
        transport.serverUp = true;
        await _tick(tester);
        expect(phaseOf(c), PosOfflinePhase.online);
      });

      testWidgets('Wi-Fi connected but the server never answers: no false '
          'recovery, and probes never stack', (tester) async {
        final transport = _ProbeTransport();
        final c = await pump(tester, transport: transport);
        expect(phaseOf(c), PosOfflinePhase.offlineCached);

        // NOW the "connected but unreachable" shape: the RPC is accepted by a
        // perfectly healthy-looking network and simply never answers.
        transport.hangMenu = true;
        final callsBefore = transport.menuCalls;
        await _tick(tester, ticks: 5);

        expect(
          transport.menuCalls,
          callsBefore + 1,
          reason:
              'the in-flight check must stop probes stacking one hung RPC per '
              'interval',
        );
        expect(
          phaseOf(c),
          PosOfflinePhase.offlineCached,
          reason: 'a reachable network that never answers is still offline',
        );

        await unmount(tester);
      });
    },
  );

  // -------------------------------------------------------------------------
  group('7. a probe in flight never un-gates a server-backed action', () {
    // -----------------------------------------------------------------------
    testWidgets('probing is presentational: the phase, and therefore every '
        'gate, is untouched while the attempt runs', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);

      // A probe starts and its fetch HANGS, so `probing` stays true and can be
      // observed. This is precisely the window where a fourth PosOfflinePhase
      // value would have silently opened payment.
      transport.hangMenu = true;
      await _tick(tester);

      expect(c.read(posOfflineModeProvider).probing, isTrue);
      expect(
        phaseOf(c),
        PosOfflinePhase.offlineCached,
        reason: 'probing must NOT be a phase',
      );
      expect(
        blockPosActionWhileOffline(tester.element(find.byType(PosMenuScreen))),
        isTrue,
        reason: 'a probe is an attempt, not proof — the gate stays closed',
      );
      await tester.pump();
      expect(find.text(l10n.posOfflineActionUnavailable), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('the banner says "reconnecting" while probing and reverts to '
        'the saved-data age when the attempt fails (Arabic)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      final transport = _ProbeTransport();
      final c = await pump(
        tester,
        transport: transport,
        locale: const Locale('ar'),
      );
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      expect(find.text(l10n.posOfflineBannerReconnecting), findsNothing);

      transport.hangMenu = true;
      await _tick(tester);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);
      expect(find.text(l10n.posOfflineBannerReconnecting), findsOneWidget);

      await unmount(tester);
    });
  });

  // -------------------------------------------------------------------------
  group('8/9. session revalidation rides the menu fetch, not the outbox', () {
    // -----------------------------------------------------------------------
    ProviderContainer sessionContainer(SyncRpcTransport transport) {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncScopeProvider.overrideWithValue(_scope),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a successful pos_menu fetch clears restoredOffline and advances the '
        'persisted 8h anchor — with an EMPTY outbox', () async {
      final t0 = DateTime.utc(2026, 8, 6, 12);
      secure[_sessionKey] = jsonEncode(
        _storedSessionRecord(lastVerify: t0.subtract(const Duration(hours: 6))),
      );
      final transport = _ProbeTransport(serverUp: true);
      final c = sessionContainer(transport);
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = () => t0;
      expect(
        await controller.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.restored,
      );
      expect(
        c.read(posSessionOfflineRestoreInfoProvider).restoredOffline,
        isTrue,
      );
      final writesBefore = sessionWrites();

      // The reconnect probe's fetch succeeds. NOTHING is queued in the outbox,
      // which is exactly the case the old `sync_push`-only revalidation missed.
      await c.read(posMenuProvider.future);
      await _settle();

      expect(phaseOf(c), PosOfflinePhase.online);
      expect(
        c.read(posSessionOfflineRestoreInfoProvider).restoredOffline,
        isFalse,
        reason: 'an authenticated pos_menu round-trip IS online proof',
      );
      expect(sessionWrites(), writesBefore + 1);
      final stored = jsonDecode(secure[_sessionKey]!) as Map<String, dynamic>;
      expect(
        stored['last_online_verify'],
        t0.toIso8601String(),
        reason: 'the 8-hour window re-anchors on genuine proof',
      );
    });

    test(
      'a REFUSED fetch revalidates nothing: the session stays marked '
      'restored-offline, the phase stays offline, and the gate stays shut',
      () async {
        final t0 = DateTime.utc(2026, 8, 6, 12);
        final anchor = t0.subtract(const Duration(hours: 6));
        secure[_sessionKey] = jsonEncode(
          _storedSessionRecord(lastVerify: anchor),
        );
        final transport = _AuthRefusingTransport();
        final c = sessionContainer(transport);
        final controller = c.read(posSessionControllerProvider.notifier);
        controller.clock = () => t0;
        expect(
          await controller.restoreOfflineSession(device: _device),
          PosOfflineRestoreResult.restored,
        );
        final writesBefore = sessionWrites();

        await c.read(posMenuProvider.future);
        await _settle();

        expect(transport.menuCalls, greaterThanOrEqualTo(1));
        expect(
          phaseOf(c),
          PosOfflinePhase.offlineCached,
          reason: 'a refusal is not a recovery',
        );
        expect(
          c.read(posSessionOfflineRestoreInfoProvider).restoredOffline,
          isTrue,
          reason: 'nothing proved this session is still valid',
        );
        expect(
          sessionWrites(),
          writesBefore,
          reason: 'the anchor may not advance on a failed round-trip',
        );
        final stored = jsonDecode(secure[_sessionKey]!) as Map<String, dynamic>;
        expect(stored['last_online_verify'], anchor.toIso8601String());
      },
    );

    testWidgets('and no payment is possible in that refused state', (
      tester,
    ) async {
      final transport = _AuthRefusingTransport();
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      expect(
        blockPosActionWhileOffline(tester.element(find.byType(PosMenuScreen))),
        isTrue,
      );
      await unmount(tester);
    });
  });

  // -------------------------------------------------------------------------
  group('10. the recovered edge re-verifies the kitchen mode', () {
    // -----------------------------------------------------------------------
    testWidgets('the readiness seam is asked to report immediately exactly '
        'once, and only on the offlineCached -> online edge', (tester) async {
      final heartbeat = _FakeReadinessHeartbeat();
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport, heartbeat: heartbeat);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      final resumesBefore = heartbeat.resumes;

      transport.serverUp = true;
      await _tick(tester);

      expect(phaseOf(c), PosOfflinePhase.online);
      expect(
        heartbeat.resumes,
        resumesBefore + 1,
        reason:
            'the 2-hour offline kitchen-mode trust window is re-verified the '
            'moment the backend answers again',
      );

      // A LATER successful fetch is not another edge — no repeat request.
      c.invalidate(posMenuProvider);
      await _tick(tester);
      expect(phaseOf(c), PosOfflinePhase.online);
      expect(heartbeat.resumes, resumesBefore + 1);
    });
  });

  // -------------------------------------------------------------------------
  group('probe hygiene', () {
    // -----------------------------------------------------------------------
    testWidgets('the probe is NEVER armed while online', (tester) async {
      final transport = _ProbeTransport(serverUp: true);
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.online);
      final callsBefore = transport.menuCalls;

      await _tick(tester, ticks: 3);

      expect(
        transport.menuCalls,
        callsBefore,
        reason: 'an online till must not poll the menu on a timer',
      );
      // No unmount: if a timer had been armed, flutter_test would fail here.
    });

    testWidgets('the probe stops when the app leaves the foreground and '
        're-arms on resume', (tester) async {
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);

      // The real Android sequence (the framework asserts on shortcuts):
      // resumed -> inactive -> hidden -> paused.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      final callsWhilePaused = transport.menuCalls;
      await _tick(tester, ticks: 3);
      expect(
        transport.menuCalls,
        callsWhilePaused,
        reason: 'a backgrounded till must not re-attempt on a timer',
      );

      // RESUME. The one resume-time invalidation happens immediately; the
      // probe re-arms behind it so a resume that LOSES the Wi-Fi association
      // race is retried instead of re-latching forever.
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final afterResume = transport.menuCalls;
      expect(afterResume, greaterThan(callsWhilePaused));
      expect(phaseOf(c), PosOfflinePhase.offlineCached);

      // Still offline after the resume fetch lost the race — the probe keeps
      // going, which is the whole point of the re-arm.
      transport.serverUp = true;
      await _tick(tester);
      expect(phaseOf(c), PosOfflinePhase.online);
    });

    testWidgets('a null cadence (the default everywhere but main.dart) arms '
        'nothing at all', (tester) async {
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport, probeInterval: null);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      final callsBefore = transport.menuCalls;
      await _tick(tester, ticks: 3);
      expect(transport.menuCalls, callsBefore);
      // No unmount needed: nothing was ever armed.
    });

    testWidgets('dispose cancels the probe', (tester) async {
      final transport = _ProbeTransport();
      final c = await pump(tester, transport: transport);
      expect(phaseOf(c), PosOfflinePhase.offlineCached);
      await unmount(tester);
      // flutter_test asserts there is no pending Timer once the tree is gone;
      // pumping past several intervals must also produce no further calls.
      final callsAfterDispose = transport.menuCalls;
      await tester.pump(_probeInterval * 3);
      expect(transport.menuCalls, callsAfterDispose);
    });
  });
}
