import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenPrepComponent, KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:test/test.dart';

/// KITCHEN-PRINT-DUAL-001B — the ONE shared kitchen-ticket layout.
///
/// Both the KDS live print (`buildKdsTicketDocument`) and the POS direct kitchen
/// print render through [buildKdsTicketPrintDocument] + [kitchenTicketToEscPosDocument],
/// so this suite pins the CANONICAL operational detail a kitchen ticket carries
/// on EITHER surface, that it is money-free, and (PRINT-LAYOUT-001B) its typographic
/// hierarchy: restaurant-name brand > big order reference > meta > counts > items
/// (quantity-leading) > modifiers > distinct notes, with a gap between items.

const _moneyTokens = [
  'total:',
  'subtotal',
  'tax',
  'discount',
  'payment',
  'tender',
  'price',
  'amount',
  '₪',
  r'$',
  '€',
  '1500',
  '3000',
];

KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'KTotal $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
  restaurantNameFallback: 'Restaurant',
);

/// Labels WITHOUT the localized fallback (an older/omitting build): the brand
/// line is then simply absent — never a hardcoded placeholder.
KitchenTicketPrintLabels _labelsNoFallback() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket preview',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'KTotal $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
);

/// A DETAILED representative order: two items, qty>1, whole-order kitchen counts
/// (meat + bread), structured modifiers with ×N, item + order notes, table +
/// order type. Station is unassigned (a POS whole-order ticket routes to no
/// station) — the station line must therefore be suppressed.
KdsTicketView _ticket({DateTime? submittedAt}) => KdsTicketView(
  kitchenTicketId: '#000042',
  stationId: KdsTicketMapper.unassignedStation,
  status: KitchenTicketStatus.newTicket,
  orderNumber: '#000042',
  orderType: 'dine_in',
  tableLabel: '5',
  customerName: 'Dana',
  notes: 'call when ready',
  submittedAt: submittedAt,
  kitchenCounts: const [
    KitchenCount(quantity: 4, label: 'قطع لحم'),
    KitchenCount(quantity: 2, label: 'خبز'),
  ],
  items: const [
    KdsItemView(
      name: 'Double Burger',
      quantity: 2,
      modifiers: ['Double ×2', 'no onion'],
      note: 'well done',
      prepComponents: [KitchenPrepComponent(name: 'خبز', quantity: 1)],
    ),
    KdsItemView(name: 'Fries', quantity: 1),
  ],
);

