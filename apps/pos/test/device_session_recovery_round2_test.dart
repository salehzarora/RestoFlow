import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/main.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _pinKey = 'restoflow.pos.pin_session.v1.org-1.rest-1.branch-1.dev-1';
const _device = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
);
const _validDevice = {
  'ok': true,
  'device_id': 'dev-1',
  'device_session_id': 'ds-1',
  'organization_id': 'org-1',
  'restaurant_id': 'rest-1',
  'branch_id': 'branch-1',
  'device_type': 'pos',
};

class _Wire implements SyncRpcTransport {
  Object? Function() deviceReply = () => _validDevice;
  String pinSession = 'pin-1';
  final orderPushes = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'restore_device_session' ||
        function == 'heartbeat_device_session') {
      return deviceReply();
    }
    if (function == 'start_pin_session') return pinSession;
    if (function == 'sync_push') {
      final op = Map<String, dynamic>.from(
        (params['p_operations'] as List).single as Map,
      );
      if (op['operation_type'] == 'order.submit') orderPushes.add(op);
      return {
        'ok': true,
        'results': [
          {
            'local_operation_id': op['local_operation_id'],
            'operation_type': op['operation_type'],
            'status': 'applied',
            'ok': true,
          },
        ],
      };
    }
    return {'ok': false};
  }
}

// The durable bytes still go through SharedPreferences. Only completion of
// one write is held, reproducing recovery while a refused sweep is in flight.
class _HeldWriteStore implements DurableOutboxStore {
  _HeldWriteStore(this.inner);
  final SharedPrefsOutboxStore inner;
  String? holdRejectedId;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<OutboxEntry>> load(String scopeKey) => inner.load(scopeKey);

  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    await inner.persist(scopeKey, entries);
    if (!entered.isCompleted &&
        entries.any(
          (e) =>
              e.id == holdRejectedId && e.syncState == OutboxSyncState.rejected,
        )) {
      entered.complete();
      await release.future;
    }
  }
}

