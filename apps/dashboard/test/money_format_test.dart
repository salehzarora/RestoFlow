import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/format/money_format.dart';

void main() {
  test('formats ILS integer minor units (no thousands separator)', () {
    expect(MoneyFormatter.formatMinor(1234500, 'ILS'), '₪12345.00');
    expect(MoneyFormatter.formatMinor(14189, 'ILS'), '₪141.89');
    expect(MoneyFormatter.formatMinor(0, 'ILS'), '₪0.00');
  });

  test(
    'renders negative amounts (e.g. cash variance) with a leading minus',
    () {
      expect(MoneyFormatter.formatMinor(-1300, 'ILS'), '-₪13.00');
    },
  );
}
