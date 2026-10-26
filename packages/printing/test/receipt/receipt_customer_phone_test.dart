import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'recognized Israeli international mobile and landline display locally',
    () {
      for (final (stored, displayed) in [
        ('+972501234567', '0501234567'),
        ('+972 54-123-4567', '0541234567'),
        ('+972(2)2345678', '022345678'),
        ('+97232345678', '032345678'),
        ('+97242345678', '042345678'),
        ('+97282345678', '082345678'),
        ('+97292345678', '092345678'),
        ('+972722345678', '0722345678'),
      ]) {
        expect(formatReceiptCustomerPhone(stored), displayed);
      }
    },
  );

  test('local and other international input retains exact stored spelling', () {
    for (final stored in [
      '050-1234567',
      '02 1234567',
      '+12025550123',
      '+44 20 7946 0958',
      '',
      '12345',
      '+9720501234567',
      '+97250123456',
      '+9725012345678',
      '+97211234567',
      '+97221234567',
      '+972712345678',
      '+972721345678',
      '+972501234567\n',
      '+972501234567\r',
      '+972501234567;ext=9',
      'tel:+972501234567',
      '٠٥٠١٢٣٤٥٦٧',
    ]) {
      expect(formatReceiptCustomerPhone(stored), stored);
    }
  });

  for (final locale in ReceiptLocale.values) {
    test(
      '${locale.tag} builder formats display without mutating receipt input',
      () async {
        final input = ReceiptInput(
          organizationId: 'synthetic-org',
          branchId: 'synthetic-branch',
          deviceId: 'synthetic-device',
          paymentId: 'synthetic-payment',
          receiptNumber: 'R1',
          orderRef: 'order1',
          customerPhone: '+972501234567',
          serviceType: ReceiptServiceType.takeaway,
          currencyCode: 'ILS',
          locale: locale,
          issuedAt: DateTime.utc(2026, 10, 22),
          items: [
            ReceiptItemLine(
              nameSnapshot: 'Meal',
              quantity: 1,
              lineTotalMinor: 1000,
            ),
          ],
          subtotalMinor: 1000,
          totalMinor: 1000,
          tender: const ReceiptTenderLine(
            method: 'Cash',
            paidMinor: 1000,
            changeMinor: 0,
          ),
        );
        final raster = FakeReceiptRasterizer();
        final document = await CustomerReceiptPrintBuilder.build(
          input: input,
          paper: ReceiptPaperSpec.mm80,
          rasterizer: raster,
        );
        final lines = locale == ReceiptLocale.en
            ? document.lines.whereType<PrintTextLine>().map((line) => line.text)
            : raster.requests.single.lines;
        expect(lines.any((line) => line.contains('0501234567')), true);
        expect(lines.any((line) => line.contains('+972501234567')), false);
        expect(input.customerPhone, '+972501234567');
      },
    );
  }
}
