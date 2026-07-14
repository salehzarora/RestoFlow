import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-ORDERS-AND-PAYMENT-001 (B/C): the local recent/unpaid-orders store —
/// pay-later creates an UNPAID recent order with no payment; a later payment
/// marks it paid; the today+yesterday window prunes older orders; and the
/// order+payment snapshots round-trip through persistence.
SubmittedOrderView _view(
  String number, {
  int subtotal = 4200,
  String? customer,
  String? table,
}) => SubmittedOrderView(
  orderNumber: number,
  orderType: table == null ? OrderType.takeaway : OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: subtotal,
  customerName: customer,
  tableLabel: table,
  orderId: 'oid-$number',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: subtotal,
      currencyCode: 'ILS',
      modifiers: const ['Cheese'],
      note: 'No onion',
    ),
  ],
);

CashPayment _payment(String number, {int amount = 4200}) => CashPayment(
  paymentId: 'pay-$number',
  orderNumber: number,
  deviceId: 'd1',
  localOperationId: 'op-$number',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: amount,
  tenderedMinor: amount,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.now(),
);

/// The order identity of a row built by [_view] — the SAME derivation production uses,
/// so these tests exercise the real association path rather than a hand-made key.
PosOrderIdentity _id(String number) => PosOrderIdentity.server('oid-$number');

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serialization round-trips the order + payment snapshot', () {
    final order = PosRecentOrder(
      order: _view('#A1', customer: 'Layla', table: 'T3'),
      submittedAt: DateTime.utc(2026, 7, 9, 12, 30),
      payment: _payment('#A1'),
    );
    final restored = PosRecentOrder.fromJson(order.toJson());
    expect(restored.orderNumber, '#A1');
    expect(restored.order!.customerName, 'Layla');
    expect(restored.order!.tableLabel, 'T3');
    expect(restored.order!.orderId, 'oid-#A1');
    expect(restored.order!.lines.single.name, 'Burger');
    expect(restored.order!.lines.single.modifiers, ['Cheese']);
    expect(restored.order!.lines.single.note, 'No onion');
    expect(restored.isPaid, isTrue);
    expect(restored.payment!.amountMinor, 4200);
    expect(restored.grandTotalMinor, 4200);
  });

  test('an unpaid order round-trips with no payment', () {
    final order = PosRecentOrder(
      order: _view('#A2'),
      submittedAt: DateTime.utc(2026, 7, 9, 12, 30),
    );
    final restored = PosRecentOrder.fromJson(order.toJson());
    expect(restored.payment, isNull);
    expect(restored.isPaid, isFalse);
  });

  test(
    'SharedPrefs store persists + reloads per scope, isolates by device',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsRecentOrdersStore(prefs);
      final order = PosRecentOrder(
        order: _view('#A3'),
        submittedAt: DateTime.now(),
        payment: _payment('#A3'),
      );
      await store.persist('device-1', [order]);
      final loaded = await store.load('device-1');
      expect(loaded.single.orderNumber, '#A3');
      expect(loaded.single.isPaid, isTrue);
      // A different device sees nothing (per-device isolation).
      expect(await store.load('device-2'), isEmpty);
    },
  );

  test(
    'recordSubmitted adds an UNPAID order; recordPayment marks it paid',
    () async {
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        posRecentOrdersControllerProvider.notifier,
      );

      notifier.recordSubmitted(_view('#A4'));
      var state = container.read(posRecentOrdersControllerProvider);
      expect(state.length, 1);
      expect(state.single.isPaid, isFalse);
      expect(notifier.unpaidCount, 1);

      notifier.recordPayment(_id('#A4'), _payment('#A4'));
      state = container.read(posRecentOrdersControllerProvider);
      expect(state.single.isPaid, isTrue);
      expect(notifier.unpaidCount, 0);
    },
  );

  test(
    'recordSubmitted is idempotent per order number (no duplicates)',
    () async {
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        posRecentOrdersControllerProvider.notifier,
      );
      notifier.recordSubmitted(_view('#A5'));
      notifier.recordSubmitted(_view('#A5'));
      expect(container.read(posRecentOrdersControllerProvider).length, 1);
    },
  );

  // ---- MONEY-VOID-001: cancelled (voided) orders ----

  test('a voided order round-trips (voidedAt + reason) with no payment', () {
    final order = PosRecentOrder(
      order: _view('#V1'),
      submittedAt: DateTime.utc(2026, 7, 9, 12, 30),
      voidedAt: DateTime.utc(2026, 7, 9, 12, 45),
      voidReason: 'wrong table',
    );
    final restored = PosRecentOrder.fromJson(order.toJson());
    expect(restored.isVoided, isTrue);
    expect(restored.voidReason, 'wrong table');
    expect(restored.payment, isNull);
    expect(restored.isPaid, isFalse);
  });

  test(
    'markVoided cancels an unpaid order; it leaves the unpaid count',
    () async {
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        posRecentOrdersControllerProvider.notifier,
      );

      notifier.recordSubmitted(_view('#V2'));
      expect(notifier.unpaidCount, 1);

      notifier.markVoided(_id('#V2'), 'duplicate order');
      final state = container.read(posRecentOrdersControllerProvider);
      expect(state.single.isVoided, isTrue);
      expect(state.single.voidReason, 'duplicate order');
      // A voided order is no longer "unpaid" (drops off the pay-later list).
      expect(notifier.unpaidCount, 0);
    },
  );

  test('a paid order cannot be voided locally (no money is unwound)', () async {
    final container = ProviderContainer(
      overrides: [
        posRecentOrdersStoreProvider.overrideWithValue(
          InMemoryRecentOrdersStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(posRecentOrdersControllerProvider.notifier);
    notifier.recordSubmitted(_view('#V3'));
    notifier.recordPayment(_id('#V3'), _payment('#V3'));

    notifier.markVoided(_id('#V3'), 'too late');
    final state = container.read(posRecentOrdersControllerProvider);
    expect(state.single.isPaid, isTrue);
    expect(state.single.isVoided, isFalse);
  });

  test(
    'a voided order cannot then be paid (terminal state wins on merge)',
    () async {
      final container = ProviderContainer(
        overrides: [
          posRecentOrdersStoreProvider.overrideWithValue(
            InMemoryRecentOrdersStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(
        posRecentOrdersControllerProvider.notifier,
      );
      notifier.recordSubmitted(_view('#V4'));
      notifier.markVoided(_id('#V4'), 'wrong');

      notifier.recordPayment(_id('#V4'), _payment('#V4'));
      final state = container.read(posRecentOrdersControllerProvider);
      expect(state.single.isVoided, isTrue);
      expect(state.single.isPaid, isFalse);
    },
  );

  test(
    'recovery loads persisted orders and prunes older than yesterday',
    () async {
      final store = InMemoryRecentOrdersStore();
      final now = DateTime.now();
      await store.persist(kDemoSyncScope.key, [
        PosRecentOrder(
          order: _view('#OLD'),
          submittedAt: now.subtract(const Duration(days: 3)),
          payment: _payment('#OLD'),
        ),
        PosRecentOrder(
          order: _view('#NEW'),
          submittedAt: now,
          payment: _payment('#NEW'),
        ),
      ]);
      final container = ProviderContainer(
        overrides: [posRecentOrdersStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // Trigger build + async recover.
      container.read(posRecentOrdersControllerProvider);
      await _settle();
      final state = container.read(posRecentOrdersControllerProvider);
      expect(state.map((o) => o.orderNumber).toList(), ['#NEW']);
    },
  );
}
