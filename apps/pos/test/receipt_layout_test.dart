import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show receiptToEscPosDocument;
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// PRINT-LAYOUT-001: the cashier receipt layout. The internal receipt number is
/// no longer printed to the customer; the customer-facing ORDER number is a big
/// heading; a thank-you footer is added; grouped centered header; and money/tax
/// formatting is UNCHANGED. The Arabic raster path still carries every content
/// line (customer/item/modifier/note/total) into the bitmap.

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#ABC',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 1000,
  tenderedMinor: 1000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-INTERNAL-9',
  paidAt: DateTime.utc(2026, 7, 8, 14, 30),
);

SubmittedOrderView _order({
  String? name,
  String item = 'Burger',
  String? modifier,
  String? note,
}) => SubmittedOrderView(
  orderNumber: '#ABC123',
  orderType: OrderType.dineIn,
  tableLabel: 'T3',
  customerName: name,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  lines: [
    SubmittedLineView(
      name: item,
      quantity: 2,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
      modifiers: modifier == null ? const [] : [modifier],
      note: note,
    ),
  ],
);

void main() {
  group('cashier receipt layout', () {
    test('does NOT print the internal receipt number', () async {
      final l10n = await _l10n('en');
      final doc = buildReceiptDocument(
        l10n,
        _order(),
        _payment(),
        isDemo: false,
      );
      final all = doc.lines
          .map((l) => '${l.left ?? ''} ${l.right ?? ''}')
          .join('\n');
      expect(all.contains('R-INTERNAL-9'), isFalse);
      expect(all.contains(l10n.posReceiptNumberLabel), isFalse);
    });

    test(
      'shows the customer-facing order number as a big title heading',
      () async {
        final l10n = await _l10n('en');
        final doc = buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          isDemo: false,
        );
        expect(
          doc.lines.any(
            (l) =>
                l.kind == PrintLineKind.title &&
                (l.left ?? '') == l10n.posReceiptOrderHeading('#ABC123'),
          ),
          isTrue,
        );
      },
    );

    test('adds a short thank-you footer', () async {
      final l10n = await _l10n('en');
      final doc = buildReceiptDocument(
        l10n,
        _order(),
        _payment(),
        isDemo: false,
      );
      expect(
        doc.lines.any((l) => (l.left ?? '') == l10n.posReceiptThankYou),
        isTrue,
      );
    });

    test(
      'preserves the emphasised TOTAL with the money value (money untouched)',
      () async {
        final l10n = await _l10n('en');
        final doc = buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          isDemo: false,
        );
        final total = doc.lines.firstWhere(
          (l) => l.emphasised && (l.right ?? '').contains('₪'),
        );
        expect(total.right, '₪10.00');
        expect(total.emphasised, isTrue);
      },
    );

    test(
      'shows the customer name centered when present, omits it when absent',
      () async {
        final l10n = await _l10n('en');
        final withName = buildReceiptDocument(
          l10n,
          _order(name: 'Sara'),
          _payment(),
          isDemo: false,
        );
        expect(
          withName.lines.any(
            (l) =>
                l.kind == PrintLineKind.center &&
                (l.left ?? '') == '${l10n.customerNameReceiptLabel}: Sara',
          ),
          isTrue,
        );
        final without = buildReceiptDocument(
          l10n,
          _order(),
          _payment(),
          isDemo: false,
        );
        expect(
          without.lines.any(
            (l) =>
                (l.left ?? '').startsWith('${l10n.customerNameReceiptLabel}:'),
          ),
          isFalse,
        );
      },
    );
  });

  group('raster Arabic receipt', () {
    test(
      'carries the Arabic customer/item/modifier/note + total INTO the bitmap',
      () async {
        final l10n = await _l10n('ar');
        final doc = buildReceiptDocument(
          l10n,
          _order(
            name: 'محمد',
            item: 'برجر',
            modifier: 'جبنة',
            note: 'بدون بصل',
          ),
          _payment(),
          isDemo: false,
        );
        final escpos = receiptToEscPosDocument(doc);
        final fake = pp.FakeReceiptRasterizer();
        final raster = await pp.maybeRasterizeForRtl(escpos, rasterizer: fake);

        // It became ONE raster image (not "?????" text lines).
        expect(raster.lines.whereType<pp.PrintRasterImageLine>(), isNotEmpty);
        final lines = fake.requests.single.lines.join('\n');
        expect(lines.contains('محمد'), isTrue); // customer name
        expect(lines.contains('برجر'), isTrue); // item
        expect(lines.contains('جبنة'), isTrue); // modifier
        expect(lines.contains('بدون بصل'), isTrue); // note
        expect(lines.contains('₪'), isTrue); // total money moved into the image
      },
    );
  });
}
