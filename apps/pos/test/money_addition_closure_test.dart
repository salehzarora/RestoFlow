import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/addition_journal_store.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MONEY-CODEX-FINAL-CLOSURE-005 — the three remaining Addition defects.
///
/// F1  STARTUP HYDRATION WINDOW. `AdditionController.build()` kicked off
///     `_restoreJournal()` and immediately returned `const AdditionState()` —
///     phase `idle`, no cart lock, no blocked orders. Everything the durable
///     journal knows arrives one or more microtasks LATER, after
///     `journal.load()`. In that window the observable state says "nothing is
///     pending" and the cashier can add cart lines, enter Add-items for the very
///     order that has an unresolved amendment, and take a payment against a
///     total the server is about to change. On a real device that window is a
///     disk read, and a cold start is exactly when a till gets tapped.
///
/// F2  INCOMPLETE APPLIED RESULTS AND UNKNOWN REFUSAL CODES. `_appliedResult`
///     accepted any row with `status == 'applied' && ok == true` and then read
///     `round_id`/`round_number` defensively — so an applied row with a null,
///     blank or missing round still closed the flow, printed nothing, and left
///     the operation looking finished. And `_definitiveRefusal` accepted ANY
///     non-blank error string on a rejecting status, so a code this build has
///     never seen became a terminal verdict: the identity is released and the
///     next send mints a NEW one for an operation the server may have applied.
///
/// F4  PREPARED RECORDS, QUEUE ADVANCEMENT, SAME-ORDER CONFLICT. The restore
///     filtered on `wasDispatched`, so a `prepared` record — persisted BEFORE
///     the first dispatch, which is precisely the proof that the identity
///     already exists — was dropped on restart. Only the oldest record was ever
///     made active and nothing advanced the queue when it closed, so the second
///     order's amendment stayed invisible for the rest of the session. And two
///     non-terminal records for the SAME order were treated as an ordinary
///     queue instead of the fail-closed conflict they are.
///
/// Money fixture (002A formula B): base 4500 + paid modifier 1500, quantity 2
/// => 12000.
const kBase = 4500;
const kDelta = 1500;
const kUnit = 6000; // 4500 + 1500, written out
const kLineTotal = 12000; // 6000 x 2, written out

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'food',
  categoryName: 'Food',
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: kDelta,
);

/// A transport that counts every invoke and answers from a scripted queue.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport([this._script = const <Object?>[]]);
  final List<Object?> _script;
  int calls = 0;
  final List<String> pushedOperationIds = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    // The container runs in REAL mode, so `posMenuProvider` fetches `pos_menu`
    // through this same transport. Answer it with an empty-but-valid menu and
    // do NOT let it consume a scripted sync_push response.
    if (function == 'pos_menu') {
      return <String, Object?>{
        'ok': true,
        'currency_code': 'ILS',
        'categories': <Object?>[],
        'items': <Object?>[],
        'modifiers': <Object?>[],
        'modifier_options': <Object?>[],
      };
    }
    calls++;
    final ops = params['p_operations'];
    if (ops is List) {
      for (final o in ops) {
        if (o is Map && o['local_operation_id'] is String) {
          pushedOperationIds.add(o['local_operation_id'] as String);
        }
      }
    }
    if (_script.isEmpty) return null;
    final next = _script.removeAt(0);
    if (next is Exception) throw next;
    return next;
  }
}

PosOrderDetail _detail({String orderId = 'o-1', String roundId = 'r-2'}) =>
    PosOrderDetail(
      orderId: orderId,
      orderCode: '#O00001',
      orderType: 'dine_in',
      status: 'preparing',
      revision: 2,
      currencyCode: 'ILS',
      subtotalMinor: 2500,
      discountTotalMinor: 0,
      taxTotalMinor: 0,
      grandTotalMinor: 2500,
      rounds: [
        PosOrderDetailRound(
          roundId: roundId,
          roundNumber: 2,
          status: 'submitted',
        ),
      ],
      items: const [],
    );

class _FakeDetailRepo implements OrderDetailRepository {
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) {
    fetches++;
    return Future.value(_detail(orderId: orderId));
  }
}

/// THE DELAYED JOURNAL SEAM (F1). `load` does not complete until the test says
/// so — a deterministic stand-in for the real disk read, with no sleeps.
class _DelayedJournalStore implements PosAdditionJournalStore {
  _DelayedJournalStore(this._records);

  final Map<String, PosAdditionJournalRecord> _records;
  final Completer<void> gate = Completer<void>();
  int loads = 0;

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) async {
    loads++;
    await gate.future;
    return Map<String, PosAdditionJournalRecord>.of(_records);
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {
    _records
      ..clear()
      ..addAll(records);
  }
}

/// A journal that delays its WRITES on demand. `_journalClose` awaits `persist`,
/// and the cart is unlocked for that whole window — which is exactly where a
/// cashier starts the next customer's order. Holding it open makes the D1 window
/// deterministic without any sleep.
class _GatedPersistJournalStore implements PosAdditionJournalStore {
  _GatedPersistJournalStore(this._inner);
  final PosAdditionJournalStore _inner;

  /// Held write, released by the test.
  Completer<void>? hold;

  /// Hold only the write that REMOVES this key — the closing write. A submit
  /// also persists a phase transition first, and gating that one would stop the
  /// flow before the cart is ever released.
  String? holdWhenClosing;

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) =>
      _inner.load(scopeKey);

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {
    final gate = hold;
    final key = holdWhenClosing;
    if (gate != null && key != null && !records.containsKey(key)) {
      hold = null;
      holdWhenClosing = null;
      await gate.future;
    }
    await _inner.persist(scopeKey, records);
  }
}

