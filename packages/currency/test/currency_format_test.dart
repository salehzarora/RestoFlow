import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:test/test.dart';

/// GOLDEN OUTPUT, per exponent class.
///
/// The parity group at the bottom is the load-bearing one: Phase 2 replaces
/// five formatters with this module, and it is only allowed to do that if ILS
/// output stays byte-identical. These strings were taken from what the POS,
/// the dashboard and the receipt formatter produce today.
void main() {
  group('2-decimal (ILS/USD/EUR) — the class that must not move', () {
    test('symbol prefix, no space, no grouping', () {
      expect(formatCurrencyMinor(4242, 'ILS'), '₪42.42');
      expect(formatCurrencyMinor(123456, 'ILS'), '₪1234.56');
      expect(formatCurrencyMinor(0, 'ILS'), '₪0.00');
      expect(formatCurrencyMinor(5, 'ILS'), '₪0.05');
      expect(formatCurrencyMinor(50, 'ILS'), '₪0.50');
      expect(formatCurrencyMinor(100, 'USD'), r'$1.00');
      expect(formatCurrencyMinor(199, 'EUR'), '€1.99');
    });

    test('the sign precedes the symbol, and zero is never signed', () {
      expect(formatCurrencyMinor(-500, 'ILS'), '-₪5.00');
      expect(formatCurrencyMinor(0, 'ILS'), '₪0.00');
      expect(formatCurrencyMinor(-0, 'ILS'), '₪0.00');
    });
  });

  group('0-decimal (JPY/KRW) — no decimal point at all', () {
    test('the minor unit IS the major unit', () {
      expect(formatCurrencyMinor(1500, 'JPY'), 'JPY 1500');
      expect(formatCurrencyMinor(0, 'JPY'), 'JPY 0');
      expect(formatCurrencyMinor(-980, 'KRW'), 'KRW -980');
    });

    test('grouped, a 0-decimal amount reads the way a till shows it', () {
      expect(formatCurrencyMinor(1500, 'JPY', grouped: true), 'JPY 1,500');
      expect(
        formatCurrencyMinor(1234567, 'JPY', grouped: true),
        'JPY 1,234,567',
      );
    });
  });

  group('3-decimal (JOD/KWD/BHD/OMR/TND) — three fractional digits', () {
    test('1500 minor units is 1.500, NOT 15.00', () {
      expect(formatCurrencyMinor(1500, 'KWD'), 'KWD 1.500');
      expect(formatCurrencyMinor(1500000, 'KWD'), 'KWD 1500.000');
      expect(formatCurrencyMinor(5, 'JOD'), 'JOD 0.005');
      expect(formatCurrencyMinor(1234, 'BHD'), 'BHD 1.234');
    });

    test('the D2 worked example', () {
      expect(
        formatCurrencyMinor(
          1500000,
          'KWD',
          style: CurrencySymbolStyle.codeSuffix,
          grouped: true,
        ),
        '1,500.000 KWD',
      );
    });
  });

  test('4-decimal fund units keep all four digits', () {
    expect(formatCurrencyMinor(12345, 'CLF'), 'CLF 1.2345');
  });

  group('styles', () {
    test('codeSuffix is the receipt style — symbol-free, code after the '
        'number', () {
      expect(
        formatCurrencyMinor(4242, 'ILS', style: CurrencySymbolStyle.codeSuffix),
        '42.42 ILS',
      );
      expect(
        formatCurrencyMinor(
          -4242,
          'ILS',
          style: CurrencySymbolStyle.codeSuffix,
        ),
        '-42.42 ILS',
      );
    });

    test('bare is digits only', () {
      expect(
        formatCurrencyMinor(4242, 'ILS', style: CurrencySymbolStyle.bare),
        '42.42',
      );
      expect(
        formatCurrencyMinor(1500, 'JPY', style: CurrencySymbolStyle.bare),
        '1500',
      );
    });

    test('D2: a currency with no unambiguous glyph shows its CODE, never an '
        'invented symbol and never a bare number', () {
      expect(formatCurrencyMinor(2500, 'CHF'), 'CHF 25.00');
      expect(formatCurrencyMinor(2500, 'AED'), 'AED 25.00');
    });

    test('an exponentOverride wins over the catalog (the printing package\'s '
        'existing escape hatch)', () {
      expect(formatCurrencyMinor(4242, 'ILS', exponentOverride: 0), '₪4242');
    });
  });

  group('signed deltas — modifier prices', () {
    test(
      'positive uses ASCII +, negative uses the typographic minus U+2212',
      () {
        expect(formatSignedCurrencyMinor(250, 'ILS'), '+₪2.50');
        expect(formatSignedCurrencyMinor(-250, 'ILS'), '−₪2.50');
        expect(formatSignedCurrencyMinor(0, 'ILS'), '+₪0.00');
      },
    );
  });

  group('grouping is OFF by default', () {
    test('so Phase 2 can swap this module in without moving a pixel', () {
      expect(formatCurrencyMinor(123456789, 'ILS'), '₪1234567.89');
      expect(
        formatCurrencyMinor(123456789, 'ILS', grouped: true),
        '₪1,234,567.89',
      );
    });

    test('grouping starts only above three whole digits', () {
      expect(formatCurrencyMinor(99900, 'ILS', grouped: true), '₪999.00');
      expect(formatCurrencyMinor(100000, 'ILS', grouped: true), '₪1,000.00');
    });
  });

  group('PARITY with the formatters Phase 2 will delete', () {
    // apps/pos/lib/src/format/money_format.dart + the dashboard's copy:
    // symbol prefix, ASCII '-' before the symbol, exponent 2, no grouping.
    test('POS/dashboard MoneyFormatter.formatMinor', () {
      const cases = <(int, String, String)>[
        (0, 'ILS', '₪0.00'),
        (1, 'ILS', '₪0.01'),
        (4242, 'ILS', '₪42.42'),
        (123456, 'ILS', '₪1234.56'),
        (-500, 'ILS', '-₪5.00'),
        (100, 'USD', r'$1.00'),
        (100, 'EUR', '€1.00'),
      ];
      for (final (minor, code, expected) in cases) {
        expect(
          formatCurrencyMinor(minor, code),
          expected,
          reason: '$minor $code',
        );
      }
    });

    // packages/printing/lib/src/receipt/receipt_money_format.dart:
    // bare number, and formatWithCurrency appends the uppercased code.
    test('ReceiptMoneyFormat.format / formatWithCurrency', () {
      expect(
        formatCurrencyMinor(4242, 'ILS', style: CurrencySymbolStyle.bare),
        '42.42',
      );
      expect(
        formatCurrencyMinor(4242, 'ils', style: CurrencySymbolStyle.codeSuffix),
        '42.42 ILS',
      );
      expect(
        formatCurrencyMinor(1500, 'JOD', style: CurrencySymbolStyle.bare),
        '1.500',
      );
    });

    // packages/feature_menu/lib/src/data/minor_money.dart formatMinorUnits is
    // the bare style too — it feeds a TextField, so it must stay symbol-free.
    test('feature_menu formatMinorUnits', () {
      expect(
        formatCurrencyMinor(4000, 'ILS', style: CurrencySymbolStyle.bare),
        '40.00',
      );
      expect(
        formatCurrencyMinor(4000, 'JPY', style: CurrencySymbolStyle.bare),
        '4000',
      );
    });
  });
}