void main() {
  group('the shared kitchen-ticket document (canonical detail)', () {
    test('carries every operational field for both items', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
        restaurantName: 'Falafel House',
      );
      final texts = [for (final l in doc.lines) l.left ?? l.right ?? ''];

      // TABLE-FLOOR-LAYOUT-021: a DINE-IN ticket opens and closes with the
      // star band; the brand hero (secondary heading) sits directly under it,
      // ABOVE the big order-number reference.
      expect(doc.lines.first.kind, PrintLineKind.banner);
      expect(doc.lines.last.kind, PrintLineKind.banner);
      expect(doc.lines[1].kind, PrintLineKind.subtitle);
      expect(doc.lines[1].left, 'Falafel House');
      expect(doc.lines[2].kind, PrintLineKind.title);
      expect(doc.lines[2].left, '#000042');
      expect(texts, contains('Dine-in'));
      expect(texts, contains('Table 5'));
      expect(texts, contains('Customer: Dana'));
      // Station is UNASSIGNED on a POS whole-order ticket => no station line.
      expect(
        texts.any((t) => t.contains('Station')),
        isFalse,
        reason: 'unassigned station is suppressed',
      );

      // Whole-order kitchen counts (meat + bread), one prominent line each.
      expect(texts, contains('KTotal 4 قطع لحم'));
      expect(texts, contains('KTotal 2 خبز'));

      // Item lines LEAD with the quantity at the emphasised item size.
      final burger = doc.lines.firstWhere(
        (l) => l.kind == PrintLineKind.item && l.left == '2 × Double Burger',
      );
      expect(burger.emphasised, isTrue);
      expect(
        doc.lines.any(
          (l) => l.kind == PrintLineKind.item && l.left == '1 × Fries',
        ),
        isTrue,
      );

      // Modifiers stay sub-lines (the ×N is preserved); item + order notes use
      // the DISTINCT note style so an instruction can't read as a modifier.
      expect(texts, contains('+ Double ×2'));
      expect(texts, contains('+ no onion'));
      final itemNote = doc.lines.firstWhere(
        (l) => l.left == '» Note: well done',
      );
      expect(itemNote.kind, PrintLineKind.note);
      final orderNote = doc.lines.firstWhere(
        (l) => l.left == '» Note: call when ready',
      );
      expect(orderNote.kind, PrintLineKind.note);

      // A blank spacer separates the two item blocks.
      expect(doc.lines.any((l) => l.kind == PrintLineKind.spacer), isTrue);
    });

    test('is money-free (no price/total/currency reaches the ticket)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
        restaurantName: 'Falafel House',
      );
      for (final line in doc.lines) {
        final text = '${line.left ?? ''} ${line.right ?? ''}'.toLowerCase();
        for (final token in _moneyTokens) {
          expect(
            text.contains(token.toLowerCase()),
            isFalse,
            reason: 'money token "$token" on line "$text"',
          );
        }
      }
    });

    test('never emits a total style (money-free by construction)', () {
      final escpos = kitchenTicketToEscPosDocument(
        buildKdsTicketPrintDocument(
          ticket: _ticket(),
          labels: _labels(),
          restaurantName: 'Falafel House',
        ),
      );
      expect(
        escpos.lines.whereType<pp.PrintTextLine>().any(
          (l) => l.style == pp.PrintLineStyle.total,
        ),
        isFalse,
      );
    });

    test(
      'converts to ESC/POS preserving sub-indent, item lead-quantity, feed + cut',
      () {
        final doc = buildKdsTicketPrintDocument(
          ticket: _ticket(),
          labels: _labels(),
        );
        final escpos = kitchenTicketToEscPosDocument(doc, columns: 48);
        final textLines = escpos.lines.whereType<pp.PrintTextLine>().toList();

        // Sub-lines are indented by two spaces (chef reads modifiers under items).
        expect(textLines.any((l) => l.text == '  + Double ×2'), isTrue);
        // Item lines LEAD with the quantity at the DEDICATED larger kitchen
        // item style (PRINT-LAYOUT-001C).
        final burger = textLines.firstWhere(
          (l) => l.text.startsWith('2 × Double Burger'),
        );
        expect(burger.style, pp.PrintLineStyle.kitchenItem);
        // A rule spans the full width.
        expect(textLines.any((l) => l.text == '-' * 48), isTrue);
        // The document ends with the paper feed + cut.
        expect(escpos.lines[escpos.lines.length - 2], isA<pp.PrintFeedLine>());
        expect(escpos.lines.last, isA<pp.PrintCutLine>());
      },
    );

    test('a takeaway ticket with no table/counts omits those lines', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: KdsTicketView(
          kitchenTicketId: '#7',
          stationId: KdsTicketMapper.unassignedStation,
          status: KitchenTicketStatus.newTicket,
          orderNumber: '#7',
          orderType: 'takeaway',
          items: const [KdsItemView(name: 'Cola', quantity: 1)],
        ),
        labels: _labels(),
      );
      final texts = [for (final l in doc.lines) l.left ?? l.right ?? ''];
      expect(texts, contains('Takeaway'));
      expect(texts.any((t) => t.startsWith('Table')), isFalse);
      expect(texts.any((t) => t.startsWith('KTotal')), isFalse);
      expect(texts, contains('1 × Cola'));
    });

    test(
      'KIOSK-PRINT-114B.6 (supersedes KITCHEN-PRINT-DUAL-001B Finding 4): the '
      'printed kitchen ticket renders the ORDER CREATION date + time from '
      'submittedAt in the header meta block — every canonical path (POS direct, '
      'kiosk/drain dispatch, POS reprint, KDS bridge) prints the same stamp; '
      'without a known creation time the ticket is byte-identical to before.',
      () {
        final labels = _labels();
        final withoutTime = buildKdsTicketPrintDocument(
          ticket: _ticket(),
          labels: labels,
        );
        final createdAt = DateTime.utc(2026, 7, 22, 10, 30, 45);
        final withTime = buildKdsTicketPrintDocument(
          ticket: _ticket(submittedAt: createdAt),
          labels: labels,
        );
        final stamp = formatKitchenTicketTimestamp(createdAt);
        // Exactly ONE extra line: the centered creation stamp, in the header
        // meta block (before the rule that precedes the counts/items).
        final withTexts = [for (final l in withTime.lines) l.left ?? ''];
        final withoutTexts = [for (final l in withoutTime.lines) l.left ?? ''];
        expect(withTime.lines.length, withoutTime.lines.length + 1);
        final at = withTexts.indexOf(stamp);
        expect(at, greaterThan(0));
        expect(withTime.lines[at].kind, PrintLineKind.center);
        expect([...withTexts]..removeAt(at), withoutTexts);
        // No line without a known creation time carries a timestamp value.
        for (final line in withoutTime.lines) {
          final text = '${line.left ?? ''} ${line.right ?? ''}';
          expect(RegExp(r'\d\d/\d\d/\d{4}').hasMatch(text), isFalse);
        }
      },
    );
  });

  group('restaurant-name brand line (PRINT-LAYOUT-001B, test A)', () {
    // The _ticket() fixture is DINE-IN, so line 0 is the 021 star band; the
    // brand hierarchy under test starts at line 1.
    test('prints the real restaurant name as the brand line above the '
        'order reference', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
        restaurantName: 'Falafel House',
      );
      expect(doc.lines[1].kind, PrintLineKind.subtitle);
      expect(doc.lines[1].left, 'Falafel House');
      expect(doc.lines[2].kind, PrintLineKind.title);
      expect(doc.lines[2].left, '#000042');
    });

    test('falls back to the localized generic brand word when no real name '
        'is supplied', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
      );
      expect(doc.lines[1].kind, PrintLineKind.subtitle);
      expect(doc.lines[1].left, 'Restaurant');
    });

    test('a blank/whitespace real name uses the fallback, never a blank '
        'brand line', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
        restaurantName: '   ',
      );
      expect(doc.lines[1].kind, PrintLineKind.subtitle);
      expect(doc.lines[1].left, 'Restaurant');
    });

    test('omits the brand line entirely when neither a real name nor a '
        'fallback exists (never a hardcoded placeholder)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labelsNoFallback(),
      );
      expect(doc.lines[1].kind, PrintLineKind.title);
      expect(doc.lines[1].left, '#000042');
      expect(doc.lines.any((l) => l.kind == PrintLineKind.subtitle), isFalse);
    });
  });

  group('dine-in star band (TABLE-FLOOR-LAYOUT-021)', () {
    test('a dine-in ticket opens AND closes with the band; takeaway carries '
        'none', () {
      final dineIn = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
      );
      expect(dineIn.lines.first.kind, PrintLineKind.banner);
      expect(dineIn.lines.last.kind, PrintLineKind.banner);
      expect(
        dineIn.lines.where((l) => l.kind == PrintLineKind.banner).length,
        2,
      );

      final takeaway = buildKdsTicketPrintDocument(
        ticket: KdsTicketView(
          kitchenTicketId: '#7',
          stationId: KdsTicketMapper.unassignedStation,
          status: KitchenTicketStatus.newTicket,
          orderNumber: '#7',
          orderType: 'takeaway',
          items: const [KdsItemView(name: 'Cola', quantity: 1)],
        ),
        labels: _labels(),
      );
      expect(
        takeaway.lines.any((l) => l.kind == PrintLineKind.banner),
        isFalse,
      );
    });

    test('an UNKNOWN/absent order type prints no band (fail-quiet)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: KdsTicketView(
          kitchenTicketId: '#8',
          stationId: KdsTicketMapper.unassignedStation,
          status: KitchenTicketStatus.newTicket,
          orderNumber: '#8',
          items: const [KdsItemView(name: 'Cola', quantity: 1)],
        ),
        labels: _labels(),
      );
      expect(doc.lines.any((l) => l.kind == PrintLineKind.banner), isFalse);
    });

    test('ESC/POS renders the band as a FULL-WIDTH bold star row — never the '
        'separator style (raster would drop the stars)', () {
      final escpos = kitchenTicketToEscPosDocument(
        buildKdsTicketPrintDocument(ticket: _ticket(), labels: _labels()),
        columns: 48,
      );
      final stars = escpos.lines
          .whereType<pp.PrintTextLine>()
          .where((l) => l.text == '*' * 48)
          .toList();
      expect(stars, hasLength(2));
      for (final band in stars) {
        expect(band.style, isNot(pp.PrintLineStyle.separator));
        expect(band.emphasis, pp.TextEmphasis.bold);
      }
      // 50mm labels get the same band at their own width.
      final narrow = kitchenTicketToEscPosDocument(
        buildKdsTicketPrintDocument(ticket: _ticket(), labels: _labels()),
        columns: 32,
      );
      expect(
        narrow.lines.whereType<pp.PrintTextLine>().where(
          (l) => l.text == '*' * 32,
        ),
        hasLength(2),
      );
    });
  });

  group('kitchen item ordering (PRINT-LAYOUT-001C, test D)', () {
    KdsTicketView mixedTicket() => KdsTicketView(
      kitchenTicketId: '#900',
      stationId: KdsTicketMapper.unassignedStation,
      status: KitchenTicketStatus.newTicket,
      orderNumber: '#900',
      orderType: 'dine_in',
      items: const [
        KdsItemView(name: 'Burger A', quantity: 1, modifiers: ['no onion']),
        KdsItemView(name: 'Cola', quantity: 1),
        KdsItemView(name: 'Burger B', quantity: 1, note: 'well done'),
        KdsItemView(name: 'Sprite', quantity: 1),
        KdsItemView(name: 'Fries', quantity: 1),
      ],
    );

    test('items print in their SUBMISSION order (stable, every item exactly '
        'once, modifiers + notes attached to the right item) — food and drinks '
        'are NOT reordered, because the kitchen snapshot carries no structured '
        'beverage/category field to group by', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: mixedTicket(),
        labels: _labels(),
        restaurantName: 'Falafel House',
      );
      final items = [
        for (final l in doc.lines)
          if (l.kind == PrintLineKind.item) l.left,
      ];
      // Exactly the submitted order — the food/drink interleaving the physical
      // test flagged is preserved (drinks-last needs a structured field first).
      expect(items, [
        '1 × Burger A',
        '1 × Cola',
        '1 × Burger B',
        '1 × Sprite',
        '1 × Fries',
      ]);
      // Modifiers + notes stay attached to their item.
      final texts = [for (final l in doc.lines) l.left ?? ''];
      expect(texts, contains('+ no onion'));
      expect(texts, contains('» Note: well done'));
    });

    test('the builder is a PURE function of the ticket — deterministic, so it '
        'performs no live menu / network lookup during rendering', () {
      final t = mixedTicket();
      List<String> dump(KdsTicketView v) {
        final doc = buildKdsTicketPrintDocument(ticket: v, labels: _labels());
        return [for (final l in doc.lines) '${l.kind}|${l.left}|${l.right}'];
      }

      expect(dump(t), dump(t));
    });
  });
}
