import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_pos/src/spool/kitchen_ticket_renderer.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KITCHEN-MODE-001C2C — the money-free kitchen ticket renderer: content
/// coverage (initial / VOID / round / items / prep / modifiers / notes),
/// ar/he/en frame labels, the RTL raster seam, deterministic output, and
/// the 80mm ESC/POS encode.
KitchenDispatchDocument _initialDoc({
  String orderCode = '#000042',
  String? customer = 'Layla',
  String? note = 'No onions on anything',
}) => KitchenDispatchDocument(
  serverPayloadVersion: 1,
  kind: KitchenSpoolDispatchType.initialOrder,
  orderCode: orderCode,
  orderType: 'dine_in',
  tableLabel: 'T4',
  customerDisplayName: customer,
  orderNote: note,
  createdAt: '2026-07-20T10:00:00Z',
  items: [
    KitchenDispatchItem(
      qty: 2,
      name: 'Falafel Deluxe',
      note: 'extra crispy',
      prep: [
        KitchenDispatchPrepComponent(name: 'Tahini', quantity: 2, unit: 'cup'),
      ],
      modifiers: [
        KitchenDispatchModifier(qty: 2, name: 'Extra pickles'),
        KitchenDispatchModifier(qty: 1, name: 'No garlic'),
      ],
    ),
    KitchenDispatchItem(qty: 1, name: 'Cola'),
  ],
);

KitchenDispatchDocument _voidDoc() => KitchenDispatchDocument(
  serverPayloadVersion: 1,
  kind: KitchenSpoolDispatchType.voidNotice,
  orderCode: '#000042',
  orderType: 'dine_in',
  reason: 'entry_error',
  voidMarker: true,
  affectedItemCount: 3,
);

KitchenDispatchDocument _roundDoc() => KitchenDispatchDocument(
  serverPayloadVersion: 1,
  kind: KitchenSpoolDispatchType.serviceRound,
  orderCode: '#000042',
  orderType: 'dine_in',
  roundId: 'round-2',
  roundNumber: 2,
  items: [KitchenDispatchItem(qty: 1, name: 'Extra bread')],
);

List<String> _texts(pp.PrintDocument doc) => [
  for (final line in doc.lines)
    if (line is pp.PrintTextLine) line.text,
];

