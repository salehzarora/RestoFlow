import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_pos/src/data/durable_outbox_store.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';

/// POS-DEFINITIVE-REJECTION-PUSH-BOUNDARY-FIX-025 — Codex HIGH.
///
/// 024 closed `retryEntry`, `retryAllFailed` and the automatic sweep, but
/// `OutboxController.pushEntry` is a PUBLIC controller boundary and stayed open.
/// A caller reaching it directly — the "Sync now" callback captured while the
/// entry was still retryable, a sweep variant, any future call site — could
/// still flip a definitively-refused entry back to `inFlight`, spend another
/// transport attempt, and overwrite the recorded verdict with a fresh one.
///
/// These drive the REAL chain: a typed transport error or a structured refusal
/// out of a real transport, through `RealOutboxRepository`, into the real
/// `OutboxController`, and then straight at `pushEntry`.
const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// A code deliberately ABSENT from kPermanentRejectionCodes.
const String _futureCode = 'future_canonical_refusal';

class _CountingTransport implements SyncRpcTransport {
  _CountingTransport(this._steps);
  final List<Object> _steps;
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return <String, dynamic>{'ok': false};
    final step = _steps[pushes < _steps.length ? pushes : _steps.length - 1];
    pushes++;
    if (step is SyncTransportException) throw step;
    final op = (params['p_operations'] as List).first as Map;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          ...(step as Map).cast<String, Object?>(),
        },
      ],
      'server_ts': '2026-08-02T09:00:01Z',
    };
  }
}

Map<String, Object?> get _accepted => <String, Object?>{
  'ok': true,
  'status': 'applied',
};

Map<String, Object?> get _futureRefusal => <String, Object?>{
  'ok': false,
  'status': 'rejected',
  'error': _futureCode,
  'entity': 'order',
};

// Pass B fixture honesty: kind `auth` is minted by the real transport only
// for a session-class 42501 message, so the fake carries one.
// (OLD: kind auth + bare code '42501', no message.)
const _authFailure = SyncTransportException(
  SyncTransportErrorKind.auth,
  code: '42501',
  message: 'sync_push: PIN session is not valid (inactive/ended/expired)',
);
const _transientFailure = SyncTransportException(
  SyncTransportErrorKind.transient,
);

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

OutboxEntry _seed() => OutboxEntry(
  id: 'e1',
  deviceId: 'dev-1',
  localOperationId: 'op-1',
  operationType: 'order.submit',
  targetEntity: 'order',
  targetId: 'order-1',
  payloadJson: '{}',
  summary: const OrderSummary(
    orderNumber: '#3F7A2C',
    orderType: OrderType.takeaway,
    tableLabel: null,
    itemCount: 1,
    subtotalMinor: 4200,
    currencyCode: 'ILS',
  ),
  syncState: OutboxSyncState.pending,
  clientCreatedAt: DateTime.utc(2026, 8, 2),
);

