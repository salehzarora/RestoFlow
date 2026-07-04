import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RF-114 — durable offline outbox: queued orders survive refresh/restart, retry
/// safely (idempotent, no duplicates), and never fake a "sent" state.

class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport(this._handler);
  final Future<Object?> Function(String function, Map<String, dynamic> params)
  _handler;
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    params.add(p);
    return _handler(function, p);
  }
}

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-123',
  deviceId: 'device-abc',
);

const String _prefsKey = 'restoflow.pos.outbox.v1';

OutboxEntry _entry({
  String localOperationId = 'op-1',
  String orderId = 'order-1',
}) {
  final payload = OrderSubmissionPayload(
    orderId: orderId,
    localOperationId: localOperationId,
    deviceId: 'demo-device',
    organizationId: 'demo-org',
    restaurantId: 'demo-restaurant',
    branchId: 'demo-branch',
    orderType: OrderType.dineIn,
    tableId: 't3',
    currencyCode: 'ILS',
    subtotalMinor: 4200,
    grandTotalMinor: 4200,
    items: const [
      OrderSubmissionItem(
        menuItemId: 'm1',
        nameSnapshot: 'Burger',
        quantity: 2,
        unitPriceMinorSnapshot: 2100,
        lineTotalMinor: 4200,
      ),
    ],
    clientCreatedAt: DateTime.utc(2026, 6, 29, 9),
  );
  return OutboxEntry(
    id: 'outbox-$localOperationId',
    deviceId: 'demo-device',
    localOperationId: localOperationId,
    operationType: 'order.submit',
    targetEntity: 'order',
    targetId: orderId,
    payloadJson: jsonEncode(payload.toJson()),
    summary: const OrderSummary(
      orderNumber: 'DEMO-1',
      orderType: OrderType.dineIn,
      tableLabel: 'T3',
      itemCount: 2,
      subtotalMinor: 4200,
      currencyCode: 'ILS',
    ),
    syncState: OutboxSyncState.pending,
    clientCreatedAt: DateTime.utc(2026, 6, 29, 9),
  );
}

Map<String, dynamic> _envelope(Map<String, dynamic> opResult) =>
    <String, dynamic>{
      'ok': true,
      'results': <dynamic>[opResult],
    };

