import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:test/test.dart';

/// The catalog is the foundation D2 makes everything else wait for: if an
/// exponent is wrong here, a 3-decimal tenant's prices are wrong by 10x
/// everywhere at once.
void main() {
  group('exponent classes', () {
    test('0-decimal currencies carry exponent 0', () {
      for (final code in ['JPY', 'KRW', 'VND', 'CLP', 'ISK', 'XAF', 'VUV']) {
        expect(currencyExponent(code), 0, reason: code);
      }
    });

    test('3-decimal currencies carry exponent 3 — all seven of them', () {
      for (final code in ['BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND']) {
        expect(currencyExponent(code), 3, reason: code);
      }
    });

    test('4-decimal fund units carry exponent 4', () {
      expect(currencyExponent('CLF'), 4);
      expect(currencyExponent('UYW'), 4);
    });

    test('the ordinary majority carry exponent 2', () {
      for (final code in ['ILS', 'USD', 'EUR', 'GBP', 'AED', 'TRY', 'ZAR']) {
        expect(currencyExponent(code), 2, reason: code);
      }
    });

    test('every catalogued exponent is one of 0/2/3/4', () {
      for (final info in isoCurrencies.values) {
        expect(
          const [0, 2, 3, 4],
          contains(info.exponent),
          reason: '${info.code} has exponent ${info.exponent}',
        );
      }
    });
  });

  group('unknown and retired codes never explode', () {
    test('an unknown code falls back to 2 decimals, matching every table this '
        'module replaces', () {
      expect(currencyExponent('ZZZ'), kDefaultCurrencyExponent);
      expect(kDefaultCurrencyExponent, 2);
    });

    test('a RETIRED code stored on a historical row still resolves — D3 '
        'forbids relabelling old money, so old money must stay printable', () {
      for (final code in ['HRK', 'SLL', 'MRO', 'STD', 'VEF', 'ZWL', 'BYR']) {
        expect(lookupCurrency(code), isNull, reason: '$code is not active');
        expect(currencyExponent(code), 2, reason: code);
        expect(
          formatCurrencyMinor(4242, code),
          '$code 42.42',
          reason: 'must render, never throw',
        );
      }
    });

    test('null / malformed input is answered, not thrown', () {
      expect(currencyExponent(null), 2);
      expect(currencyExponent(''), 2);
      expect(currencyExponent('12'), 2);
      expect(lookupCurrency('il'), isNull);
    });
  });

  group('normalization', () {
    test('case and surrounding whitespace are normalized away', () {
      expect(normalizeCurrencyCode(' ils '), 'ILS');
      expect(lookupCurrency('jpy')?.code, 'JPY');
    });

    test('anything that is not exactly three letters is rejected', () {
      for (final raw in ['IL', 'ILSS', 'I L', '1LS', '', '   ']) {
        expect(normalizeCurrencyCode(raw), isNull, reason: raw);
        expect(isValidCurrencyCodeShape(raw), isFalse, reason: raw);
      }
      expect(isValidCurrencyCodeShape('ILS'), isTrue);
    });
  });

  group('symbols — D2: never invent a glyph', () {
    test('only unambiguous glyphs are carried', () {
      expect(lookupCurrency('ILS')!.symbol, '₪');
      expect(lookupCurrency('USD')!.symbol, r'$');
      expect(lookupCurrency('EUR')!.symbol, '€');
      expect(lookupCurrency('GBP')!.symbol, '£');
    });

    test('a currency with no unambiguous glyph carries none, so the formatter '
        'falls back to its code', () {
      for (final code in ['CHF', 'KWD', 'JPY', 'AED', 'TRY']) {
        expect(lookupCurrency(code)!.symbol, isNull, reason: code);
      }
    });
  });

  test('metals, funds and reserved codes are catalogued but marked as having '
      'no minor unit', () {
    for (final code in ['XAU', 'XDR', 'XXX', 'XTS']) {
      final info = lookupCurrency(code)!;
      expect(info.hasMinorUnit, isFalse, reason: code);
      expect(info.exponent, 0, reason: code);
    }
    expect(lookupCurrency('ILS')!.hasMinorUnit, isTrue);
  });
}
