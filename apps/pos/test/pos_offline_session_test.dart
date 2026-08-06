// POS-OFFLINE-OPERATIONS-002 — C6 secure bounded session persistence.
//
// Covers OFFLINE-ARCH-SPEC tests 5, 6, 11, 12, 13, 14:
//   5  — a successful ONLINE PIN establish persists the bounded session record
//        (and NEVER the PIN);
//   6  — cold restore: a valid stored record restores the SAME session marked
//        restoredOffline (and survives a restart), an expired one refuses;
//   11 — the 8-hour lastOnlineVerify window boundary is exact;
//   12 — a server expiry EARLIER than lastOnlineVerify+8h wins (min() rule);
//   13 — reconnect revalidation: a structured sync_push answer advances the
//        persisted lastOnlineVerify (throttled) and clears restoredOffline;
//   14 — a batch 42501 ends the session (PIN gate seam) and destroys the
//        stored record, while the queued entries stay AUTH_HOLD — preserved
//        verbatim across restart and never swept.
//
// Real seams: the real PosSessionController, the real secure-storage channel
// (mocked at the MethodChannel), the real RealOutboxRepository + controller.
import 'dart:convert';

import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/secure_session_store.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_offline_session_policy.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _device = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
);

const _sessionKey = 'restoflow.pos.pin_session.v1.org-1.rest-1.branch-1.dev-1';

/// Scripted transport: `start_pin_session` answers a session id; `sync_push`
/// runs [onSyncPush] (throw or answer); everything else is benign.
class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport({this.onSyncPush});

  Object? Function(Map<String, dynamic> params)? onSyncPush;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (function == 'start_pin_session') return 'pin-1';
    if (function == 'sync_push' && onSyncPush != null) {
      return onSyncPush!(params);
    }
    return <String, dynamic>{'ok': false};
  }
}

Object? _appliedEnvelope(Map<String, dynamic> params) {
  final op = (params['p_operations'] as List).first as Map;
  return <String, dynamic>{
    'ok': true,
    'results': <dynamic>[
      <String, dynamic>{
        'local_operation_id': op['local_operation_id'],
        'operation_type': op['operation_type'],
        'status': 'applied',
        'ok': true,
      },
    ],
  };
}

class _MemoryStore implements DurableOutboxStore {
  final Map<String, List<Map<String, Object?>>> saved = {};
  @override
  Future<List<OutboxEntry>> load(String scopeKey) async => [
    for (final j in saved[scopeKey] ?? const <Map<String, Object?>>[])
      OutboxEntry.fromJson(j),
  ];
  @override
  Future<void> persist(String scopeKey, List<OutboxEntry> entries) async {
    saved[scopeKey] = [for (final e in entries) e.toJson()];
  }
}

OutboxEntry _orderEntry({String op = 'op-1'}) => OutboxEntry(
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
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 6),
);

