import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenCount, KitchenPrepComponent, KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:test/test.dart';

/// DEFERRED-ORDER-AMENDMENTS-001 — the ADDITION marker on the ONE shared
/// kitchen-ticket layout.
///
/// A service-round ticket is a DELTA: the kitchen must be able to tell at a
/// glance that this paper is items ADDED to an order already on the line, and
/// which order that is. Getting it wrong means either cooking the whole order a
/// second time or missing the addition entirely. This suite pins:
///
///  * the typed [KitchenTicketDocumentKind] and its derivation from the ONE
///    authoritative signal (the server's round number);
///  * that an addition prints the localized "Addition · Round N" band in the
///    LARGE heading style, directly under the ORIGINAL order code;
///  * that an INITIAL order is byte-identical to before (no marker, no line
///    moved) — proven by diffing the two documents, not by eyeballing;
///  * that the marker is money-free, delta-only, and quantity-correct.

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

/// One ticket shape, parameterized ONLY by the round identity, so the initial
/// and addition documents differ by exactly the thing under test.
KdsTicketView _ticket({
  String? roundId,
  int? roundNumber,
  String orderType = 'dine_in',
  String? tableLabel = 'T7',
}) => KdsTicketView(
  kitchenTicketId: 'kt-1',
  stationId: KdsTicketMapper.unassignedStation,
  items: const [
    KdsItemView(
      name: 'Shawarma Plate',
      quantity: 3,
      modifiers: ['Extra garlic ×2'],
      note: 'no pickles',
      prepComponents: [
        KitchenPrepComponent(name: 'Skewers', quantity: 2, unit: 'skewer'),
      ],
    ),
  ],
  status: KitchenTicketStatus.newTicket,
  orderNumber: '#A1B2C3',
  orderType: orderType,
  tableLabel: tableLabel,
  kitchenCounts: const [KitchenCount(quantity: 6, label: 'skewer')],
  roundId: roundId,
  roundNumber: roundNumber,
);

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

void main() {
  group('A. the typed document kind', () {
    test('A1 an initial order (no round) is initialOrder', () {
      expect(
        KitchenTicketDocumentKind.forTicket(_ticket()),
        KitchenTicketDocumentKind.initialOrder,
      );
    });

    test('A2 any ticket carrying a round number is an orderAddition', () {
      for (final n in [2, 3, 17]) {
        expect(
          KitchenTicketDocumentKind.forTicket(
            _ticket(roundId: 'r', roundNumber: n),
          ),
          KitchenTicketDocumentKind.orderAddition,
          reason: 'round $n is an addition',
        );
      }
    });
  });

  group('B. the printed addition marker', () {
    test('B1 an addition prints the localized "Addition · Round N"', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      expect(_texts(doc), contains('Addition · Round 3'));
    });

    test('B2 the marker sits directly under the ORIGINAL order code, in the '
        'same LARGE heading style (it cannot be missed)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      final titles = doc.lines
          .where((l) => l.kind == PrintLineKind.title)
          .toList();
      final codeAt = _texts(doc).indexOf('#A1B2C3');
      final markerAt = _texts(doc).indexOf('Addition · Round 3');
      expect(codeAt, greaterThanOrEqualTo(0));
      expect(markerAt, codeAt + 1, reason: 'immediately below the order code');
      // Both are `title` lines => the ESC/POS mapper renders them headingLarge.
      expect(
        titles.map((l) => l.left),
        containsAll(<String>['#A1B2C3', 'Addition · Round 3']),
      );
    });

    test('B3 the marker names the ORIGINAL order, not a new one', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      // The order code the kitchen ties the delta to is the parent's own code.
      expect(_texts(doc), contains('#A1B2C3'));
      expect(doc.title, contains('#A1B2C3'));
    });

    test('B4 an INITIAL order prints NO marker and is byte-identical to the '
        'pre-change layout (the addition band is the ONLY difference)', () {
      final initial = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
      );
      final addition = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      expect(
        _texts(initial).where((t) => t.contains('Addition')),
        isEmpty,
        reason: 'no marker on work unit 1',
      );
      expect(
        _texts(initial).where((t) => t.contains('Round')),
        isEmpty,
        reason: 'no fabricated round on work unit 1',
      );
      // Removing the one marker line makes the addition document EQUAL to the
      // initial one: nothing else moved, was restyled, or was dropped.
      final strippedAddition = [
        for (final l in addition.lines)
          if (l.left != 'Addition · Round 3') l,
      ];
      expect(strippedAddition.length, initial.lines.length);
      for (var i = 0; i < initial.lines.length; i++) {
        expect(strippedAddition[i].kind, initial.lines[i].kind);
        expect(strippedAddition[i].left, initial.lines[i].left);
        expect(strippedAddition[i].right, initial.lines[i].right);
        expect(strippedAddition[i].emphasised, initial.lines[i].emphasised);
      }
      expect(addition.title, initial.title);
    });

    test('B5 an explicit kind override with NO round number prints the bare '
        'marker, never a fabricated "Round null"', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
        kind: KitchenTicketDocumentKind.orderAddition,
      );
      expect(_texts(doc), contains('Addition'));
      expect(_texts(doc).where((t) => t.contains('Round')), isEmpty);
    });

    test('B6 an explicit initialOrder override suppresses the marker even on a '
        'round ticket (the caller stays in control)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
        kind: KitchenTicketDocumentKind.initialOrder,
      );
      expect(_texts(doc).where((t) => t.contains('Addition')), isEmpty);
    });
  });

  group('C. the addition ticket stays a correct kitchen ticket', () {
    test('C1 delta items keep their quantities, modifiers and notes', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      final texts = _texts(doc);
      expect(texts.any((t) => t.startsWith('3 × Shawarma Plate')), isTrue);
      expect(texts, contains('+ Extra garlic ×2'));
      expect(texts.any((t) => t.contains('no pickles')), isTrue);
      expect(texts, contains('KTotal 6 skewer'));
    });

    test('C2 the addition ticket carries NO money (T-003)', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 3),
        labels: _labels(),
      );
      final blob = _texts(doc).join('\n').toLowerCase();
      for (final token in [
        'total:',
        'subtotal',
        'tax',
        'discount',
        'payment',
        'tender',
        'price',
        '₪',
        r'$',
        '€',
      ]) {
        expect(blob, isNot(contains(token)), reason: 'money token: $token');
      }
      for (final l in doc.lines) {
        expect(l.right ?? '', isEmpty, reason: 'no money right column');
      }
    });

    test('C3 a TAKEAWAY addition prints its type and NO table line; a dine-in '
        'addition keeps its table', () {
      final takeaway = buildKdsTicketPrintDocument(
        ticket: _ticket(
          roundId: 'r-9',
          roundNumber: 2,
          orderType: 'takeaway',
          tableLabel: null,
        ),
        labels: _labels(),
      );
      final texts = _texts(takeaway);
      expect(texts, contains('Takeaway'));
      expect(texts, contains('Addition · Round 2'));
      expect(
        texts.where((t) => t.startsWith('Table')),
        isEmpty,
        reason: 'a takeaway order has no table and none is invented',
      );

      final dineIn = buildKdsTicketPrintDocument(
        ticket: _ticket(roundId: 'r-9', roundNumber: 2),
        labels: _labels(),
      );
      expect(_texts(dineIn), contains('Table T7'));
    });
  });
}
