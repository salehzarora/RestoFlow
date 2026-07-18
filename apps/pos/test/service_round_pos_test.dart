import 'dart:async';

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
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/addition_controller.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart'
    show SubmittedOrderView;

/// PSC-001C — POS unit coverage for service rounds:
///  A. the canAddItems policy (one place decides; server re-enforces);
///  B. the addition controller: exact wire contract, honest failure retention,
///     idempotent retry (SAME operation id), verified-refresh cleanup;
///  C. the pos_order_detail parse + the COMBINED receipt converters;
///  D. the frozen addition attempt (correction Finding 2);
///  E. the fail-closed detail parser (correction Finding 5);
///  F. CONTROLLER-OWNED safe entry (final correction Finding 1);
///  G. sending-cancel refusal + stale-response fencing (final Finding 2);
///  H. applied-awaiting-refresh reconciliation (final Finding 4);
///  I. the authoritative receipt-source policy (final Finding 4);
///  J. authoritative payment identity/status parsing (final Finding 3).

PosOrderSnapshot _snapshot({
  String id = 'o-1',
  String status = 'preparing',
  String orderType = 'dine_in',
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosOrderSnapshot(
  orderId: id,
  orderCode: '#O00001',
  revision: 2,
  status: status,
  settlement: settlement,
  subtotalMinor: 2500,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 2500,
  createdAt: DateTime.utc(2026, 7, 22, 12),
  updatedAt: DateTime.utc(2026, 7, 22, 12),
  syncAt: DateTime.utc(2026, 7, 22, 12),
  orderType: orderType,
  tableLabel: 'T1',
  currencyCode: 'ILS',
);

PosRecentOrder _order({
  String status = 'preparing',
  String orderType = 'dine_in',
  PosSettlement settlement = PosSettlement.unpaid,
}) => PosRecentOrder.discovered(
  _snapshot(status: status, orderType: orderType, settlement: settlement),
);

/// The default detail carries the round every `_applied` result names
/// ('r-new') so the post-apply reconciliation can VERIFY the addition.
PosOrderDetail _detail({
  String orderId = 'o-1',
  List<PosOrderDetailRound> rounds = const [
    PosOrderDetailRound(roundId: 'r-new', roundNumber: 2, status: 'submitted'),
  ],
}) => PosOrderDetail(
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
  tableLabel: 'T1',
  items: const [],
  rounds: rounds,
);

const _menuItem = DemoMenuItem(
  id: 'm-race',
  name: 'Race Burger',
  priceMinor: 700,
  categoryId: 'c1',
  categoryName: 'Food',
);

/// The hostile mutation the LOCKED cart must refuse.
const _hackedItem = DemoMenuItem(
  id: 'm-hacked',
  name: 'Hacked',
  priceMinor: 9999,
  categoryId: 'c1',
  categoryName: 'Food',
);

/// The REAL payments.id the canonical envelope carries (Finding 3).
const _paymentUuid = '0a911111-2222-4333-8444-555566667777';

/// The canonical FULL pos_order_detail envelope the parser tests start from.
/// Inner maps are explicitly Object?-valued so mutation tests can null fields.
Map<String, Object?> envelope() => {
  'ok': true,
  'order': <String, Object?>{
    'order_id': 'o-1',
    'order_code': '#O00001',
    'order_type': 'dine_in',
    'status': 'served',
    'revision': 5,
    'table_label': 'T1',
    'customer_name': 'Dana',
    'currency_code': 'ILS',
    'subtotal_minor': 3500,
    'discount_total_minor': 500,
    'tax_total_minor': 0,
    'grand_total_minor': 3000,
    'receipt_number': '42',
  },
  'items': [
    {
      'menu_item_name_snapshot': 'Burger',
      'quantity': 2,
      'unit_price_minor_snapshot': 1000,
      'line_discount_minor': 0,
      'line_total_minor': 2500,
      'status': 'pending',
      'modifiers': [
        {
          'option_name_snapshot': 'Extra',
          'price_minor_snapshot': 250,
          'quantity': 2,
        },
      ],
    },
    {
      'menu_item_name_snapshot': 'Fries',
      'quantity': 1,
      'unit_price_minor_snapshot': 1000,
      'line_discount_minor': 0,
      'line_total_minor': 1000,
      'status': 'pending',
      'service_round_id': 'r1',
      'round_number': 2,
    },
  ],
  'rounds': [
    {'round_id': 'r1', 'round_number': 2, 'status': 'ready'},
  ],
  'payment': <String, Object?>{
    'payment_id': _paymentUuid,
    'payment_status': 'completed',
    'method': 'card',
    'amount_minor': 3000,
    'tendered_minor': 3000,
    'change_minor': 0,
    'receipt_number': '42',
    'created_at': '2026-07-22T12:34:56.000Z',
  },
};

class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._responses);
  final List<Object? Function(Map<String, dynamic>)> _responses;

  /// ONLY the sync_push calls — the controller's environment may issue other
  /// reads (pos_menu) through the same transport; they are not the contract
  /// under test.
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
}

/// A transport whose sync_push responses are GATED on per-call completers —
/// the test decides when (and in what order) each response arrives.
class _GatedTransport implements SyncRpcTransport {
  final List<Map<String, dynamic>> calls = [];
  final List<Completer<Object?>> gates = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) {
    if (function != 'sync_push') return Future.value({'ok': false});
    calls.add(params);
    final gate = Completer<Object?>();
    gates.add(gate);
    return gate.future;
  }
}

