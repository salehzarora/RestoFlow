import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_actions.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/data/addition_journal_store.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_prefs.dart';

/// MONEY-DURABLE-ADDITIONS-003C — failing-first proof that an Add-items
/// amendment has no durable identity.
///
/// THE INVARIANT: an Add-items operation must have ONE durable identity and ONE
/// frozen payload from the moment before its first network dispatch until
/// authoritative reconciliation proves its final server state.
///
/// Today `AdditionAttempt` lives only in `AdditionState` on an in-memory
/// Notifier — `AdditionController.build()` returns `const AdditionState()`, and
/// the type appears nowhere else in `apps/pos/lib`. So process death loses the
/// operation id and the frozen payload, and the next submit mints a NEW
/// `local_operation_id` at `addition_controller.dart:465`. That is a SECOND
/// server round for food the kitchen is already cooking.
///
/// The server side is not the problem and is not touched here.
/// `app.add_order_items` already replays the SAME round for the same
/// `(org, device, local_operation_id)`, and `app.sync_push` already replays a
/// terminal row's STORED result verbatim with `idempotency_replay: true`. What
/// is missing is entirely client-side: the identity has to survive to be
/// replayed with.
///
/// Every expected amount below is an INDEPENDENT LITERAL.

// The canonical 002A/003 money fixture.
const kBase = 4500;
const kDelta = 1500;
// 4500 + 1500 = 6000 per unit; 6000 x 2 = 12000. Written out, never computed.
const kLineTotal = 12000;

const _burger = DemoMenuItem(
  id: 'burger-meat',
  name: 'Burger',
  priceMinor: kBase,
  categoryId: 'c1',
  categoryName: 'Food',
);

const _meat240 = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: kDelta,
);

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

/// A transport that records every op and can be scripted per call, including a
/// hard transport failure (the uncertainty case that matters most).
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._responses);
  final List<Object? Function(Map<String, dynamic>)> _responses;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    calls.add(params);
    final handler = _responses.length >= calls.length
        ? _responses[calls.length - 1]
        : _responses.last;
    return handler(params);
  }

  List<Map<String, dynamic>> get additionOps => [
    for (final c in calls)
      for (final op
          in (c['p_operations'] as List).cast<Map<dynamic, dynamic>>())
        if (op['operation_type'] == 'order.items_add')
          op.cast<String, dynamic>(),
  ];

  /// The distinct `local_operation_id`s this transport was asked to send for an
  /// addition. More than one means a duplicate amendment round.
  Set<String> get additionIdentities => {
    for (final op in additionOps) op['local_operation_id'] as String,
  };
}

/// The server APPLIED the operation and named the round.
Object? _applied(Map<String, dynamic> params) {
  final localOp =
      ((params['p_operations'] as List).single as Map)['local_operation_id']
          as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'applied',
        'ok': true,
        'round_id': 'r-2',
        'round_number': 2,
      },
    ],
  };
}

/// The server REPLAYED an already-applied operation: the SAME round comes back,
/// flagged. This is `app.add_order_items`'s documented behaviour for a repeated
/// `(org, device, local_operation_id)`.
Object? _replayApplied(Map<String, dynamic> params) {
  final localOp =
      ((params['p_operations'] as List).single as Map)['local_operation_id']
          as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'applied',
        'ok': true,
        'round_id': 'r-2',
        'round_number': 2,
        'idempotency_replay': true,
      },
    ],
  };
}

/// The transport itself failed — the client CANNOT know whether the server
/// applied the round. This is the uncertainty the whole phase is about.
Object? _transportDown(Map<String, dynamic> params) {
  throw const SyncTransportException(
    SyncTransportErrorKind.transient,
    code: 'offline',
  );
}

PosOrderDetail _detail({String orderId = 'o-1', bool withRound = true}) =>
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
      rounds: withRound
          ? const [
              PosOrderDetailRound(
                roundId: 'r-2',
                roundNumber: 2,
                status: 'submitted',
              ),
            ]
          : const [],
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

