import 'package:restoflow_currency/restoflow_currency.dart';
import 'package:test/test.dart';

/// The parser is the half that can CORRUPT money rather than merely
/// mis-display it: `parseCashToMinor("1000", fractionDigits: 2)` against a JPY
/// till books 100,000 yen for a 1,000 yen note. Every case below exists to
/// stop that class of bug.
void main() {
  group('round-trips per exponent class', () {
    test('2-decimal', () {
      expect(parseMajorToMinor('42.42', 'ILS'), 4242);
      expect(parseMajorToMinor('42.4', 'ILS'), 4240);
      expect(parseMajorToMinor('42', 'ILS'), 4200);
      expect(parseMajorToMinor('0', 'ILS'), 0);
      expect(parseMajorToMinor('0.05', 'ILS'), 5);
    });

    test('0-decimal: the typed number IS the minor amount', () {
      expect(parseMajorToMinor('1500', 'JPY'), 1500);
      expect(parseMajorToMinor('0', 'JPY'), 0);
    });

    test('3-decimal', () {
      expect(parseMajorToMinor('1.5', 'KWD'), 1500);
      expect(parseMajorToMinor('1.500', 'KWD'), 1500);
      expect(parseMajorToMinor('0.005', 'JOD'), 5);
      expect(parseMajorToMinor('12', 'BHD'), 12000);
    });

    test('format -> parse is lossless for every class', () {
      for (final (minor, code) in const <(int, String)>[
        (0, 'ILS'),
        (5, 'ILS'),
        (123456, 'ILS'),
        (1500, 'JPY'),
        (7, 'KRW'),
        (1500, 'KWD'),
        (5, 'JOD'),
        (1234567, 'OMR'),
      ]) {
        final text = formatCurrencyMinor(
          minor,
          code,
          style: CurrencySymbolStyle.bare,
        );
        expect(
          parseMajorToMinor(text, code),
          minor,
          reason: '$minor $code -> "$text"',
        );
      }
    });
  });

  group('REJECTS rather than rounds', () {
    test('more fractional digits than the currency has', () {
      expect(parseMajorToMinor('1.234', 'ILS'), isNull);
      expect(parseMajorToMinor('1.5', 'JPY'), isNull);
      expect(parseMajorToMinor('1.2345', 'KWD'), isNull);
    });

    test('a 0-decimal currency accepts no fraction at all — not even ".0"', () {
      expect(parseMajorToMinor('100.0', 'JPY'), isNull);
      expect(parseMajorToMinor('100.00', 'JPY'), isNull);
    });
  });

  group('malformed input', () {
    test('grouping separators, glyphs, spaces and partial numbers are all '
        'refused', () {
      for (final raw in [
        '1,500',
        '1 500',
        '₪42',
        '42‏',
        'abc',
        '',
        '  ',
        '4 2',
        '1.2.3',
        '42.',
        '4,2',
        '+42',
      ]) {
        expect(parseMajorToMinor(raw, 'ILS'), isNull, reason: '"$raw"');
      }
    });

    test('surrounding whitespace alone is tolerated', () {
      expect(parseMajorToMinor('  42.42  ', 'ILS'), 4242);
    });
  });

  group('flags', () {
    test('negatives are refused by default and accepted on request', () {
      expect(parseMajorToMinor('-5.00', 'ILS'), isNull);
      expect(parseMajorToMinor('-5.00', 'ILS', allowNegative: true), -500);
      expect(parseMajorToMinor('-0.00', 'ILS', allowNegative: true), 0);
    });

    test('a leading dot is refused by default and accepted on request', () {
      expect(parseMajorToMinor('.50', 'ILS'), isNull);
      expect(parseMajorToMinor('.50', 'ILS', allowLeadingDot: true), 50);
    });

    test('the whole part is capped for JS integer safety', () {
      expect(parseMajorToMinor('123456789012', 'ILS'), 12345678901200);
      expect(parseMajorToMinor('1234567890123', 'ILS'), isNull);
      expect(
        parseMajorToMinor('1234567890123', 'ILS', maxWholeDigits: 13),
        isNotNull,
      );
    });

    test('an unknown code parses at the 2-decimal default', () {
      expect(parseMajorToMinor('1.23', 'ZZZ'), 123);
      expect(parseMajorToMinor('1.234', 'ZZZ'), isNull);
    });
  });

  group('parseCashToMinor — the till contract', () {
    test('is the strict parser: no negatives, no leading dot', () {
      expect(parseCashToMinor('50', 'ILS'), 5000);
      expect(parseCashToMinor('-50', 'ILS'), isNull);
      expect(parseCashToMinor('.50', 'ILS'), isNull);
    });

    test('THE BUG THIS MODULE EXISTS TO PREVENT: a 1000-yen note tendered at a '
        'JPY till is 1000 minor units, not 100000', () {
      expect(parseCashToMinor('1000', 'JPY'), 1000);
      // What the current hardcoded `fractionDigits: 2` produces instead:
      expect(parseCashToMinor('1000', 'ILS'), 100000);
    });
  });

  group('quick amounts', () {
    test('2-decimal ladders are the familiar note values', () {
      expect(quickAmountStepsMinor('ILS'), [1000, 2000, 5000, 10000]);
    });

    test('0-decimal ladders are NOT the 2-decimal ones divided by 100 — they '
        'are real JPY notes', () {
      expect(quickAmountStepsMinor('JPY'), [500, 1000, 5000, 10000]);
    });

    test('3-decimal ladders scale by 1000', () {
      expect(quickAmountStepsMinor('KWD'), [1000, 5000, 10000, 20000]);
    });

    test('every step re-parses to itself through the formatter', () {
      for (final code in ['ILS', 'JPY', 'KWD']) {
        for (final step in quickAmountStepsMinor(code)) {
          final text = formatCurrencyMinor(
            step,
            code,
            style: CurrencySymbolStyle.bare,
          );
          expect(parseMajorToMinor(text, code), step, reason: '$code $step');
        }
      }
    });
  });
}