Object? _applied(Map<String, dynamic> params, {int roundNumber = 2}) {
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
        'round_number': roundNumber,
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

class _ProbeCart extends CartController {
  int clearCount = 0;
  @override
  CartMutationResult clear() {
    final result = super.clear();
    if (result == CartMutationResult.applied) clearCount++;
    return result;
  }

  @override
  bool clearForAddition(CartLockOwner owner) {
    final cleared = super.clearForAddition(owner);
    if (cleared) clearCount++;
    return cleared;
  }
}

/// Seeds ONE real line into the REAL cart controller (entry requires an empty
/// cart, so seeding always happens AFTER enterForOrder committed).
void seedCart(ProviderContainer container) {
  expect(
    container.read(cartControllerProvider.notifier).addItem(_menuItem),
    CartMutationResult.applied,
  );
}

/// Detail repo with an optional per-fetch handler sequence (the last handler
/// repeats). No handlers = every fetch succeeds with the default detail.
class _FakeDetailRepo implements OrderDetailRepository {
  _FakeDetailRepo([this._handlers = const []]);
  final List<Future<PosOrderDetail> Function(String)> _handlers;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) {
    fetches++;
    if (_handlers.isEmpty) return Future.value(_detail(orderId: orderId));
    final h = _handlers.length >= fetches
        ? _handlers[fetches - 1]
        : _handlers.last;
    return h(orderId);
  }
}

/// Detail repo GATED on per-call completers — the test resolves each fetch
/// when (and in whatever order) it chooses, to drive genuine races.
class _GatedDetailRepo implements OrderDetailRepository {
  final List<String> requested = [];
  final List<Completer<PosOrderDetail>> gates = [];
  @override
  Future<PosOrderDetail> fetch(String orderId) {
    requested.add(orderId);
    final gate = Completer<PosOrderDetail>();
    gates.add(gate);
    return gate.future;
  }
}

class _ThrowingDetailRepo implements OrderDetailRepository {
  @override
  Future<PosOrderDetail> fetch(String orderId) async =>
      throw const PosOrderDetailException(PosOrderDetailFailure.malformed);
}

(ProviderContainer, _FakeTransport, _ProbeCart, _FakeDetailRepo) _harness(
  List<Object? Function(Map<String, dynamic>)> responses, {
  _FakeDetailRepo? detailRepo,
}) {
  final transport = _FakeTransport(responses);
  final cart = _ProbeCart();
  final repo = detailRepo ?? _FakeDetailRepo();
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
      cartControllerProvider.overrideWith(() => cart),
      orderDetailRepositoryProvider.overrideWithValue(repo),
      // The post-success targeted refresh must never reach the REAL snapshot
      // repository through the fake transport: pin it to the demo repo with
      // polling off, so `transport.calls` sees ONLY the sync_push ops.
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport, cart, repo);
}

/// A harness around a GATED detail repo (entry/refresh races).
(ProviderContainer, _FakeTransport, _ProbeCart, _GatedDetailRepo) _gatedHarness(
  List<Object? Function(Map<String, dynamic>)> responses,
) {
  final transport = _FakeTransport(responses);
  final cart = _ProbeCart();
  final repo = _GatedDetailRepo();
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(transport),
      posSyncSessionProvider.overrideWithValue(
        const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
      ),
      cartControllerProvider.overrideWith(() => cart),
      orderDetailRepositoryProvider.overrideWithValue(repo),
      orderSnapshotRepositoryProvider.overrideWithValue(
        DemoOrderSnapshotRepository(),
      ),
      posSyncPollIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return (container, transport, cart, repo);
}

