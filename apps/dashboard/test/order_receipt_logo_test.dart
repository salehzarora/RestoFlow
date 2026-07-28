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

  group('§9/§10 browser failed-image fallback', () {
    const url = 'https://example.test/org/rest/logo/abc.webp?token=x';

    test('a valid logo emits EXACTLY one wrapper + one <img>', () {
      final html = documentToHtml(
        buildOrderReceiptPreview(l10n, _order(), logoUrl: url),
      );
      expect('class="logo"'.allMatches(html).length, 1);
      expect('<img'.allMatches(html).length, 1);
      expect(html, contains('src="https://example.test'));
    });

    test('the <img> carries a fixed onerror that removes the WHOLE .logo '
        'wrapper (image + its reserved spacing), not just the image', () {
      final html = documentToHtml(
        buildOrderReceiptPreview(l10n, _order(), logoUrl: url),
      );
      // Removes this.parentNode (the .logo div that carries the margin), so no
      // broken-image icon AND no blank gap survive.
      expect(html, contains('onerror="'));
      expect(html, contains('this.parentNode'));
      expect(html, contains('removeChild'));
    });

    test(
      'the print script sweeps a failed image (naturalWidth===0) and removes '
      'its wrapper BEFORE window.print()',
      () {
        final html = documentToHtml(
          buildOrderReceiptPreview(l10n, _order(), logoUrl: url),
        );
        final sweepAt = html.indexOf('naturalWidth===0');
        final printAt = html.indexOf('window.print()');
        expect(sweepAt, greaterThanOrEqualTo(0));
        expect(
          printAt,
          greaterThan(sweepAt),
          reason: 'sweep runs before print',
        );
        expect(html, contains('querySelectorAll(".logo")'));
      },
    );

    test('the logo wrapper precedes the title, so removing it makes the title '
        'the first visible header', () {
      final doc = buildOrderReceiptPreview(l10n, _order(), logoUrl: url);
      final html = documentToHtml(doc);
      final logoAt = html.indexOf('class="logo"');
      final titleAt = html.indexOf('class="t"');
      expect(logoAt, greaterThanOrEqualTo(0));
      expect(titleAt, greaterThan(logoAt));
      // The title is present regardless of the logo.
      expect(doc.lines.any((l) => l.kind == PrintLineKind.title), isTrue);
    });

    test(
      'a disabled / unresolved logo (null url) emits NO wrapper, NO gap',
      () {
        final html = documentToHtml(buildOrderReceiptPreview(l10n, _order()));
        expect(html.contains('class="logo"'), isFalse);
        expect(html.contains('<img'), isFalse);
      },
    );

    test('an empty url string is treated as no logo (text-only)', () {
      final html = documentToHtml(
        buildOrderReceiptPreview(l10n, _order(), logoUrl: ''),
      );
      expect(html.contains('<img'), isFalse);
    });

    test('a hostile url is HTML-escaped in the src (no injection)', () {
      const hostile = 'https://x.test/a"><script>alert(1)</script>?t=1';
      final html = documentToHtml(
        buildOrderReceiptPreview(l10n, _order(), logoUrl: hostile),
      );
      expect(html.contains('<script>alert(1)</script>'), isFalse);
      expect(html, contains('&quot;'));
      expect(html, contains('&lt;script&gt;'));
    });

    test(
      'the kitchen ticket preview NEVER emits a logo (money-free, brand-free)',
      () {
        final doc = buildOrderKitchenTicketPreview(l10n, _order());
        expect(
          doc.lines.any((l) => l.kind == PrintLineKind.headerImage),
          isFalse,
        );
        expect(documentToHtml(doc).contains('<img'), isFalse);
      },
    );
  });
}
