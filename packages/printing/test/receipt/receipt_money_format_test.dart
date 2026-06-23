import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-073 — integer-only receipt money formatting (D-007). No float anywhere;
/// the formatter renders an authoritative minor-unit value, it never computes.
void main() {
  group('format (bare numeric)', () {
    test('two-decimal currency: 4242 -> 42.42', () {
      expect(ReceiptMoneyFormat.format(4242, currencyCode: 'ILS'), '42.42');
    });

    test('whole values keep the fraction: 1000 -> 10.00', () {
      expect(ReceiptMoneyFormat.format(1000, currencyCode: 'USD'), '10.00');
    });

    test('zero -> 0.00', () {
      expect(ReceiptMoneyFormat.format(0, currencyCode: 'EUR'), '0.00');
    });

    test('sub-unit padding: 5 -> 0.05', () {
      expect(ReceiptMoneyFormat.format(5, currencyCode: 'ILS'), '0.05');
    });

    test('negative values (discounts): -500 -> -5.00, -5 -> -0.05', () {
      expect(ReceiptMoneyFormat.format(-500, currencyCode: 'ILS'), '-5.00');
      expect(ReceiptMoneyFormat.format(-5, currencyCode: 'ILS'), '-0.05');
    });

    test('zero-exponent currency (JPY): 1000 -> 1000, -250 -> -250', () {
      expect(ReceiptMoneyFormat.format(1000, currencyCode: 'JPY'), '1000');
      expect(ReceiptMoneyFormat.format(-250, currencyCode: 'JPY'), '-250');
    });

    test('three-exponent currency (KWD): 1234567 -> 1234.567', () {
      expect(
        ReceiptMoneyFormat.format(1234567, currencyCode: 'KWD'),
        '1234.567',
      );
    });

    test('unknown currency falls back to exponent 2', () {
      expect(ReceiptMoneyFormat.format(4242, currencyCode: 'XYZ'), '42.42');
    });

    test('explicit exponent override wins over the table', () {
      expect(
        ReceiptMoneyFormat.format(
          1234567,
          currencyCode: 'ILS',
          exponentOverride: 3,
        ),
        '1234.567',
      );
      expect(
        ReceiptMoneyFormat.format(
          1000,
          currencyCode: 'ILS',
          exponentOverride: 0,
        ),
        '1000',
      );
    });

    test('exponentFor resolves table + override + default', () {
      expect(ReceiptMoneyFormat.exponentFor('jpy'), 0);
      expect(ReceiptMoneyFormat.exponentFor('ILS'), 2);
      expect(
        ReceiptMoneyFormat.exponentFor('???'),
        ReceiptMoneyFormat.defaultExponent,
      );
      expect(ReceiptMoneyFormat.exponentFor('ILS', exponentOverride: 4), 4);
    });
  });

  group('formatWithCurrency', () {
    test('appends the upper-cased code', () {
      expect(
        ReceiptMoneyFormat.formatWithCurrency(4242, currencyCode: 'ils'),
        '42.42 ILS',
      );
    });
  });

  group('determinism', () {
    test('repeated calls are identical', () {
      final a = ReceiptMoneyFormat.format(987654, currencyCode: 'ILS');
      final b = ReceiptMoneyFormat.format(987654, currencyCode: 'ILS');
      expect(a, b);
      expect(a, '9876.54');
    });
  });
}
