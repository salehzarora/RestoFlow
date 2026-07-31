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
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';

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

ProviderContainer _container(_FakeTransport transport) {
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
    ],
  );
  addTearDown(c.dispose);
  return c;
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
        // Session 1: the addition goes out and the transport dies. The client
        // cannot know whether the server applied the round.
        final t1 = _FakeTransport([_transportDown]);
        final c1 = _container(t1);
        final r1 = await _buildAndSubmit(c1);
        expect(r1.applied, isFalse, reason: 'the outcome is genuinely UNKNOWN');
        expect(t1.additionIdentities, hasLength(1));
        final original = t1.additionIdentities.single;

        c1.dispose(); // PROCESS DEATH — the in-memory attempt is gone

        // Session 2: the cashier re-does the same addition on the same order.
        final t2 = _FakeTransport([_replayApplied]);
        final c2 = _container(t2);
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
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1);
      await _buildAndSubmit(c1);
      final original = t1.additionIdentities.single;
      c1.dispose();

      final t2 = _FakeTransport([_replayApplied]);
      final c2 = _container(t2);
      // Reading the controller is enough to build it; a durable attempt must
      // be visible without the cashier having to re-key anything.
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
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1);
      await _buildAndSubmit(c1);
      final firstPayload = t1.additionOps.single['payload'];
      c1.dispose();

      final t2 = _FakeTransport([_replayApplied]);
      final c2 = _container(t2);
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
      final t1 = _FakeTransport([_transportDown]);
      final c1 = _container(t1);
      await _buildAndSubmit(c1);
      c1.dispose();

      final c2 = _container(_FakeTransport([_replayApplied]));
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
    test(
      'B1 a round printed before a restart is not auto-printed again',
      () async {
        final key = posAdditionKitchenPrintGuardKey(
          orderId: 'o-1',
          roundId: 'r-2',
        );
        var physicalSends = 0;
        Future<PosKitchenPrintOutcome> send() async {
          physicalSends++;
          return PosKitchenPrintOutcome.printed;
        }

        final c1 = _container(_FakeTransport([_applied]));
        expect(
          await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send),
          PosKitchenPrintOutcome.printed,
        );
        expect(physicalSends, 1, reason: 'the first ticket is genuinely ours');

        // A duplicate callback in the SAME session is already suppressed.
        await c1.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);
        expect(physicalSends, 1);

        c1.dispose(); // PROCESS DEATH

        // The restart replays the applied round; the automatic print fires again.
        final c2 = _container(_FakeTransport([_replayApplied]));
        await c2.read(posAutoKitchenPrintGuardProvider).runGuarded(key, send);

        expect(
          physicalSends,
          1,
          reason:
              'PosAutoKitchenPrintGuard holds its claim in two plain in-memory '
              'collections on a Provider, so process death releases it. The '
              'kitchen receives a SECOND ticket for a round it is already '
              'cooking. The claim has to be as durable as the round it names.',
        );
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
}
