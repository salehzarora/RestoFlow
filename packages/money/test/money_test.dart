import 'package:restoflow_money/restoflow_money.dart';
import 'package:test/test.dart';

void main() {
  group('Money construction (RF-036, D-007)', () {
    test('carries integer minor units + normalized currency', () {
      final m = Money(1234, 'ils');
      expect(m.amountMinor, 1234);
      expect(m.currencyCode, 'ILS'); // trimmed + uppercased
    });

    test('zero factory', () {
      final z = Money.zero('ILS');
      expect(z.amountMinor, 0);
      expect(z.isZero, isTrue);
      expect(z.currencyCode, 'ILS');
    });

    test('empty currency is rejected', () {
      expect(() => Money(100, '  '), throwsA(isA<InvalidMoneyException>()));
    });
  });

  group('Money arithmetic (same currency only)', () {
    test('addition and subtraction', () {
      expect(Money(100, 'ILS') + Money(50, 'ILS'), Money(150, 'ILS'));
      expect(Money(100, 'ILS') - Money(150, 'ILS'), Money(-50, 'ILS'));
    });

    test('scale by an integer factor', () {
      expect(Money(1200, 'ILS').scale(3), Money(3600, 'ILS'));
    });

    test('comparison', () {
      expect(Money(100, 'ILS').compareTo(Money(200, 'ILS')), lessThan(0));
      expect(Money(200, 'ILS') > Money(100, 'ILS'), isTrue);
      expect(Money(100, 'ILS') <= Money(100, 'ILS'), isTrue);
    });

    test('cross-currency add/subtract/compare throw', () {
      expect(
        () => Money(100, 'ILS') + Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchException>()),
      );
      expect(
        () => Money(100, 'ILS') - Money(100, 'USD'),
        throwsA(isA<CurrencyMismatchException>()),
      );
      expect(
        () => Money(100, 'ILS').compareTo(Money(100, 'USD')),
        throwsA(isA<CurrencyMismatchException>()),
      );
    });
  });

  group('Money clamp + negatives', () {
    test('negative amounts are allowed internally', () {
      expect(Money(-50, 'ILS').isNegative, isTrue);
    });

    test('clampToZero', () {
      expect(Money(-50, 'ILS').clampToZero(), Money(0, 'ILS'));
      expect(Money(50, 'ILS').clampToZero(), Money(50, 'ILS'));
    });
  });

  group('Money equality', () {
    test('value equality + hashCode', () {
      expect(Money(100, 'ILS'), Money(100, 'ILS'));
      expect(Money(100, 'ILS').hashCode, Money(100, 'ILS').hashCode);
      expect(Money(100, 'ILS'), isNot(Money(101, 'ILS')));
      expect(Money(100, 'ILS'), isNot(Money(100, 'USD')));
    });
  });
}