Map<String, Object?> _record({
  required DateTime lastOnlineVerify,
  DateTime? serverExpiry,
  String sessionId = 'pin-stored',
  String employeeProfileId = 'emp-1',
  String deviceSessionId = 'ds-1',
}) => <String, Object?>{
  'v': 1,
  'session_id': sessionId,
  'employee_profile_id': employeeProfileId,
  'display_name': 'Amira K.',
  'organization_id': 'org-1',
  'restaurant_id': 'rest-1',
  'branch_id': 'branch-1',
  'device_id': 'dev-1',
  'device_session_id': deviceSessionId,
  if (serverExpiry != null)
    'server_expiry': serverExpiry.toUtc().toIso8601String(),
  'last_online_verify': lastOnlineVerify.toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secure;
  late List<MethodCall> secureCalls;

  setUp(() {
    secure = <String, String>{};
    secureCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
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
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
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

  ProviderContainer realContainer({
    required SyncRpcTransport transport,
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('C6 — persist on establish (spec test 5)', () {
    test('a successful ONLINE sign-in persists the bounded record — '
        'and NEVER the PIN', () async {
      final transport = _ScriptedTransport();
      final c = realContainer(transport: transport);
      final controller = c.read(posSessionControllerProvider.notifier);
      final t0 = DateTime.utc(2026, 8, 6, 10);
      controller.clock = () => t0;

      final error = await controller.signInWithPin(
        device: _device,
        deviceId: 'dev-1',
        deviceSessionId: 'ds-1',
        employeeProfileId: 'emp-1',
        pin: '4321',
        employeeDisplayName: 'Amira K.',
      );
      expect(error, isNull);
      await settle();

      final raw = secure[_sessionKey];
      expect(raw, isNotNull, reason: 'the record persists under the scope key');
      final stored = jsonDecode(raw!) as Map<String, dynamic>;
      expect(stored['v'], 1);
      expect(stored['session_id'], 'pin-1');
      expect(stored['employee_profile_id'], 'emp-1');
      expect(stored['display_name'], 'Amira K.');
      expect(stored['organization_id'], 'org-1');
      expect(stored['restaurant_id'], 'rest-1');
      expect(stored['branch_id'], 'branch-1');
      expect(stored['device_id'], 'dev-1');
      expect(stored['device_session_id'], 'ds-1');
      expect(stored['last_online_verify'], t0.toIso8601String());
      expect(
        stored.containsKey('server_expiry'),
        isFalse,
        reason: 'start_pin_session exposes no expiry today — stored null',
      );
      // SECURITY: the typed PIN must not appear ANYWHERE in secure storage.
      expect(raw.contains('4321'), isFalse);
      for (final value in secure.values) {
        expect(value.contains('4321'), isFalse);
      }
      // A live establish is not a restore.
      expect(
        c.read(posSessionOfflineRestoreInfoProvider).restoredOffline,
        isFalse,
      );
      expect(c.read(posOfflineSessionPolicyProvider).canSubmit, isTrue);
    });
  });

  group('C6 — cold restore (spec test 6)', () {
    test('a VALID stored record restores the same session, marked '
        'restoredOffline, and survives a restart', () async {
      final t0 = DateTime.utc(2026, 8, 6, 10);
      secure[_sessionKey] = jsonEncode(
        _record(lastOnlineVerify: t0.subtract(const Duration(hours: 1))),
      );

      final c = realContainer(transport: _ScriptedTransport());
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = () => t0;
      final result = await controller.restoreOfflineSession(device: _device);
      expect(result, PosOfflineRestoreResult.restored);

      final session = c.read(posSyncSessionProvider);
      expect(session, isNotNull);
      expect(session!.pinSessionId, 'pin-stored');
      expect(session.deviceId, 'dev-1');
      // The gate's unlock contract: a FULL binding matching this pairing.
      expect(
        c.read(posPinSessionBindingProvider)!.matchesContext(_device),
        isTrue,
      );
      // Marked restoredOffline, with its hard window mirrored reactively.
      final info = c.read(posSessionOfflineRestoreInfoProvider);
      expect(info.restoredOffline, isTrue);
      expect(
        info.validUntil,
        t0.add(const Duration(hours: 7)),
        reason: 'lastOnlineVerify(-1h) + 8h',
      );
      // The operator identity is republished for the shift/recovery surfaces.
      expect(c.read(posSignedInStaffNameProvider), 'Amira K.');
      expect(c.read(posSignedInEmployeeProfileIdProvider), 'emp-1');

      // RESTART (new container over the SAME secure storage): still restores —
      // nothing about a restart may consume or reset the window.
      final c2 = realContainer(transport: _ScriptedTransport());
      final controller2 = c2.read(posSessionControllerProvider.notifier);
      controller2.clock = () => t0.add(const Duration(hours: 2));
      expect(
        await controller2.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.restored,
      );
    });

    test('an EXPIRED stored record refuses to restore (fail closed)', () async {
      final t0 = DateTime.utc(2026, 8, 6, 10);
      secure[_sessionKey] = jsonEncode(
        _record(lastOnlineVerify: t0.subtract(const Duration(hours: 9))),
      );
      final c = realContainer(transport: _ScriptedTransport());
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = () => t0;
      expect(
        await controller.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.expired,
      );
      expect(c.read(posSyncSessionProvider), isNull);
    });

    test('a record from a DIFFERENT pairing (device session) never restores '
        'and is destroyed', () async {
      final t0 = DateTime.utc(2026, 8, 6, 10);
      secure[_sessionKey] = jsonEncode(
        _record(
          lastOnlineVerify: t0.subtract(const Duration(minutes: 5)),
          deviceSessionId: 'ds-OLD-PAIRING',
        ),
      );
      final c = realContainer(transport: _ScriptedTransport());
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = () => t0;
      expect(
        await controller.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.wrongPairing,
      );
      expect(c.read(posSyncSessionProvider), isNull);
      await settle();
      expect(secure.containsKey(_sessionKey), isFalse);
    });

    test('a typed-PIN transport failure never restores ANOTHER employee\'s '
        'stored session', () async {
      final t0 = DateTime.utc(2026, 8, 6, 10);
      secure[_sessionKey] = jsonEncode(
        _record(
          lastOnlineVerify: t0.subtract(const Duration(minutes: 5)),
          employeeProfileId: 'emp-OTHER',
        ),
      );
      final c = realContainer(transport: _ScriptedTransport());
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = () => t0;
      expect(
        await controller.restoreOfflineSession(
          device: _device,
          attemptedEmployeeProfileId: 'emp-1',
        ),
        PosOfflineRestoreResult.wrongEmployee,
      );
      expect(c.read(posSyncSessionProvider), isNull);
    });
  });

  group('C6 — the 8h window boundary (spec test 11)', () {
    test('valid strictly BEFORE lastOnlineVerify+8h; expired AT it', () async {
      final t0 = DateTime.utc(2026, 8, 6, 6);
      secure[_sessionKey] = jsonEncode(_record(lastOnlineVerify: t0));

      final inside = realContainer(transport: _ScriptedTransport());
      final c1 = inside.read(posSessionControllerProvider.notifier);
      c1.clock = () =>
          t0.add(const Duration(hours: 8) - const Duration(seconds: 1));
      expect(
        await c1.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.restored,
      );

      final atBoundary = realContainer(transport: _ScriptedTransport());
      final c2 = atBoundary.read(posSessionControllerProvider.notifier);
      c2.clock = () => t0.add(const Duration(hours: 8));
      expect(
        await c2.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.expired,
        reason: 'the boundary instant itself is already outside the window',
      );
    });
  });

  group('C6 — server expiry wins when earlier (spec test 12)', () {
    test('min(serverExpiry, lastOnlineVerify+8h) bounds the restore', () async {
      final t0 = DateTime.utc(2026, 8, 6, 6);
      secure[_sessionKey] = jsonEncode(
        _record(
          lastOnlineVerify: t0,
          serverExpiry: t0.add(const Duration(hours: 1)),
        ),
      );

      final before = realContainer(transport: _ScriptedTransport());
      final c1 = before.read(posSessionControllerProvider.notifier);
      c1.clock = () => t0.add(const Duration(minutes: 30));
      expect(
        await c1.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.restored,
      );

      final after = realContainer(transport: _ScriptedTransport());
      final c2 = after.read(posSessionControllerProvider.notifier);
      c2.clock = () => t0.add(const Duration(hours: 2));
      expect(
        await c2.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.expired,
        reason: 'still inside 8h, but the SERVER expiry ended the window',
      );
      // The record itself agrees (the pure rule, pinned).
      final record = PosStoredPinSession.tryFromJson(
        jsonDecode(secure[_sessionKey]!),
      )!;
      expect(record.offlineValidUntil, t0.add(const Duration(hours: 1)));
    });
  });

  group('C6 — reconnect revalidation (spec test 13)', () {
    test('a structured sync_push answer advances the persisted anchor '
        '(throttled) and clears restoredOffline', () async {
      final t0 = DateTime.utc(2026, 8, 6, 10);
      secure[_sessionKey] = jsonEncode(
        _record(lastOnlineVerify: t0.subtract(const Duration(hours: 6))),
      );
      final transport = _ScriptedTransport(onSyncPush: _appliedEnvelope);
      final store = _MemoryStore();
      final c = realContainer(
        transport: transport,
        extra: [durableOutboxStoreProvider.overrideWithValue(store)],
      );
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

      // The backend comes back: a queued order pushes and is APPLIED.
      final outbox = c.read(outboxControllerProvider.notifier);
      await c.read(outboxRepositoryProvider).enqueue(_orderEntry());
      final writesBefore = sessionWrites();
      await outbox.pushEntry('e-op-1');
      await settle();

      expect(
        c.read(posSessionOfflineRestoreInfoProvider).restoredOffline,
        isFalse,
        reason: 'a real authenticated round-trip IS online proof',
      );
      final record = PosStoredPinSession.tryFromJson(
        jsonDecode(secure[_sessionKey]!),
      )!;
      expect(
        record.lastOnlineVerify,
        t0,
        reason: 'the anchor advances to the verified moment',
      );
      expect(sessionWrites(), writesBefore + 1);

      // THROTTLE: a second success within 5 minutes persists nothing new.
      await c.read(outboxRepositoryProvider).enqueue(_orderEntry(op: 'op-2'));
      await outbox.pushEntry('e-op-2');
      await settle();
      expect(
        sessionWrites(),
        writesBefore + 1,
        reason: 'verify writes are throttled to once per 5 minutes',
      );
    });
  });

  group('C6/C8 — a batch 42501 ends the session, holds the queue '
      '(spec test 14)', () {
    test('session ends + notice raised + record destroyed; entries stay '
        'AUTH_HOLD verbatim across restart and are never swept', () async {
      // Establish ONLINE first (so a record exists), then the server starts
      // refusing the whole batch.
      final transport = _ScriptedTransport(
        // Pass B fixture honesty: kind `auth` is minted by the real transport
        // only for a session-class 42501 message, so the fake carries one.
        // (OLD message: 'revoked device / expired session'.)
        onSyncPush: (_) => throw const SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message:
              'sync_push: PIN session is not valid (inactive/ended/expired)',
        ),
      );
      final store = _MemoryStore();
      final c = realContainer(
        transport: transport,
        extra: [durableOutboxStoreProvider.overrideWithValue(store)],
      );
      final controller = c.read(posSessionControllerProvider.notifier);
      controller.clock = DateTime.now;
      expect(
        await controller.signInWithPin(
          device: _device,
          deviceId: 'dev-1',
          deviceSessionId: 'ds-1',
          employeeProfileId: 'emp-1',
          pin: '4321',
        ),
        isNull,
      );
      await settle();
      expect(secure.containsKey(_sessionKey), isTrue);

      final original = _orderEntry();
      await c.read(outboxRepositoryProvider).enqueue(original);
      await c.read(outboxControllerProvider.notifier).pushEntry('e-op-1');
      await settle();

      // The session seam fired exactly as C8 specifies.
      expect(c.read(posSyncSessionProvider), isNull, reason: 'session ended');
      expect(
        c.read(posSessionReauthNoticeProvider),
        isTrue,
        reason: 'the PIN gate shows the re-auth notice',
      );
      expect(
        secure.containsKey(_sessionKey),
        isFalse,
        reason: 'the server proved the stored session worthless',
      );

      // The queued work is HELD, not deleted — byte-verbatim, restart-proof.
      final reloaded = RealOutboxRepository(
        _ScriptedTransport(),
        const SyncSession(pinSessionId: 'pin-2', deviceId: 'dev-1'),
        store: store,
      );
      final held = (await reloaded.recentEntries()).single;
      expect(held.syncState, OutboxSyncState.authHold);
      expect(held.localOperationId, original.localOperationId);
      expect(held.payloadJson, original.payloadJson);
      expect(held.outcome, PosOrderOutcome.pending);
      expect(held.hasDefinitiveVerdict, isFalse);

      // And a fresh controller with a live session NEVER sweeps it.
      final sweepTransport = _ScriptedTransport(
        onSyncPush: (_) => fail('an AUTH_HOLD entry must never be swept'),
      );
      final c2 = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(sweepTransport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-2', deviceId: 'dev-1'),
          ),
          durableOutboxStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c2.dispose);
      final outbox2 = c2.read(outboxControllerProvider.notifier);
      await settle();
      await outbox2.pushQueued();
      await outbox2.retryAllFailed();
      await outbox2.retryEntry('e-op-1');
      await outbox2.pushEntry('e-op-1');
      expect(outbox2.entryById('e-op-1')!.syncState, OutboxSyncState.authHold);
    });
  });
}