/// A journal whose load always throws — hydration must NOT fall back to idle.
class _FailingJournalStore implements PosAdditionJournalStore {
  final Completer<void> gate = Completer<void>();

  @override
  Future<Map<String, PosAdditionJournalRecord>> load(String scopeKey) async {
    await gate.future;
    throw StateError('journal unreadable');
  }

  @override
  Future<void> persist(
    String scopeKey,
    Map<String, PosAdditionJournalRecord> records,
  ) async {}
}

PosAdditionJournalRecord _record({
  String localOperationId = 'op-1',
  String orderId = 'o-1',
  PosAdditionJournalPhase phase = PosAdditionJournalPhase.transportUncertain,
  DateTime? createdAt,
  int generation = 1,
  String lineId = 'l-1',
}) => PosAdditionJournalRecord(
  localOperationId: localOperationId,
  orderId: orderId,
  orderCode: '#O00001',
  orderTypeWire: 'dine_in',
  generation: generation,
  itemsJson: const [
    {'menu_item_id': 'burger-meat', 'quantity': 2},
  ],
  lines: [
    CartLineView(
      lineId: lineId,
      menuItemId: 'burger-meat',
      name: 'Burger',
      quantity: 2,
      unitPriceMinor: kBase,
      lineTotalMinor: kLineTotal,
      currencyCode: 'ILS',
      modifiers: const [_meat240],
    ),
  ],
  prepByItemId: const {},
  expectedDeltaMinor: kLineTotal,
  currencyCode: 'ILS',
  clientCreatedAt: createdAt ?? DateTime.utc(2026, 8, 6, 12),
  phase: phase,
);

