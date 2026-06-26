import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('currencyExponent', () {
    test('defaults to 2; JPY=0; JOD=3', () {
      expect(currencyExponent('USD'), 2);
      expect(currencyExponent('eur'), 2);
      expect(currencyExponent('JPY'), 0);
      expect(currencyExponent('JOD'), 3);
    });
  });

  group('formatMinorUnits (integer-only)', () {
    test('two-decimal currencies', () {
      expect(formatMinorUnits(4242, 'USD'), '42.42');
      expect(formatMinorUnits(5, 'USD'), '0.05');
      expect(formatMinorUnits(0, 'USD'), '0.00');
      expect(formatMinorUnits(-50, 'USD'), '-0.50');
    });
    test('zero-decimal currency', () {
      expect(formatMinorUnits(500, 'JPY'), '500');
      expect(formatMinorUnits(-7, 'JPY'), '-7');
    });
    test('three-decimal currency', () {
      expect(formatMinorUnits(1000, 'JOD'), '1.000');
      expect(formatMinorUnits(1, 'JOD'), '0.001');
    });
  });

  group('parseMajorToMinor (integer-only)', () {
    test('valid inputs', () {
      expect(parseMajorToMinor('12.50', 'USD'), 1250);
      expect(parseMajorToMinor('12', 'USD'), 1200);
      expect(parseMajorToMinor('0.05', 'USD'), 5);
      expect(parseMajorToMinor('-3.20', 'USD'), -320);
      expect(parseMajorToMinor('.5', 'USD'), 50);
      expect(parseMajorToMinor('5', 'JPY'), 5);
      expect(parseMajorToMinor('1.000', 'JOD'), 1000);
    });
    test('invalid inputs return null (no silent rounding)', () {
      expect(parseMajorToMinor('abc', 'USD'), isNull);
      expect(parseMajorToMinor('', 'USD'), isNull);
      expect(
        parseMajorToMinor('1.234', 'USD'),
        isNull,
      ); // too many fraction digits
      expect(parseMajorToMinor('1.2.3', 'USD'), isNull);
      expect(parseMajorToMinor('1.5', 'JPY'), isNull); // JPY has no fraction
      expect(parseMajorToMinor('1,5', 'USD'), isNull);
    });
    test('round trips through format', () {
      final minor = parseMajorToMinor('42.42', 'USD');
      expect(minor, 4242);
      expect(formatMinorUnits(minor!, 'USD'), '42.42');
    });
  });
}
