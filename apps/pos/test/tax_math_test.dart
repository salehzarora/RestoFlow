import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/format/tax_math.dart';

/// RF-117: the tax/percent math is integer minor units, rounded
/// HALF-AWAY-FROM-ZERO, with NO floating point. Pure-Dart unit test of the
/// helpers behind the tax line and the demo percentage discount.
void main() {
  group('taxMinorExclusive / percentMinor (RF-117, D-007)', () {
    test('the spec sample: 10000 @ 1700bp -> 1700 (integer, no float)', () {
      final tax = taxMinorExclusive(10000, 1700);
      expect(tax, 1700);
      // The result TYPE is int — money is never a double.
      expect(tax, isA<int>());
    });

    test('rounds HALF-AWAY-FROM-ZERO (x.5 rounds up)', () {
      // 1 * 50% = 0.5 -> 1 ; 3 * 50% = 1.5 -> 2 ; 5 * 50% = 2.5 -> 3.
      expect(taxMinorExclusive(1, 5000), 1);
      expect(taxMinorExclusive(3, 5000), 2);
      expect(taxMinorExclusive(5, 5000), 3);
    });

    test('rounds a sub-half fraction down and a super-half up', () {
      // 9999 @ 17% = 1699.83 -> 1700 (super-half rounds up).
      expect(taxMinorExclusive(9999, 1700), 1700);
      // 100 @ 17.25% = 17.25 -> 17 (sub-half rounds down).
      expect(taxMinorExclusive(100, 1725), 17);
      // 100 @ 17.75% = 17.75 -> 18.
      expect(taxMinorExclusive(100, 1775), 18);
    });

    test('a disabled rate or zero base adds no tax', () {
      expect(taxMinorExclusive(10000, 0), 0);
      expect(taxMinorExclusive(0, 1700), 0);
    });

    test('percentMinor computes a percentage discount identically', () {
      // 10% of 10000 = 1000 ; 17.5% of 4200 = 735.
      expect(percentMinor(10000, 1000), 1000);
      expect(percentMinor(4200, 1750), 735);
    });

    test('grandWithExclusiveTax adds the tax on top', () {
      expect(grandWithExclusiveTax(10000, 1700), 11700);
      expect(grandWithExclusiveTax(10000, 0), 10000);
    });
  });

  group('formatRateBpPercent (RF-117)', () {
    test('formats whole and fractional basis-point rates', () {
      expect(formatRateBpPercent(1700), '17%');
      expect(formatRateBpPercent(1000), '10%');
      expect(formatRateBpPercent(1750), '17.5%');
      expect(formatRateBpPercent(1733), '17.33%');
      expect(formatRateBpPercent(1705), '17.05%');
    });
  });
}