ProviderContainer _container({
  required PosAdditionJournalStore? journal,
  _FakeTransport? transport,
  OrderDetailRepository? details,
  // SELF-REVIEW CORRECTION. This defaulted to `['op-1']`, and
  // `FixedClientIdGenerator` CLAMPS on its last element instead of throwing —
  // so a production regression that re-minted an identity would hand out 'op-1'
  // again and every "the replay carries the ORIGINAL identity" assertion would
  // still pass green, blind to the one failure this whole program exists to
  // prevent. The second id exists solely to make a re-mint visible.
  List<String> mintedIds = const ['op-1', 'RE-MINTED-SECOND-IDENTITY'],
}) {
  final c = ProviderContainer(
    overrides: [
      // Deterministic identities so a scripted response can name the operation
      // the controller actually minted.
      clientIdGeneratorProvider.overrideWithValue(
        FixedClientIdGenerator(mintedIds),
      ),
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport ?? _FakeTransport()),
      posSyncSessionProvider.overrideWithValue(_session),
      orderDetailRepositoryProvider.overrideWithValue(
        details ?? _FakeDetailRepo(),
      ),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
      if (journal != null)
        additionJournalStoreProvider.overrideWithValue(journal),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

/// One applied result row exactly as `public.sync_push` merges it: the RPC's
/// own object plus `{local_operation_id, operation_type, status,
/// idempotency_replay}`.
Map<String, Object?> _appliedRow({
  String localOp = 'op-1',
  String orderId = 'o-1',
  Object? roundId = 'r-2',
  Object? roundNumber = 2,
  Object? ok = true,
  bool includeRoundId = true,
  bool includeRoundNumber = true,
  String operationType = 'order.items_add',
  String status = 'applied',
}) => <String, Object?>{
  'local_operation_id': localOp,
  'operation_type': operationType,
  'status': status,
  'ok': ok,
  'order_id': orderId,
  if (includeRoundId) 'round_id': roundId,
  if (includeRoundNumber) 'round_number': roundNumber,
  'added_item_count': 1,
  'revision': 3,
  'idempotency_replay': false,
};

Map<String, Object?> _envelope(List<Object?> results) => <String, Object?>{
  'ok': true,
  'results': results,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // F1 — THE STARTUP HYDRATION WINDOW
  // =========================================================================
  group('F1. nothing may be mutated before the journal is hydrated', () {
    test('F1a a delayed hydration BLOCKS cart add, Add-items entry, quantity '
        'edits and any dispatch — and mints no identity', () async {
      final journal = _DelayedJournalStore({'op-1': _record()});
      final transport = _FakeTransport();
      final c = _container(journal: journal, transport: transport);

      // Construct the real controller. Its build() runs synchronously; the
      // journal read has NOT completed.
      final addition = c.read(additionControllerProvider.notifier);
      final hydratingState = c.read(additionControllerProvider);

      // The restore is deliberately deferred one microtask so that NOTHING it
      // does runs during build (Riverpod forbids cross-provider writes there).
      // The gate, however, is closed synchronously — asserted below.
      await Future<void>.microtask(() {});
      expect(
        journal.loads,
        1,
        reason:
            'hydration really is in flight for this assertion to mean '
            'anything',
      );
      expect(
        hydratingState.phase,
        isNot(AdditionPhase.idle),
        reason:
            'THE DEFECT: the controller published an ordinary idle state while '
            'the durable journal was still being read, so every gate that asks '
            '"is anything pending?" answered no',
      );
      expect(
        hydratingState.isHydrating,
        isTrue,
        reason: 'the gate must be observable synchronously, before any await',
      );

      // ---- CART MUTATIONS ARE REFUSED
      final cart = c.read(cartControllerProvider.notifier);
      expect(
        cart.addItem(_burger),
        isNot(CartMutationResult.applied),
        reason:
            'a line typed now is not covered by any journal we have not read '
            'yet, and the restored attempt would then own — and destroy — it',
      );
      expect(
        cart.addItemWithModifiers(_burger, const [_meat240]),
        isNot(CartMutationResult.applied),
      );
      // Quantity, note and clear are separate entry points and each is gated.
      expect(
        cart.increaseQuantity('line-0'),
        isNot(CartMutationResult.applied),
        reason: 'a quantity edit changes money and is refused too',
      );
      expect(
        cart.decreaseQuantity('line-0'),
        isNot(CartMutationResult.applied),
      );
      expect(
        cart.updateLineNote('line-0', 'no onions'),
        isNot(CartMutationResult.applied),
      );
      expect(cart.clear(), isNot(CartMutationResult.applied));
      expect(
        c.read(cartControllerProvider).lines,
        isEmpty,
        reason: 'nothing reached the cart',
      );
      expect(
        c.read(cartControllerProvider).lockedByAddition,
        isTrue,
        reason:
            'the cart reports itself locked, so the UI disables its controls',
      );

      // ---- ADD-ITEMS ENTRY IS REFUSED
      expect(
        await addition.enterForOrder('o-1'),
        AdditionEntryResult.blockedHydrating,
        reason:
            'entering for the very order whose amendment we have not yet read '
            'is the worst case: it would look like a fresh attempt',
      );

      // ---- NOTHING DISPATCHED, NO IDENTITY MINTED
      final submitted = await addition.submit();
      expect(submitted.applied, isFalse);
      expect(
        transport.calls,
        0,
        reason: 'no network operation may begin before hydration completes',
      );
      expect(
        transport.pushedOperationIds,
        isEmpty,
        reason: 'nothing carrying an identity reached the wire',
      );
      expect(c.read(additionControllerProvider).attempt, isNull);
      // AND THE GENERATOR WAS NEVER ASKED. `pushedOperationIds` only records
      // what was SENT, so a minted-but-unsent id would be invisible to it. The
      // first id is still unissued, which proves no identity was created.
      expect(
        c.read(clientIdGeneratorProvider).newId(),
        'op-1',
        reason:
            'the generator is still on its first id — nothing consumed one '
            'during the hydration window',
      );

      // ---- COMPLETE THE LOAD
      journal.gate.complete();
      await _settle();

      final after = c.read(additionControllerProvider);
      expect(after.isHydrating, isFalse, reason: 'the gate is released');
      expect(
        after.attempt?.localOperationId,
        'op-1',
        reason: 'the restored amendment is now active',
      );
      expect(
        c.read(cartControllerProvider).lockedByAddition,
        isTrue,
        reason:
            'and its cart ownership is held by the RESTORED attempt (F1/004)',
      );
      expect(addition.blockedOrderIds, contains('o-1'));
    });

    test('F1b hydration that FAILS never becomes ordinary idle', () async {
      final journal = _FailingJournalStore();
      final c = _container(journal: journal);
      final addition = c.read(additionControllerProvider.notifier);
      expect(c.read(additionControllerProvider).isHydrating, isTrue);

      journal.gate.complete();
      await _settle();

      final s = c.read(additionControllerProvider);
      expect(
        s.phase,
        isNot(AdditionPhase.idle),
        reason:
            'a journal we could not read is not an empty journal — treating it '
            'as one silently frees every identity it held',
      );
      expect(s.hydrationFailed, isTrue);
      expect(
        await addition.enterForOrder('o-1'),
        isNot(AdditionEntryResult.entered),
        reason: 'no new Addition identity may be created on an unknown journal',
      );
      expect(
        c.read(cartControllerProvider.notifier).addItem(_burger),
        isNot(CartMutationResult.applied),
        reason: 'and the cart stays closed until an operator recovers it',
      );
    });

    test('F1c with NO durable journal wired the pre-005 behaviour is kept — '
        'the till starts idle and sells immediately', () async {
      final c = _container(journal: null);
      final s = c.read(additionControllerProvider);
      expect(s.phase, AdditionPhase.idle);
      expect(s.isHydrating, isFalse);
      expect(
        c.read(cartControllerProvider.notifier).addItem(_burger),
        CartMutationResult.applied,
        reason:
            'demo mode and every test without a store must not pay for a gate '
            'that guards a store they do not have',
      );
    });

    test(
      'F1d an EMPTY hydrated journal releases the gate completely',
      () async {
        final journal = _DelayedJournalStore(
          <String, PosAdditionJournalRecord>{},
        );
        final c = _container(journal: journal);
        c.read(additionControllerProvider);
        expect(
          c.read(cartControllerProvider.notifier).addItem(_burger),
          isNot(CartMutationResult.applied),
        );

        journal.gate.complete();
        await _settle();

        expect(c.read(additionControllerProvider).phase, AdditionPhase.idle);
        expect(
          c.read(cartControllerProvider.notifier).addItem(_burger),
          CartMutationResult.applied,
          reason: 'a till with no unresolved amendment must sell normally',
        );
      },
    );
  });

  // =========================================================================
  // F2 — ONLY A COMPLETE APPLIED RESULT OR AN ALLOWLISTED REFUSAL IS DEFINITIVE
  // =========================================================================
  group('F2. an incomplete or unrecognised response is OUTCOME-UNKNOWN', () {
    /// Builds one addition and submits it against [response].
    Future<(ProviderContainer, _FakeTransport, AdditionResult)> submitAgainst(
      Object? response,
    ) async {
      final journal = InMemoryAdditionJournalStore();
      final transport = _FakeTransport(<Object?>[response]);
      final c = _container(journal: journal, transport: transport);
      // Build the controller FIRST, then let hydration settle — reading it is
      // what starts hydration, so settling before the read settles nothing.
      final addition = c.read(additionControllerProvider.notifier);
      await _settle();
      expect(await addition.enterForOrder('o-1'), AdditionEntryResult.entered);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_meat240]);
      cart.increaseQuantity(c.read(cartControllerProvider).lines.single.lineId);
      expect(
        c.read(cartControllerProvider).lines.single.lineTotalMinor,
        kLineTotal,
      );
      final result = await addition.submit();
      return (c, transport, result);
    }

    /// Every assertion an OUTCOME-UNKNOWN response must satisfy.
    ///
    /// HONESTY NOTE (self-review). Not every case below is a REGRESSION guard.
    /// The pre-005 `_appliedResult`/`_definitiveRefusal` pair already returned
    /// unknown for a wrong operation id, a non-true `ok`, an unknown status and
    /// an unparseable envelope, so F2-5, F2-6b, F2-8 and F2-9 are
    /// CHARACTERIZATION — they pin behaviour that was already correct and would
    /// not fail on a revert. The cases that genuinely discriminate the 005 fix
    /// are F2-1/2/2b/3/4 (round completeness), F2-6 (target-order match),
    /// F2-7 (unknown refusal code) and F2-10 (the parser exception, which used
    /// to escape `_submit` entirely).
    Future<void> expectUncertain(Object? response, String label) async {
      final (c, transport, result) = await submitAgainst(response);
      final addition = c.read(additionControllerProvider.notifier);
      final s = c.read(additionControllerProvider);
      final opId = s.attempt?.localOperationId;

      expect(result.applied, isFalse, reason: '$label: not applied');
      expect(
        s.dispatched,
        isTrue,
        reason: '$label: it REACHED the wire, so the server may own it',
      );
      expect(s.attempt, isNotNull, reason: '$label: the identity is retained');
      expect(
        s.attempt!.lines.single.lineTotalMinor,
        kLineTotal,
        reason: '$label: the frozen payload is retained byte-for-byte',
      );
      expect(
        addition.exit(),
        isFalse,
        reason: '$label: exit() must not release an operation of unknown fate',
      );
      expect(
        c.read(cartControllerProvider).lockedByAddition,
        isTrue,
        reason: '$label: the cart stays owned',
      );
      expect(
        c.read(cartControllerProvider).lines,
        isNotEmpty,
        reason: '$label: nothing was cleared',
      );
      expect(
        result.printPayload,
        isNull,
        reason: '$label: no kitchen ticket on an unknown outcome',
      );

      // A RETRY reuses the SAME identity — never a replacement.
      transport.pushedOperationIds.clear();
      await addition.submit();
      expect(
        transport.pushedOperationIds,
        [opId],
        reason: '$label: the replay must carry the ORIGINAL identity',
      );
    }

    test(
      'F2-1 applied with a MISSING round_id is not a settled round',
      () async {
        await expectUncertain(
          _envelope([_appliedRow(includeRoundId: false)]),
          'missing round_id',
        );
      },
    );

    test('F2-2 applied with a BLANK round_id is not a settled round', () async {
      await expectUncertain(
        _envelope([_appliedRow(roundId: '   ')]),
        'blank round_id',
      );
    });

    test('F2-2b applied with a NULL round_id is not a settled round', () async {
      await expectUncertain(
        _envelope([_appliedRow(roundId: null)]),
        'null round_id',
      );
    });

    test(
      'F2-3 applied with a MISSING round_number is not a settled round',
      () async {
        await expectUncertain(
          _envelope([_appliedRow(includeRoundNumber: false)]),
          'missing round_number',
        );
      },
    );

    test(
      'F2-4 applied with a STRING round_number is not a settled round',
      () async {
        await expectUncertain(
          _envelope([_appliedRow(roundNumber: '2')]),
          'string round_number',
        );
      },
    );

    test(
      'F2-5 applied for a DIFFERENT operation identity proves nothing',
      () async {
        await expectUncertain(
          _envelope([_appliedRow(localOp: 'someone-elses-op')]),
          'wrong operation id',
        );
      },
    );

    test('F2-6 applied for a DIFFERENT target order proves nothing', () async {
      await expectUncertain(
        _envelope([_appliedRow(orderId: 'o-999')]),
        'wrong target order',
      );
    });

    test('F2-6b applied with a non-true ok proves nothing', () async {
      await expectUncertain(
        _envelope([_appliedRow(ok: 'true')]),
        'ok is a string',
      );
    });

    test(
      'F2-7 a rejecting status with an UNKNOWN error code is not a verdict',
      () async {
        await expectUncertain(
          _envelope([
            <String, Object?>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'status': 'rejected',
              'ok': false,
              'error': 'some_future_code_this_build_never_saw',
            },
          ]),
          'unknown refusal code',
        );
      },
    );

    test(
      'F2-8 an UNKNOWN status carrying a known-looking error is not a verdict',
      () async {
        await expectUncertain(
          _envelope([
            <String, Object?>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'status': 'queued_for_review',
              'ok': false,
              'error': 'item_unavailable',
            },
          ]),
          'unknown status',
        );
      },
    );

    test(
      'F2-9 a response that cannot be parsed at all is not a verdict',
      () async {
        await expectUncertain('not-an-envelope', 'unparseable envelope');
        await expectUncertain(<String, Object?>{
          'ok': true,
          'results': 'not-a-list',
        }, 'results is not a list');
      },
    );

    test('F2-10 a response whose parse THROWS is not a verdict', () async {
      // A `results` entry that explodes on member access — the TypeError /
      // cast-failure class the classification boundary must absorb.
      await expectUncertain(_envelope([_ThrowingRow()]), 'parser throws');
    });

    test(
      'F2-11 a KNOWN business rejection IS terminal and cancellable',
      () async {
        final (c, _, result) = await submitAgainst(
          _envelope([
            <String, Object?>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'status': 'rejected',
              'ok': false,
              'error': 'item_unavailable',
            },
          ]),
        );
        final addition = c.read(additionControllerProvider.notifier);
        expect(result.applied, isFalse);
        expect(result.error, 'item_unavailable');
        expect(result.printPayload, isNull, reason: 'a refusal prints nothing');
        expect(
          c.read(additionControllerProvider).dispatched,
          isFalse,
          reason: 'the server said NO, so no round exists and the id is free',
        );
        expect(
          addition.exit(),
          isTrue,
          reason: 'the cashier may abandon a definitive refusal and re-pick',
        );
      },
    );

    test('F2-11b every allowlisted add-items refusal is terminal', () async {
      for (final code in const [
        'item_unavailable',
        'invalid_item_payload',
        'order_not_dine_in',
        'order_not_eligible',
        'order_already_settled',
        'permission_denied',
        'invalid_device_type',
        'modifier_option_not_in_scope',
        'rejected',
      ]) {
        final (c, _, result) = await submitAgainst(
          _envelope([
            <String, Object?>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'status': 'rejected',
              'ok': false,
              'error': code,
            },
          ]),
        );
        expect(result.error, code, reason: '$code is a real server refusal');
        expect(
          c.read(additionControllerProvider).dispatched,
          isFalse,
          reason: '$code releases the identity',
        );
      }
    });

    test('F2-7b a DEAD status is not a verdict either — retry exhaustion is '
        'not a server answer', () async {
      // The repository's own contract for this ledger column
      // (`order_submission.dart`) is that `dead` entries stay retryable: no
      // server verdict was positively recorded. Routing it through the refusal
      // allowlist would free the identity and let the next send build a SECOND
      // round. (No migration writes `dead` today; it was wrong in the unsafe
      // direction regardless.)
      await expectUncertain(
        _envelope([
          <String, Object?>{
            'local_operation_id': 'op-1',
            'operation_type': 'order.items_add',
            'status': 'dead',
            'ok': false,
            'error': 'item_unavailable',
          },
        ]),
        'dead status with an allowlisted code',
      );
    });

    test('F2-7c a row answering under a DIFFERENT operation type, or under '
        'none at all, is not our verdict', () async {
      await expectUncertain(
        _envelope([
          <String, Object?>{
            'local_operation_id': 'op-1',
            'operation_type': 'order.submit',
            'status': 'rejected',
            'ok': false,
            'error': 'item_unavailable',
          },
        ]),
        'foreign operation type',
      );
      await expectUncertain(
        _envelope([
          <String, Object?>{
            'local_operation_id': 'op-1',
            'status': 'applied',
            'ok': true,
            'order_id': 'o-1',
            'round_id': 'r-2',
            'round_number': 2,
          },
        ]),
        'missing operation type',
      );
    });

    test('F2-7d invalid_payload IS a terminal refusal — omitting it from the '
        'allowlist bricked the order forever', () async {
      // `sync_push` emits this for order.items_add when target_id and
      // payload.order_id are not a matching uuid pair, and it is emitted BEFORE
      // the ledger claim — so there is no stored row to replay and the same
      // identity gets the identical answer every time. Classified as unknown the
      // cart stayed locked and Pay / Void / Discount stayed withdrawn on that
      // order for the life of the install.
      final (c, _, result) = await submitAgainst(
        _envelope([
          <String, Object?>{
            'local_operation_id': 'op-1',
            'operation_type': 'order.items_add',
            'status': 'rejected',
            'ok': false,
            'error': 'invalid_payload',
          },
        ]),
      );
      expect(result.error, 'invalid_payload');
      expect(
        c.read(additionControllerProvider).dispatched,
        isFalse,
        reason: 'the server refused before any ledger row existed',
      );
      expect(
        c.read(additionControllerProvider.notifier).exit(),
        isTrue,
        reason: 'so the cashier can abandon it and correct the order',
      );
    });

    test(
      'F2-11c a CONFLICT stays locked — it needs a person, not a retry',
      () async {
        final (c, _, result) = await submitAgainst(
          _envelope([
            <String, Object?>{
              'local_operation_id': 'op-1',
              'operation_type': 'order.items_add',
              'status': 'conflict',
              'ok': false,
              'error': 'conflict',
            },
          ]),
        );
        expect(result.error, 'conflict');
        expect(
          c.read(additionControllerProvider).dispatched,
          isTrue,
          reason:
              'the identity is in use server-side; it can never be re-keyed',
        );
        expect(c.read(additionControllerProvider.notifier).exit(), isFalse);
      },
    );

    test('F2-12 a COMPLETE applied result proceeds: round confirmed, the owned '
        'cart clears exactly once, the journal closes', () async {
      final journal = InMemoryAdditionJournalStore();
      final transport = _FakeTransport(<Object?>[
        _envelope([_appliedRow()]),
      ]);
      final c = _container(journal: journal, transport: transport);
      // Build the controller FIRST, then let hydration settle — reading it is
      // what starts hydration, so settling before the read settles nothing.
      final addition = c.read(additionControllerProvider.notifier);
      await _settle();
      expect(await addition.enterForOrder('o-1'), AdditionEntryResult.entered);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_meat240]);
      cart.increaseQuantity(c.read(cartControllerProvider).lines.single.lineId);

      final result = await addition.submit();

      expect(result.applied, isTrue);
      expect(result.roundNumber, 2);
      expect(
        result.printPayload?.roundId,
        'r-2',
        reason: 'a COMPLETE result carries the round the ticket is keyed on',
      );
      expect(
        c.read(cartControllerProvider).lines,
        isEmpty,
        reason: 'the owned cart clears on verified reconciliation',
      );
      expect(
        c.read(cartControllerProvider).lockedByAddition,
        isFalse,
        reason: 'and the lock is released with it',
      );
      expect(
        await journal.load(_session.deviceId),
        isEmpty,
        reason: 'the journal record closes exactly once',
      );
      expect(addition.blockedOrderIds, isEmpty);
    });
  });

  // =========================================================================
  // F4 — EVERY ACTIONABLE RECORD PARTICIPATES; THE QUEUE ADVANCES; SAME-ORDER
  //      RECORDS ARE A FAIL-CLOSED CONFLICT
  // =========================================================================
  group('F4. prepared records, sequencing and same-order conflicts', () {
    const prefsKey = 'restoflow.pos.addition_journal.v1.dev-1';

    /// Seeds REAL SharedPreferences with [records] under the production key, so
    /// a second container over the same prefs IS a process restart.
    Future<SharedPreferences> seed(
      List<PosAdditionJournalRecord> records,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        prefsKey: jsonEncode(<String, Object?>{
          'version': SharedPrefsAdditionJournalStore.schemaVersion,
          'records': <String, Object?>{
            for (final r in records) r.localOperationId: r.toJson(),
          },
        }),
      });
      return SharedPreferences.getInstance();
    }

    test(
      'F4-1 a PREPARED record survives a restart and blocks new work',
      () async {
        final prefs = await seed([
          _record(phase: PosAdditionJournalPhase.prepared),
        ]);
        final c = _container(journal: SharedPrefsAdditionJournalStore(prefs));
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        expect(
          addition.pendingAmendments.map((r) => r.localOperationId),
          ['op-1'],
          reason:
              'a prepared record was persisted BEFORE the first dispatch — that '
              'write is the proof the identity exists, so dropping it on restart '
              'is exactly how a second identity gets minted',
        );
        expect(addition.blockedOrderIds, {'o-1'});
        expect(addition.hasUnresolvedAmendmentFor('o-1'), isTrue);
      },
    );

    test(
      'F4-2 a PREPARED record becomes the resumable active attempt',
      () async {
        final prefs = await seed([
          _record(phase: PosAdditionJournalPhase.prepared),
        ]);
        final transport = _FakeTransport(<Object?>[
          _envelope([_appliedRow()]),
        ]);
        final c = _container(
          journal: SharedPrefsAdditionJournalStore(prefs),
          transport: transport,
        );
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          'op-1',
        );
        expect(
          c.read(cartControllerProvider).lockedByAddition,
          isTrue,
          reason: 'the restored attempt owns its cart',
        );

        await addition.submit();
        expect(
          transport.pushedOperationIds,
          ['op-1'],
          reason: 'resuming replays the SAME identity — never a new one',
        );
      },
    );

    test('F4-3/4/5/6/7 two DIFFERENT orders both restore, oldest first, and '
        'closing the first automatically activates the second', () async {
      final prefs = await seed([
        _record(
          localOperationId: 'op-old',
          orderId: 'o-1',
          createdAt: DateTime.utc(2026, 8, 6, 10),
        ),
        _record(
          localOperationId: 'op-new',
          orderId: 'o-2',
          createdAt: DateTime.utc(2026, 8, 6, 11),
          lineId: 'l-2',
        ),
      ]);
      final transport = _FakeTransport(<Object?>[
        _envelope([_appliedRow(localOp: 'op-old', orderId: 'o-1')]),
        _envelope([
          _appliedRow(localOp: 'op-new', orderId: 'o-2', roundId: 'r-2'),
        ]),
      ]);
      final c = _container(
        journal: SharedPrefsAdditionJournalStore(prefs),
        transport: transport,
      );
      c.read(additionControllerProvider);
      await _settle();

      final addition = c.read(additionControllerProvider.notifier);

      // 3 — BOTH restore.
      expect(
        addition.pendingAmendments.map((r) => r.localOperationId).toList(),
        ['op-old', 'op-new'],
        reason: 'durable chronological order, oldest first',
      );
      // 4 — the OLDEST is the active one.
      expect(
        c.read(additionControllerProvider).attempt?.localOperationId,
        'op-old',
      );
      // Both orders are blocked, not just the active one.
      expect(addition.blockedOrderIds, {'o-1', 'o-2'});

      // 5 — closing the first ACTIVATES the second.
      final first = await addition.submit();
      expect(first.applied, isTrue);
      await _settle();

      expect(
        c.read(additionControllerProvider).attempt?.localOperationId,
        'op-new',
        reason:
            'the queue advances on its own — otherwise the second amendment '
            'stays invisible for the rest of the session',
      );
      expect(addition.blockedOrderIds, {'o-2'});
      expect(addition.pendingAmendments.map((r) => r.localOperationId), [
        'op-new',
      ]);

      // 6/7 — entering for o-2 RESUMES it and mints no new identity.
      expect(await addition.enterForOrder('o-2'), AdditionEntryResult.entered);
      expect(
        c.read(additionControllerProvider).attempt?.localOperationId,
        'op-new',
      );
      transport.pushedOperationIds.clear();
      await addition.submit();
      expect(transport.pushedOperationIds, ['op-new']);

      await _settle();
      // 15 — only now do the counts reach zero.
      expect(addition.pendingAmendments, isEmpty);
      expect(addition.blockedOrderIds, isEmpty);
      expect(addition.conflictCount, 0);
    });

    test('F4-8..13 two SAME-ORDER records are a fail-closed conflict', () async {
      final prefs = await seed([
        _record(
          localOperationId: 'op-a',
          orderId: 'o-1',
          createdAt: DateTime.utc(2026, 8, 6, 10),
        ),
        _record(
          localOperationId: 'op-b',
          orderId: 'o-1',
          createdAt: DateTime.utc(2026, 8, 6, 11),
          lineId: 'l-2',
        ),
        _record(
          localOperationId: 'op-other',
          orderId: 'o-9',
          createdAt: DateTime.utc(2026, 8, 6, 12),
          lineId: 'l-3',
        ),
      ]);
      final transport = _FakeTransport();
      final c = _container(
        journal: SharedPrefsAdditionJournalStore(prefs),
        transport: transport,
      );
      c.read(additionControllerProvider);
      await _settle();

      final addition = c.read(additionControllerProvider.notifier);

      // 8/9 — the conflict survived the restart and is reported as one.
      expect(
        addition.conflictingOrderIds,
        {'o-1'},
        reason: 'two live records claim the SAME order; neither may win',
      );
      expect(addition.conflictCount, greaterThan(0));

      // 12 — BOTH records are still stored.
      expect(
        addition.pendingAmendments.map((r) => r.localOperationId).toSet(),
        {'op-a', 'op-b', 'op-other'},
      );
      final stored = await SharedPrefsAdditionJournalStore(
        prefs,
      ).load(_session.deviceId);
      expect(stored.keys.toSet(), {'op-a', 'op-b', 'op-other'});

      // 10 — neither same-order record is dispatched, automatically or on demand.
      expect(
        transport.calls,
        0,
        reason: 'no automatic dispatch may pick a winner',
      );
      expect(
        c.read(additionControllerProvider).attempt?.orderId,
        isNot('o-1'),
        reason: 'a conflicted order is never made the active attempt',
      );

      // 11 — no third identity.
      expect(
        await addition.enterForOrder('o-1'),
        AdditionEntryResult.blockedConflict,
      );
      expect(
        transport.pushedOperationIds,
        isEmpty,
        reason: 'nothing was dispatched for the conflicted order',
      );
      // The generator is the only thing that can prove an id was not MINTED —
      // `pushedOperationIds` would miss one that was created but never sent.
      expect(
        c.read(clientIdGeneratorProvider).newId(),
        'op-1',
        reason: 'no third local_operation_id was generated',
      );

      // 13 — order actions stay blocked for the conflicted order.
      expect(addition.hasUnresolvedAmendmentFor('o-1'), isTrue);
      expect(addition.blockedOrderIds, contains('o-1'));

      // 14 — the UNRELATED order is usable: it is the safe active record.
      expect(c.read(additionControllerProvider).attempt?.orderId, 'o-9');
    });

    test(
      'F4-18 the queue advance NEVER seizes a cart the cashier is using',
      () async {
        // SELF-REVIEW (D1). The advance runs in a continuation after
        // `await _journalClose` — two real SharedPreferences round-trips — and the
        // cart is unlocked for that whole window. Locking whatever it holds would
        // strand the next customer's lines under a DIFFERENT order's identity:
        // every mutation refused, `exit()` refused because the record is
        // dispatched, and the only escape a successful replay over the network
        // whose absence created the record.
        final prefs = await seed([
          _record(
            localOperationId: 'op-old',
            orderId: 'o-1',
            createdAt: DateTime.utc(2026, 8, 6, 10),
          ),
          _record(
            localOperationId: 'op-new',
            orderId: 'o-2',
            createdAt: DateTime.utc(2026, 8, 6, 11),
            lineId: 'l-2',
          ),
        ]);
        final transport = _FakeTransport(<Object?>[
          _envelope([_appliedRow(localOp: 'op-old', orderId: 'o-1')]),
        ]);
        final store = _GatedPersistJournalStore(
          SharedPrefsAdditionJournalStore(prefs),
        );
        final c = _container(journal: store, transport: transport);
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        final cart = c.read(cartControllerProvider.notifier);
        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          'op-old',
        );

        // HOLD the closing write. `_journalClose` awaits it, the cart has
        // already been released, and the queue has not advanced yet — the exact
        // window a real device spends on two SharedPreferences round-trips.
        final closeGate = Completer<void>();
        store
          ..hold = closeGate
          ..holdWhenClosing = 'op-old';
        final first = addition.submit();
        await _settle();

        // The cashier starts the next customer in the freed cart.
        expect(
          cart.addItemWithModifiers(_burger, const [_meat240]),
          CartMutationResult.applied,
          reason: 'the cart really is free at this moment',
        );

        closeGate.complete(); // the write lands; the queue now advances
        expect((await first).applied, isTrue);
        await _settle();

        expect(
          c.read(cartControllerProvider).lines,
          hasLength(1),
          reason: 'the new work is intact',
        );
        expect(
          c.read(cartControllerProvider).lockedByAddition,
          isFalse,
          reason:
              'op-new must NOT have seized it — those lines belong to the '
              'cashier, not to a frozen payload',
        );
        expect(
          c.read(additionControllerProvider).attempt,
          isNull,
          reason: 'activation is DEFERRED, not forced',
        );
        // The record is not lost, and its order stays blocked.
        expect(addition.pendingAmendments.map((r) => r.localOperationId), [
          'op-new',
        ]);
        expect(addition.blockedOrderIds, {'o-2'});

        // Once the cart is free, entering for that order resumes it normally.
        expect(cart.clear(), CartMutationResult.applied);
        expect(
          await addition.enterForOrder('o-2'),
          AdditionEntryResult.entered,
        );
        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          'op-new',
        );
      },
    );

    test(
      'F4-19 resuming a queued record is REFUSED while the cart is busy',
      () async {
        // D2: `enterForOrder` is documented as the actual guarantee, so the
        // resume branch must respect the empty-cart rule every other entry path
        // enforces rather than sitting above it.
        final prefs = await seed([
          _record(
            localOperationId: 'op-prepared',
            orderId: 'o-1',
            phase: PosAdditionJournalPhase.prepared,
            createdAt: DateTime.utc(2026, 8, 6, 10),
          ),
          _record(
            localOperationId: 'op-queued',
            orderId: 'o-2',
            createdAt: DateTime.utc(2026, 8, 6, 11),
            lineId: 'l-2',
          ),
        ]);
        final c = _container(journal: SharedPrefsAdditionJournalStore(prefs));
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        final cart = c.read(cartControllerProvider.notifier);
        expect(addition.exit(), isTrue); // prepared => safe to abandon
        expect(cart.addItem(_burger), CartMutationResult.applied);

        expect(
          await addition.enterForOrder('o-2'),
          AdditionEntryResult.cartNotEmpty,
          reason:
              'a cart holding the cashier\'s work is never silently retargeted',
        );
        expect(c.read(cartControllerProvider).lines, hasLength(1));
        expect(c.read(cartControllerProvider).lockedByAddition, isFalse);
      },
    );

    test(
      'F4-17 the RESUME branch: entering for a queued order between exit() '
      'and the queue advancing resumes it instead of minting a new identity',
      () async {
        // `exit()` resets the state SYNCHRONOUSLY, while `_journalClose` and the
        // queue advance run in a continuation. In that window `state.attempt` is
        // null and a second order's record is still pending — the exact case
        // `enterForOrder`'s resume branch exists for. Without it, entering would
        // reserve a fresh target and the next submit would mint a SECOND identity
        // for an operation the server may already own.
        final prefs = await seed([
          _record(
            localOperationId: 'op-prepared',
            orderId: 'o-1',
            phase: PosAdditionJournalPhase.prepared,
            createdAt: DateTime.utc(2026, 8, 6, 10),
          ),
          _record(
            localOperationId: 'op-queued',
            orderId: 'o-2',
            createdAt: DateTime.utc(2026, 8, 6, 11),
            lineId: 'l-2',
          ),
        ]);
        final transport = _FakeTransport();
        final c = _container(
          journal: SharedPrefsAdditionJournalStore(prefs),
          transport: transport,
        );
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          'op-prepared',
        );

        // A PREPARED record provably never reached the transport, so abandoning
        // it is safe — and it is the only phase where that is true.
        expect(addition.exit(), isTrue);
        expect(
          c.read(additionControllerProvider).attempt,
          isNull,
          reason: 'the window is open: no attempt, queue not yet advanced',
        );

        // SYNCHRONOUSLY, inside that window:
        expect(
          await addition.enterForOrder('o-2'),
          AdditionEntryResult.entered,
        );
        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          'op-queued',
          reason:
              'the QUEUED record was resumed — a fresh reservation would have '
              'made the next submit mint a second identity for o-2',
        );
        expect(
          c.read(clientIdGeneratorProvider).newId(),
          'op-1',
          reason: 'and no identity was generated to do it',
        );
      },
    );

    test(
      'F4-16 unreadable records are counted separately and never dispatched',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          prefsKey: jsonEncode(<String, Object?>{
            'version': SharedPrefsAdditionJournalStore.schemaVersion,
            'records': <String, Object?>{
              'op-1': _record().toJson(),
              'op-broken': <String, Object?>{'local_operation_id': 'op-broken'},
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsAdditionJournalStore(prefs);
        final c = _container(journal: store);
        c.read(additionControllerProvider);
        await _settle();

        final addition = c.read(additionControllerProvider.notifier);
        expect(
          addition.pendingAmendments.map((r) => r.localOperationId),
          ['op-1'],
          reason: 'only the readable record is actionable',
        );
        expect(
          store.unreadableRecordCount(_session.deviceId),
          1,
          reason:
              'and the unreadable one is COUNTED, so "zero pending" can only be '
              'said when it is true',
        );
      },
    );
  });
}

/// A `results` entry whose member access throws — the TypeError/cast-failure
/// class the classification boundary must absorb into outcome-unknown.
class _ThrowingRow implements Map<String, Object?> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('exploding response row');
}
