import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

Money ils(int v) => Money(v, 'ILS');

void main() {
  group('order/line validation (RF-036)', () {
    test('an empty order is rejected', () {
      expect(
        () => MoneyOrder(currency: 'ILS', lines: []),
        throwsA(isA<InvalidMoneyException>()),
      );
    });

    test('a line whose currency differs from the order is rejected', () {
      expect(
        () => MoneyOrder(
          currency: 'ILS',
          lines: [MoneyLine(unitPrice: Money(100, 'USD'), quantity: 1)],
        ),
        throwsA(isA<CurrencyMismatchException>()),
      );
    });

    test('a non-positive line quantity is rejected', () {
      expect(
        () => MoneyLine(unitPrice: ils(100), quantity: 0),
        throwsA(isA<InvalidQuantityException>()),
      );
      expect(
        () => MoneyLine(unitPrice: ils(100), quantity: -2),
        throwsA(isA<InvalidQuantityException>()),
      );
    });
  });

  group('engine clamping + defaults (RF-036)', () {
    test(
      'a fixed discount larger than the line clamps the line total to zero',
      () {
        final calc = OrderCalculator.calculate(
          MoneyOrder(
            currency: 'ILS',
            lines: [
              MoneyLine(
                unitPrice: ils(1000),
                quantity: 1,
                itemDiscount: DiscountSet(fixed: FixedDiscount(999999)),
              ),
            ],
          ),
        );
        final line = calc.lines.single;
        expect(line.subtotal, ils(1000));
        expect(line.total, ils(0)); // clamped, never negative
        expect(line.discount, ils(1000)); // effective discount = capped at base
        expect(calc.subtotal, ils(0));
        expect(calc.grandTotal, ils(0));
        expect(calc.reconciles, isTrue);
      },
    );

    test('an order-level discount larger than the subtotal clamps to zero', () {
      final calc = OrderCalculator.calculate(
        MoneyOrder(
          currency: 'ILS',
          lines: [MoneyLine(unitPrice: ils(500), quantity: 1)],
          orderDiscount: DiscountSet(fixed: FixedDiscount(999999)),
        ),
      );
      expect(calc.subtotal, ils(500));
      expect(calc.orderDiscount, ils(500)); // capped at subtotal
      expect(calc.grandTotal, ils(0));
      expect(calc.reconciles, isTrue);
    });

    test('tax is zero by default (disabled policy, no policy supplied)', () {
      final calc = OrderCalculator.calculate(
        MoneyOrder(
          currency: 'ILS',
          lines: [MoneyLine(unitPrice: ils(1000), quantity: 1)],
        ),
      );
      expect(calc.tax, ils(0));
      expect(calc.serviceCharge, ils(0));
      expect(calc.grandTotal, ils(1000));
    });
  });
}
