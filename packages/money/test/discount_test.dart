import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

void main() {
  const rounding = RoundHalfAwayFromZero();
  Money ils(int v) => Money(v, 'ILS');

  group('percentage discount (basis points)', () {
    test('10% of 10400 = 1040', () {
      expect(
        PercentageDiscount(1000).computeAmount(ils(10400), rounding),
        ils(1040),
      );
    });

    test('100% (10000 bp) of a base equals the base', () {
      expect(
        PercentageDiscount(10000).computeAmount(ils(5000), rounding),
        ils(5000),
      );
    });

    test('negative basis points are rejected', () {
      expect(
        () => PercentageDiscount(-1),
        throwsA(isA<InvalidDiscountException>()),
      );
    });

    test('basis points above 10000 are rejected', () {
      expect(
        () => PercentageDiscount(10001),
        throwsA(isA<InvalidDiscountException>()),
      );
    });
  });

  group('fixed discount', () {
    test('fixed amount', () {
      expect(FixedDiscount(500).computeAmount(ils(10000), rounding), ils(500));
    });

    test('negative fixed discount is rejected', () {
      expect(() => FixedDiscount(-1), throwsA(isA<InvalidDiscountException>()));
    });
  });

  group('DiscountSet (percentage before fixed, clamp at zero)', () {
    test('percentage applies before fixed', () {
      // base 1000: 10% -> 100 off -> 900; then fixed 200 -> 700.
      final set = DiscountSet(
        percentage: PercentageDiscount(1000),
        fixed: FixedDiscount(200),
      );
      expect(set.applyTo(ils(1000), rounding), ils(700));
    });

    test('a fixed discount cannot push a line below zero (clamp)', () {
      final set = DiscountSet(fixed: FixedDiscount(1500));
      expect(set.applyTo(ils(1000), rounding), ils(0));
    });

    test('a 100% percentage discount yields zero', () {
      final set = DiscountSet(percentage: PercentageDiscount(10000));
      expect(set.applyTo(ils(1000), rounding), ils(0));
    });

    test('an empty set leaves the base unchanged', () {
      expect(const DiscountSet().applyTo(ils(1000), rounding), ils(1000));
      expect(const DiscountSet().isEmpty, isTrue);
    });
  });
}