PosRecentOrder _order({
  String status = 'preparing',
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosRecentOrder.discovered(
  PosOrderSnapshot(
    orderId: 'o-1',
    orderCode: '#O00001',
    revision: 2,
    status: status,
    settlement: settlement,
    subtotalMinor: 2500,
    discountTotalMinor: 0,
    taxTotalMinor: 0,
    grandTotalMinor: 2500,
    createdAt: DateTime.utc(2026, 8, 6, 12),
    updatedAt: DateTime.utc(2026, 8, 6, 12),
    syncAt: DateTime.utc(2026, 8, 6, 12),
    orderType: 'dine_in',
    tableLabel: 'T1',
    currencyCode: 'ILS',
  ),
);

ProviderContainer _container(
  _FakeTransport transport, {
  SharedPreferences? prefs,
  SharedPreferences? journal,
}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(_session),
      orderDetailRepositoryProvider.overrideWithValue(_FakeDetailRepo()),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
      // The REAL production wiring when a durable store is supplied: the same
      // SharedPreferences across two containers IS a process restart.
      if (prefs != null)
        posRoundPrintClaimStoreProvider.overrideWithValue(
          SharedPrefsRoundPrintClaimStore(prefs)..scopeKey = _session.deviceId,
        ),
      if (journal != null)
        additionJournalStoreProvider.overrideWithValue(
          SharedPrefsAdditionJournalStore(journal),
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A durable journal record carrying the canonical paid fixture.
PosAdditionJournalRecord _record({String localOperationId = 'op-1'}) =>
    PosAdditionJournalRecord(
      localOperationId: localOperationId,
      orderId: 'o-1',
      orderCode: '#O00001',
      orderTypeWire: 'dine_in',
      generation: 1,
      itemsJson: const [
        {'menu_item_id': 'burger-meat', 'quantity': 2},
      ],
      lines: const [
        CartLineView(
          lineId: 'l-1',
          menuItemId: 'burger-meat',
          name: 'Burger',
          quantity: 2,
          unitPriceMinor: kBase,
          lineTotalMinor: kLineTotal,
          currencyCode: 'ILS',
          modifiers: [_meat240],
        ),
      ],
      prepByItemId: const {},
      expectedDeltaMinor: kLineTotal,
      currencyCode: 'ILS',
      clientCreatedAt: DateTime.utc(2026, 8, 6, 12),
      phase: PosAdditionJournalPhase.transportUncertain,
    );

/// Drains the microtask queue so an asynchronous journal restore completes.
Future<void> _settle(ProviderContainer c) async {
  c.read(additionControllerProvider); // force the Notifier to build
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

/// Builds the canonical paid addition in [c]'s cart and submits it.
Future<AdditionResult> _buildAndSubmit(ProviderContainer c) async {
  final entry = await c
      .read(additionControllerProvider.notifier)
      .enterForOrder('o-1');
  expect(entry, AdditionEntryResult.entered);
  final cart = c.read(cartControllerProvider.notifier);
  cart.addItemWithModifiers(_burger, const [_meat240]);
  final lineId = c.read(cartControllerProvider).lines.single.lineId;
  cart.increaseQuantity(lineId); // item quantity 2
  expect(
    c.read(cartControllerProvider).lines.single.lineTotalMinor,
    kLineTotal,
  );
  return c.read(additionControllerProvider.notifier).submit();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // A — THE FROZEN IDENTITY MUST SURVIVE PROCESS DEATH
  // =========================================================================
  group('A. process death must not mint a second amendment identity', () {
    test(
      'A1 after a restart the SAME operation identity is dispatched',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final j = await SharedPreferences.getInstance();
        // Session 1: the addition goes out and the transport dies. The client
        // cannot know whether the server applied the round.
        final t1 = _FakeTransport([_transportDown]);
        final c1 = _container(t1, journal: j);
        final r1 = await _buildAndSubmit(c1);
        expect(r1.applied, isFalse, reason: 'the outcome is genuinely UNKNOWN');
        expect(t1.additionIdentities, hasLength(1));
        final original = t1.additionIdentities.single;

        c1.dispose(); // PROCESS DEATH — the in-memory attempt is gone

        // Session 2: the cashier re-does the same addition on the same order.
        final t2 = _FakeTransport([_replayApplied]);
        final c2 = _container(t2, journal: j);
        await _settle(c2);
        await _buildAndSubmit(c2);

        expect(
          t2.additionIdentities,
          <String>{original},
          reason:
              'THE RELEASE BLOCKER: a NEW local_operation_id means the server '
              'sees a DIFFERENT operation and creates a SECOND service round. '
              'The kitchen cooks the same food twice and the bill charges for '
              'it twice. Replaying the FROZEN identity is what makes the '
              'existing app.add_order_items idempotency reachable.',
        );
      },
    );

    test('A2 the unresolved attempt is still known after a restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1, journal: j);
      await _buildAndSubmit(c1);
      final original = t1.additionIdentities.single;
      c1.dispose();

      final t2 = _FakeTransport([_replayApplied]);
      final c2 = _container(t2, journal: j);
      // Reading the controller is enough to build it; a durable attempt must
      // be visible without the cashier having to re-key anything.
      await _settle(c2);
      final restored = c2.read(additionControllerProvider);

      expect(
        restored.attempt?.localOperationId,
        original,
        reason:
            'an operation whose outcome is unknown must not disappear just '
            'because the process died — nothing else can resolve it',
      );
      expect(
        restored.hasOpenAttempt,
        isTrue,
        reason: 'the till must show that this order has an unresolved addition',
      );
    });

    test('A3 the frozen payload is replayed byte-identically', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1, journal: j);
      await _buildAndSubmit(c1);
      final firstPayload = t1.additionOps.single['payload'];
      c1.dispose();

      final t2 = _FakeTransport([_replayApplied]);
      final c2 = _container(t2, journal: j);
      await _settle(c2);
      await _buildAndSubmit(c2);

      expect(
        t2.additionOps.single['payload'],
        firstPayload,
        reason:
            'the server fingerprint is md5(op_type|payload|target_id): a '
            'payload rebuilt from the live cart or menu is refused as a '
            'CONFLICT instead of replaying the applied round, so the frozen '
            'bytes must be stored and re-sent verbatim',
      );
    });

    test('A4 the restored attempt carries the exact frozen money', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1, journal: j);
      await _buildAndSubmit(c1);
      c1.dispose();

      final c2 = _container(_FakeTransport([_replayApplied]), journal: j);
      await _settle(c2);
      final attempt = c2.read(additionControllerProvider).attempt;
      expect(attempt, isNotNull, reason: 'nothing survived the restart');

      final item = attempt!.itemsJson.single;
      expect(item['quantity'], 2);
      expect(item['unit_price_minor_snapshot'], kBase);
      expect(item['line_total_minor'], kLineTotal);
      final mods = (item['modifiers']! as List)
          .cast<Map<dynamic, dynamic>>()
          .map((e) => e.cast<String, Object?>())
          .toList();
      expect(mods.single['price_minor_snapshot'], kDelta);
      expect(
        mods.single.containsKey('modifier_group_id'),
        isFalse,
        reason: 'modifierGroupId is LOCAL-only and never reaches the wire',
      );
    });
  });

  // =========================================================================
  // B — A REPLAYED ROUND MUST NOT PRINT A SECOND KITCHEN TICKET
  // =========================================================================
  group('B. the kitchen ticket is printed at most once per round', () {
    final key = posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-2');

    test(
      'B1 a round printed before a restart is not auto-printed again',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        var physicalSends = 0;
        Future<PosKitchenPrintOutcome> send() async {
          physicalSends++;
          return PosKitchenPrintOutcome.printed;
        }

        final c1 = _container(_FakeTransport([_applied]), prefs: prefs);
        expect(
          await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send),
          PosKitchenPrintOutcome.printed,
        );
        expect(physicalSends, 1, reason: 'the first ticket is genuinely ours');

        // A duplicate callback in the SAME session is already suppressed.
        await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);
        expect(physicalSends, 1);

        c1.dispose(); // PROCESS DEATH

        // The restart replays the applied round; the automatic print must NOT
        // fire again.
        final c2 = _container(_FakeTransport([_replayApplied]), prefs: prefs);
        await c2.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);

        expect(
          physicalSends,
          1,
          reason:
              'PosAutoKitchenPrintGuard held its claim in two plain in-memory '
              'collections on a Provider, so process death released it and the '
              'kitchen received a SECOND ticket for a round it was already '
              'cooking. The claim has to be as durable as the round it names.',
        );
      },
    );

    test('B2 a FAILED send releases the round for a later retry', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      var attempts = 0;

      final c1 = _container(_FakeTransport([_applied]), prefs: prefs);
      await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, () async {
        attempts++;
        return PosKitchenPrintOutcome.failed;
      });
      expect(attempts, 1);
      c1.dispose();

      final c2 = _container(_FakeTransport([_applied]), prefs: prefs);
      final outcome = await c2
          .read(posAutoKitchenPrintGuardProvider)
          .runGuarded(key, () async {
            attempts++;
            return PosKitchenPrintOutcome.printed;
          });

      expect(
        (attempts, outcome),
        (2, PosKitchenPrintOutcome.printed),
        reason:
            'a print that never happened must not be remembered as one that '
            'did — otherwise a paper jam permanently withholds the ticket',
      );
    });

    test('B3 a claim is scoped to ONE order and ONE round', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      var sends = 0;
      Future<PosKitchenPrintOutcome> send() async {
        sends++;
        return PosKitchenPrintOutcome.printed;
      }

      final c = _container(_FakeTransport([_applied]), prefs: prefs);
      final guard = c.read(posAutoKitchenPrintGuardProvider);
      await guard.runGuarded(key, send);
      await guard.runGuarded(
        posAdditionKitchenPrintGuardKey(orderId: 'o-2', roundId: 'r-2'),
        send,
      );
      await guard.runGuarded(
        posAdditionKitchenPrintGuardKey(orderId: 'o-1', roundId: 'r-3'),
        send,
      );

      expect(
        sends,
        3,
        reason:
            'a different order, and a later round on the same order, are '
            'different tickets and must each print',
      );
    });

    test(
      'B4 with NO durable store the pre-003C session behaviour is kept',
      () async {
        var sends = 0;
        Future<PosKitchenPrintOutcome> send() async {
          sends++;
          return PosKitchenPrintOutcome.printed;
        }

        final c1 = _container(_FakeTransport([_applied]));
        await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);
        await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);
        expect(sends, 1, reason: 'the in-session guard still works on its own');
      },
    );
  });

  // =========================================================================
  // C — ORDER ACTIONS MUST NOT ACT ON A STALE TOTAL
  // =========================================================================
  group('C. an unresolved addition withdraws conflicting order actions', () {
    PosOrderActions actions({PosPendingKind? pending}) =>
        resolveOrderActions(_order(), pending: pending);

    test('C1 Pay is withheld while an addition is unresolved', () {
      expect(
        actions(pending: PosPendingKind.itemsAdd).canPay,
        isFalse,
        reason:
            'the displayed total predates the amendment. Taking payment now '
            'charges for less food than the kitchen is making, and '
            'payments_one_completed_per_order_uidx means it cannot be topped '
            'up afterwards.',
      );
    });

    test('C2 Discount is withheld while an addition is unresolved', () {
      expect(actions(pending: PosPendingKind.itemsAdd).canDiscount, isFalse);
    });

    test('C3 Full comp is withheld while an addition is unresolved', () {
      expect(actions(pending: PosPendingKind.itemsAdd).canFullComp, isFalse);
    });

    test('C4 Void is withheld while an addition is unresolved', () {
      expect(
        actions(pending: PosPendingKind.itemsAdd).canVoid,
        isFalse,
        reason: 'voiding an order whose amendment is still in flight races it',
      );
    });

    test('C5 a second Add-items and a table move were ALREADY withheld', () {
      final a = actions(pending: PosPendingKind.itemsAdd);
      expect(a.canAddItems, isFalse);
      expect(a.canMoveTable, isFalse);
    });

    test('C6 with NOTHING pending every action is offered as before', () {
      final a = actions();
      expect(a.canPay, isTrue);
      expect(a.canDiscount, isTrue);
      expect(a.canVoid, isTrue);
      expect(a.canAddItems, isTrue);
    });

    test('C7 an unrelated pending kind is unaffected', () {
      expect(actions(pending: PosPendingKind.discount).canPay, isTrue);
      expect(actions(pending: PosPendingKind.payment).canDiscount, isTrue);
      expect(
        actions(pending: PosPendingKind.submit).canVoid,
        isTrue,
        reason: 'order B must stay usable while order A reconciles',
      );
    });
  });
  // =========================================================================
  // D — EXIT AFTER AN UNCERTAIN FAILURE MUST NOT RELEASE THE IDENTITY
  // =========================================================================
  group('D. exit() must not abandon a dispatched, unresolved attempt', () {
    test(
      'D1 exit after a transport timeout keeps the operation identity',
      () async {
        final t1 = _FakeTransport([_transportDown]);
        final c = _container(t1);
        await _buildAndSubmit(c);
        final original = t1.additionIdentities.single;
        expect(
          c.read(additionControllerProvider).phase,
          AdditionPhase.failed,
          reason: 'a dead transport leaves a RETRYABLE frozen attempt',
        );

        // The cashier taps Cancel on the failed banner. No crash is involved.
        c.read(additionControllerProvider.notifier).exit();

        expect(
          c.read(additionControllerProvider).attempt?.localOperationId,
          original,
          reason:
              'THE SERVER MAY ALREADY OWN THIS OPERATION. After a timeout the '
              'client cannot know the round was not applied, so discarding the '
              'identity means the next submission dispatches a DIFFERENT '
              'operation and the server creates a SECOND round — a duplicate '
              'amendment with no process crash required.',
        );
      },
    );

    test('D2 a re-submission after that exit reuses the SAME identity', () async {
      final t1 = _FakeTransport([_transportDown]);
      final c = _container(t1);
      await _buildAndSubmit(c);
      final original = t1.additionIdentities.single;

      c.read(additionControllerProvider.notifier).exit();

      // The real-world path after a Cancel: the cart still holds the lines, so
      // the cashier clears it, re-enters Add-items for the SAME order, re-keys
      // the same items and sends again.
      c.read(cartControllerProvider.notifier).clear();
      final reentry = await c
          .read(additionControllerProvider.notifier)
          .enterForOrder('o-1');
      expect(
        (reentry, c.read(additionControllerProvider).attempt?.localOperationId),
        (AdditionEntryResult.entered, original),
        reason:
            're-entry RESUMES the unresolved operation rather than starting a '
            'fresh one: the cashier is let back in, but the frozen attempt is '
            'still the original identity, so the submit below replays it',
      );

      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_meat240]);
      final lineId = c.read(cartControllerProvider).lines.single.lineId;
      cart.increaseQuantity(lineId);
      await c.read(additionControllerProvider.notifier).submit();

      expect(
        t1.additionIdentities,
        <String>{original},
        reason:
            'the unresolved operation must be RESUMED, never replaced — the '
            'existing app.add_order_items idempotency only protects us when we '
            'come back under the same identity',
      );
    });

    test(
      'D3 exit is still allowed for an attempt that never dispatched',
      () async {
        final t = _FakeTransport([_applied]);
        final c = _container(t);
        await c.read(additionControllerProvider.notifier).enterForOrder('o-1');
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItemWithModifiers(_burger, const [_meat240]);

        // Nothing was ever sent, so nothing can be owned by the server.
        expect(c.read(additionControllerProvider.notifier).exit(), isTrue);
        expect(t.additionOps, isEmpty);
        expect(
          c.read(additionControllerProvider).hasOpenAttempt,
          isFalse,
          reason:
              'abandoning an addition the server never heard of is safe and must '
              'stay possible — otherwise a cashier who changes their mind is '
              'stuck with a lock nothing can clear',
        );
        expect(
          c.read(cartControllerProvider).lines,
          isNotEmpty,
          reason:
              'the cashier keeps their items (their own Clear discards them)',
        );
      },
    );

    test('D4 exit is refused while the operation is on the wire', () async {
      final t = _FakeTransport([_applied]);
      final c = _container(t);
      await c.read(additionControllerProvider.notifier).enterForOrder('o-1');
      c.read(cartControllerProvider.notifier).addItem(_burger);
      final pending = c.read(additionControllerProvider.notifier).submit();

      expect(
        c.read(additionControllerProvider.notifier).exit(),
        isFalse,
        reason: 'unchanged pre-003C behaviour: cancel is refused while sending',
      );
      await pending;
    });
  });
  // =========================================================================
  // E — AN AMENDMENT THAT CANNOT BE JOURNALLED MUST NOT BE SENT
  // =========================================================================
  group('E. persist before dispatch', () {
    test('E1 a refused journal write dispatches NOTHING', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = FailingPrefs(await SharedPreferences.getInstance());
      final t = _FakeTransport([_applied]);
      final c = _container(t, journal: j);

      j.failWrites = true;
      final result = await _buildAndSubmit(c);

      expect(
        t.additionOps,
        isEmpty,
        reason:
            'without a durable record there is nothing to replay under, so a '
            'later retry would mint a new identity and the server would build '
            'a SECOND round — the amendment must not leave the device',
      );
      expect(result.applied, isFalse);
      expect(result.error, 'storage');
      expect(
        c.read(cartControllerProvider).lines,
        isNotEmpty,
        reason: 'the cashier keeps the addition and can retry',
      );
    });

    test('E2 nothing is left claiming to be pending', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = FailingPrefs(await SharedPreferences.getInstance());
      final c1 = _container(_FakeTransport([_applied]), journal: j);
      j.failWrites = true;
      await _buildAndSubmit(c1);
      c1.dispose();

      j.failWrites = false;
      final t2 = _FakeTransport([_applied]);
      final c2 = _container(t2, journal: j);
      await _settle(c2);

      expect(
        c2.read(additionControllerProvider).hasOpenAttempt,
        isFalse,
        reason:
            'an operation that was never sent must not come back as an '
            'unresolved amendment blocking the order',
      );
    });

    test('E3 a healthy write still dispatches exactly once', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t = _FakeTransport([_applied]);
      final c = _container(t, journal: j);

      final result = await _buildAndSubmit(c);
      expect(result.applied, isTrue);
      expect(t.additionOps, hasLength(1));
    });
  });

  // =========================================================================
  // F — REPLAY OUTCOMES
  // =========================================================================
  group('F. replay outcomes', () {
    /// The server refuses the identity because the stored payload fingerprint
    /// differs — `sync_push` returns this instead of ever building a 2nd round.
    Object? conflict(Map<String, dynamic> params) {
      final localOp =
          ((params['p_operations'] as List).single as Map)['local_operation_id']
              as String;
      return {
        'ok': true,
        'results': [
          {
            'local_operation_id': localOp,
            'status': 'conflict',
            'ok': false,
            'error': 'conflict',
          },
        ],
      };
    }

    Object? rejected(Map<String, dynamic> params) {
      final localOp =
          ((params['p_operations'] as List).single as Map)['local_operation_id']
              as String;
      return {
        'ok': true,
        'results': [
          {
            'local_operation_id': localOp,
            'status': 'rejected',
            'ok': false,
            'error': 'item_unavailable',
          },
        ],
      };
    }

    test('F1 an already-applied replay closes on the SAME round', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final c1 = _container(_FakeTransport([_transportDown]), journal: j);
      await _buildAndSubmit(c1);
      c1.dispose();

      final t2 = _FakeTransport([_replayApplied]);
      final c2 = _container(t2, journal: j);
      await _settle(c2);
      final resumed = await c2
          .read(additionControllerProvider.notifier)
          .submit();

      expect(resumed.applied, isTrue);
      expect(resumed.roundNumber, 2);
      expect(t2.additionOps, hasLength(1), reason: 'one replay, one round');
      // Confirmed against the authoritative detail, so the record is gone.
      final journal = SharedPrefsAdditionJournalStore(j);
      expect(
        await journal.load('dev-1'),
        isEmpty,
        reason:
            'the journal closes ONLY after the refresh proved the round — and '
            'then it must actually close, or the order stays locked forever',
      );
    });

    test('F2 a CONFLICT keeps the record and creates no second round', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t = _FakeTransport([_transportDown, conflict]);
      final c = _container(t, journal: j);
      await _buildAndSubmit(c);
      final original = t.additionIdentities.single;

      final second = await c.read(additionControllerProvider.notifier).submit();

      expect(second.applied, isFalse);
      expect(t.additionIdentities, <String>{original});
      final journal = SharedPrefsAdditionJournalStore(j);
      final held = await journal.load('dev-1');
      expect(
        held[original]?.phase,
        PosAdditionJournalPhase.conflict,
        reason:
            'a conflict can never be resolved by retrying and can never make a '
            'second round — it is retained for a person to settle',
      );
      expect(
        c.read(cartControllerProvider).lines,
        isNotEmpty,
        reason: 'nothing is cleared on a conflict',
      );
    });

    test('F3 a permanent rejection is terminal, and cancellable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t = _FakeTransport([rejected]);
      final c = _container(t, journal: j);
      final r = await _buildAndSubmit(c);

      expect(r.applied, isFalse);
      expect(r.error, 'item_unavailable');
      final journal = SharedPrefsAdditionJournalStore(j);
      expect(
        (await journal.load('dev-1')).values.single.phase,
        PosAdditionJournalPhase.rejected,
      );
      expect(
        c.read(additionControllerProvider.notifier).exit(),
        isTrue,
        reason:
            'the server definitively said no, so no round exists and the '
            'cashier may redo the addition — this is the ordinary '
            '"we are out of that" path and must not be locked',
      );
    });

    test('F4 transport still down: same identity, record retained', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final t = _FakeTransport([_transportDown]);
      final c = _container(t, journal: j);
      await _buildAndSubmit(c);
      final original = t.additionIdentities.single;

      await c.read(additionControllerProvider.notifier).submit();

      expect(t.additionIdentities, <String>{original});
      final journal = SharedPrefsAdditionJournalStore(j);
      expect(
        (await journal.load('dev-1'))[original]?.phase,
        PosAdditionJournalPhase.transportUncertain,
      );
    });
  });

  // =========================================================================
  // G — THE JOURNAL PRESERVES WHAT IT CANNOT READ
  // =========================================================================
  group('G. journal durability contract', () {
    const key = 'restoflow.pos.addition_journal.v1.dev-1';

    test('G1 an absent key is a valid EMPTY journal', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPrefsAdditionJournalStore(
        await SharedPreferences.getInstance(),
      );
      expect(await store.load('dev-1'), isEmpty);
      expect(store.unreadableRecordCount('dev-1'), 0);
    });

    test('G2 a refused write THROWS a typed persistence failure', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = FailingPrefs(await SharedPreferences.getInstance());
      final store = SharedPrefsAdditionJournalStore(prefs);
      prefs.failWrites = true;
      await expectLater(
        store.persist('dev-1', <String, PosAdditionJournalRecord>{
          'op-1': _record(),
        }),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'G3 one corrupt record is quarantined; valid siblings survive',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          key: jsonEncode(<String, Object?>{
            'version': SharedPrefsAdditionJournalStore.schemaVersion,
            'records': <String, Object?>{
              'op-good': _record(localOperationId: 'op-good').toJson(),
              // `expected_delta_minor` as a String: a tolerant decoder would send
              // a silently-zeroed amendment.
              'op-bad': {
                ..._record(localOperationId: 'op-bad').toJson(),
                'expected_delta_minor': 'not-a-number',
              },
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsAdditionJournalStore(prefs);

        final loaded = await store.load('dev-1');
        expect(
          loaded.keys,
          <String>['op-good'],
          reason: 'the unreadable record is never handed out to be dispatched',
        );
        expect(store.unreadableRecordCount('dev-1'), 1);

        await store.persist('dev-1', loaded);
        final stored =
            (jsonDecode(prefs.getString(key)!) as Map)['records'] as Map;
        expect(
          stored.keys,
          containsAll(<String>['op-good', 'op-bad']),
          reason:
              'a record naming a possibly-live server amendment is not ours to '
              'delete just because this build cannot read it',
        );
      },
    );

    test('G4 a malformed ENVELOPE is preserved, not read as empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: '{not json at all',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsAdditionJournalStore(prefs);

      expect(await store.load('dev-1'), isEmpty);
      await store.persist('dev-1', <String, PosAdditionJournalRecord>{
        'op-1': _record(),
      });

      final preserved = prefs
          .getKeys()
          .where((k) => k.startsWith(key) && k != key)
          .toList();
      expect(preserved, isNotEmpty);
      expect(prefs.getString(preserved.single), '{not json at all');
    });

    test('G5 an unknown schema version is not mis-parsed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: jsonEncode(<String, Object?>{'version': 99, 'records': {}}),
      });
      final store = SharedPrefsAdditionJournalStore(
        await SharedPreferences.getInstance(),
      );
      expect(await store.load('dev-1'), isEmpty);
    });

    test('G6 the frozen money round-trips exactly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsAdditionJournalStore(prefs);
      await store.persist('dev-1', <String, PosAdditionJournalRecord>{
        'op-1': _record(),
      });

      final back = (await SharedPrefsAdditionJournalStore(
        prefs,
      ).load('dev-1'))['op-1']!;
      expect(back.expectedDeltaMinor, kLineTotal);
      final line = back.lines.single;
      expect(line.quantity, 2);
      expect(line.unitPriceMinor, kBase);
      expect(line.lineTotalMinor, kLineTotal);
      expect(line.modifiers.single.priceDeltaMinor, kDelta);
      expect(line.modifiers.single.quantity, 1);
      expect(
        line.modifiers.single.modifierGroupId,
        'grp-meat',
        reason: 'the LOCAL group identity survives locally (002C)',
      );
    });
  });

  // =========================================================================
  // H — THE ORDER STAYS LOCKED ACROSS A RESTART
  // =========================================================================
  group('H. affected-order lock survives process recreation', () {
    test('H1 the restored amendment still withdraws money actions', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final c1 = _container(_FakeTransport([_transportDown]), journal: j);
      await _buildAndSubmit(c1);
      c1.dispose();

      final c2 = _container(_FakeTransport([_replayApplied]), journal: j);
      await _settle(c2);
      final notifier = c2.read(additionControllerProvider.notifier);

      expect(
        notifier.hasUnresolvedAmendmentFor('o-1'),
        isTrue,
        reason:
            'the pending kind is published from this, so without it the gates '
            'have nothing to fire on after a restart',
      );
      final blocked = resolveOrderActions(
        _order(),
        pending: notifier.hasUnresolvedAmendmentFor('o-1')
            ? PosPendingKind.itemsAdd
            : null,
      );
      expect(
        (blocked.canPay, blocked.canDiscount, blocked.canVoid),
        (false, false, false),
      );
    });

    test('H2 an UNRELATED order is untouched by the restored lock', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final j = await SharedPreferences.getInstance();
      final c1 = _container(_FakeTransport([_transportDown]), journal: j);
      await _buildAndSubmit(c1);
      c1.dispose();

      final c2 = _container(_FakeTransport([_replayApplied]), journal: j);
      await _settle(c2);
      final notifier = c2.read(additionControllerProvider.notifier);

      expect(notifier.hasUnresolvedAmendmentFor('o-2'), isFalse);
      final other = resolveOrderActions(_order(), pending: null);
      expect(
        (other.canPay, other.canDiscount, other.canVoid),
        (true, true, true),
        reason: 'order B must stay fully usable while order A reconciles',
      );
    });
  });
}
