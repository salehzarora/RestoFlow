import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
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

/// PSC-001C — POS unit coverage for service rounds:
///  A. the canAddItems policy (one place decides; server re-enforces);
///  B. the addition controller: exact wire contract, honest failure retention,
///     idempotent retry (SAME operation id), authoritative-success cleanup;
///  C. the pos_order_detail parse + the COMBINED receipt converters.

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
  tableLabel: 'T1',
  items: const [],
  rounds: const [],
);

CartLineView _line({String id = 'l1', String item = 'm1'}) => CartLineView(
  lineId: id,
  menuItemId: item,
  name: 'Fries',
  quantity: 2,
  unitPriceMinor: 500,
  lineTotalMinor: 1000,
  currencyCode: 'ILS',
);

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
  bool cleared = false;
  @override
  void clear() {
    cleared = true;
    super.clear();
  }
}

class _FakeDetailRepo implements OrderDetailRepository {
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    return _detail(orderId: orderId);
  }
}

(ProviderContainer, _FakeTransport, _ProbeCart, _FakeDetailRepo) _harness(
  List<Object? Function(Map<String, dynamic>)> responses,
) {
  final transport = _FakeTransport(responses);
  final cart = _ProbeCart();
  final detailRepo = _FakeDetailRepo();
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
      orderDetailRepositoryProvider.overrideWithValue(detailRepo),
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
  return (container, transport, cart, detailRepo);
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
      notifier.enter(_detail());
      final result = await notifier.submit([_line()]);
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
      expect(item['menu_item_id'], 'm1');
      expect(item['quantity'], 2);
      expect(item['unit_price_minor_snapshot'], 500);
      // Additions never carry a line discount.
      expect(item.containsKey('line_discount_minor'), isFalse);
      // NO order-level client totals ride the payload.
      expect(payload.containsKey('subtotal_minor'), isFalse);
      expect(payload.containsKey('grand_total_minor'), isFalse);
    });

    test(
      'B2 applied: cart cleared ONLY then + authoritative detail reload',
      () async {
        final (container, _, cart, detailRepo) = _harness([(p) => _applied(p)]);
        final notifier = container.read(additionControllerProvider.notifier);
        notifier.enter(_detail());
        await notifier.submit([_line()]);
        expect(cart.cleared, isTrue);
        expect(detailRepo.fetches, 1);
        final state = container.read(additionControllerProvider);
        expect(state.failed, isFalse);
        expect(state.sending, isFalse);
      },
    );

    test('B3 a typed rejection keeps the pending addition local + retryable '
        '(cart NOT cleared)', () async {
      final (container, _, cart, _) = _harness([
        (p) => _rejected(p, 'order_already_settled'),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      notifier.enter(_detail());
      final result = await notifier.submit([_line()]);
      expect(result.applied, isFalse);
      expect(result.error, 'order_already_settled');
      expect(cart.cleared, isFalse);
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
        notifier.enter(_detail());
        await notifier.submit([_line()]);
        final retry = await notifier.submit([_line()]);
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
        notifier.enter(_detail());
        final result = await notifier.submit([_line()]);
        expect(result.applied, isFalse);
        expect(cart.cleared, isFalse);
      },
    );

    test('B6 a transport failure is a retryable local failure', () async {
      final (container, _, cart, _) = _harness([
        (p) => throw StateError('offline'),
      ]);
      final notifier = container.read(additionControllerProvider.notifier);
      notifier.enter(_detail());
      final result = await notifier.submit([_line()]);
      expect(result.applied, isFalse);
      expect(cart.cleared, isFalse);
      expect(container.read(additionControllerProvider).failed, isTrue);
    });
  });

  group('C. pos_order_detail parse + combined receipt converters', () {
    Map<String, Object?> envelope() => {
      'ok': true,
      'order': {
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
      'payment': {
        'method': 'card',
        'amount_minor': 3000,
        'tendered_minor': 3000,
        'change_minor': 0,
        'receipt_number': '42',
      },
    };

    test('C1 the combined authoritative detail parses (original + added)', () {
      final detail = PosOrderDetail.fromJson(envelope());
      expect(detail, isNotNull);
      expect(detail!.items, hasLength(2));
      expect(detail.items.first.roundNumber, isNull);
      expect(detail.items.last.roundNumber, 2);
      expect(detail.rounds.single.status, 'ready');
      expect(detail.grandTotalMinor, 3000);
      expect(detail.payment?.method, 'card');
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
    });

    test('C3 a malformed item row rejects the WHOLE detail (atomic)', () {
      final bad = envelope();
      (bad['items']! as List).add({'quantity': 'NaN'});
      expect(PosOrderDetail.fromJson(bad), isNull);
    });
  });
}