String _localOpOf(Map<String, dynamic> p) =>
    ((p['p_operations'] as List).single as Map)['local_operation_id'] as String;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OutboxEntry JSON (schema-versioned persistence)', () {
    test('toJson -> fromJson preserves every field (integer minor money)', () {
      final e = _entry().copyWith(
        syncState: OutboxSyncState.rejected,
        attemptCount: 2,
        lastErrorCode: '42501',
      );
      final round = OutboxEntry.fromJson(e.toJson());
      expect(round.id, e.id);
      expect(round.deviceId, e.deviceId);
      expect(round.localOperationId, e.localOperationId);
      expect(round.operationType, 'order.submit');
      expect(round.targetId, 'order-1');
      expect(round.payloadJson, e.payloadJson);
      expect(round.syncState, OutboxSyncState.rejected);
      expect(round.attemptCount, 2);
      expect(round.lastErrorCode, '42501');
      expect(round.summary.subtotalMinor, 4200);
      expect(round.summary.subtotalMinor, isA<int>());
      expect(round.clientCreatedAt, e.clientCreatedAt);
    });

    test(
      'fromJson throws on an unknown sync_state (so the store can drop it)',
      () {
        final bad = _entry().toJson()..['sync_state'] = 'teleported';
        expect(
          () => OutboxEntry.fromJson(bad),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('SharedPrefsOutboxStore durability (localStorage/web)', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('persist then a FRESH load (simulated restart) round-trips', () async {
      final store1 = SharedPrefsOutboxStore(
        await SharedPreferences.getInstance(),
      );
      await store1.persist([_entry()]);
      final persisted = (await SharedPreferences.getInstance()).getString(
        _prefsKey,
      );
      expect(persisted, isNotNull);

      // Simulate an app restart reading the persisted localStorage value.
      SharedPreferences.setMockInitialValues(<String, Object>{
        _prefsKey: persisted!,
      });
      final store2 = SharedPrefsOutboxStore(
        await SharedPreferences.getInstance(),
      );
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.localOperationId, 'op-1');
      expect(loaded.single.syncState, OutboxSyncState.pending);
    });

    test(
      'an unknown schema version loads as EMPTY (safe, never mis-parses)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: jsonEncode(<String, Object?>{
            'version': 999,
            'entries': [],
          }),
        });
        final store = SharedPrefsOutboxStore(
          await SharedPreferences.getInstance(),
        );
        expect(await store.load(), isEmpty);
      },
    );

    test(
      'a corrupt value loads as EMPTY (never crashes the POS on start)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: 'not-json-at-all',
        });
        final store = SharedPrefsOutboxStore(
          await SharedPreferences.getInstance(),
        );
        expect(await store.load(), isEmpty);
      },
    );
  });

  group('RealOutboxRepository durability + retry safety (RF-114)', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Future<SharedPrefsOutboxStore> freshStore() async =>
        SharedPrefsOutboxStore(await SharedPreferences.getInstance());

    test('a queued order survives repo/app RECREATION (durable)', () async {
      // A backend that never answers: the order is enqueued but not delivered.
      final transport = _RecordingTransport(
        (_, _) async => throw const SyncTransportException(
          SyncTransportErrorKind.transient,
          code: '503',
          message: 'offline',
        ),
      );
      final repo1 = RealOutboxRepository(
        transport,
        _session,
        store: await freshStore(),
      );
      await repo1.enqueue(_entry());

      // Restart: a brand-new store + repo reading the persisted prefs.
      final persisted = (await SharedPreferences.getInstance()).getString(
        _prefsKey,
      )!;
      SharedPreferences.setMockInitialValues(<String, Object>{
        _prefsKey: persisted,
      });
      final repo2 = RealOutboxRepository(
        transport,
        _session,
        store: await freshStore(),
      );
      final recovered = await repo2.recentEntries();

      expect(recovered, hasLength(1));
      expect(recovered.single.localOperationId, 'op-1');
      expect(recovered.single.syncState, OutboxSyncState.pending);
    });

    test(
      'a FAILED network push persists the rejected entry (survives restart)',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '503',
          ),
        );
        final repo1 = RealOutboxRepository(
          transport,
          _session,
          store: await freshStore(),
        );
        await repo1.enqueue(_entry());
        final pushed = await repo1.push('outbox-op-1');
        expect(pushed.syncState, OutboxSyncState.rejected);

        final persisted = (await SharedPreferences.getInstance()).getString(
          _prefsKey,
        )!;
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: persisted,
        });
        final repo2 = RealOutboxRepository(
          transport,
          _session,
          store: await freshStore(),
        );
        final recovered = await repo2.recentEntries();
        expect(recovered.single.syncState, OutboxSyncState.rejected);
      },
    );

    test(
      'retry re-pushes the SAME local_operation_id (idempotent — no duplicate)',
      () async {
        var first = true;
        final transport = _RecordingTransport((_, _) async {
          if (first) {
            first = false;
            return _envelope(<String, dynamic>{
              'local_operation_id': 'op-1',
              'status': 'rejected',
              'error': 'transient',
            });
          }
          return _envelope(<String, dynamic>{
            'local_operation_id': 'op-1',
            'status': 'applied',
            'idempotency_replay': true,
          });
        });
        final repo = RealOutboxRepository(
          transport,
          _session,
          store: await freshStore(),
        );
        await repo.enqueue(_entry());

        final rejected = await repo.push('outbox-op-1');
        expect(rejected.syncState, OutboxSyncState.rejected);
        await repo.retry('outbox-op-1');
        final applied = await repo.push('outbox-op-1');
        expect(applied.syncState, OutboxSyncState.applied);

        // BOTH pushes carried the identical (deviceId, local_operation_id), so the
        // server dedupes the replay — a retry can never create a second order.
        expect(transport.params.map(_localOpOf).toList(), <String>[
          'op-1',
          'op-1',
        ]);
        expect(
          transport.params.every((p) => p['p_device_id'] == 'device-abc'),
          isTrue,
        );
      },
    );

    test(
      'durable dedup: re-enqueuing the same op across restart stays ONE',
      () async {
        final transport = _RecordingTransport(
          (_, _) async => throw const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: '503',
          ),
        );
        final repo1 = RealOutboxRepository(
          transport,
          _session,
          store: await freshStore(),
        );
        await repo1.enqueue(_entry());

        final persisted = (await SharedPreferences.getInstance()).getString(
          _prefsKey,
        )!;
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: persisted,
        });
        final repo2 = RealOutboxRepository(
          transport,
          _session,
          store: await freshStore(),
        );
        // The cashier's device re-rings the SAME logical op (same local_operation_id).
        await repo2.enqueue(_entry());
        expect(await repo2.recentEntries(), hasLength(1));
      },
    );
  });
}
