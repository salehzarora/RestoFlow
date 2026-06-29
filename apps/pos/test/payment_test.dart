import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';

void main() {
  late DemoPaymentStore store;
  late ProviderContainer container;

  setUp(() {
    store = DemoPaymentStore(
      clock: () => DateTime(2026, 6, 28, 9, 30),
      openingFloatMinor: 20000,
    );
    container = ProviderContainer(
      overrides: [paymentRepositoryProvider.overrideWithValue(store)],
    );
  });
  tearDown(() => container.dispose());

  PaymentController controller() =>
      container.read(paymentControllerProvider.notifier);
  PaymentState state() => container.read(paymentControllerProvider);

  test('opens with the drawer active and the opening float in the drawer', () {
    final shift = state().shift;
    expect(shift.drawerOpen, isTrue);
    expect(shift.openingFloatMinor, 20000);
    expect(shift.cashInDrawerMinor, 20000);
    expect(shift.lastPaymentMinor, isNull);
  });

  test('an exact cash payment completes with zero change', () async {
    final p = await controller().payCash(
      orderId: 'order-1',
      orderNumber: 'DEMO-0001',
      amountMinor: 4200,
      tenderedMinor: 4200,
      currencyCode: 'ILS',
    );
    expect(p.status, PaymentStatus.completed);
    expect(p.status.isPaid, isTrue);
    expect(p.method, PaymentMethod.cash);
    expect(p.amountMinor, 4200);
    expect(p.tenderedMinor, 4200);
    expect(p.changeMinor, 0);
    expect(p.receiptNumber, 'PROV-0001');
    expect(state().paymentFor('DEMO-0001'), isNotNull);
  });

  test('an overpayment computes the change in integer minor units', () async {
    final p = await controller().payCash(
      orderId: 'order-1',
      orderNumber: 'DEMO-0001',
      amountMinor: 4200,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
    );
    expect(p.changeMinor, 800);
    expect(p.changeMinor, isA<int>());
    expect(p.tenderedMinor, isA<int>());
  });

  test('insufficient cash is rejected and records nothing', () async {
    await expectLater(
      controller().payCash(
        orderId: 'order-1',
        orderNumber: 'DEMO-0001',
        amountMinor: 4200,
        tenderedMinor: 4000,
        currencyCode: 'ILS',
      ),
      throwsA(isA<PaymentException>()),
    );
    expect(state().paymentFor('DEMO-0001'), isNull);
    expect(state().shift.cashInDrawerMinor, 20000);
  });

  test(
    'the drawer grows by the ORDER amount (not the tender) per payment',
    () async {
      await controller().payCash(
        orderId: 'order-1',
        orderNumber: 'DEMO-0001',
        amountMinor: 4200,
        tenderedMinor: 5000, // ₪8.00 change handed back
        currencyCode: 'ILS',
      );
      expect(state().shift.cashInDrawerMinor, 20000 + 4200);
      expect(state().shift.lastPaymentMinor, 4200);

      await controller().payCash(
        orderId: 'order-2',
        orderNumber: 'DEMO-0002',
        amountMinor: 900,
        tenderedMinor: 1000,
        currencyCode: 'ILS',
      );
      expect(state().shift.cashInDrawerMinor, 20000 + 4200 + 900);
      expect(state().shift.lastPaymentMinor, 900);
    },
  );

  test('paying an already-paid order is idempotent', () async {
    final a = await controller().payCash(
      orderId: 'order-1',
      orderNumber: 'DEMO-0001',
      amountMinor: 4200,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
    );
    final b = await controller().payCash(
      orderId: 'order-1',
      orderNumber: 'DEMO-0001',
      amountMinor: 4200,
      tenderedMinor: 9999,
      currencyCode: 'ILS',
    );
    expect(b.paymentId, a.paymentId);
    expect(b.tenderedMinor, 5000); // the original tender, not re-recorded
    expect(state().shift.cashInDrawerMinor, 20000 + 4200); // not double-counted
  });
}
