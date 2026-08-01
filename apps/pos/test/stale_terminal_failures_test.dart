import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007 — BUG 2.
///
/// THE DEFECT. Before the hosted pricing migrations, a paid-modifier meal made
/// the OLD server raise on the subtotal recompute; `app.sync_push` collapses a
/// raised failure to the literal `rejected`, which is a member of
/// [kPermanentRejectionCodes]. So each of those submits is durably stored as
/// `syncState: rejected` + `lastErrorCode: 'rejected'`, i.e.
/// [OutboxEntry.isPermanentBusinessRejection] — and, being an `order.submit`,
/// [OutboxEntry.isNeverCreatedOrderSubmit]: the server provably created NO
/// order row for it.
///
/// Three things then combine:
///   * `OutboxStatusIndicator` counts `rejected` + `dead` together as "N failed
///     — retry";
///   * `retryAllFailed()` deliberately SKIPS permanent rejections
///     (`!e.isPermanentBusinessRejection`), because replaying the identity
///     returns the same stored refusal for ever — so the count never moves;
///   * there is NO dismissal path anywhere in the controller or the repository.
///
/// The entries are durable, so they come back on every start, and the only way
/// the cashier found to hide them was ending the shift.
///
/// These tests use the REAL `SharedPrefsOutboxStore` over real
/// SharedPreferences, and a container recreation IS the app restart.
/// `RealOutboxRepository` keys its durable queue on the SESSION DEVICE ID
/// (`_scopeKey => _session!.deviceId`), so the fixture must use exactly that —
/// a hand-rolled composite key would seed a queue nothing reads.
const _deviceId = 'dev-1';
const _scopeKey = _deviceId;
const _prefsKey = 'restoflow.pos.outbox.v1.$_deviceId';
const _session = SyncSession(pinSessionId: 'pin-1', deviceId: _deviceId);

OutboxEntry _entry({
  required String localOperationId,
  required OutboxSyncState syncState,
  String operationType = 'order.submit',
  String? lastErrorCode,
}) => OutboxEntry(
  id: 'outbox-$localOperationId',
  deviceId: _deviceId,
  organizationId: 'demo-org',
  restaurantId: 'demo-restaurant',
  branchId: 'demo-branch',
  localOperationId: localOperationId,
  operationType: operationType,
  targetEntity: 'order',
  targetId: 'order-$localOperationId',
  payloadJson: '{}',
  summary: const OrderSummary(
    orderNumber: 'A-1',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 12000,
    currencyCode: 'ILS',
  ),
  syncState: syncState,
  clientCreatedAt: DateTime.utc(2026, 7, 30, 9),
  lastErrorCode: lastErrorCode,
);

/// EXACTLY the six the cashier is looking at: `order.submit` operations the old
/// server permanently refused, so no order exists for any of them.
List<OutboxEntry> _sixStale() => [
  for (var i = 1; i <= 6; i++)
    _entry(
      localOperationId: 'op-old-$i',
      syncState: OutboxSyncState.rejected,
      lastErrorCode: 'rejected',
    ),
];

/// `RealOutboxRepository` refuses to operate without a transport AND a session
/// (`_ready`), so one must exist — but nothing may actually be sent. This one
/// fails every call as a TRANSIENT transport error, which is the outcome that
/// changes no stored verdict.
class _OfflineTransport implements SyncRpcTransport {
  int calls = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls++;
    throw const SyncTransportException(
      SyncTransportErrorKind.transient,
      code: 'offline',
    );
  }
}

