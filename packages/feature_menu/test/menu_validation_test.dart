import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('validateName', () {
    test('blank / whitespace is rejected', () {
      expect(validateName(''), MenuFieldError.blank);
      expect(validateName('   '), MenuFieldError.blank);
    });
    test('non-blank passes', () {
      expect(validateName('Espresso'), isNull);
    });
  });

  group('validateBasePriceMinor', () {
    test('null (unparsable) -> notAnInteger', () {
      expect(validateBasePriceMinor(null), MenuFieldError.notAnInteger);
    });
    test('negative -> negativePrice', () {
      expect(validateBasePriceMinor(-1), MenuFieldError.negativePrice);
    });
    test('zero and positive pass', () {
      expect(validateBasePriceMinor(0), isNull);
      expect(validateBasePriceMinor(1500), isNull);
    });
  });

  group('validatePriceDeltaMinor (signed)', () {
    test('null -> notAnInteger', () {
      expect(validatePriceDeltaMinor(null), MenuFieldError.notAnInteger);
    });
    test('negative deltas are allowed', () {
      expect(validatePriceDeltaMinor(-100), isNull);
      expect(validatePriceDeltaMinor(0), isNull);
      expect(validatePriceDeltaMinor(50), isNull);
    });
  });

  group('validateCurrencyCode', () {
    test('valid uppercase 3-letter passes', () {
      expect(validateCurrencyCode('USD'), isNull);
      expect(validateCurrencyCode('ILS'), isNull);
    });
    test('lowercase / wrong length is rejected', () {
      expect(validateCurrencyCode('usd'), MenuFieldError.invalidCurrency);
      expect(validateCurrencyCode('US'), MenuFieldError.invalidCurrency);
      expect(validateCurrencyCode('USDD'), MenuFieldError.invalidCurrency);
    });
  });

  group('validateSelectionType', () {
    test('single / multiple pass', () {
      expect(validateSelectionType('single'), isNull);
      expect(validateSelectionType('multiple'), isNull);
    });
    test('anything else is rejected', () {
      expect(
        validateSelectionType('many'),
        MenuFieldError.invalidSelectionType,
      );
    });
  });

  group('min/max select', () {
    test('min must be >= 0', () {
      expect(validateMinSelect(-1), MenuFieldError.negativeMinSelect);
      expect(validateMinSelect(0), isNull);
      expect(validateMinSelect(2), isNull);
    });
    test('max null is allowed; max < min rejected; max < 0 rejected', () {
      expect(validateMaxSelect(null, 0), isNull);
      expect(validateMaxSelect(3, 1), isNull);
      expect(validateMaxSelect(1, 2), MenuFieldError.maxLessThanMin);
      expect(validateMaxSelect(-1, 0), MenuFieldError.negativeMinSelect);
    });
  });
}
