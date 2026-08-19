@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_currency/restoflow_currency.dart'
    show CurrencySymbolStyle, formatCurrencyMinor, quickAmountStepsMinor;
import 'package:restoflow_pos/src/format/cash_input.dart';
import 'package:restoflow_pos/src/format/money_format.dart';

/// OPS-043 Phase 2 — the paths that can CORRUPT money rather than mis-display
/// it.
///
/// Every assertion here is on RECORDED MINOR UNITS, not on a display string.
/// A wrong label is embarrassing; a wrong integer is a wrong drawer, a wrong
/// payment row and a wrong shift variance, and none of them can be spotted by
/// looking at the screen.
void main() {
  group('A. cash tender — the parse that books the money', () {
    test('A1. 2-decimal currencies are unchanged', () {
      expect(parseCashToMinor('50', currencyCode: 'ILS'), 5000);
      expect(parseCashToMinor('50.5', currencyCode: 'ILS'), 5050);
      expect(parseCashToMinor('50.55', currencyCode: 'USD'), 5055);
    });

    test('A2. THE BUG: a 1,000 yen note is 1000 minor units, not 100,000', () {
      expect(parseCashToMinor('1000', currencyCode: 'JPY'), 1000);
      // What the pre-Phase-2 hardcoded two decimals produced for the same note:
      expect(parseCashToMinor('1000', currencyCode: 'ILS'), 100000);
    });

    test('A3. a 3-decimal currency scales by 1000, not by 100', () {
      expect(parseCashToMinor('5', currencyCode: 'KWD'), 5000);
      expect(parseCashToMinor('5.25', currencyCode: 'KWD'), 5250);
      expect(parseCashToMinor('5.255', currencyCode: 'JOD'), 5255);
    });

    test('A4. excess precision is REJECTED, never rounded — a rounded tender '
        'is a wrong drawer', () {
      expect(parseCashToMinor('1.5', currencyCode: 'JPY'), isNull);
      expect(parseCashToMinor('1.234', currencyCode: 'ILS'), isNull);
      expect(parseCashToMinor('1.2345', currencyCode: 'KWD'), isNull);
    });

    test('A5. the till grammar stays strict: no negatives, no leading dot, no '
        'grouping', () {
      // NB: surrounding whitespace has always been trimmed and still is;
      // what must stay refused is a different NUMBER, not a stray space.
      for (final raw in ['-5', '.5', '1,000', '5.', '+5', 'abc', '']) {
        expect(parseCashToMinor(raw, currencyCode: 'ILS'), isNull, reason: raw);
      }
    });
  });

  group('B. the quick-amount round trip', () {
    test('B1. every quick amount survives format -> parse unchanged, in every '
        'exponent class', () {
      for (final code in ['ILS', 'USD', 'JPY', 'KRW', 'KWD', 'JOD']) {
        for (final minor in quickAmountStepsMinor(code)) {
          final typed = formatCurrencyMinor(
            minor,
            code,
            style: CurrencySymbolStyle.bare,
          );
          expect(
            parseCashToMinor(typed, currencyCode: code),
            minor,
            reason: '$code $minor rendered as "$typed"',
          );
        }
      }
    });

    test('B2. the ladders are real notes per class, not one list scaled by '
        '100', () {
      expect(quickAmountStepsMinor('ILS'), [1000, 2000, 5000, 10000]);
      expect(quickAmountStepsMinor('JPY'), [500, 1000, 5000, 10000]);
      expect(quickAmountStepsMinor('KWD'), [1000, 5000, 10000, 20000]);
    });

    test('B3. writing an amount back into the field uses the currency digits, '
        'so the button and the parse agree', () {
      // This is the `% 100` / `~/ 100` the cash sheet used to hardcode.
      expect(
        formatCurrencyMinor(1000, 'JPY', style: CurrencySymbolStyle.bare),
        '1000',
      );
      expect(
        formatCurrencyMinor(1000, 'ILS', style: CurrencySymbolStyle.bare),
        '10.00',
      );
      expect(
        formatCurrencyMinor(1000, 'KWD', style: CurrencySymbolStyle.bare),
        '1.000',
      );
    });
  });

  group('C. a PERCENTAGE is not money', () {
    test('C1. basis points stay two decimals whatever the currency — the '
        'discount sheet must never inherit the exponent', () {
      expect(parseCashToMinor('17.5', fractionDigits: 2), 1750);
      expect(parseCashToMinor('100', fractionDigits: 2), 10000);
      // If this had been re-pointed at a JPY exponent, 17.5% would have been
      // rejected outright and 100% would have become 100 basis points.
      expect(parseCashToMinor('17.5', currencyCode: 'JPY'), isNull);
    });
  });

  group('D. display follows the same catalog', () {
    test('D1. ILS is byte-identical to the pre-Phase-2 formatter', () {
      expect(MoneyFormatter.formatMinor(4242, 'ILS'), '₪42.42');
      expect(MoneyFormatter.formatMinor(0, 'ILS'), '₪0.00');
      expect(MoneyFormatter.formatMinor(-500, 'ILS'), '-₪5.00');
      expect(MoneyFormatter.formatSignedDeltaMinor(300, 'ILS'), '+₪3.00');
      expect(MoneyFormatter.formatSignedDeltaMinor(-300, 'ILS'), '−₪3.00');
    });

    test('D2. the exponent classes render correctly instead of 100x/10x '
        'wrong', () {
      expect(MoneyFormatter.formatMinor(1500, 'JPY'), 'JPY 1500');
      expect(MoneyFormatter.formatMinor(1500, 'KWD'), 'KWD 1.500');
    });
  });
}