/// A real repository + real controller over [steps], with the seed enqueued and
/// pushed exactly once. Returns the controller, the transport and the push
/// count observed after that first delivery.
Future<({OutboxController controller, _CountingTransport transport, int after})>
_pushedOnce(List<Object> steps) async {
  final transport = _CountingTransport(steps);
  final repo = RealOutboxRepository(transport, _session, store: _MemoryStore());
  final container = ProviderContainer(
    overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await repo.enqueue(_seed());
  final controller = container.read(outboxControllerProvider.notifier);
  await controller.pushEntry('e1');
  return (
    controller: controller,
    transport: transport,
    after: transport.pushes,
  );
}

void main() {
  group('A. a definitive verdict closes the PUSH boundary itself', () {
    test('025-A1 a typed AUTH failure (now AUTH_HOLD) cannot be pushed again '
        'directly [POS-OFFLINE-OPERATIONS-002]', () async {
      // UPDATED CONTRACT (was: auth => rejected + definitive verdict).
      // AUTH_HOLD keeps the SAME push-boundary guarantee this test exists
      // for — no direct push may spend another transport attempt on a
      // session the server refused — while the entry is HELD verbatim
      // (pending, not rejected) until a fresh online sign-in releases it.
      final r = await _pushedOnce(const [_authFailure]);
      final before = r.controller.entryById('e1')!;
      expect(before.syncState, OutboxSyncState.authHold);
      expect(before.outcome, PosOrderOutcome.pending);
      expect(before.lastErrorKind, 'auth');

      // THE DEFECT: a caller reaching the public boundary directly.
      await r.controller.pushEntry('e1');

      expect(
        r.transport.pushes,
        r.after,
        reason: 'no second transport attempt may be spent on a held entry',
      );
      final after = r.controller.entryById('e1')!;
      expect(after.syncState, OutboxSyncState.authHold);
      expect(
        after.syncState,
        isNot(OutboxSyncState.inFlight),
        reason: 'the entry must never re-enter the in-flight lifecycle',
      );
      expect(after.outcome, PosOrderOutcome.pending);
      expect(after.lastErrorKind, 'auth', reason: 'diagnosis is preserved');
      expect(after.lastErrorCode, before.lastErrorCode);
      expect(
        after.attemptCount,
        before.attemptCount,
        reason: 'no attempt burnt',
      );
      expect(after.localOperationId, 'op-1', reason: 'no new identity');
      expect(
        after.isDefinitiveNoServerOrder,
        isFalse,
        reason: 'a hold is not a verdict about the order',
      );
    });

    test(
      '025-A2 an UNKNOWN structured verdict cannot be pushed again',
      () async {
        final r = await _pushedOnce([_futureRefusal]);
        final before = r.controller.entryById('e1')!;
        expect(
          kPermanentRejectionCodes.contains(_futureCode),
          isFalse,
          reason: 'no allowlist entry exists — the guard must not need one',
        );
        expect(before.lastErrorKind, kServerVerdictErrorKind);

        await r.controller.pushEntry('e1');

        expect(r.transport.pushes, r.after);
        final after = r.controller.entryById('e1')!;
        expect(after.syncState, OutboxSyncState.rejected);
        expect(after.lastErrorKind, kServerVerdictErrorKind);
        expect(after.lastErrorCode, _futureCode);
        expect(after.attemptCount, before.attemptCount);
        expect(after.localOperationId, 'op-1');
      },
    );

    test(
      '025-A3 a STALE CALLBACK holding the old entry cannot revive it',
      () async {
        // The real shape of the bug: the widget captured a callback while the
        // entry was still retryable, the verdict landed, and the callback fired.
        final transport = _CountingTransport(const [
          _transientFailure,
          _authFailure,
        ]);
        final repo = RealOutboxRepository(
          transport,
          _session,
          store: _MemoryStore(),
        );
        final container = ProviderContainer(
          overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        await repo.enqueue(_seed());
        final controller = container.read(outboxControllerProvider.notifier);

        await controller.pushEntry('e1');
        // The caller captures THIS object: retryable, no verdict.
        final captured = controller.entryById('e1')!;
        expect(captured.outcome, PosOrderOutcome.deliveryUnconfirmed);
        expect(captured.hasDefinitiveVerdict, isFalse);

        // The AUTH_HOLD arrives ([POS-OFFLINE-OPERATIONS-002]: was a
        // definitive rejection — the boundary contract is identical).
        await controller.retryEntry('e1');
        expect(controller.entryById('e1')!.syncState, OutboxSyncState.authHold);
        final settled = transport.pushes;

        // The stale callback fires, still holding the retryable object.
        await controller.pushEntry(captured.id);

        expect(
          transport.pushes,
          settled,
          reason:
              'the guard must re-read the CURRENT entry, not trust the captured '
              'one — the current held state wins',
        );
        expect(controller.entryById('e1')!.syncState, OutboxSyncState.authHold);
      },
    );
  });

  group('B. every legitimate push still works', () {
    test('025-B1 a PENDING entry still pushes', () async {
      final transport = _CountingTransport([_accepted]);
      final repo = RealOutboxRepository(
        transport,
        _session,
        store: _MemoryStore(),
      );
      final container = ProviderContainer(
        overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await repo.enqueue(_seed());
      final controller = container.read(outboxControllerProvider.notifier);
      await controller.pushEntry('e1');
      expect(transport.pushes, greaterThan(0));
      expect(controller.entryById('e1')!.outcome, PosOrderOutcome.accepted);
    });

    test('025-B2 a DELIVERY-UNCONFIRMED entry still pushes again', () async {
      final r = await _pushedOnce(const [_transientFailure]);
      expect(
        r.controller.entryById('e1')!.outcome,
        PosOrderOutcome.deliveryUnconfirmed,
      );

      await r.controller.pushEntry('e1');
      expect(
        r.transport.pushes,
        greaterThan(r.after),
        reason: 'delivery is unknown — re-asking the same identity is the fix',
      );
      expect(r.controller.entryById('e1')!.localOperationId, 'op-1');
    });

    test('025-B3 SERVER and UNKNOWN uncertainty still push', () async {
      for (final step in const [
        SyncTransportException(SyncTransportErrorKind.server, code: 'P0001'),
        SyncTransportException(SyncTransportErrorKind.unknown),
      ]) {
        final r = await _pushedOnce([step]);
        await r.controller.pushEntry('e1');
        expect(r.transport.pushes, greaterThan(r.after), reason: '$step');
      }
    });

    test('025-B4 an UNREADABLE response still pushes', () async {
      final r = await _pushedOnce(const [<String, Object?>{}]);
      expect(
        r.controller.entryById('e1')!.outcome,
        PosOrderOutcome.deliveryUnconfirmed,
      );
      await r.controller.pushEntry('e1');
      expect(r.transport.pushes, greaterThan(r.after));
    });

    test(
      '025-B5 a LEGACY failed row with no classification still pushes',
      () async {
        final store = _MemoryStore()
          ..saved['dev-1'] = [
            _seed()
                .copyWith(
                  syncState: OutboxSyncState.rejected,
                  lastErrorCode: 'some_old_code',
                )
                .toJson(),
          ];
        final transport = _CountingTransport([_accepted]);
        final repo = RealOutboxRepository(transport, _session, store: store);
        final container = ProviderContainer(
          overrides: [outboxRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        final controller = container.read(outboxControllerProvider.notifier);
        final loaded = (await repo.recentEntries()).single;
        expect(loaded.hasDefinitiveVerdict, isFalse);

        await controller.pushEntry('e1');
        expect(
          transport.pushes,
          greaterThan(0),
          reason: 'a row we cannot classify must stay reconcilable',
        );
      },
    );
  });
}