void main() {
  const renderer = KitchenTicketRenderer();

  test('INITIAL ticket carries every money-free content field', () {
    final doc = renderer.buildDocument(_initialDoc());
    final texts = _texts(doc).join('\n');
    expect(texts, contains('KITCHEN'));
    expect(texts, contains('#000042'));
    expect(texts, contains('Dine-in'));
    expect(texts, contains('Table: T4'));
    expect(texts, contains('Layla'));
    expect(texts, contains('2026-07-20T10:00:00Z'));
    expect(texts, contains('2 × Falafel Deluxe'));
    expect(texts, contains('+ Extra pickles ×2'));
    expect(texts, contains('+ No garlic'));
    expect(texts, contains('• Tahini 2 cup'));
    expect(texts, contains('» extra crispy'));
    expect(texts, contains('1 × Cola'));
    expect(texts, contains('Note: No onions on anything'));
    expect(texts, isNot(contains('VOID')));
    // Structure: feed + cut close the ticket.
    expect(doc.lines.whereType<pp.PrintFeedLine>(), isNotEmpty);
    expect(doc.lines.whereType<pp.PrintCutLine>(), hasLength(1));
  });

  test('VOID ticket carries a visually distinct banner, reason, and '
      'affected count', () {
    final doc = renderer.buildDocument(_voidDoc());
    final texts = _texts(doc).join('\n');
    expect(texts, contains('*** VOID ***'));
    expect(texts, contains('#000042'));
    expect(texts, contains('Reason: entry_error'));
    expect(texts, contains('Affected items: 3'));
    final banner = doc.lines.whereType<pp.PrintTextLine>().firstWhere(
      (l) => l.text.contains('VOID'),
    );
    expect(banner.style, pp.PrintLineStyle.headingLarge);
    expect(banner.emphasis, pp.TextEmphasis.bold);
  });

  test('SERVICE ROUND ticket shows the round sequence', () {
    final texts = _texts(renderer.buildDocument(_roundDoc())).join('\n');
    expect(texts, contains('Round 2'));
    expect(texts, contains('1 × Extra bread'));
  });

  test('the ticket NEVER carries money: no total style, no financial '
      'vocabulary, and the model cannot express it', () {
    for (final doc in [_initialDoc(), _voidDoc(), _roundDoc()]) {
      final rendered = renderer.buildDocument(doc);
      expect(
        rendered.lines.whereType<pp.PrintTextLine>().where(
          (l) => l.style == pp.PrintLineStyle.total,
        ),
        isEmpty,
        reason: 'PrintLineStyle.total is never emitted',
      );
      final joined = _texts(rendered).join('\n').toLowerCase();
      for (final banned in [
        'total',
        'subtotal',
        'tax',
        'discount',
        'payment',
        'paid',
        'tender',
        'change',
        '₪',
        r'$',
        '€',
      ]) {
        expect(joined, isNot(contains(banned)), reason: banned);
      }
    }
  });

  test('ar/he/en frame labels resolve per language code with an en '
      'fail-safe', () {
    expect(KitchenTicketLabels.forLanguageCode('ar').kitchenMarker, 'المطبخ');
    expect(KitchenTicketLabels.forLanguageCode('he').voidMarker, 'מבוטל');
    expect(KitchenTicketLabels.forLanguageCode('iw').voidMarker, 'מבוטל');
    expect(KitchenTicketLabels.forLanguageCode('en').kitchenMarker, 'KITCHEN');
    expect(KitchenTicketLabels.forLanguageCode(null).kitchenMarker, 'KITCHEN');
    expect(KitchenTicketLabels.forLanguageCode('fr').kitchenMarker, 'KITCHEN');

    final arDoc = const KitchenTicketRenderer(
      labels: KitchenTicketLabels.ar,
    ).buildDocument(_voidDoc());
    expect(_texts(arDoc).join('\n'), contains('ملغي'));
  });

  test(
    'tickets route through the raster seam as ONE GS v 0 bitmap at 576 '
    'dots (the ×/•/» markers are non-ASCII by design, exactly like the '
    'receipt path); without a rasterizer the text path still encodes',
    () async {
      final fake = pp.FakeReceiptRasterizer();
      final renderer = KitchenTicketRenderer(
        labels: KitchenTicketLabels.ar,
        rasterizer: fake,
      );
      final bytes = await renderer.renderToBytes(_initialDoc());
      expect(fake.requests, hasLength(1));
      expect(fake.requests.single.widthDots, pp.kNativeRasterWidthDots);
      // GS v 0 header present exactly once.
      var count = 0;
      for (var i = 0; i + 3 < bytes.length; i++) {
        if (bytes[i] == 0x1d &&
            bytes[i + 1] == 0x76 &&
            bytes[i + 2] == 0x30 &&
            bytes[i + 3] == 0x00) {
          count++;
        }
      }
      expect(count, 1, reason: 'one raster block per ticket');
      // The AR frame labels reached the raster request (RTL content routed).
      expect(fake.requests.single.lines.join('\n'), contains('المطبخ'));

      // No rasterizer injected -> the ESC/POS TEXT path still produces bytes
      // (never a silent no-print).
      final textBytes = await const KitchenTicketRenderer().renderToBytes(
        _initialDoc(customer: 'Sam', note: 'no cheese'),
      );
      expect(fake.requests, hasLength(1), reason: 'no further raster calls');
      expect(textBytes, isNotEmpty);
    },
  );

  test('a THROWING rasterizer falls back to the text document', () async {
    final renderer = KitchenTicketRenderer(
      labels: KitchenTicketLabels.he,
      rasterizer: _ExplodingRasterizer(),
    );
    final bytes = await renderer.renderToBytes(_voidDoc());
    expect(bytes, isNotEmpty, reason: 'a ? ticket beats no ticket');
  });

  test('rendering is deterministic (same document, same bytes)', () async {
    final a = await renderer.renderToBytes(_initialDoc());
    final b = await renderer.renderToBytes(_initialDoc());
    expect(a, b);
  });

  group('POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): crash-replay phone', () {
    test('customerPhoneOverride prints the phone below the name', () {
      final texts = _texts(
        renderer.buildDocument(
          _initialDoc(),
          customerPhoneOverride: '050-7654321',
        ),
      );
      expect(texts, contains('Layla'));
      expect(texts, contains('050-7654321'));
    });

    test(
      'no override + null document phone -> no phone line (byte-identical)',
      () {
        final texts = _texts(renderer.buildDocument(_initialDoc()));
        expect(texts.any((t) => t.contains('7654321')), isFalse);
      },
    );

    test('the crash-replay phone line stays money-free', () {
      final texts = _texts(
        renderer.buildDocument(
          _initialDoc(),
          customerPhoneOverride: '050-7654321',
        ),
      );
      for (final t in texts) {
        for (final money in ['₪', 'total:', 'price', 'amount']) {
          expect(t.toLowerCase().contains(money.toLowerCase()), isFalse);
        }
      }
    });
  });

  group('TABLE-FLOOR-LAYOUT-021: the dine-in star band on spool tickets', () {
    KitchenDispatchDocument takeawayDoc() => KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#000043',
      orderType: 'takeaway',
      items: [KitchenDispatchItem(qty: 1, name: 'Cola')],
    );

    test('a DINE-IN ticket opens and closes with a full-width bold star row '
        '(never the separator style)', () {
      final doc = renderer.buildDocument(_initialDoc());
      final stars = doc.lines.whereType<pp.PrintTextLine>().where(
        (l) => l.text == '*' * 48,
      );
      expect(stars, hasLength(2));
      for (final band in stars) {
        expect(band.style, isNot(pp.PrintLineStyle.separator));
        expect(band.emphasis, pp.TextEmphasis.bold);
      }
      // First content line + last content line before the feed/cut.
      final texts = doc.lines.whereType<pp.PrintTextLine>().toList();
      expect(texts.first.text, '*' * 48);
      expect(texts.last.text, '*' * 48);
    });

    test(
      'a takeaway ticket carries NO star band (byte-identical to before)',
      () {
        final doc = renderer.buildDocument(takeawayDoc());
        expect(
          doc.lines.whereType<pp.PrintTextLine>().any(
            (l) => l.text.contains('*' * 8),
          ),
          isFalse,
        );
      },
    );

    test('owner decision 5: the ar spool ticket names dine-in with the '
        'CANONICAL wording (aligned to posOrderTypeDineIn)', () {
      final texts = _texts(
        const KitchenTicketRenderer(
          labels: KitchenTicketLabels.ar,
        ).buildDocument(_initialDoc()),
      ).join('\n');
      expect(texts, contains('تناول في المطعم'));
      expect(texts, isNot(contains('محلي')));
    });
  });
}

class _ExplodingRasterizer implements pp.ReceiptRasterizer {
  @override
  Future<pp.ReceiptRasterImage> rasterize(pp.ReceiptRasterRequest request) =>
      throw StateError('raster exploded');
}
