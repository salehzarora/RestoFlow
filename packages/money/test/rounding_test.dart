import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

void main() {
  const policy = RoundHalfAwayFromZero();

  group('round half away from zero (RF-036, MONEY_AND_TAX_SPEC §5)', () {
    test('exact division', () {
      expect(policy.roundDiv(10400 * 1000, 10000), 1040); // 1040.0 -> 1040
    });

    test('fraction below half rounds down', () {
      expect(policy.roundDiv(12344, 10), 1234); // 1234.4 -> 1234
    });

    test('exactly half rounds away from zero (up for positive)', () {
      expect(policy.roundDiv(12345, 10), 1235); // 1234.5 -> 1235
    });

    test('above half rounds up', () {
      expect(policy.roundDiv(10060 * 1700, 10000), 1710); // 1710.2 -> 1710
    });

    test('negative half rounds away from zero', () {
      expect(policy.roundDiv(-12345, 10), -1235); // -1234.5 -> -1235
    });

    test('negative below half rounds toward zero (smaller magnitude)', () {
      expect(policy.roundDiv(-12344, 10), -1234); // -1234.4 -> -1234
    });

    test('negative above half rounds away from zero', () {
      expect(policy.roundDiv(-12346, 10), -1235); // -1234.6 -> -1235
    });

    test('non-positive denominator is rejected', () {
      expect(() => policy.roundDiv(100, 0), throwsArgumentError);
      expect(() => policy.roundDiv(100, -10), throwsArgumentError);
    });
  });
}
