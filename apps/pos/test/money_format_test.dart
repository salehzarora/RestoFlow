import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_money/restoflow_money.dart';
import 'package:restoflow_pos/src/format/money_format.dart';

void main() {
  test('formats ILS minor units with the shekel symbol and two decimals', () {
    expect(MoneyFormatter.formatMinor(4200, 'ILS'), '₪42.00');
    expect(MoneyFormatter.formatMinor(900, 'ILS'), '₪9.00');
    expect(MoneyFormatter.formatMinor(0, 'ILS'), '₪0.00');
    expect(MoneyFormatter.formatMinor(1299, 'ILS'), '₪12.99');
    expect(MoneyFormatter.formatMinor(5, 'ILS'), '₪0.05');
  });

  test('formats a Money value object', () {
    expect(MoneyFormatter.format(Money(4200, 'ILS')), '₪42.00');
  });

  test('renders negative amounts with a leading minus', () {
    expect(MoneyFormatter.formatMinor(-500, 'ILS'), '-₪5.00');
  });
}