void main() {
  group('A. canAddItems policy', () {
    test('A1 an ACTIVE unpaid dine-in server order may take additions', () {
      expect(resolveOrderActions(_order()).canAddItems, isTrue);
      expect(resolveOrderActions(_order(status: 'served')).canAddItems, isTrue);
    });

    test('A2 a TAKEAWAY order never takes additions (locked scope)', () {
      expect(
        resolveOrderActions(_order(orderType: 'takeaway')).canAddItems,
        isFalse,
      );
    });

    test('A3 a TERMINAL order never takes additions', () {
      for (final s in ['completed', 'voided', 'cancelled']) {
        expect(resolveOrderActions(_order(status: s)).canAddItems, isFalse);
      }
    });

    test('A4 a CHARGED order is frozen (the payment freeze)', () {
      expect(
        resolveOrderActions(_order(settlement: PosSettlement.paid)).canAddItems,
        isFalse,
      );
    });

    test('A5 in-flight local work withholds the action', () {
      expect(
        resolveOrderActions(
          _order(),
          pending: PosPendingKind.itemsAdd,
        ).canAddItems,
        isFalse,
      );
    });

    test('A6 a PAID server order gains the authoritative receipt actions '
        'even without local lines (cross-device reprint)', () {
      final paid = resolveOrderActions(_order(settlement: PosSettlement.paid));
      expect(paid.canOpenReceipt, isTrue);
      // Unpaid discovered orders still get none (nothing to receipt).
      expect(resolveOrderActions(_order()).canOpenReceipt, isFalse);
    });
  });

  group('B. addition controller', () {
    test('B1 submit sends ONE order.items_add with matching target/payload '
        'and ONLY the new lines', () async {
      final (container, transport, _, _) = _harness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isTrue);
      expect(result.roundNumber, 2);
      final op = (transport.calls.single['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'order.items_add');
      expect(op['target_entity'], 'order');
      expect(op['target_id'], 'o-1');
      final payload = op['payload'] as Map;
      expect(payload['order_id'], 'o-1');
      final items = payload['order_items'] as List;
      expect(items, hasLength(1));
      final item = items.single as Map;
      expect(item['menu_item_id'], 'm-race');
      expect(item['quantity'], 1);
      expect(item['unit_price_minor_snapshot'], 700);
      // Additions never carry a line discount.
      expect(item.containsKey('line_discount_minor'), isFalse);
      // NO order-level client totals ride the payload.
      expect(payload.containsKey('subtotal_minor'), isFalse);
      expect(payload.containsKey('grand_total_minor'), isFalse);
    });

    test('B2 applied + VERIFIED refresh: cart cleared ONLY then, the attempt '
        'reconciled, addition mode exited', () async {
      final (container, _, cart, detailRepo) = _harness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isTrue);
      expect(result.refreshRequired, isFalse);
      expect(cart.clearCount, 1);
      expect(detailRepo.fetches, 2); // the entry load + the verifying refresh
      final state = container.read(additionControllerProvider);
      expect(state.active, isFalse); // Finding 4: cleanup EXITS addition mode
      expect(state.hasOpenAttempt, isFalse);
      expect(state.phase, AdditionPhase.idle);
    });

    test('B3 a typed rejection keeps the pending addition local + retryable '
        '(cart NOT cleared)', () async {
      final (container, _, cart, _) = _harness([
        (p) => _rejected(p, 'order_already_settled'),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isFalse);
      expect(result.error, 'order_already_settled');
      expect(cart.clearCount, 0);
      final state = container.read(additionControllerProvider);
      expect(state.failed, isTrue);
      expect(state.active, isTrue);
    });

    test(
      'B4 a retry reuses the SAME local_operation_id (no duplicate round)',
      () async {
        final (container, transport, _, _) = _harness([
          (p) => _rejected(p, 'rejected'),
          (p) => _applied(p),
        ]);
        final notifier = container.read(additionControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        seedCart(container);
        await notifier.submit();
        final retry = await notifier.submit();
        expect(retry.applied, isTrue);
        String opId(Map<String, dynamic> call) =>
            ((call['p_operations'] as List).single as Map)['local_operation_id']
                as String;
        expect(transport.calls, hasLength(2));
        expect(opId(transport.calls[0]), opId(transport.calls[1]));
      },
    );

    test(
      'B5 strict success parse: applied WITHOUT ok=true is a failure',
      () async {
        final (container, _, cart, _) = _harness([
          (p) {
            final ops = p['p_operations'] as List;
            final localOp = (ops.single as Map)['local_operation_id'];
            return {
              'ok': true,
              'results': [
                {'local_operation_id': localOp, 'status': 'applied'},
              ],
            };
          },
        ]);
        final notifier = container.read(additionControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        seedCart(container);
        final result = await notifier.submit();
        expect(result.applied, isFalse);
        expect(cart.clearCount, 0);
      },
    );

    test('B6 a transport failure is a retryable local failure', () async {
      final (container, _, cart, _) = _harness([
        (p) => throw StateError('offline'),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isFalse);
      expect(cart.clearCount, 0);
      expect(container.read(additionControllerProvider).failed, isTrue);
    });
  });

  group('C. pos_order_detail parse + combined receipt converters', () {
    test('C1 the combined authoritative detail parses (original + added)', () {
      final detail = PosOrderDetail.fromJson(envelope());
      expect(detail, isNotNull);
      expect(detail!.items, hasLength(2));
      expect(detail.items.first.roundNumber, isNull);
      expect(detail.items.last.roundNumber, 2);
      expect(detail.rounds.single.status, 'ready');
      expect(detail.grandTotalMinor, 3000);
      expect(detail.payment?.method, PaymentMethod.card);
    });

    test('C2 the receipt converters build ONE combined list + the payment', () {
      final detail = PosOrderDetail.fromJson(envelope())!;
      final view = submittedOrderViewFromDetail(detail);
      expect(view.lines, hasLength(2)); // one list — never round sections
      expect(view.lines.first.modifiers.single, 'Extra ×2');
      expect(view.grandTotalMinor, 3000);
      expect(view.customerName, 'Dana');
      final payment = cashPaymentFromDetail(detail);
      expect(payment, isNotNull);
      expect(payment!.method, PaymentMethod.card);
      expect(payment.receiptNumber, '42');
      expect(payment.amountMinor, 3000);
      // Finding 3: the REAL payment identity + stored status — fabricated
      // placeholders are gone from the payment's own facts.
      expect(payment.paymentId, _paymentUuid);
      expect(payment.status, PaymentStatus.completed);
      // Finding 4: the reprint carries the AUTHORITATIVE payment time (T1),
      // never the fetch/view time — stable across devices and timezones.
      expect(payment.paidAt, DateTime.parse('2026-07-22T12:34:56.000Z'));
    });

    test('C3 a malformed item row rejects the WHOLE detail (atomic)', () {
      final bad = envelope();
      (bad['items']! as List).add({'quantity': 'NaN'});
      expect(PosOrderDetail.fromJson(bad), isNull);
    });
  });

  group('D. frozen addition attempt (Finding 2)', () {
    test(
      'D1 an active addition cannot retarget to a DIFFERENT order',
      () async {
        final (container, _, _, _) = _harness([(p) => _applied(p)]);
        final notifier = container.read(additionControllerProvider.notifier);
        expect(
          await notifier.enterForOrder('o-1'),
          AdditionEntryResult.entered,
        );
        expect(
          await notifier.enterForOrder('o-2'),
          AdditionEntryResult.blockedDifferentTarget,
        );
        expect(
          container.read(additionControllerProvider).target?.orderId,
          'o-1',
        );
      },
    );

    test(
      'D2 a failed retry resends the FROZEN payload + SAME op id — the '
      'locked cart cannot mutate under it (and never carries a table_id)',
      () async {
        final (container, transport, cart, _) = _harness([
          (p) => _rejected(p, 'rejected'),
          (p) => _applied(p),
        ]);
        final notifier = container.read(additionControllerProvider.notifier);
        await notifier.enterForOrder('o-1');
        seedCart(container);
        await notifier.submit();
        // Cart-safety: the frozen attempt LOCKED the cart — a mutation between
        // failure and retry is refused, so the retry payload cannot diverge.
        expect(cart.addItem(_hackedItem), CartMutationResult.lockedByAddition);
        final retry = await notifier.submit();
        expect(retry.applied, isTrue);
        expect(transport.calls, hasLength(2));
        final op1 = (transport.calls[0]['p_operations'] as List).single as Map;
        final op2 = (transport.calls[1]['p_operations'] as List).single as Map;
        expect(op2['local_operation_id'], op1['local_operation_id']);
        expect(op2['payload'], op1['payload']); // canonical-equivalent snapshot
        expect(op2['client_created_at'], op1['client_created_at']);
        final items = (op2['payload'] as Map)['order_items'] as List;
        // The frozen line — never the refused mutation.
        expect((items.single as Map)['menu_item_id'], 'm-race');
        expect((op2['payload'] as Map).containsKey('table_id'), isFalse);
      },
    );

    test('D3 while an attempt is open, even the failed state blocks a new '
        'target; explicit cancel unlocks with a NEW op id', () async {
      final (container, transport, cart, _) = _harness([
        (p) => _rejected(p, 'rejected'),
        (p) => _applied(p),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      await notifier.submit();
      expect(container.read(additionControllerProvider).hasOpenAttempt, isTrue);
      expect(
        await notifier.enterForOrder('o-2'),
        AdditionEntryResult.blockedPendingAttempt,
      );
      // EXPLICIT cancel (allowed on a retryable failure) discards the frozen
      // attempt entirely — and releases the cart lock WITHOUT clearing the
      // lines (discarding them is the cashier's explicit next step).
      expect(notifier.exit(), isTrue);
      expect(
        container.read(additionControllerProvider).hasOpenAttempt,
        isFalse,
      );
      expect(container.read(cartControllerProvider).lines, hasLength(1));
      expect(cart.clear(), CartMutationResult.applied);
      await notifier.enterForOrder('o-2');
      seedCart(container);
      await notifier.submit();
      final op1 = (transport.calls[0]['p_operations'] as List).single as Map;
      final op2 = (transport.calls[1]['p_operations'] as List).single as Map;
      expect(op2['local_operation_id'], isNot(op1['local_operation_id']));
      expect(op2['target_id'], 'o-2');
    });

    test('D4 re-entering the SAME target is a harmless no-op', () async {
      final (container, _, _, detailRepo) = _harness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      expect(await notifier.enterForOrder('o-1'), AdditionEntryResult.entered);
      expect(await notifier.enterForOrder('o-1'), AdditionEntryResult.entered);
      expect(container.read(additionControllerProvider).target?.orderId, 'o-1');
      expect(detailRepo.fetches, 1); // no refetch — idempotent
    });

    test('D5 authoritative success reconciles the attempt; the NEXT addition '
        '(fresh entry) gets a NEW op id', () async {
      final (container, transport, _, _) = _harness([
        (p) => _applied(p),
        (p) => _applied(p),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      await notifier.submit();
      expect(
        container.read(additionControllerProvider).hasOpenAttempt,
        isFalse,
      );
      // Cleanup exited addition mode (Finding 4) — enter again for the next.
      expect(await notifier.enterForOrder('o-1'), AdditionEntryResult.entered);
      seedCart(container);
      await notifier.submit();
      final op1 = (transport.calls[0]['p_operations'] as List).single as Map;
      final op2 = (transport.calls[1]['p_operations'] as List).single as Map;
      expect(op2['local_operation_id'], isNot(op1['local_operation_id']));
    });

    test('D6 the PURE entry guard: a non-empty normal cart never silently '
        'enters addition mode', () {
      const idle = AdditionState();
      expect(
        canBeginAddition(addition: idle, cartIsEmpty: false, orderId: 'o-1'),
        isFalse,
      );
      expect(
        canBeginAddition(addition: idle, cartIsEmpty: true, orderId: 'o-1'),
        isTrue,
      );
      // Re-entering the CURRENT target stays allowed regardless of the cart
      // (the cart holds this addition's own pending lines).
      final active = AdditionState(
        generation: 1,
        entryOrderId: 'o-1',
        target: _detail(),
        phase: AdditionPhase.active,
      );
      expect(
        canBeginAddition(addition: active, cartIsEmpty: false, orderId: 'o-1'),
        isTrue,
      );
      expect(
        canBeginAddition(addition: active, cartIsEmpty: true, orderId: 'o-2'),
        isFalse,
      );
      // A RESERVED entry (detail still loading) blocks other targets too.
      const entering = AdditionState(
        generation: 1,
        entryOrderId: 'o-1',
        phase: AdditionPhase.entering,
      );
      expect(
        canBeginAddition(addition: entering, cartIsEmpty: true, orderId: 'o-2'),
        isFalse,
      );
      expect(
        canBeginAddition(addition: entering, cartIsEmpty: true, orderId: 'o-1'),
        isTrue,
      );
    });
  });

  group('E. fail-closed detail parser (Finding 5)', () {
    test(
      'E1 each REQUIRED money field missing or mistyped fails the parse',
      () {
        for (final field in [
          'subtotal_minor',
          'discount_total_minor',
          'tax_total_minor',
          'grand_total_minor',
        ]) {
          final missing = envelope();
          (missing['order']! as Map).remove(field);
          expect(
            PosOrderDetail.fromJson(missing),
            isNull,
            reason: '$field gone',
          );
          final mistyped = envelope();
          (mistyped['order']! as Map)[field] = '3000';
          expect(
            PosOrderDetail.fromJson(mistyped),
            isNull,
            reason: '$field string',
          );
          final nulled = envelope();
          (nulled['order']! as Map)[field] = null;
          expect(
            PosOrderDetail.fromJson(nulled),
            isNull,
            reason: '$field null',
          );
        }
      },
    );

    test('E2 a malformed revision fails', () {
      final zero = envelope();
      (zero['order']! as Map)['revision'] = 0;
      expect(PosOrderDetail.fromJson(zero), isNull);
      final missing = envelope();
      (missing['order']! as Map).remove('revision');
      expect(PosOrderDetail.fromJson(missing), isNull);
    });

    test('E3 an UNKNOWN payment method fails (never defaults to cash)', () {
      final bad = envelope();
      (bad['payment']! as Map)['method'] = 'crypto';
      expect(PosOrderDetail.fromJson(bad), isNull);
      final missing = envelope();
      (missing['payment']! as Map).remove('method');
      expect(PosOrderDetail.fromJson(missing), isNull);
    });

    test('E4 a completed payment with a missing or malformed timestamp fails '
        '(a reprint never substitutes now)', () {
      final missing = envelope();
      (missing['payment']! as Map).remove('created_at');
      expect(PosOrderDetail.fromJson(missing), isNull);
      final malformed = envelope();
      (malformed['payment']! as Map)['created_at'] = 'yesterday-ish';
      expect(PosOrderDetail.fromJson(malformed), isNull);
    });

    test('E5 a payment missing a REQUIRED amount — or carrying a NEGATIVE '
        'amount — fails', () {
      final bad = envelope();
      (bad['payment']! as Map).remove('amount_minor');
      expect(PosOrderDetail.fromJson(bad), isNull);
      final negative = envelope();
      (negative['payment']! as Map)['amount_minor'] = -1;
      expect(PosOrderDetail.fromJson(negative), isNull);
    });

    test('E6 a modifier or line with missing money fails atomically; a '
        'NEGATIVE modifier price (impossible per the stored CHECK) fails', () {
      final badMod = envelope();
      ((((badMod['items']! as List).first as Map)['modifiers']) as List).add({
        'option_name_snapshot': 'X',
        'quantity': 1,
      });
      expect(PosOrderDetail.fromJson(badMod), isNull);
      final badLine = envelope();
      ((badLine['items']! as List).first as Map).remove('line_total_minor');
      expect(PosOrderDetail.fromJson(badLine), isNull);
      final negative = envelope();
      ((((negative['items']! as List).first as Map)['modifiers'])
          as List)[0] = {
        'option_name_snapshot': 'Extra',
        'price_minor_snapshot': -250,
        'quantity': 2,
      };
      expect(PosOrderDetail.fromJson(negative), isNull);
    });

    test('E7 a genuinely zero-valued order still parses (zero is authoritative '
        'when explicit)', () {
      final comped = envelope();
      final order = comped['order']! as Map;
      order['subtotal_minor'] = 0;
      order['discount_total_minor'] = 0;
      order['tax_total_minor'] = 0;
      order['grand_total_minor'] = 0;
      comped['items'] = <Object?>[];
      comped['rounds'] = <Object?>[];
      comped['payment'] = null;
      final detail = PosOrderDetail.fromJson(comped);
      expect(detail, isNotNull);
      expect(detail!.grandTotalMinor, 0);
      expect(detail.payment, isNull);
    });
  });

  group('F. controller-owned safe entry (final Finding 1)', () {
    test('F1 a cart line added DURING the detail load blocks the commit: no '
        'addition mode, no target, no op id — the line stays a normal cart '
        'line', () async {
      final (container, transport, cart, repo) = _gatedHarness([
        (p) => _applied(p),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      final entry = notifier.enterForOrder('o-1');
      // The reservation is SYNCHRONOUS: the fetch started, the target is held.
      expect(repo.requested, ['o-1']);
      expect(
        container.read(additionControllerProvider).phase,
        AdditionPhase.entering,
      );
      // The cashier keeps working the NORMAL cart while the detail loads.
      cart.addItem(_menuItem);
      expect(container.read(cartControllerProvider).isEmpty, isFalse);
      // The fetch finally lands — the commit must now REFUSE.
      repo.gates.single.complete(_detail());
      expect(await entry, AdditionEntryResult.cartNotEmpty);
      final state = container.read(additionControllerProvider);
      expect(state.active, isFalse);
      expect(state.entryOrderId, isNull); // the reservation was released
      expect(state.hasOpenAttempt, isFalse); // no operation id was allocated
      expect(transport.calls, isEmpty);
      // The cart was NOT touched: the line is still an ordinary cart line.
      final cartState = container.read(cartControllerProvider);
      expect(cartState.lines.single.menuItemId, 'm-race');
      expect(cart.clearCount, 0);
    });

    test('F2 while order A is loading, entry for order B is REFUSED', () async {
      final (container, _, _, repo) = _gatedHarness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      final entryA = notifier.enterForOrder('o-a');
      expect(
        await notifier.enterForOrder('o-b'),
        AdditionEntryResult.blockedDifferentTarget,
      );
      expect(repo.requested, ['o-a']); // B never even fetched
      repo.gates.single.complete(_detail(orderId: 'o-a'));
      expect(await entryA, AdditionEntryResult.entered);
      expect(container.read(additionControllerProvider).target?.orderId, 'o-a');
    });

    test('F3 entering the SAME order twice while loading is an idempotent '
        'no-op (one fetch, one commit)', () async {
      final (container, _, _, repo) = _gatedHarness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      final first = notifier.enterForOrder('o-1');
      expect(await notifier.enterForOrder('o-1'), AdditionEntryResult.entered);
      repo.gates.single.complete(_detail());
      expect(await first, AdditionEntryResult.entered);
      expect(repo.requested, hasLength(1));
      expect(container.read(additionControllerProvider).target?.orderId, 'o-1');
    });

    test('F4 a detail-fetch failure releases the reservation; a later clean '
        'entry succeeds', () async {
      final (container, _, _, repo) = _gatedHarness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      final failing = notifier.enterForOrder('o-1');
      repo.gates.single.completeError(
        const PosOrderDetailException(PosOrderDetailFailure.transport),
      );
      expect(await failing, AdditionEntryResult.detailUnavailable);
      final released = container.read(additionControllerProvider);
      expect(released.entryOrderId, isNull);
      expect(released.phase, AdditionPhase.idle);
      // The path is clean again: the SAME order can be entered fresh.
      final retry = notifier.enterForOrder('o-1');
      repo.gates.last.complete(_detail());
      expect(await retry, AdditionEntryResult.entered);
      expect(container.read(additionControllerProvider).active, isTrue);
    });

    test('F5 a STALE entry fetch (cancelled, then a new target) has ZERO side '
        'effects — it can never install order A over order B', () async {
      final (container, _, _, repo) = _gatedHarness([(p) => _applied(p)]);
      final notifier = container.read(additionControllerProvider.notifier);
      final entryA = notifier.enterForOrder('o-a');
      // Cancel while ENTERING is allowed (nothing is on the wire yet).
      expect(notifier.exit(), isTrue);
      final entryB = notifier.enterForOrder('o-b');
      repo.gates[1].complete(_detail(orderId: 'o-b'));
      expect(await entryB, AdditionEntryResult.entered);
      expect(container.read(additionControllerProvider).target?.orderId, 'o-b');
      // Order A's DELAYED fetch lands LAST — the fence must discard it.
      repo.gates[0].complete(_detail(orderId: 'o-a'));
      expect(await entryA, AdditionEntryResult.superseded);
      expect(container.read(additionControllerProvider).target?.orderId, 'o-b');
    });
  });

  group('G. sending-cancel refusal + stale-response fencing (final F2)', () {
    test('G1 cancel is REFUSED while sending; no new target may begin; the '
        'delayed response then completes attempt A normally', () async {
      final transport = _GatedTransport();
      final cart = _ProbeCart();
      final repo = _FakeDetailRepo();
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(transport),
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1'),
          ),
          cartControllerProvider.overrideWith(() => cart),
          orderDetailRepositoryProvider.overrideWithValue(repo),
          orderSnapshotRepositoryProvider.overrideWithValue(
            DemoOrderSnapshotRepository(),
          ),
          posSyncPollIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final submitted = notifier.submit();
      final sendingState = container.read(additionControllerProvider);
      expect(sendingState.sending, isTrue);
      expect(sendingState.canCancel, isFalse);
      // Finding 2: cancel while the operation is on the wire is a NO-OP.
      expect(notifier.exit(), isFalse);
      final held = container.read(additionControllerProvider);
      expect(held.sending, isTrue);
      expect(held.target?.orderId, 'o-1');
      // No other target may begin while the attempt is open.
      expect(
        await notifier.enterForOrder('o-2'),
        AdditionEntryResult.blockedPendingAttempt,
      );
      // The delayed response finally lands — ONLY attempt A's state updates,
      // and the flow completes through the verified refresh.
      transport.gates.single.complete(_applied(transport.calls.single));
      final result = await submitted;
      expect(result.applied, isTrue);
      expect(result.refreshRequired, isFalse);
      expect(cart.clearCount, 1);
      expect(
        container.read(additionControllerProvider).phase,
        AdditionPhase.idle,
      );
    });

    test('G2 a STALE refresh callback (a newer generation exists) has ZERO '
        'side effects: it cannot clear a newer cart, retarget, or complete '
        'another attempt', () async {
      final (container, transport, cart, repo) = _gatedHarness([
        (p) => _applied(p),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      final entry = notifier.enterForOrder('o-1');
      repo.gates[0].complete(_detail());
      expect(await entry, AdditionEntryResult.entered);
      seedCart(container);
      // Submit applies instantly; the IN-SUBMIT refresh fetch (gate 1) hangs.
      final submitted = notifier.submit();
      await pumpEventQueue(times: 5);
      expect(
        container.read(additionControllerProvider).awaitingRefresh,
        isTrue,
      );
      // The cashier retries the refresh (gate 2) — THIS one lands first and
      // completes the reconciliation exactly once.
      final retried = notifier.retryRefresh();
      await pumpEventQueue(times: 5);
      repo.gates[2].complete(_detail());
      expect(await retried, isTrue);
      expect(cart.clearCount, 1);
      expect(
        container.read(additionControllerProvider).phase,
        AdditionPhase.idle,
      );
      // A NEW flow begins: order B is entered and the cart holds new work.
      final entryB = notifier.enterForOrder('o-b');
      repo.gates[3].complete(_detail(orderId: 'o-b'));
      expect(await entryB, AdditionEntryResult.entered);
      cart.addItem(_menuItem);
      // NOW the stale in-submit refresh (gate 1) finally lands: the fence
      // must discard it — no second cart clear, no retarget, no completion
      // of the newer attempt, no phase change.
      repo.gates[1].complete(_detail());
      final result = await submitted;
      expect(result.applied, isTrue); // the operation DID apply
      expect(cart.clearCount, 1); // the newer cart was NOT cleared
      final state = container.read(additionControllerProvider);
      expect(state.target?.orderId, 'o-b');
      expect(state.phase, AdditionPhase.active);
      expect(container.read(cartControllerProvider).isEmpty, isFalse);
      expect(transport.calls, hasLength(1)); // and nothing was re-dispatched
    });
  });

  group('H. applied-awaiting-refresh (final Finding 4)', () {
    test('H1 applied + refresh NETWORK failure → appliedAwaitingRefresh: the '
        'attempt is retained, the cart is NOT cleared, the previous detail '
        'stays installed, cancel is refused', () async {
      final repo = _FakeDetailRepo([
        (id) async => _detail(orderId: id), // the entry load
        (id) async => throw const PosOrderDetailException(
          PosOrderDetailFailure.transport,
        ),
      ]);
      final (container, transport, cart, _) = _harness([
        (p) => _applied(p),
      ], detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isTrue);
      expect(result.refreshRequired, isTrue); // honest: saved, view stale
      final state = container.read(additionControllerProvider);
      expect(state.awaitingRefresh, isTrue);
      expect(state.hasOpenAttempt, isTrue); // identity stays known
      expect(state.target?.orderId, 'o-1'); // previous valid detail survives
      expect(cart.clearCount, 0); // nothing silently merged
      expect(state.canCancel, isFalse); // the server owns the addition
      expect(notifier.exit(), isFalse);
      expect(transport.calls, hasLength(1));
    });

    test('H2 applied + MALFORMED refresh (parse rejects) behaves the same — '
        'the malformed data is never installed', () async {
      final repo = _FakeDetailRepo([
        (id) async => _detail(orderId: id),
        (id) async => throw const PosOrderDetailException(
          PosOrderDetailFailure.malformed,
        ),
      ]);
      final (container, _, cart, _) = _harness([
        (p) => _applied(p),
      ], detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.applied, isTrue);
      expect(result.refreshRequired, isTrue);
      final state = container.read(additionControllerProvider);
      expect(state.awaitingRefresh, isTrue);
      expect(state.target?.orderId, 'o-1');
      expect(cart.clearCount, 0);
    });

    test('H3 a refresh that parses but LACKS the applied round is NOT '
        'verification — the state stays awaiting-refresh', () async {
      final repo = _FakeDetailRepo([
        (id) async => _detail(orderId: id),
        // Valid parse, but the applied round r-new is absent (a stale read).
        (id) async => _detail(orderId: id, rounds: const []),
        (id) async => _detail(orderId: id), // the later honest read
      ]);
      final (container, _, cart, _) = _harness([
        (p) => _applied(p),
      ], detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      final result = await notifier.submit();
      expect(result.refreshRequired, isTrue);
      expect(
        container.read(additionControllerProvider).awaitingRefresh,
        isTrue,
      );
      expect(cart.clearCount, 0);
      // The later read DOES contain the round — cleanup completes.
      expect(await notifier.retryRefresh(), isTrue);
      expect(cart.clearCount, 1);
    });

    test('H4 the refresh retry dispatches NO second order.items_add and '
        'completes the cleanup EXACTLY once', () async {
      final repo = _FakeDetailRepo([
        (id) async => _detail(orderId: id),
        (id) async => throw const PosOrderDetailException(
          PosOrderDetailFailure.transport,
        ),
        (id) async => _detail(orderId: id),
      ]);
      final (container, transport, cart, _) = _harness([
        (p) => _applied(p),
      ], detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      await notifier.submit();
      expect(transport.calls, hasLength(1));
      expect(await notifier.retryRefresh(), isTrue);
      expect(transport.calls, hasLength(1)); // refresh-only — never a re-send
      expect(cart.clearCount, 1);
      final state = container.read(additionControllerProvider);
      expect(state.phase, AdditionPhase.idle);
      expect(state.hasOpenAttempt, isFalse);
      // Cleanup ran EXACTLY once: a duplicate retry is a harmless no-op.
      expect(await notifier.retryRefresh(), isFalse);
      expect(cart.clearCount, 1);
    });

    test('H5 submit() during awaiting-refresh NEVER re-dispatches the applied '
        'operation — even a mutated cart only retries the refresh', () async {
      final repo = _FakeDetailRepo([
        (id) async => _detail(orderId: id),
        (id) async => throw const PosOrderDetailException(
          PosOrderDetailFailure.transport,
        ),
        (id) async => _detail(orderId: id),
      ]);
      final (container, transport, cart, _) = _harness([
        (p) => _applied(p),
      ], detailRepo: repo);
      final notifier = container.read(additionControllerProvider.notifier);
      await notifier.enterForOrder('o-1');
      seedCart(container);
      await notifier.submit();
      expect(
        container.read(additionControllerProvider).awaitingRefresh,
        isTrue,
      );
      final again = await notifier.submit();
      expect(again.applied, isTrue);
      expect(again.refreshRequired, isFalse); // handler 3 verified the round
      expect(transport.calls, hasLength(1)); // the cart was NOT reinterpreted
      expect(cart.clearCount, 1);
    });
  });

  group('I. the authoritative receipt-source policy (final Finding 4)', () {
    SubmittedOrderView localView() =>
        submittedOrderViewFromDetail(_detail(rounds: const []));
    CashPayment localPayment() => CashPayment(
      paymentId: 'local-1',
      orderNumber: '#O00001',
      deviceId: 'dev-1',
      localOperationId: 'op-1',
      method: PaymentMethod.cash,
      status: PaymentStatus.completed,
      amountMinor: 2500,
      tenderedMinor: 3000,
      changeMinor: 500,
      currencyCode: 'ILS',
      receiptNumber: 'L-1',
      paidAt: DateTime.utc(2026, 7, 22, 13),
    );

    test(
      'I1 a server-backed order with a FAILED detail load yields NO '
      'receipt — never a partial local one (additions could be missing)',
      () async {
        final repo = _ThrowingDetailRepo();
        final source = await authoritativeReceiptSource(
          isDemoMode: false,
          orderId: 'o-1',
          localView: localView(),
          localPayment: localPayment(),
          repository: repo,
        );
        expect(source, isNull); // the caller shows the honest retry message
      },
    );

    test('I2 a malformed completed-payment detail yields NO receipt (honest '
        'retry, never a guessed payment)', () async {
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'o-1',
        localView: localView(),
        localPayment: null,
        repository: _ThrowingDetailRepo(),
      );
      expect(source, isNull);
    });

    test(
      'I3 a later SUCCESSFUL load yields the combined receipt: original '
      'AND round items together, with the REAL payment id/status/time',
      () async {
        final detail = PosOrderDetail.fromJson(envelope())!;
        final repo = _FakeDetailRepo([(id) async => detail]);
        final source = await authoritativeReceiptSource(
          isDemoMode: false,
          orderId: 'o-1',
          localView: null,
          localPayment: null,
          repository: repo,
        );
        expect(source, isNotNull);
        expect(source!.$1.lines, hasLength(2)); // Burger (orig) + Fries (round)
        expect(source.$2.paymentId, _paymentUuid);
        expect(source.$2.status, PaymentStatus.completed);
        expect(source.$2.paidAt, DateTime.parse('2026-07-22T12:34:56.000Z'));
      },
    );

    test('I4 demo mode keeps its self-contained local receipt and never asks '
        'the server', () async {
      final repo = _FakeDetailRepo();
      final source = await authoritativeReceiptSource(
        isDemoMode: true,
        orderId: 'o-1',
        localView: localView(),
        localPayment: localPayment(),
        repository: repo,
      );
      expect(source, isNotNull);
      expect(repo.fetches, 0);
      expect(source!.$2.paymentId, 'local-1');
    });

    test('I5 an authoritative detail WITHOUT a payment may stand on this '
        'till\'s own queued payment record — the itemized view stays '
        'authoritative', () async {
      final repo = _FakeDetailRepo(); // default detail has NO payment block
      final source = await authoritativeReceiptSource(
        isDemoMode: false,
        orderId: 'o-1',
        localView: null,
        localPayment: localPayment(),
        repository: repo,
      );
      expect(source, isNotNull);
      expect(source!.$2.paymentId, 'local-1'); // the real local record
      expect(repo.fetches, 1);
    });
  });

  group('J. authoritative payment identity/status (final Finding 3)', () {
    test('J1 a missing or NON-UUID payment_id fails the whole detail (no '
        'fabricated identity)', () {
      final missing = envelope();
      (missing['payment']! as Map).remove('payment_id');
      expect(PosOrderDetail.fromJson(missing), isNull);
      final fabricated = envelope();
      (fabricated['payment']! as Map)['payment_id'] = 'authoritative';
      expect(PosOrderDetail.fromJson(fabricated), isNull);
      final truncated = envelope();
      (truncated['payment']! as Map)['payment_id'] = '0a911111-2222-4333';
      expect(PosOrderDetail.fromJson(truncated), isNull);
    });

    test('J2 a missing, unknown, or NON-COMPLETED payment_status fails (the '
        'detail RPC emits only completed — anything else is a lie)', () {
      final missing = envelope();
      (missing['payment']! as Map).remove('payment_status');
      expect(PosOrderDetail.fromJson(missing), isNull);
      for (final status in [
        'paid',
        'pending',
        'tendered',
        'voided',
        'failed',
      ]) {
        final wrong = envelope();
        (wrong['payment']! as Map)['payment_status'] = status;
        expect(PosOrderDetail.fromJson(wrong), isNull, reason: status);
      }
    });

    test('J3 a valid completed payment parses with its REAL id, stored '
        'status, method and authoritative time — nothing synthesized', () {
      final detail = PosOrderDetail.fromJson(envelope());
      expect(detail, isNotNull);
      final p = detail!.payment!;
      expect(p.paymentId, _paymentUuid);
      expect(p.status, PaymentStatus.completed);
      expect(p.method, PaymentMethod.card);
      expect(p.paidAt, DateTime.parse('2026-07-22T12:34:56.000Z'));
    });

    test('J4 a SECOND POS parsing the same detail receives the SAME real '
        'payment identity (cross-device receipt truth)', () {
      final first = cashPaymentFromDetail(
        PosOrderDetail.fromJson(envelope())!,
      )!;
      final second = cashPaymentFromDetail(
        PosOrderDetail.fromJson(envelope())!,
      )!;
      expect(first.paymentId, _paymentUuid);
      expect(second.paymentId, first.paymentId);
      expect(second.status, first.status);
      expect(second.paidAt, first.paidAt);
    });
  });
}
