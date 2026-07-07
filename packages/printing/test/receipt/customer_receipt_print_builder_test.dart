import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-073 — the customer receipt builder. English renders as ESC/POS text lines
/// (stable document golden); Arabic/Hebrew render to a single raster image (no
/// unreadable `?` text). Money is displayed exactly as supplied, never computed.
void main() {
  final issuedAt = DateTime.utc(2026, 6, 23, 12, 0, 0);

  // --- English goldens ----------------------------------------------------

  group('English receipt golden (text path)', () {
    test('80mm (48 columns): exact, stable line layout', () async {
      final doc = await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt),
        paper: ReceiptPaperSpec.mm80,
      );
      expect(doc.localeTag, 'en');
      expect(doc.lines.map(_repr).toList(), _expectedEn(48));
      // every text line fits the paper width
      for (final l in doc.lines.whereType<PrintTextLine>()) {
        expect(l.text.length, lessThanOrEqualTo(48));
      }
    });

    test(
      '58mm (32 columns): same content, narrower right-aligned rows',
      () async {
        final doc = await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt),
          paper: ReceiptPaperSpec.mm58,
        );
        expect(doc.lines.map(_repr).toList(), _expectedEn(32));
        for (final l in doc.lines.whereType<PrintTextLine>()) {
          expect(l.text.length, lessThanOrEqualTo(32));
        }
      },
    );

    test(
      'the total line is emphasized and carries the currency code',
      () async {
        final doc = await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt),
          paper: ReceiptPaperSpec.mm80,
        );
        final total = doc.lines.whereType<PrintTextLine>().firstWhere(
          (l) => l.text.contains('TOTAL'),
        );
        expect(total.emphasis, TextEmphasis.bold);
        expect(total.text.trimRight(), endsWith('58.50 ILS'));
      },
    );

    test('receipt number and payment method appear', () async {
      final doc = await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt),
        paper: ReceiptPaperSpec.mm80,
      );
      final texts = doc.lines
          .whereType<PrintTextLine>()
          .map((l) => l.text)
          .join('\n');
      expect(texts, contains('Receipt: R-1001'));
      expect(texts, contains('Paid (Cash)'));
    });
  });

  // --- No money recomputation --------------------------------------------

  group('money is displayed, never recomputed (D-008)', () {
    test(
      'the printed total is the SUPPLIED total, not a sum of items',
      () async {
        // Items sum to 50.00 but the authoritative total is deliberately 99.99.
        final doc = await CustomerReceiptPrintBuilder.build(
          input: ReceiptInput(
            organizationId: 'org-1',
            branchId: 'branch-1',
            deviceId: 'dev-1',
            paymentId: 'pay-9',
            receiptNumber: 'R-9',
            orderRef: 'o9',
            serviceType: ReceiptServiceType.takeaway,
            currencyCode: 'ILS',
            locale: ReceiptLocale.en,
            issuedAt: issuedAt,
            items: [
              ReceiptItemLine(
                nameSnapshot: 'Burger',
                quantity: 1,
                lineTotalMinor: 5000,
              ),
            ],
            subtotalMinor: 5000,
            totalMinor: 9999, // intentionally != items
            tender: const ReceiptTenderLine(
              method: 'Cash',
              paidMinor: 10000,
              changeMinor: 1,
            ),
          ),
          paper: ReceiptPaperSpec.mm80,
        );
        final texts = doc.lines
            .whereType<PrintTextLine>()
            .map((l) => l.text)
            .join('\n');
        expect(texts, contains('99.99 ILS'));
      },
    );
  });

  // --- Layout wrapping ----------------------------------------------------

  group('58/80mm layout: wrap names, never truncate money', () {
    test('a long item name wraps; the amount survives intact', () async {
      final doc = await CustomerReceiptPrintBuilder.build(
        input: ReceiptInput(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          paymentId: 'pay-2',
          receiptNumber: 'R-2',
          orderRef: 'o2',
          serviceType: ReceiptServiceType.dineIn,
          currencyCode: 'ILS',
          locale: ReceiptLocale.en,
          issuedAt: issuedAt,
          items: [
            ReceiptItemLine(
              nameSnapshot:
                  'Triple Bacon Cheeseburger Deluxe With Extra Everything',
              quantity: 1,
              lineTotalMinor: 12345,
            ),
          ],
          subtotalMinor: 12345,
          totalMinor: 12345,
          tender: const ReceiptTenderLine(
            method: 'Cash',
            paidMinor: 12345,
            changeMinor: 0,
          ),
        ),
        paper: ReceiptPaperSpec.mm58,
      );
      final texts = doc.lines
          .whereType<PrintTextLine>()
          .map((l) => l.text)
          .toList();
      // The long name wraps: its first and last words land on DIFFERENT lines.
      final firstWordLine = texts.indexWhere((t) => t.contains('Triple'));
      final lastWordLine = texts.indexWhere((t) => t.contains('Everything'));
      expect(firstWordLine, isNonNegative);
      expect(lastWordLine, greaterThan(firstWordLine));
      // The amount is present in full, never truncated, and within width.
      expect(texts.any((t) => t.contains('123.45')), isTrue);
      for (final t in texts) {
        expect(t.length, lessThanOrEqualTo(32));
      }
    });
  });

  // --- Reprint marker -----------------------------------------------------

  group('reprint marker (D7 builder support)', () {
    test(
      'English: isReprint adds a centered bold DUPLICATE / REPRINT line',
      () async {
        final doc = await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt, isReprint: true),
          paper: ReceiptPaperSpec.mm80,
        );
        final marker = doc.lines.whereType<PrintTextLine>().firstWhere(
          (l) => l.text == ReceiptLabelBundle.en.duplicateMarker,
        );
        expect(marker.alignment, PrintAlignment.center);
        expect(marker.emphasis, TextEmphasis.bold);
      },
    );

    test(
      'the original (non-reprint) receipt has no duplicate marker',
      () async {
        final doc = await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt),
          paper: ReceiptPaperSpec.mm80,
        );
        final texts = doc.lines.whereType<PrintTextLine>().map((l) => l.text);
        expect(texts.contains(ReceiptLabelBundle.en.duplicateMarker), isFalse);
      },
    );
  });

  // --- ORDER-CUSTOMER-001: optional customer name -------------------------

  group('optional customer name on the receipt', () {
    List<String> textsOf(PrintDocument doc) =>
        doc.lines.whereType<PrintTextLine>().map((l) => l.text).toList();

    test('prints a "Customer: <name>" header row when present', () async {
      final texts = textsOf(
        await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt, customerName: 'Sara Cohen'),
          paper: ReceiptPaperSpec.mm80,
        ),
      );
      expect(texts, contains('Customer: Sara Cohen'));
      // It sits directly under the Order line (near the top, above items/money).
      final orderIdx = texts.indexWhere((t) => t.startsWith('Order:'));
      final custIdx = texts.indexWhere((t) => t.startsWith('Customer:'));
      expect(custIdx, orderIdx + 1);
    });

    test(
      'prints NO customer row when absent (existing receipts unchanged)',
      () async {
        final texts = textsOf(
          await CustomerReceiptPrintBuilder.build(
            input: _enInput(issuedAt),
            paper: ReceiptPaperSpec.mm80,
          ),
        );
        expect(texts.any((t) => t.startsWith('Customer:')), isFalse);
      },
    );

    test('does not disturb money/tax formatting', () async {
      final texts = textsOf(
        await CustomerReceiptPrintBuilder.build(
          input: _enInput(issuedAt, customerName: 'Dana'),
          paper: ReceiptPaperSpec.mm80,
        ),
      );
      // The authoritative total is still rendered exactly as before.
      expect(texts.any((t) => t.contains('58.50 ILS')), isTrue);
    });

    test('a long (80-char) name wraps within the paper width', () async {
      final long = 'Name ${'x' * 80}';
      final doc = await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt, customerName: long),
        paper: ReceiptPaperSpec.mm58, // 32 cols
      );
      for (final l in doc.lines.whereType<PrintTextLine>()) {
        expect(l.text.length, lessThanOrEqualTo(32));
      }
    });

    test('goes into the Arabic raster source (never as "?" text)', () async {
      final raster = FakeReceiptRasterizer();
      await CustomerReceiptPrintBuilder.build(
        input: _enInput(
          issuedAt,
          customerName: 'محمد',
        ).copyLocale(ReceiptLocale.ar),
        paper: ReceiptPaperSpec.mm80,
        rasterizer: raster,
      );
      expect(
        raster.requests.single.lines.any(
          (l) => l.contains('${ReceiptLabelBundle.ar.customer}: محمد'),
        ),
        isTrue,
      );
    });
  });

  // --- Arabic / Hebrew raster path ---------------------------------------

  group('Arabic receipt (raster fallback)', () {
    test('produces ONE raster image, no text lines, no "?"', () async {
      final raster = FakeReceiptRasterizer();
      final doc = await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt).copyLocale(ReceiptLocale.ar),
        paper: ReceiptPaperSpec.mm80,
        rasterizer: raster,
      );
      expect(doc.localeTag, 'ar');
      // No ESC/POS text lines at all -> Arabic can never become '?'.
      expect(doc.lines.whereType<PrintTextLine>(), isEmpty);
      final image = doc.lines.whereType<PrintRasterImageLine>().single;
      expect(image.widthBytes, 72); // 576 / 8
      expect(image.heightDots, greaterThan(0));
      // Arabic labels were present BEFORE rasterization.
      final sent = raster.requests.single;
      expect(sent.direction, ReceiptTextDirection.rtl);
      expect(sent.widthDots, 576);
      expect(
        sent.lines.any((l) => l.contains(ReceiptLabelBundle.ar.total)),
        isTrue,
      );
    });

    test('isReprint marker goes into the Arabic raster source', () async {
      final raster = FakeReceiptRasterizer();
      await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt, isReprint: true).copyLocale(ReceiptLocale.ar),
        paper: ReceiptPaperSpec.mm58,
        rasterizer: raster,
      );
      expect(
        raster.requests.single.lines.any(
          (l) => l.contains(ReceiptLabelBundle.ar.duplicateMarker),
        ),
        isTrue,
      );
      // 58mm raster width.
      expect(raster.requests.single.widthDots, 384);
    });

    test(
      'Arabic build without a rasterizer throws (no silent text fallback)',
      () async {
        expect(
          () => CustomerReceiptPrintBuilder.build(
            input: _enInput(issuedAt).copyLocale(ReceiptLocale.ar),
            paper: ReceiptPaperSpec.mm80,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('Hebrew receipt (raster fallback)', () {
    test('produces a raster image with Hebrew labels, no text lines', () async {
      final raster = FakeReceiptRasterizer();
      final doc = await CustomerReceiptPrintBuilder.build(
        input: _enInput(issuedAt).copyLocale(ReceiptLocale.he),
        paper: ReceiptPaperSpec.mm80,
        rasterizer: raster,
      );
      expect(doc.localeTag, 'he');
      expect(doc.lines.whereType<PrintTextLine>(), isEmpty);
      expect(doc.lines.whereType<PrintRasterImageLine>(), hasLength(1));
      expect(
        raster.requests.single.lines.any(
          (l) => l.contains(ReceiptLabelBundle.he.total),
        ),
        isTrue,
      );
    });
  });

  // --- Modifier quantities + item notes (product-rescue sprint) -----------

  group('modifier quantities and item notes (additive)', () {
    ReceiptInput noteInput(ReceiptLocale locale) => ReceiptInput(
      organizationId: 'org-1',
      branchId: 'branch-1',
      deviceId: 'dev-1',
      paymentId: 'pay-3',
      receiptNumber: 'R-3',
      orderRef: 'o3',
      serviceType: ReceiptServiceType.dineIn,
      currencyCode: 'ILS',
      locale: locale,
      issuedAt: issuedAt,
      items: [
        ReceiptItemLine(
          nameSnapshot: 'Burger',
          quantity: 1,
          lineTotalMinor: 5000,
          modifiers: const [
            ReceiptModifierLine(
              nameSnapshot: 'Extra Cheese',
              amountMinor: 500,
              quantity: 2,
            ),
            ReceiptModifierLine(nameSnapshot: 'No Onion'),
          ],
          note: 'well done',
        ),
        ReceiptItemLine(
          nameSnapshot: 'Cola',
          quantity: 1,
          lineTotalMinor: 1000,
        ),
      ],
      subtotalMinor: 6000,
      totalMinor: 6000,
      tender: const ReceiptTenderLine(
        method: 'Cash',
        paidMinor: 6000,
        changeMinor: 0,
      ),
    );

    test('text path: quantity > 1 renders " xN", quantity 1 keeps the bare '
        'name, and the note prints indented after the modifiers', () async {
      final doc = await CustomerReceiptPrintBuilder.build(
        input: noteInput(ReceiptLocale.en),
        paper: ReceiptPaperSpec.mm80,
      );
      final texts = doc.lines
          .whereType<PrintTextLine>()
          .map((l) => l.text)
          .toList();
      final modIdx = texts.indexWhere(
        (t) => t.startsWith('  + Extra Cheese x2'),
      );
      expect(modIdx, isNonNegative);
      // Quantity-1 modifier keeps the historical bare-name format.
      expect(texts.any((t) => t.startsWith('  + No Onion')), isTrue);
      expect(texts.any((t) => t.contains('No Onion x')), isFalse);
      // The note follows the modifiers and precedes the next item.
      final noteIdx = texts.indexOf('  * well done');
      expect(noteIdx, greaterThan(modIdx));
      final colaIdx = texts.indexWhere((t) => t.contains('1 x Cola'));
      expect(noteIdx, lessThan(colaIdx));
      // The note-less Cola contributes no note line.
      expect(texts.where((t) => t.startsWith('  * ')).length, 1);
    });

    test('raster path: the logical source lines carry the xN multiplier and '
        'the note', () async {
      final raster = FakeReceiptRasterizer();
      await CustomerReceiptPrintBuilder.build(
        input: noteInput(ReceiptLocale.ar),
        paper: ReceiptPaperSpec.mm80,
        rasterizer: raster,
      );
      final lines = raster.requests.single.lines;
      expect(lines.any((l) => l.contains('+ Extra Cheese x2')), isTrue);
      expect(lines, contains('  * well done'));
      expect(lines.any((l) => l.contains('No Onion x')), isFalse);
    });
  });

  // --- Immutability / defensive copy (RF073-B1) --------------------------

  group('DTOs are immutable against caller-owned list mutation (RF073-B1)', () {
    test(
      'Test 1: mutating ReceiptInput source lists does not affect it',
      () async {
        final merchant = <String>['My Cafe'];
        final items = <ReceiptItemLine>[
          ReceiptItemLine(
            nameSnapshot: 'Burger',
            quantity: 1,
            lineTotalMinor: 4000,
          ),
        ];
        final discounts = <ReceiptDiscountLine>[
          const ReceiptDiscountLine(label: 'Promo', amountMinor: -500),
        ];
        final taxes = <ReceiptTaxLine>[
          const ReceiptTaxLine(label: 'VAT 17%', amountMinor: 850),
        ];
        final footer = <String>['Thank you!'];

        final input = ReceiptInput(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          paymentId: 'pay-1',
          receiptNumber: 'R-1',
          orderRef: 'o1',
          serviceType: ReceiptServiceType.dineIn,
          currencyCode: 'ILS',
          locale: ReceiptLocale.en,
          issuedAt: issuedAt,
          merchantLines: merchant,
          items: items,
          discounts: discounts,
          taxes: taxes,
          totalMinor: 4350,
          subtotalMinor: 4000,
          tender: const ReceiptTenderLine(
            method: 'Cash',
            paidMinor: 5000,
            changeMinor: 650,
          ),
          footerLines: footer,
        );

        // Mutate every source list AFTER construction.
        merchant.add('HACKED');
        items.add(
          ReceiptItemLine(
            nameSnapshot: 'HACKED',
            quantity: 9,
            lineTotalMinor: 9,
          ),
        );
        discounts.add(
          const ReceiptDiscountLine(label: 'HACKED', amountMinor: -9),
        );
        taxes.add(const ReceiptTaxLine(label: 'HACKED', amountMinor: 9));
        footer.add('HACKED');

        // The DTO retains only the original values.
        expect(input.merchantLines, ['My Cafe']);
        expect(input.items.map((i) => i.nameSnapshot), ['Burger']);
        expect(input.discounts.map((d) => d.label), ['Promo']);
        expect(input.taxes.map((t) => t.label), ['VAT 17%']);
        expect(input.footerLines, ['Thank you!']);

        // And the stored lists are themselves unmodifiable.
        expect(
          () => input.items.add(input.items.first),
          throwsUnsupportedError,
        );
        expect(() => input.merchantLines.add('x'), throwsUnsupportedError);
      },
    );

    test(
      'Test 2: mutating ReceiptItemLine source modifiers does not affect it',
      () {
        final modifiers = <ReceiptModifierLine>[
          const ReceiptModifierLine(
            nameSnapshot: 'Extra Cheese',
            amountMinor: 500,
          ),
        ];
        final item = ReceiptItemLine(
          nameSnapshot: 'Burger',
          quantity: 1,
          lineTotalMinor: 4000,
          modifiers: modifiers,
        );

        modifiers.add(const ReceiptModifierLine(nameSnapshot: 'HACKED'));

        expect(item.modifiers.map((m) => m.nameSnapshot), ['Extra Cheese']);
        expect(
          () =>
              item.modifiers.add(const ReceiptModifierLine(nameSnapshot: 'x')),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'Test 3: rendered receipt is stable after source-list mutation',
      () async {
        final merchant = <String>['My Cafe'];
        final modifiers = <ReceiptModifierLine>[
          const ReceiptModifierLine(
            nameSnapshot: 'Extra Cheese',
            amountMinor: 500,
          ),
        ];
        final items = <ReceiptItemLine>[
          ReceiptItemLine(
            nameSnapshot: 'Burger',
            quantity: 1,
            lineTotalMinor: 4000,
            modifiers: modifiers,
          ),
        ];
        final footer = <String>['Thank you!'];

        final input = ReceiptInput(
          organizationId: 'org-1',
          branchId: 'branch-1',
          deviceId: 'dev-1',
          paymentId: 'pay-1',
          receiptNumber: 'R-1',
          orderRef: 'o1',
          serviceType: ReceiptServiceType.dineIn,
          currencyCode: 'ILS',
          locale: ReceiptLocale.en,
          issuedAt: issuedAt,
          merchantLines: merchant,
          items: items,
          subtotalMinor: 4000,
          totalMinor: 4000,
          tender: const ReceiptTenderLine(
            method: 'Cash',
            paidMinor: 4000,
            changeMinor: 0,
          ),
          footerLines: footer,
        );

        // Mutate the original sources before rendering.
        merchant.add('HACKED-MERCHANT');
        modifiers.add(const ReceiptModifierLine(nameSnapshot: 'HACKED-MOD'));
        items.add(
          ReceiptItemLine(
            nameSnapshot: 'HACKED-ITEM',
            quantity: 1,
            lineTotalMinor: 1,
          ),
        );
        footer.add('HACKED-FOOTER');

        final doc = await CustomerReceiptPrintBuilder.build(
          input: input,
          paper: ReceiptPaperSpec.mm80,
        );
        final text = doc.lines
            .whereType<PrintTextLine>()
            .map((l) => l.text)
            .join('\n');

        // No mutated value leaks into the output.
        expect(text, isNot(contains('HACKED')));
        // Original values are present.
        expect(text, contains('My Cafe'));
        expect(text, contains('Burger'));
        expect(text, contains('Extra Cheese'));
        expect(text, contains('Thank you!'));
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Fixtures + stable-representation helper.
// ---------------------------------------------------------------------------

ReceiptInput _enInput(
  DateTime at, {
  bool isReprint = false,
  String? customerName,
}) => ReceiptInput(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  paymentId: 'pay-1',
  receiptNumber: 'R-1001',
  orderRef: 'o1',
  serviceType: ReceiptServiceType.dineIn,
  currencyCode: 'ILS',
  locale: ReceiptLocale.en,
  issuedAt: at,
  customerName: customerName,
  merchantLines: const ['My Cafe', 'Tel 123'],
  items: [
    ReceiptItemLine(
      nameSnapshot: 'Burger',
      quantity: 2,
      lineTotalMinor: 4000,
      modifiers: const [
        ReceiptModifierLine(nameSnapshot: 'Extra Cheese', amountMinor: 500),
      ],
    ),
    ReceiptItemLine(nameSnapshot: 'Cola', quantity: 1, lineTotalMinor: 1000),
  ],
  subtotalMinor: 5500,
  discounts: const [ReceiptDiscountLine(label: 'Promo', amountMinor: -500)],
  taxes: const [ReceiptTaxLine(label: 'VAT 17%', amountMinor: 850)],
  totalMinor: 5850,
  tender: const ReceiptTenderLine(
    method: 'Cash',
    paidMinor: 6000,
    changeMinor: 150,
  ),
  footerLines: const ['Thank you!'],
  isReprint: isReprint,
);

/// Single-line name-left / amount-right row at [width] (mirrors the builder's
/// fits-on-one-line case; all fixture rows fit at both 32 and 48).
String _row1(String left, String right, int width) =>
    '$left${' ' * (width - left.length - right.length)}$right';

List<String> _expectedEn(int w) => <String>[
  'CN|My Cafe',
  'CN|Tel 123',
  'LN|Receipt: R-1001',
  'LN|Order: o1',
  'LN|Dine-in',
  'LN|2026-06-23T12:00:00.000Z',
  'FEED 1',
  'LN|${_row1('2 x Burger', '40.00', w)}',
  'LN|${_row1('  + Extra Cheese', '5.00', w)}',
  'LN|${_row1('1 x Cola', '10.00', w)}',
  'FEED 1',
  'LN|${_row1('Subtotal', '55.00', w)}',
  'LN|${_row1('Promo', '-5.00', w)}',
  'LN|${_row1('VAT 17%', '8.50', w)}',
  'LB|${_row1('TOTAL', '58.50 ILS', w)}',
  'FEED 1',
  'LN|${_row1('Paid (Cash)', '60.00', w)}',
  'LN|${_row1('Change', '1.50', w)}',
  'CN|Thank you!',
  'FEED 2',
  'CUT',
];

String _repr(PrintLine line) {
  if (line is PrintTextLine) {
    final a = switch (line.alignment) {
      PrintAlignment.center => 'C',
      PrintAlignment.right => 'R',
      PrintAlignment.left => 'L',
    };
    final e = line.emphasis == TextEmphasis.bold ? 'B' : 'N';
    return '$a$e|${line.text}';
  }
  if (line is PrintFeedLine) return 'FEED ${line.lines}';
  if (line is PrintCutLine) return 'CUT';
  if (line is PrintRasterImageLine) {
    return 'RASTER ${line.widthBytes}x${line.heightDots}';
  }
  return 'OTHER';
}

extension _ReceiptInputTestX on ReceiptInput {
  /// Rebuild this input under a different [locale] (keeps all other data).
  ReceiptInput copyLocale(ReceiptLocale locale) => ReceiptInput(
    organizationId: organizationId,
    branchId: branchId,
    deviceId: deviceId,
    paymentId: paymentId,
    receiptNumber: receiptNumber,
    orderRef: orderRef,
    serviceType: serviceType,
    currencyCode: currencyCode,
    locale: locale,
    issuedAt: issuedAt,
    merchantLines: merchantLines,
    items: items,
    subtotalMinor: subtotalMinor,
    discounts: discounts,
    taxes: taxes,
    totalMinor: totalMinor,
    tender: tender,
    footerLines: footerLines,
    isReprint: isReprint,
    isPaid: isPaid,
    isVoidedOrCancelled: isVoidedOrCancelled,
    exponentOverride: exponentOverride,
    labels: labels,
    customerName: customerName,
  );
}
