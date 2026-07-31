import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D [C] — Codex Blocker 7, paid Add-items.
///
/// WHY THIS SUITE EXISTS. `service_round_pos_test.dart` already proves the
/// addition contract thoroughly — including that a retry reuses the SAME
/// `local_operation_id`. But it contains no `SelectedModifier` anywhere: every
/// case uses a PLAIN 700-minor item. So the one thing a money-integrity review
/// needs to know — that a PAID SURCHARGE is neither lost nor duplicated across
/// an addition retry — was never asserted.
///
/// This suite drives the REAL `AdditionController` (entry guard, atomic freeze,
/// cart lock, dispatch, failure retention, retry) over the REAL cart controller,
/// with a fake transport at the ONE network boundary.
///
/// Every expected amount is an INDEPENDENT LITERAL.
///
/// Classification: CODEX COVERAGE GAP.
///
/// SCOPE LIMIT, stated rather than papered over. Unlike the order-submit
/// outbox — which IS durable and whose restart survival is proven in
/// `money_durable_outbox_production_test.dart` — a PENDING ADDITION is not
/// persisted anywhere. `AdditionAttempt` exists only inside `AdditionState` on
/// the in-memory Notifier (its type appears in `addition_controller.dart` and
/// nowhere else in `apps/pos/lib`), and `ParkedCartsController` deliberately
/// REFUSES to park an amendment cart. Disposing the ProviderContainer therefore
/// loses the frozen attempt and its idempotency id outright.
///
/// So this suite proves retry identity WITHIN a session, which is the whole of
/// what production offers today. It deliberately does NOT assert restart
/// survival for an addition, because that behaviour does not exist — asserting
/// it would require a production change this phase forbids, and pretending to
/// prove it would be exactly the overstated coverage Blocker 7 is about. The
/// gap is reported as a residual product risk with a recommended bounded phase.

const kBase = 4500;
const k240 = 1500;
// 4500 + 1500 = 6000 per unit; x 2 = 12000. Written out, not computed.
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
  priceDeltaMinor: k240,
);

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

  /// Every `order.items_add` op this transport was actually asked to send.
  List<Map<String, dynamic>> get additionOps => [
    for (final c in calls)
      for (final op
          in (c['p_operations'] as List).cast<Map<dynamic, dynamic>>())
        if (op['operation_type'] == 'order.items_add')
          op.cast<String, dynamic>(),
  ];
}

Object? _applied(Map<String, dynamic> params) {
  final ops = params['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'applied',
        'ok': true,
        'round_id': 'r-new',
        'round_number': 2,
      },
    ],
  };
}

Object? _rejected(Map<String, dynamic> params, String error) {
  final ops = params['p_operations'] as List;
  final localOp = (ops.single as Map)['local_operation_id'] as String;
  return {
    'ok': true,
    'results': [
      {
        'local_operation_id': localOp,
        'status': 'rejected',
        'ok': false,
        'error': error,
      },
    ],
  };
}

