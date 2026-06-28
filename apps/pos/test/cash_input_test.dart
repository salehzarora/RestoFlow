import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/format/cash_input.dart';

void main() {
  group('parseCashToMinor', () {
    test('parses whole shekels', () {
      expect(parseCashToMinor('50'), 5000);
      expect(parseCashToMinor('0'), 0);
      expect(parseCashToMinor('200'), 20000);
    });

    test('parses two-decimal amounts', () {
      expect(parseCashToMinor('50.00'), 5000);
      expect(parseCashToMinor('42.50'), 4250);
      expect(parseCashToMinor('0.05'), 5);
    });

    test('pads a single fractional digit', () {
      expect(parseCashToMinor('50.5'), 5050);
      expect(parseCashToMinor('1.2'), 120);
    });

    test('trims surrounding whitespace', () {
      expect(parseCashToMinor('  75 '), 7500);
    });

    test('rejects empty and whitespace-only input', () {
      expect(parseCashToMinor(''), isNull);
      expect(parseCashToMinor('   '), isNull);
    });

    test('rejects negative, non-numeric, and malformed input', () {
      expect(parseCashToMinor('-50'), isNull);
      expect(parseCashToMinor('abc'), isNull);
      expect(parseCashToMinor('50.'), isNull);
      expect(parseCashToMinor('.50'), isNull);
      expect(parseCashToMinor('5,0'), isNull);
      expect(parseCashToMinor('50.0.0'), isNull);
    });

    test('rejects more fractional digits than the currency allows', () {
      expect(parseCashToMinor('50.567'), isNull);
      expect(parseCashToMinor('1.000'), isNull);
    });

    test(
      'rejects an implausibly large whole part (web int-precision safety)',
      () {
        expect(parseCashToMinor('9' * 13), isNull); // 13 digits
        expect(
          parseCashToMinor('999999999999'),
          99999999999900,
        ); // 12 digits ok
      },
    );
  });
}
