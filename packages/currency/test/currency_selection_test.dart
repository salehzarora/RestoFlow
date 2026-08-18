import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:test/test.dart';

/// D2's hard ordering rule, expressed as a test: nothing may become
/// selectable before the sites that would mishandle it are fixed.
void main() {
  group('THE PHASE GATE', () {
    test('Phase 1 ships with the selector restricted to exponent-2 '
        'currencies', () {
      expect(kCurrencySelectorScope, CurrencySelectorScope.exponent2Only);
    });

    test('under the Phase-1 gate no 0-, 3- or 4-decimal currency is offerable '
        '— the POS cash path still assumes two decimals', () {
      for (final code in [
        'JPY',
        'KRW',
        'KWD',
        'JOD',
        'BHD',
        'OMR',
        'TND',
        'CLF',
      ]) {
        expect(isSelectableCurrency(code), isFalse, reason: code);
      }
    });

    test('flipping the gate to fullIso is all Phase 2 has to do', () {
      const full = CurrencySelectorScope.fullIso;
      expect(isSelectableCurrency('JPY', scope: full), isTrue);
      expect(isSelectableCurrency('KWD', scope: full), isTrue);
      expect(
        selectableCurrencies(scope: full).length,
        greaterThan(selectableCurrencies().length),
      );
    });
  });

  group('what is offerable at all', () {
    test('ordinary trading currencies are', () {
      for (final code in [
        'ILS',
        'USD',
        'EUR',
        'GBP',
        'AED',
        'TRY',
        'CHF',
        'EGP',
        'JOD',
      ]) {
        expect(
          isSelectableCurrency(code, scope: CurrencySelectorScope.fullIso),
          isTrue,
          reason: code,
        );
      }
    });

    test('funds, metals and reserved codes never are — a restaurant cannot be '
        'paid in gold or in XXX', () {
      for (final code in [
        'XAU',
        'XDR',
        'XXX',
        'XTS',
        'CLF',
        'USN',
        'BOV',
        'UYW',
      ]) {
        expect(
          isSelectableCurrency(code, scope: CurrencySelectorScope.fullIso),
          isFalse,
          reason: code,
        );
      }
    });

    test('unknown, retired and malformed codes are not offerable', () {
      for (final code in ['ZZZ', 'HRK', 'SLL', 'il', '', 'ILSS']) {
        expect(
          isSelectableCurrency(code, scope: CurrencySelectorScope.fullIso),
          isFalse,
          reason: code,
        );
      }
      expect(isSelectableCurrency(null), isFalse);
    });
  });

  group('the offered list', () {
    test('is sorted, deduplicated and contains the pilot currency', () {
      final list = selectableCurrencies();
      final codes = list.map((c) => c.code).toList();
      expect(codes, contains('ILS'));
      expect(codes, orderedEquals(List<String>.from(codes)..sort()));
      expect(codes.toSet().length, codes.length);
      expect(list.every((c) => c.exponent == 2), isTrue);
    });

    test('is big enough to be a real ISO list, not an allowlist of three', () {
      expect(selectableCurrencies().length, greaterThan(100));
    });
  });

  group('labels', () {
    test('a glyph is shown beside the code when it is unambiguous', () {
      expect(currencySelectorLabel('ILS'), 'ILS (₪)');
      expect(currencySelectorLabel('USD'), r'USD ($)');
    });

    test('otherwise the code stands alone — D2 forbids inventing one', () {
      expect(currencySelectorLabel('CHF'), 'CHF');
      expect(currencySelectorLabel('AED'), 'AED');
    });

    test('a malformed code yields an empty label rather than a crash', () {
      expect(currencySelectorLabel('nope!'), '');
      expect(currencySelectorLabel(null), '');
    });
  });

  group('bidi isolation', () {
    test('the isolated label wraps the code so an RTL sentence cannot reorder '
        'its brackets', () {
      final isolated = currencySelectorLabelIsolated('ILS');
      expect(isolated.codeUnitAt(0), 0x2066);
      expect(isolated.codeUnitAt(isolated.length - 1), 0x2069);
      expect(
        isolated.substring(1, isolated.length - 1),
        currencySelectorLabel('ILS'),
      );
    });

    test('it is safe on a malformed code', () {
      expect(currencySelectorLabelIsolated(null).length, 2);
    });
  });
}