class _Staff implements DeviceStaffRepository {
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

OutboxEntry _entry(String op, {bool held = false}) => OutboxEntry(
  id: 'e-$op',
  deviceId: 'dev-1',
  localOperationId: op,
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-$op',
  payloadJson: '{"order_id":"order-$op","subtotal_minor":4200}',
  summary: const OrderSummary(
    orderNumber: '#AA11BB',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: held ? OutboxSyncState.authHold : OutboxSyncState.pending,
  // A guard refusal will schedule a long backoff. Recovery must bypass it,
  // without lifting genuine AUTH_HOLD entries or creating new identities.
  attemptCount: 20,
  clientCreatedAt: DateTime.utc(2026, 10, 6),
);

void main() {
  final secure = <String, String>{};
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, Object?>();
          final key = args?['key'] as String?;
          switch (call.method) {
            case 'read':
              return secure[key];
            case 'write':
              secure[key!] = args!['value']! as String;
            case 'delete':
              secure.remove(key);
            case 'containsKey':
              return secure.containsKey(key);
            case 'readAll':
              return Map<String, String>.of(secure);
            case 'deleteAll':
              secure.clear();
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  Future<
    ({
      ProviderContainer container,
      SupabaseDevicePairingRepository pairing,
      _Wire wire,
      InMemoryDeviceSessionSecretStore secrets,
      SharedPreferences prefs,
      _HeldWriteStore store,
    })
  >
  mountPos(WidgetTester tester, {DeviceImageUrlResolver? images}) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = _HeldWriteStore(SharedPrefsOutboxStore(prefs));
    final wire = _Wire();
    final guard = DeviceSessionGuardedTransport(wire);
    final secrets = InMemoryDeviceSessionSecretStore();
    await secrets.write(
      const DeviceSessionCredential(deviceId: 'dev-1', sessionToken: 'token'),
    );
    final pairing = SupabaseDevicePairingRepository(
      transport: guard,
      secretStore: secrets,
    );
    await pairing.restoreOutcome(expectedDeviceType: 'pos');
    final now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(guard),
        posImageUrlResolverProvider.overrideWithValue(images),
        // The native printer-readiness timer is unrelated to device auth.
        posKitchenReadinessHeartbeatProvider.overrideWithValue(null),
        durableOutboxStoreProvider.overrideWithValue(store),
        posSyncClockProvider.overrideWithValue(() => now),
        posMenuProvider.overrideWith(
          (ref) async =>
              const PosMenuData(categories: [], items: [], currencyCode: 'ILS'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: PosApp(
          demoMode: false,
          devicePairingRepository: pairing,
          deviceStaffRepository: _Staff(),
          initialDevice: _device,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = container.read(posSessionControllerProvider.notifier)
      ..clock = () => now;
    expect(
      await session.signInWithPin(
        device: _device,
        deviceId: 'dev-1',
        deviceSessionId: 'ds-1',
        employeeProfileId: 'emp-1',
        pin: '4321',
      ),
      isNull,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PosMenuScreen), findsOneWidget);
    expect(secure[_pinKey], isNotNull);
    return (
      container: container,
      pairing: pairing,
      wire: wire,
      secrets: secrets,
      prefs: prefs,
      store: store,
    );
  }

  testWidgets(
    'H2 real POS recovery immediately sweeps SharedPrefs retry once and preserves PIN and AUTH_HOLD',
    (tester) async {
      final h = await mountPos(tester);
      h.wire.deviceReply = () => {'ok': true};
      await h.pairing.heartbeat();
      await h.pairing.heartbeat();
      await tester.pumpAndSettle();
      expect(h.pairing.protectedCallsBlocked, isTrue);
      expect(
        find.byKey(const Key('device-session-unavailable-title')),
        findsOneWidget,
      );
      final original = _entry('retry-op');
      final held = _entry('held-op', held: true);
      final repo = h.container.read(outboxRepositoryProvider);
      await repo.enqueue(original);
      await repo.enqueue(held);
      final outbox = h.container.read(outboxControllerProvider.notifier);
      await outbox.pushEntry(original.id);
      await tester.pumpAndSettle();
      final refused = outbox.entryById(original.id)!;
      expect(refused.lastErrorCode, 'device_session_unverified');
      expect(refused.syncState, isNot(OutboxSyncState.authHold));
      expect(refused.hasDefinitiveVerdict, isFalse);
      expect(
        refused.nextAttemptAt!.isAfter(
          h.container.read(posSyncClockProvider)(),
        ),
        isTrue,
      );
      expect(h.wire.orderPushes, isEmpty);

      h.wire.deviceReply = () =>
          throw const SyncTransportException(SyncTransportErrorKind.transient);
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('device-session-unavailable-title')),
        findsOneWidget,
      );
      expect(find.byType(PosMenuScreen), findsOneWidget);
      expect(h.container.read(posSyncSessionProvider)?.pinSessionId, 'pin-1');

      h.wire.deviceReply = () => _validDevice;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      // No outbox method is invoked here: the REAL PosApp recovery callback
      // must deliver this not-yet-due retry using resetBackoff: true.
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      expect(
        outbox.entryById(original.id)!.syncState,
        OutboxSyncState.applied,
        reason:
            'wire order pushes: ${h.wire.orderPushes.length}; '
            'blocked: ${h.pairing.protectedCallsBlocked}',
      );
      expect(h.wire.orderPushes, hasLength(1));
      expect(
        h.wire.orderPushes.single['local_operation_id'],
        original.localOperationId,
      );
      expect(outbox.entryById(original.id)!.payloadJson, original.payloadJson);
      expect(outbox.entryById(held.id)!.syncState, OutboxSyncState.authHold);
      expect(h.container.read(posSyncSessionProvider)?.pinSessionId, 'pin-1');
      expect(h.container.read(posSessionReauthNoticeProvider), isFalse);
      expect(secure[_pinKey], isNotNull);
      expect(
        find.byKey(const Key('device-session-unavailable-title')),
        findsNothing,
      );
      await h.pairing.heartbeat();
      await tester.pumpAndSettle();
      expect(h.wire.orderPushes, hasLength(1));
      final restarted = RealOutboxRepository(
        DeviceSessionGuardedTransport(h.wire),
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
        store: SharedPrefsOutboxStore(h.prefs),
      );
      final durable = await restarted.recentEntries();
      expect(
        durable.singleWhere((e) => e.id == original.id).syncState,
        OutboxSyncState.applied,
      );
      expect(
        durable.singleWhere((e) => e.id == held.id).syncState,
        OutboxSyncState.authHold,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'H2 recovery during refused SharedPrefs sweep immediately consumes coalesced reset without timer',
    (tester) async {
      final h = await mountPos(tester);
      h.wire.deviceReply = () => {'ok': true};
      await h.pairing.heartbeat();
      await h.pairing.heartbeat();
      await tester.pumpAndSettle();
      final first = _entry('first-op');
      final delayed = _entry('delayed-op').copyWith(
        syncState: OutboxSyncState.rejected,
        lastErrorCode: '502',
        lastErrorKind: 'transient',
        nextAttemptAt: h.container
            .read(posSyncClockProvider)()
            .add(const Duration(minutes: 5)),
      );
      final repo = h.container.read(outboxRepositoryProvider);
      await repo.enqueue(first);
      await repo.enqueue(delayed);
      h.store.holdRejectedId = first.id;
      h.container.invalidate(outboxControllerProvider);
      final outbox = h.container.read(outboxControllerProvider.notifier);
      for (var i = 0; i < 10 && !h.store.entered.isCompleted; i++) {
        await tester.pump();
      }
      expect(h.store.entered.isCompleted, isTrue);
      expect(h.wire.orderPushes, isEmpty);
      h.wire.deviceReply = () => _validDevice;
      await tester.tap(find.byKey(const Key('device-session-retry')));
      // The held in-flight order deliberately keeps its progress animation
      // alive; drain microtasks without waiting for that animation to settle.
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      // Another valid heartbeat does not duplicate the pending recovery.
      await h.pairing.heartbeat();
      expect(h.wire.orderPushes, isEmpty);
      h.store.release.complete();
      for (var i = 0; i < 15; i++) {
        await tester.pump();
      }
      expect(outbox.entryById(delayed.id)!.syncState, OutboxSyncState.applied);
      expect(outbox.entryById(first.id)!.syncState, OutboxSyncState.applied);
      expect(
        h.wire.orderPushes.map((e) => e['local_operation_id']),
        unorderedEquals([first.localOperationId, delayed.localOperationId]),
      );
      expect(h.container.read(posSyncSessionProvider)?.pinSessionId, 'pin-1');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'H2 old sweep cannot publish or continue through a newer PIN repository',
    (tester) async {
      final h = await mountPos(tester);
      h.wire.deviceReply = () => {'ok': true};
      await h.pairing.heartbeat();
      await h.pairing.heartbeat();
      await tester.pumpAndSettle();
      final first = _entry('old-op');
      await h.container.read(outboxRepositoryProvider).enqueue(first);
      h.store.holdRejectedId = first.id;
      h.container.invalidate(outboxControllerProvider);
      h.container.read(outboxControllerProvider);
      for (var i = 0; i < 10 && !h.store.entered.isCompleted; i++) {
        await tester.pump();
      }
      expect(h.store.entered.isCompleted, isTrue);
      h.container.read(posSessionControllerProvider.notifier).endSession();
      await tester.pumpAndSettle();
      h.wire.deviceReply = () => _validDevice;
      await h.pairing.heartbeat();
      h.wire.pinSession = 'pin-2';
      expect(
        await h.container
            .read(posSessionControllerProvider.notifier)
            .signInWithPin(
              device: _device,
              deviceId: 'dev-1',
              deviceSessionId: 'ds-1',
              employeeProfileId: 'emp-2',
              pin: '5678',
            ),
        isNull,
      );
      await tester.pumpAndSettle();
      final fresh = _entry('fresh-op');
      await h.container.read(outboxRepositoryProvider).enqueue(fresh);
      final current = h.container.read(outboxControllerProvider.notifier);
      await current.pushEntry(fresh.id);
      await tester.pumpAndSettle();
      expect(current.entryById(fresh.id)!.syncState, OutboxSyncState.applied);
      h.store.release.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      expect(h.container.read(posSyncSessionProvider)?.pinSessionId, 'pin-2');
      expect(current.entryById(fresh.id)?.syncState, OutboxSyncState.applied);
      expect(
        h.wire.orderPushes.where(
          (e) => e['local_operation_id'] == fresh.localOperationId,
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'H5 actual POS confirmed local repair ends PIN neutrally and clears signed image cache',
    (tester) async {
      final source = FakeDeviceImageUrlResolver(
        urls: {'org-1/item.jpg': 'https://example.test/item.jpg?token=one'},
      );
      final images = CachingDeviceImageUrlResolver(source);
      await images.signedUrlsFor(['org-1/item.jpg']);
      await images.signedUrlsFor(['org-1/item.jpg']);
      expect(source.requests, hasLength(1));
      final h = await mountPos(tester, images: images);
      h.wire.deviceReply = () => {'ok': true};
      for (var i = 0; i < 2; i++) {
        await h.pairing.heartbeat();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-session-retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-session-repair')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-session-repair-confirm')));
      await tester.pumpAndSettle();
      expect(await h.secrets.read(), isNull);
      expect(h.container.read(posSyncSessionProvider), isNull);
      expect(h.container.read(posSessionReauthNoticeProvider), isFalse);
      expect(secure[_pinKey], isNull);
      await images.signedUrlsFor(['org-1/item.jpg']);
      expect(source.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
