import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/order_history_models.dart';
import 'package:restoflow_dashboard/src/print/order_preview_builders.dart';
import 'package:restoflow_dashboard/src/print/print_document.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

OrderDetail _order() => const OrderDetail(
  orderId: 'o1',
  orderCode: '#1001AA',
  status: 'completed',
  orderType: 'takeaway',
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 1000,
  branchName: 'Downtown',
  items: [
    OrderDetailItem(
      name: 'Item',
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
    ),
  ],
  payments: [
    OrderPayment(
      method: 'cash',
      status: 'completed',
      amountMinor: 1000,
      tenderedMinor: 1000,
      changeMinor: 0,
    ),
  ],
);

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('no logoUrl => byte-identical text-only reprint (no header image)', () {
    final doc = buildOrderReceiptPreview(l10n, _order());
    expect(doc.lines.any((l) => l.kind == PrintLineKind.headerImage), isFalse);
    expect(documentToHtml(doc).contains('<img'), isFalse);
  });

  test('with logoUrl => a headerImage line + an <img> in the HTML', () {
    const url = 'https://example.test/org/rest/logo/abc.png?token=x';
    final doc = buildOrderReceiptPreview(l10n, _order(), logoUrl: url);
    expect(doc.lines.first.kind, PrintLineKind.headerImage);
    expect(doc.lines.first.imageUrl, url);
    final html = documentToHtml(doc);
    expect(html.contains('<img'), isTrue);
    expect(html.contains('example.test'), isTrue);
    // Stripping the header image reproduces the exact no-logo line kinds.
    final plain = buildOrderReceiptPreview(l10n, _order());
    final strippedKinds = doc.lines
        .where((l) => l.kind != PrintLineKind.headerImage)
        .map((l) => l.kind)
        .toList();
    expect(strippedKinds, plain.lines.map((l) => l.kind).toList());
  });
}
