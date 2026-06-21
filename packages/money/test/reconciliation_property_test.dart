import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

Money ils(int v) => Money(v, 'ILS');

/// Deterministic fixture matrix (no randomness) covering item/order discounts,
/// clamping, and quantities. Asserts the reconciliation invariants hold with
/// ZERO drift for every combination (RF-036 AC#3).
void main() {
  final discountOptions = <DiscountSet?>[
    null,
    DiscountSet(percentage: PercentageDiscount(1000)), // 10%
    DiscountSet(fixed: FixedDiscount(300)),
    DiscountSet(percentage: PercentageDiscount(500), fixed: FixedDiscount(200)),
    DiscountSet(fixed: FixedDiscount(100000000)), // forces a clamp to zero
  ];
  const quantities = [1, 2, 3, 7];
  const unitPrices = [100, 999, 4500, 12345];

  test('reconciliation invariants hold across the matrix (no drift)', () {
    var combos = 0;
    for (final q in quantities) {
      for (final up in unitPrices) {
        for (final itemD in discountOptions) {
          for (final orderD in discountOptions) {
            final order = MoneyOrder(
              currency: 'ILS',
              lines: [
                MoneyLine(unitPrice: ils(up), quantity: q, itemDiscount: itemD),
                MoneyLine(unitPrice: ils(777), quantity: 2),
              ],
              orderDiscount: orderD,
            );
            final calc = OrderCalculator.calculate(order);
            combos++;
            final ctx = 'q=$q up=$up itemD=$itemD orderD=$orderD';

            // The two reconciliation invariants, exact (integer) equality.
            expect(calc.reconciles, isTrue, reason: ctx);
            expect(
              calc.grandTotal,
              calc.subtotal -
                  calc.orderDiscount +
                  calc.serviceCharge +
                  calc.tax,
              reason: ctx,
            );
            expect(
              calc.discountTotal,
              calc.itemDiscountTotal + calc.orderDiscount,
              reason: ctx,
            );

            // No negative totals; subtotal == sum of discounted line totals.
            expect(calc.grandTotal.isNegative, isFalse, reason: ctx);
            var lineSum = ils(0);
            for (final line in calc.lines) {
              expect(line.total.isNegative, isFalse, reason: ctx);
              expect(line.subtotal, line.total + line.discount, reason: ctx);
              lineSum = lineSum + line.total;
            }
            expect(calc.subtotal, lineSum, reason: ctx);
          }
        }
      }
    }
    expect(combos, 4 * 4 * 5 * 5); // 400 deterministic fixtures
  });
}
