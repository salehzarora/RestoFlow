import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

Money ils(int v) => Money(v, 'ILS');

/// TEST-ONLY tax policy (a tax-exclusive percentage in basis points). It exists
/// only here to validate the MONEY_AND_TAX_SPEC §9.1 worked example including
/// tax — production code ships NO rate (Q-002). Not exported by the package.
class _TestExclusiveTaxPolicy implements TaxPolicy {
  const _TestExclusiveTaxPolicy(this.basisPoints);
  final int basisPoints;

  @override
  Money computeTax(Money discountedBase, RoundingPolicy rounding) => Money(
    rounding.roundDiv(discountedBase.amountMinor * basisPoints, 10000),
    discountedBase.currencyCode,
  );
}

void main() {
  group('MONEY_AND_TAX_SPEC §9.1 golden values (RF-036)', () {
    // Line A: 5200 x 2 = 10400, item 10% off; Line B: 1200; order fixed 500.
    MoneyOrder orderA({TaxPolicy taxPolicy = const DisabledTaxPolicy()}) =>
        MoneyOrder(
          currency: 'ILS',
          taxPolicy: taxPolicy,
          lines: [
            MoneyLine(
              unitPrice: ils(5200),
              quantity: 2,
              itemDiscount: DiscountSet(percentage: PercentageDiscount(1000)),
            ),
            MoneyLine(unitPrice: ils(1200), quantity: 1),
          ],
          orderDiscount: DiscountSet(fixed: FixedDiscount(500)),
        );

    test('Example A — disabled tax → grand total 10060', () {
      final calc = OrderCalculator.calculate(orderA());
      expect(calc.lines[0].subtotal, ils(10400));
      expect(calc.lines[0].discount, ils(1040));
      expect(calc.lines[0].total, ils(9360));
      expect(calc.lines[1].total, ils(1200));
      expect(calc.subtotal, ils(10560));
      expect(calc.itemDiscountTotal, ils(1040));
      expect(calc.orderDiscount, ils(500));
      expect(calc.discountTotal, ils(1540));
      expect(calc.serviceCharge, ils(0));
      expect(calc.tax, ils(0));
      expect(calc.grandTotal, ils(10060));
      expect(calc.reconciles, isTrue);
    });

    test('Example B — test-only 17% exclusive tax → tax 1710, grand 11770', () {
      final calc = OrderCalculator.calculate(
        orderA(taxPolicy: const _TestExclusiveTaxPolicy(1700)),
      );
      expect(
        calc.tax,
        ils(1710),
      ); // round(10060 * 1700 / 10000) = round(1710.2)
      expect(calc.grandTotal, ils(11770));
      expect(calc.reconciles, isTrue);
    });

    test('Example C — fixed item discount + 10% order discount → 2835', () {
      // 1200 x 2 = 2400; 850 with fixed 100 -> 750; subtotal 3150; order 10%.
      final calc = OrderCalculator.calculate(
        MoneyOrder(
          currency: 'ILS',
          lines: [
            MoneyLine(unitPrice: ils(1200), quantity: 2),
            MoneyLine(
              unitPrice: ils(850),
              quantity: 1,
              itemDiscount: DiscountSet(fixed: FixedDiscount(100)),
            ),
          ],
          orderDiscount: DiscountSet(percentage: PercentageDiscount(1000)),
        ),
      );
      expect(calc.subtotal, ils(3150));
      expect(calc.itemDiscountTotal, ils(100));
      expect(calc.orderDiscount, ils(315)); // round(3150 * 1000 / 10000) = 315
      expect(calc.grandTotal, ils(2835));
      expect(calc.reconciles, isTrue);
    });
  });
}