Future<SharedPreferences> _seed(List<OutboxEntry> entries) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _prefsKey: jsonEncode(<String, Object?>{
      'version': SharedPrefsOutboxStore.schemaVersion,
      'entries': [for (final e in entries) e.toJson()],
    }),
  });
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) {
  final c = ProviderContainer(
    overrides: [
      // REAL mode: demo uses an in-memory `DemoOutboxStore` that never touches
      // the durable queue, and the durable queue IS the defect.
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posSyncSessionProvider.overrideWithValue(_session),
      // A transport that always fails transiently: the repository is `_ready`
      // (it refuses to work without one) but nothing can actually be sent, so
      // no stored verdict is altered by the recovery sweep.
      posAuthTransportProvider.overrideWithValue(_OfflineTransport()),
      durableOutboxStoreProvider.overrideWithValue(
        SharedPrefsOutboxStore(prefs),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. the six stale pre-cutover failures', () {
    test('A1 are classified as dismissible, cleared by ONE action, and stay '
        'gone across a restart — with the shift untouched', () async {
      final prefs = await _seed(_sixStale());
      final c = _container(prefs);
      final outbox = c.read(outboxControllerProvider.notifier);
      await _settle();

      expect(
        c.read(outboxControllerProvider),
        hasLength(6),
        reason: 'they are durable, which is why they return on every start',
      );
      expect(
        outbox.dismissibleFailureCount,
        6,
        reason:
            'each is an order.submit the server permanently refused, so no '
            'order row was ever created for it',
      );
      expect(
        outbox.retryableFailureCount,
        0,
        reason:
            'THE MISLEADING PART: they were counted under "N failed — retry" '
            'while retryAllFailed deliberately skips them, so the number could '
            'never move',
      );

      // ---- ONE press.
      final dismissed = await outbox.dismissResolvedFailures();
      expect(dismissed, 6);
      await _settle();

      expect(c.read(outboxControllerProvider), isEmpty);
      expect(outbox.dismissibleFailureCount, 0);

      // ---- RESTART: a new container over the SAME SharedPreferences.
      c.dispose();
      final c2 = _container(prefs);
      c2.read(outboxControllerProvider);
      await _settle();

      expect(
        c2.read(outboxControllerProvider),
        isEmpty,
        reason:
            'the removal is persisted — this is what "ending the shift" was '
            'being used to fake',
      );
    });
  });

  group('B. a MIXED queue — only the provably safe ones leave', () {
    test('B1 terminal rejections go; retryable, uncertain, conflict and '
        'unreadable all stay', () async {
      final prefs = await _seed([
        // two terminal permanent refusals of an order.submit
        _entry(
          localOperationId: 'perm-1',
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'item_unavailable',
        ),
        _entry(
          localOperationId: 'perm-2',
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'rejected',
        ),
        // a RETRYABLE transport failure — no server verdict was recorded
        _entry(
          localOperationId: 'retry-1',
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'transport',
        ),
        // retry-exhausted, but still no positive verdict
        _entry(localOperationId: 'dead-1', syncState: OutboxSyncState.dead),
        // an identity conflict — needs a person
        _entry(
          localOperationId: 'conflict-1',
          syncState: OutboxSyncState.conflict,
        ),
        // in flight — the server may already own it
        _entry(
          localOperationId: 'inflight-1',
          syncState: OutboxSyncState.inFlight,
        ),
        // a permanent rejection of a LATER operation: it says NOTHING about
        // whether the order exists, so it must not be dismissed
        _entry(
          localOperationId: 'pay-1',
          syncState: OutboxSyncState.rejected,
          operationType: 'payment.create',
          lastErrorCode: 'rejected',
        ),
      ]);
      final c = _container(prefs);
      final outbox = c.read(outboxControllerProvider.notifier);
      await _settle();

      await _settle();
      await _settle();
      expect(outbox.dismissibleFailureCount, 2);
      final dismissed = await outbox.dismissResolvedFailures();
      expect(dismissed, 2);
      await _settle();

      final left = c
          .read(outboxControllerProvider)
          .map((e) => e.localOperationId)
          .toSet();
      expect(left, {
        'retry-1',
        'dead-1',
        'conflict-1',
        'inflight-1',
        'pay-1',
      }, reason: 'nothing whose outcome is unknown or unproven may disappear');
      expect(
        outbox.retryableFailureCount,
        2,
        reason: 'the transport failure and the dead entry are still retryable',
      );
    });

    test('B2 an entry with an UNKNOWN error code is never dismissed', () async {
      final prefs = await _seed([
        _entry(
          localOperationId: 'unknown-1',
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'some_code_this_build_never_saw',
        ),
      ]);
      final c = _container(prefs);
      final outbox = c.read(outboxControllerProvider.notifier);
      await _settle();

      expect(outbox.dismissibleFailureCount, 0);
      expect(await outbox.dismissResolvedFailures(), 0);
      await _settle();
      expect(c.read(outboxControllerProvider), hasLength(1));
    });
  });

  group('C. retry is unchanged and never re-keys', () {
    test('C1 dismissing does not retry, and a permanent rejection is still '
        'never re-sent', () async {
      final prefs = await _seed([
        ..._sixStale(),
        _entry(
          localOperationId: 'retry-1',
          syncState: OutboxSyncState.rejected,
          lastErrorCode: 'transport',
        ),
      ]);
      final c = _container(prefs);
      final outbox = c.read(outboxControllerProvider.notifier);
      await _settle();

      await outbox.dismissResolvedFailures();
      await _settle();

      final left = c.read(outboxControllerProvider);
      expect(left, hasLength(1));
      expect(
        left.single.localOperationId,
        'retry-1',
        reason:
            'the retryable one keeps its ORIGINAL identity — dismissal never '
            'mints a new operation id and never creates a second server order',
      );
    });
  });

  group('G. the corrupt sibling is untouched', () {
    test(
      'G1 an unreadable entry survives a dismissal write byte-for-byte',
      () async {
        const corrupt = <String, Object?>{'id': 'broken', 'device_id': 'x'};
        SharedPreferences.setMockInitialValues(<String, Object>{
          _prefsKey: jsonEncode(<String, Object?>{
            'version': SharedPrefsOutboxStore.schemaVersion,
            'entries': [for (final e in _sixStale()) e.toJson(), corrupt],
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsOutboxStore(prefs);
        final c = _container(prefs);
        final outbox = c.read(outboxControllerProvider.notifier);
        await _settle();

        expect(
          store.unreadableRecordCount(_scopeKey),
          1,
          reason: 'the operator surface counts it before the dismissal',
        );

        await outbox.dismissResolvedFailures();
        await _settle();

        expect(
          store.unreadableRecordCount(_scopeKey),
          1,
          reason:
              'a record we cannot read is not a record we may destroy — clearing '
              'the readable ones must not overwrite it',
        );
        final raw = jsonDecode(prefs.getString(_prefsKey)!) as Map;
        final entries = (raw['entries'] as List).cast<Object?>();
        expect(
          entries.any(
            (e) => e is Map && e['id'] == 'broken' && e['device_id'] == 'x',
          ),
          isTrue,
          reason: 'preserved verbatim',
        );
      },
    );
  });
}