PosOrderDetail _detail({String orderId = 'o-1'}) => PosOrderDetail(
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
  rounds: const [
    PosOrderDetailRound(roundId: 'r-new', roundNumber: 2, status: 'submitted'),
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

(ProviderContainer, _FakeTransport) _harness(
  List<Object? Function(Map<String, dynamic>)> responses,
) {
  final transport = _FakeTransport(responses);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
      orderDetailRepositoryProvider.overrideWithValue(_FakeDetailRepo()),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport);
}

/// The single `order.items_add` payload the production path dispatched.
Map<String, Object?> payloadOf(Map<String, dynamic> op) =>
    (op['payload']! as Map).cast<String, Object?>();

List<Map<String, Object?>> itemsOf(Map<String, dynamic> op) =>
    (payloadOf(op)['order_items']! as List)
        .cast<Map<dynamic, dynamic>>()
        .map((e) => e.cast<String, Object?>())
        .toList();

void main() {
  group('[C] a PAID addition survives failure and retry exactly once', () {
    test(
      'C1 the dispatched addition carries the exact configured money',
      () async {
        final (c, transport) = _harness([_applied]);
        final entry = await c
            .read(additionControllerProvider.notifier)
            .enterForOrder('o-1');
        expect(
          entry,
          AdditionEntryResult.entered,
          reason: 'the order is eligible for a service round',
        );

        final cart = c.read(cartControllerProvider.notifier);
        cart.addItemWithModifiers(_burger, const [_meat240]);
        final lineId = c.read(cartControllerProvider).lines.single.lineId;
        cart.increaseQuantity(lineId); // item quantity 2
        expect(
          c.read(cartControllerProvider).lines.single.lineTotalMinor,
          kLineTotal,
        );

        final result = await c
            .read(additionControllerProvider.notifier)
            .submit();
        expect(result.applied, isTrue);

        expect(transport.additionOps, hasLength(1));
        final items = itemsOf(transport.additionOps.single);
        expect(items, hasLength(1));
        final item = items.single;

        expect(item['quantity'], 2);
        expect(item['unit_price_minor_snapshot'], kBase);
        expect(
          item['line_total_minor'],
          kLineTotal,
          reason: 'the addition is charged qty x (base + modifiers)',
        );
        final mods = (item['modifiers']! as List)
            .cast<Map<dynamic, dynamic>>()
            .map((e) => e.cast<String, Object?>())
            .toList();
        expect(mods, hasLength(1), reason: 'exactly one surcharge, once');
        expect(mods.single['modifier_option_id'], 'opt-240');
        expect(mods.single['price_minor_snapshot'], k240);
        expect(mods.single['quantity'], 1);

        // 002C wire isolation on the amendment path too.
        final wire = jsonEncode(transport.additionOps.single);
        expect(wire.contains('modifier_group_id'), isFalse);
        expect(wire.contains('grp-meat'), isFalse);
      },
    );

    test('C2 a REJECTED addition is retried under the SAME identity with a '
        'byte-identical payload, and the surcharge is neither lost nor '
        'duplicated', () async {
      final (c, transport) = _harness([
        (p) => _rejected(p, 'temporarily_unavailable'),
        _applied,
      ]);
      await c.read(additionControllerProvider.notifier).enterForOrder('o-1');
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_meat240]);
      final lineId = c.read(cartControllerProvider).lines.single.lineId;
      cart.increaseQuantity(lineId);

      final first = await c.read(additionControllerProvider.notifier).submit();
      expect(first.applied, isFalse, reason: 'the server refused it');

      // The cart and its money are RETAINED for the retry — nothing cleared.
      expect(
        c.read(cartControllerProvider).lines.single.lineTotalMinor,
        kLineTotal,
      );

      final second = await c.read(additionControllerProvider.notifier).submit();
      expect(second.applied, isTrue);

      expect(transport.additionOps, hasLength(2));
      final ids = transport.additionOps
          .map((op) => op['local_operation_id'])
          .toSet();
      expect(
        ids,
        hasLength(1),
        reason:
            'D-022: one amendment identity, so the server can dedupe — '
            'two identities would be two rounds and a double charge',
      );

      // Both attempts are the SAME frozen payload, byte for byte.
      final encoded = transport.additionOps
          .map((op) => jsonEncode(payloadOf(op)))
          .toSet();
      expect(
        encoded,
        hasLength(1),
        reason: 'the frozen attempt must not be rebuilt on retry',
      );

      for (final op in transport.additionOps) {
        final items = itemsOf(op);
        expect(items, hasLength(1));
        final mods = (items.single['modifiers']! as List)
            .cast<Map<dynamic, dynamic>>()
            .map((e) => e.cast<String, Object?>())
            .toList();
        expect(mods, hasLength(1));
        expect(mods.single['price_minor_snapshot'], k240);
        expect(items.single['quantity'], 2);
        expect(items.single['line_total_minor'], kLineTotal);
      }
    });

    test('C3 a TRANSPORT failure keeps the addition retryable and does not '
        'dispatch a second business operation', () async {
      final transport = _ThrowingOnceTransport();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
          ),
          orderDetailRepositoryProvider.overrideWithValue(_FakeDetailRepo()),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(additionControllerProvider.notifier)
          .enterForOrder('o-1');
      final cart = container.read(cartControllerProvider.notifier);
      cart.addItemWithModifiers(_burger, const [_meat240]);
      final lineId = container.read(cartControllerProvider).lines.single.lineId;
      cart.increaseQuantity(lineId);

      final first = await container
          .read(additionControllerProvider.notifier)
          .submit();
      expect(first.applied, isFalse);
      expect(first.error, 'transport');

      final second = await container
          .read(additionControllerProvider.notifier)
          .submit();
      expect(second.applied, isTrue);

      expect(transport.additionOps, hasLength(2));
      expect(
        transport.additionOps.map((op) => op['local_operation_id']).toSet(),
        hasLength(1),
        reason: 'a network failure must not mint a new amendment identity',
      );
      final items = itemsOf(transport.additionOps.last);
      expect(items.single['line_total_minor'], kLineTotal);
      expect(
        ((items.single['modifiers']! as List).single
            as Map)['price_minor_snapshot'],
        k240,
      );
    });

    test(
      'C4 two configured lines in ONE addition each keep their own money',
      () async {
        const cola = DemoMenuItem(
          id: 'cola',
          name: 'Cola',
          priceMinor: 1000,
          categoryId: 'c1',
          categoryName: 'Food',
        );
        const extra = SelectedModifier(
          optionId: 'opt-ice',
          modifierGroupId: 'grp-ice',
          groupName: 'Ice',
          optionName: 'Extra ice',
          priceDeltaMinor: 300,
        );
        final (c, transport) = _harness([_applied]);
        await c.read(additionControllerProvider.notifier).enterForOrder('o-1');
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItemWithModifiers(_burger, const [_meat240]);
        final burgerLine = c.read(cartControllerProvider).lines.single.lineId;
        cart.increaseQuantity(burgerLine); // qty 2 -> 12000
        cart.addItemWithModifiers(cola, const [extra]); // qty 1 -> 1300

        expect(c.read(cartControllerProvider).subtotalMinor, 13300);

        final result = await c
            .read(additionControllerProvider.notifier)
            .submit();
        expect(result.applied, isTrue);

        final items = itemsOf(transport.additionOps.single);
        expect(items, hasLength(2), reason: 'both lines are in the round');
        final burgerItem = items.firstWhere(
          (i) => i['menu_item_id'] == 'burger-meat',
        );
        final colaItem = items.firstWhere((i) => i['menu_item_id'] == 'cola');
        expect(burgerItem['line_total_minor'], kLineTotal);
        expect(colaItem['line_total_minor'], 1300);
        // The round's own arithmetic, independent of any production helper.
        expect(
          items.fold<int>(0, (s, i) => s + (i['line_total_minor']! as int)),
          13300,
        );
      },
    );
  });
}

/// Throws a transport error on the FIRST sync_push only, then applies.
class _ThrowingOnceTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = [];
  bool _thrown = false;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    calls.add(params);
    if (!_thrown) {
      _thrown = true;
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    return _applied(params);
  }

  List<Map<String, dynamic>> get additionOps => [
    for (final c in calls)
      for (final op
          in (c['p_operations'] as List).cast<Map<dynamic, dynamic>>())
        if (op['operation_type'] == 'order.items_add')
          op.cast<String, dynamic>(),
  ];
}
