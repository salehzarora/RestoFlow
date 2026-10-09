import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/state/kds_edit_ack_controller.dart';
import 'package:restoflow_kds/src/state/kds_session.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// ORDER-EDIT-001D — the "Got it" controller (`order.edit_ack`, API_CONTRACT
/// §4.46): the canonical single-op envelope, a strict per-op result parse
/// (applied / superseded by a void / terminal refusal / unknown outcome),
/// operation-id reuse ONLY after an unknown outcome (D-022), per-card keys
/// with sibling coverage, and authoritative reconciliation.

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final FutureOr<Object?> Function(String fn, Map<String, dynamic> p) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

class _FakeSource implements KdsSyncSource {
  _FakeSource({this.throwOnRefresh = false});
  final bool throwOnRefresh;
  int refreshCalls = 0;
  @override
  KdsSyncState get state => KdsSyncState.initial;
  @override
  Stream<KdsSyncState> get states => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {
    refreshCalls++;
    if (throwOnRefresh) throw StateError('refresh down');
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async {}
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

KdsOrderEdit _edit(int number, {String orderId = 'o1'}) => KdsOrderEdit(
  id: '$orderId-e$number',
  orderId: orderId,
  editNumber: number,
  channel: KdsEditChannel.kds,
  ackRequired: true,
);

/// A card carrying an unconfirmed change: [edits] are the pending edits that
/// touched it; [orderPending] every pending edit number of the order.
KdsTicketView _card({
  String orderId = 'o1',
  String unit = 'unassigned',
  List<int> edits = const [1],
  List<int>? orderPending,
  KitchenTicketStatus status = KitchenTicketStatus.inPreparation,
  String? voidedFromStatus,
  bool withChange = true,
  bool withOrderId = true,
}) => KdsTicketView(
  kitchenTicketId: '$orderId:$unit',
  stationId: 'unassigned',
  orderId: withOrderId ? orderId : null,
  orderNumber: '#ABC123',
  status: status,
  voidedFromStatus: voidedFromStatus,
  items: const [KdsItemView(name: 'Burger', quantity: 1)],
  change: withChange
      ? KdsTicketChange(
          pendingEdits: [for (final n in edits) _edit(n, orderId: orderId)],
          orderPendingEditNumbers: orderPending ?? edits,
        )
      : null,
);

Map<String, dynamic> _op(Map<String, dynamic> p) =>
    ((p['p_operations'] as List).single as Map).cast<String, dynamic>();

String _opId(Map<String, dynamic> p) => _op(p)['local_operation_id'] as String;

/// An envelope whose single result echoes the pushed op with [fields].
Object? Function(String, Map<String, dynamic>) _answer(
  Map<String, dynamic> fields,
) =>
    (fn, p) => {
      'ok': true,
      'results': [
        {'local_operation_id': _opId(p), ...fields},
      ],
    };

final _applied2 = _answer({
  'status': 'applied',
  'ok': true,
  'acknowledged_count': 2,
});

(ProviderContainer, _FakeTransport, _FakeSource) _harness(
  FutureOr<Object?> Function(String fn, Map<String, dynamic> p) handler, {
  bool throwOnRefresh = false,
}) {
  final transport = _FakeTransport(handler);
  final source = _FakeSource(throwOnRefresh: throwOnRefresh);
  final container = ProviderContainer(
    overrides: [
      kdsAuthTransportProvider.overrideWithValue(transport),
      kdsSyncSessionProvider.overrideWithValue(_session),
      kdsSyncSourceProvider.overrideWithValue(source),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport, source);
}

void main() {
  test('the envelope is ONE canonical order.edit_ack op: target_id == '
      'payload.order_id, payload exactly {order_id, up_to_edit_number} with '
      'an integer number, and a v4 operation id', () async {
    final (container, transport, _) = _harness(_applied2);
    await container
        .read(kdsEditAckControllerProvider.notifier)
        .acknowledge(_card(edits: [1, 2]));

    final (fn, params) = transport.calls.single;
    expect(fn, 'sync_push');
    expect(params['p_pin_session_id'], 'pin-1');
    expect(params['p_device_id'], 'dev-1');
    final op = _op(params);
    expect(op['operation_type'], 'order.edit_ack');
    expect(op['target_entity'], 'order');
    expect(op['target_id'], 'o1');
    final payload = op['payload'] as Map;
    expect(op['target_id'], payload['order_id']);
    expect(payload.keys.toSet(), {'order_id', 'up_to_edit_number'});
    expect(payload['up_to_edit_number'], isA<int>());
    expect(payload['up_to_edit_number'], 2);
    expect(op['local_operation_id'], matches(_uuidV4));
    expect(op['client_created_at'], isA<String>());
  });

  test('APPLIED with acknowledged_count 2: the card stays pending (never '
      'hidden locally) and the immediate pull runs once', () async {
    final (container, _, source) = _harness(_applied2);
    final card = _card(edits: [2]);
    final result = await container
        .read(kdsEditAckControllerProvider.notifier)
        .acknowledge(card);

    expect(result.outcome, KdsEditAckOutcome.applied);
    expect(result.acknowledgedCount, 2);
    final state = container.read(kdsEditAckControllerProvider);
    expect(state.isPending(card), isTrue);
    expect(state.isFailed(card), isFalse);
    expect(state.pending.keys, [card.changeAlertKey]);
    expect(state.failed, isEmpty);
    expect(source.refreshCalls, 1);
    // The ticket itself is never mutated.
    expect(card.status, KitchenTicketStatus.inPreparation);
    expect(card.change, isNotNull);
  });

  test('APPLIED without a usable acknowledged_count reads as 0 (another KDS '
      'confirmed first)', () async {
    for (final count in <Object?>[null, '2', 1.0]) {
      final (container, _, _) = _harness(
        _answer({'status': 'applied', 'ok': true, 'acknowledged_count': count}),
      );
      final result = await container
          .read(kdsEditAckControllerProvider.notifier)
          .acknowledge(_card());
      expect(result.outcome, KdsEditAckOutcome.applied, reason: '$count');
      expect(result.acknowledgedCount, 0, reason: '$count');
    }
  });

  test('order_voided is SUPERSEDED, not a failure: the key stays pending, no '
      'connection-failure state, and the pull runs', () async {
    final (container, _, source) = _harness(
      _answer({'status': 'rejected', 'ok': false, 'error': 'order_voided'}),
    );
    final card = _card();
    final result = await container
        .read(kdsEditAckControllerProvider.notifier)
        .acknowledge(card);

    expect(result.outcome, KdsEditAckOutcome.superseded);
    expect(result.acknowledgedCount, 0);
    final state = container.read(kdsEditAckControllerProvider);
    expect(state.isPending(card), isTrue);
    expect(state.isFailed(card), isFalse);
    expect(state.failed, isEmpty);
    expect(source.refreshCalls, 1);
  });

  group('a TERMINAL server answer fails with NO reusable id — the retry is a '
      'new operation', () {
    final terminal = <String, Map<String, dynamic>>{
      'invalid_edit_number': {
        'status': 'rejected',
        'ok': false,
        'error': 'invalid_edit_number',
      },
      'permission_denied': {
        'status': 'rejected',
        'ok': false,
        'error': 'permission_denied',
      },
      'invalid_device_type': {
        'status': 'rejected',
        'ok': false,
        'error': 'invalid_device_type',
      },
      'conflict': {'status': 'conflict', 'ok': false, 'error': 'conflict'},
      'dead': {'status': 'dead', 'ok': false},
      'applied with ok=false': {'status': 'applied', 'ok': false},
      'applied with ok missing': {'status': 'applied'},
    };
    for (final MapEntry(key: name, value: fields) in terminal.entries) {
      test(name, () async {
        var attempt = 0;
        final (container, transport, source) = _harness((fn, p) {
          attempt++;
          return attempt == 1
              ? _answer(fields)(fn, p)
              : _answer({'status': 'applied', 'ok': true})(fn, p);
        });
        final notifier = container.read(kdsEditAckControllerProvider.notifier);
        final card = _card();

        final first = await notifier.acknowledge(card);
        expect(first.outcome, KdsEditAckOutcome.failed);
        var state = container.read(kdsEditAckControllerProvider);
        expect(state.isFailed(card), isTrue);
        expect(state.isPending(card), isFalse);
        expect(state.failed.containsKey(card.changeAlertKey), isTrue);
        expect(state.failed[card.changeAlertKey], isNull);
        expect(source.refreshCalls, 0);

        final retry = await notifier.acknowledge(card);
        expect(retry.outcome, KdsEditAckOutcome.applied);
        expect(transport.calls, hasLength(2));
        expect(
          _opId(transport.calls[1].$2),
          isNot(_opId(transport.calls[0].$2)),
        );
        state = container.read(kdsEditAckControllerProvider);
        expect(state.isFailed(card), isFalse);
        expect(state.isPending(card), isTrue);
      });
    }
  });

  group('an UNKNOWN outcome fails and the retry REUSES the same id (D-022 '
      'replay returns the stored result)', () {
    final unknown = <String, Object? Function(String, Map<String, dynamic>)>{
      'a transport throw': (fn, p) => throw StateError('offline'),
      'a non-Map body': (fn, p) => 'garbage',
      'missing results': (fn, p) => {'ok': true},
      'malformed results': (fn, p) => {'ok': true, 'results': 'garbage'},
      'no matching op': (fn, p) => {
        'ok': true,
        'results': [
          {'local_operation_id': 'another-op', 'status': 'applied', 'ok': true},
        ],
      },
    };
    for (final MapEntry(key: name, value: firstAnswer) in unknown.entries) {
      test(name, () async {
        var attempt = 0;
        final (container, transport, source) = _harness((fn, p) {
          attempt++;
          return attempt == 1 ? firstAnswer(fn, p) : _applied2(fn, p);
        });
        final notifier = container.read(kdsEditAckControllerProvider.notifier);
        final card = _card(edits: [1, 2]);

        final first = await notifier.acknowledge(card);
        expect(first.outcome, KdsEditAckOutcome.failed);
        final firstId = _opId(transport.calls[0].$2);
        var state = container.read(kdsEditAckControllerProvider);
        expect(state.isFailed(card), isTrue);
        expect(state.failed[card.changeAlertKey], firstId);
        expect(source.refreshCalls, 0);

        // The timed-out tap may have been applied: the replay of the SAME id
        // returns the stored applied result (with its count).
        final retry = await notifier.acknowledge(card);
        expect(retry.outcome, KdsEditAckOutcome.applied);
        expect(retry.acknowledgedCount, 2);
        expect(_opId(transport.calls[1].$2), firstId);
        state = container.read(kdsEditAckControllerProvider);
        expect(state.failed, isEmpty);
        expect(state.isPending(card), isTrue);
      });
    }
  });

  test(
    'a duplicate tap while in flight (and after applied) sends ONCE',
    () async {
      final gate = Completer<void>();
      final (container, transport, _) = _harness((fn, p) async {
        await gate.future;
        return _applied2(fn, p);
      });
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();

      final first = notifier.acknowledge(card);
      final duplicate = await notifier.acknowledge(card);
      expect(duplicate.outcome, KdsEditAckOutcome.skipped);
      expect(
        container.read(kdsEditAckControllerProvider).isPending(card),
        isTrue,
      );

      gate.complete();
      expect((await first).outcome, KdsEditAckOutcome.applied);
      final again = await notifier.acknowledge(card);
      expect(again.outcome, KdsEditAckOutcome.skipped);
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'sibling coverage: "Got it" on card B (up to 2) covers card A (up to '
    '1) of the SAME order; a newer edit and another order stay open',
    () async {
      final gate = Completer<void>();
      final (container, transport, _) = _harness((fn, p) async {
        await gate.future;
        return _applied2(fn, p);
      });
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final cardA = _card(unit: 'grill', edits: [1], orderPending: [1, 2]);
      final cardB = _card(unit: 'bar', edits: [2], orderPending: [1, 2]);
      final cardE3 = _card(unit: 'fry', edits: [3], orderPending: [1, 2, 3]);
      final otherOrder = _card(orderId: 'o2', edits: [1]);

      final inFlight = notifier.acknowledge(cardB);
      var state = container.read(kdsEditAckControllerProvider);
      expect(state.isPending(cardB), isTrue);
      expect(state.isPending(cardA), isTrue, reason: 'covered by up_to 2');
      expect(state.isPending(cardE3), isFalse, reason: 'a newer edit');
      expect(state.isPending(otherOrder), isFalse);
      // A covered sibling is not re-sent.
      expect(
        (await notifier.acknowledge(cardA)).outcome,
        KdsEditAckOutcome.skipped,
      );

      gate.complete();
      await inFlight;
      state = container.read(kdsEditAckControllerProvider);
      expect(state.isPending(cardA), isTrue);
      expect(state.isPending(cardE3), isFalse);
      expect(transport.calls, hasLength(1));
    },
  );

  test('a covering tap hides an older failure line (failed but now '
      'covered reads as pending)', () async {
    var attempt = 0;
    final (container, _, _) = _harness((fn, p) {
      attempt++;
      if (attempt == 1) throw StateError('offline');
      return _applied2(fn, p);
    });
    final notifier = container.read(kdsEditAckControllerProvider.notifier);
    final cardA = _card(unit: 'grill', edits: [1], orderPending: [1, 2]);
    final cardB = _card(unit: 'bar', edits: [2], orderPending: [1, 2]);

    await notifier.acknowledge(cardA);
    expect(
      container.read(kdsEditAckControllerProvider).isFailed(cardA),
      isTrue,
    );
    await notifier.acknowledge(cardB);
    final state = container.read(kdsEditAckControllerProvider);
    expect(state.isPending(cardA), isTrue);
    expect(state.isFailed(cardA), isFalse);
  });

  test(
    'a refresh failure after APPLIED is swallowed (the poll converges)',
    () async {
      final (container, _, source) = _harness(_applied2, throwOnRefresh: true);
      final card = _card();
      final result = await container
          .read(kdsEditAckControllerProvider.notifier)
          .acknowledge(card);
      expect(result.outcome, KdsEditAckOutcome.applied);
      expect(source.refreshCalls, 1);
      expect(
        container.read(kdsEditAckControllerProvider).isPending(card),
        isTrue,
      );
    },
  );

  group('nothing is sent (skipped)', () {
    test('with no transport', () async {
      final container = ProviderContainer(
        overrides: [
          kdsAuthTransportProvider.overrideWithValue(null),
          kdsSyncSessionProvider.overrideWithValue(_session),
          kdsSyncSourceProvider.overrideWithValue(_FakeSource()),
        ],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(kdsEditAckControllerProvider.notifier)
          .acknowledge(_card());
      expect(result.outcome, KdsEditAckOutcome.skipped);
      expect(container.read(kdsEditAckControllerProvider).pending, isEmpty);
    });

    test('with no session', () async {
      final transport = _FakeTransport(_applied2);
      final container = ProviderContainer(
        overrides: [
          kdsAuthTransportProvider.overrideWithValue(transport),
          kdsSyncSessionProvider.overrideWithValue(null),
          kdsSyncSourceProvider.overrideWithValue(_FakeSource()),
        ],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(kdsEditAckControllerProvider.notifier)
          .acknowledge(_card());
      expect(result.outcome, KdsEditAckOutcome.skipped);
      expect(transport.calls, isEmpty);
    });

    test('for a card with no change, no order id, or a red cancellation '
        'card', () async {
      final (container, transport, _) = _harness(_applied2);
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      for (final card in [
        _card(withChange: false),
        _card(withOrderId: false),
        _card(
          status: KitchenTicketStatus.cancelled,
          voidedFromStatus: 'preparing',
        ),
      ]) {
        expect(
          (await notifier.acknowledge(card)).outcome,
          KdsEditAckOutcome.skipped,
        );
      }
      expect(transport.calls, isEmpty);
      expect(container.read(kdsEditAckControllerProvider).pending, isEmpty);
    });
  });

  group('an UNKNOWN outcome owes its change chit, replayed with the SAME id '
      'once an authoritative pull shows its edits confirmed', () {
    test('owed only with a confirmed board; never replayed while an edit up '
        'to N is still pending on the board; an applied count > 0 is '
        'returned ONCE', () async {
      var attempt = 0;
      final (container, transport, _) = _harness((fn, p) {
        attempt++;
        if (attempt <= 2) throw StateError('reply lost');
        return _applied2(fn, p);
      });
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();

      await notifier.acknowledge(card);
      expect(notifier.owedChits, isEmpty, reason: 'no board, no chit');

      final board = [card, _card(orderId: 'o2')];
      await notifier.acknowledge(card, confirmedBoard: board);
      final opId = _opId(transport.calls[1].$2);
      final owed = notifier.owedChits.single;
      expect(owed.localOperationId, opId);
      expect(owed.orderId, 'o1');
      expect(owed.upToEditNumber, 1);
      expect(owed.board, board);

      // The change still shows: nothing is sent.
      expect(await notifier.replayOwedChits([card]), isEmpty);
      // The card moved on to edit 2 while edit 1 is still pending (the key
      // changed): the lost tap never applied, and a replay now would confirm
      // a change still on the board — nothing is sent.
      final movedOn = _card(edits: [2], orderPending: [1, 2]);
      expect(movedOn.changeAlertKey, isNot(card.changeAlertKey));
      expect(await notifier.replayOwedChits([movedOn]), isEmpty);
      // Another card of the order still shows edit 1 pending.
      final sibling = _card(unit: 'bar', edits: [1]);
      expect(await notifier.replayOwedChits([sibling]), isEmpty);
      expect(transport.calls, hasLength(2));
      expect(notifier.owedChits, hasLength(1));

      // Edits up to 1 confirmed (only a newer edit and another order are
      // pending): the replay runs.
      final due = await notifier.replayOwedChits([
        _card(edits: [2], orderPending: [2]),
        _card(orderId: 'o2'),
      ]);
      expect(due.single.localOperationId, opId);
      expect(_opId(transport.calls[2].$2), opId);
      expect(_op(transport.calls[2].$2)['payload'], {
        'order_id': 'o1',
        'up_to_edit_number': 1,
      });
      expect(notifier.owedChits, isEmpty);
      expect(await notifier.replayOwedChits(const <KdsTicketView>[]), isEmpty);
      expect(transport.calls, hasLength(3));
    });

    test('a replay still UNKNOWN is kept for the next pull, at most 3 '
        'times', () async {
      final (container, transport, _) = _harness(
        (fn, p) => throw StateError('offline'),
      );
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();
      await notifier.acknowledge(card, confirmedBoard: [card]);
      for (var i = 0; i < 3; i++) {
        expect(notifier.owedChits, hasLength(1), reason: 'replay $i');
        expect(
          await notifier.replayOwedChits(const <KdsTicketView>[]),
          isEmpty,
        );
      }
      expect(notifier.owedChits, isEmpty);
      expect(transport.calls, hasLength(4));
      await notifier.replayOwedChits(const <KdsTicketView>[]);
      expect(transport.calls, hasLength(4));
    });

    for (final (name, answer) in [
      (
        'order_voided',
        {'status': 'rejected', 'ok': false, 'error': 'order_voided'},
      ),
      (
        'a refusal',
        {'status': 'rejected', 'ok': false, 'error': 'permission_denied'},
      ),
      ('count 0', {'status': 'applied', 'ok': true, 'acknowledged_count': 0}),
    ]) {
      test(
        'a replay answered with $name is dropped and prints nothing',
        () async {
          var attempt = 0;
          final (container, transport, _) = _harness((fn, p) {
            attempt++;
            if (attempt == 1) throw StateError('reply lost');
            return _answer(answer)(fn, p);
          });
          final notifier = container.read(
            kdsEditAckControllerProvider.notifier,
          );
          final card = _card();
          await notifier.acknowledge(card, confirmedBoard: [card]);
          expect(
            await notifier.replayOwedChits(const <KdsTicketView>[]),
            isEmpty,
          );
          expect(notifier.owedChits, isEmpty);
          await notifier.replayOwedChits(const <KdsTicketView>[]);
          expect(transport.calls, hasLength(2));
        },
      );
    }

    test('a definitive answer to a re-tap of the same operation settles the '
        'owed chit (the tap prints through its own caller)', () async {
      var attempt = 0;
      final (container, transport, _) = _harness((fn, p) {
        attempt++;
        if (attempt == 1) throw StateError('reply lost');
        return _applied2(fn, p);
      });
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();
      await notifier.acknowledge(card, confirmedBoard: [card]);
      final retry = await notifier.acknowledge(card, confirmedBoard: [card]);
      expect(retry.outcome, KdsEditAckOutcome.applied);
      expect(notifier.owedChits, isEmpty);
      expect(await notifier.replayOwedChits(const <KdsTicketView>[]), isEmpty);
      expect(transport.calls, hasLength(2));
    });

    test('a chit owed by another PIN session is dropped unsent (never '
        'attributed to the next person signed in)', () async {
      final sessionHolder = StateProvider<SyncSession?>((ref) => _session);
      var attempt = 0;
      final transport = _FakeTransport((fn, p) {
        attempt++;
        if (attempt == 1) throw StateError('reply lost');
        return _applied2(fn, p);
      });
      final container = ProviderContainer(
        overrides: [
          kdsAuthTransportProvider.overrideWithValue(transport),
          kdsSyncSessionProvider.overrideWith(
            (ref) => ref.watch(sessionHolder),
          ),
          kdsSyncSourceProvider.overrideWithValue(_FakeSource()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();
      await notifier.acknowledge(card, confirmedBoard: [card]);
      expect(notifier.owedChits, hasLength(1));

      container.read(sessionHolder.notifier).state = null;
      expect(await notifier.replayOwedChits(const <KdsTicketView>[]), isEmpty);
      expect(notifier.owedChits, hasLength(1), reason: 'signed out: kept');

      container.read(sessionHolder.notifier).state = const SyncSession(
        pinSessionId: 'pin-2',
        deviceId: 'dev-1',
      );
      expect(await notifier.replayOwedChits(const <KdsTicketView>[]), isEmpty);
      expect(notifier.owedChits, isEmpty);
      expect(transport.calls, hasLength(1));
    });
  });

  group('authoritative reconciliation', () {
    test(
      'drops absent keys (pending AND failed) and keeps present ones',
      () async {
        var attempt = 0;
        final (container, _, _) = _harness((fn, p) {
          attempt++;
          if (attempt == 2) throw StateError('offline');
          return _applied2(fn, p);
        });
        final notifier = container.read(kdsEditAckControllerProvider.notifier);
        final applied = _card(orderId: 'o1');
        final failed = _card(orderId: 'o2');
        final keep = _card(orderId: 'o3');
        await notifier.acknowledge(applied);
        await notifier.acknowledge(failed);
        await notifier.acknowledge(keep);
        var state = container.read(kdsEditAckControllerProvider);
        expect(state.pending.keys.toSet(), {
          applied.changeAlertKey,
          keep.changeAlertKey,
        });
        expect(state.failed.keys, [failed.changeAlertKey]);

        notifier.reconcile([keep.changeAlertKey!]);
        state = container.read(kdsEditAckControllerProvider);
        expect(state.pending.keys, [keep.changeAlertKey]);
        expect(state.failed, isEmpty);

        notifier.reconcile(const <String>[]);
        state = container.read(kdsEditAckControllerProvider);
        expect(state.pending, isEmpty);
      },
    );

    test('a reconcile with nothing stale causes no state churn', () async {
      final (container, _, _) = _harness(_applied2);
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final card = _card();
      await notifier.acknowledge(card);
      final before = container.read(kdsEditAckControllerProvider);
      var notifications = 0;
      container.listen(
        kdsEditAckControllerProvider,
        (_, __) => notifications++,
      );
      notifier.reconcile([card.changeAlertKey!, 'other|e1']);
      expect(
        identical(container.read(kdsEditAckControllerProvider), before),
        isTrue,
      );
      expect(notifications, 0);
    });

    test('the next edit of the same card (e1 -> e2) is a NEW key: dropping '
        'e1 leaves e2 open for its own "Got it"', () async {
      final (container, transport, _) = _harness(_applied2);
      final notifier = container.read(kdsEditAckControllerProvider.notifier);
      final e1 = _card(edits: [1]);
      await notifier.acknowledge(e1);
      final e2 = _card(edits: [2], orderPending: [2]);
      expect(e2.changeAlertKey, isNot(e1.changeAlertKey));
      notifier.reconcile([e2.changeAlertKey!]);
      final state = container.read(kdsEditAckControllerProvider);
      expect(state.isPending(e2), isFalse);
      expect(
        (await notifier.acknowledge(e2)).outcome,
        KdsEditAckOutcome.applied,
      );
      expect(transport.calls, hasLength(2));
    });
  });
}
