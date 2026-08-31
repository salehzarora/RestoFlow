import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;

/// KIOSK-PRINT-114B.6 — the canonical kitchen ticket HEADER:
///  * a LARGE service-mode badge directly under the order code (dine-in vs
///    takeaway) — ASCII-framed so it prints identically on the text path and
///    the raster path, POS and kiosk alike;
///  * the order CREATION date + time (never the print time) in the header
///    meta block, formatted by the ONE shared formatter;
///  * item sub-lines keep the AUTHORITATIVE stored order — the adapter never
///    re-sorts, never alphabetizes.
KitchenTicketPrintLabels _labels() => KitchenTicketPrintLabels(
  ticketLabel: 'Ticket',
  previewTitle: 'Kitchen ticket',
  dineIn: 'Dine-in',
  takeaway: 'Takeaway',
  tableLabel: 'Table',
  customerLabel: 'Customer',
  customerPhoneLabel: 'Phone',
  stationLabel: 'Station',
  noteLabel: 'Note',
  kitchenTotal: (count, unit) => 'Kitchen total: $count $unit',
  additionLabel: 'Addition',
  roundLabel: (n) => 'Round $n',
  restaurantNameFallback: 'Demo Bistro',
);

final _createdAt = DateTime(2026, 8, 25, 14, 7);

KdsTicketView _ticket({String orderType = 'takeaway', DateTime? submittedAt}) =>
    KdsTicketView(
      kitchenTicketId: '#ABC123',
      stationId: KdsTicketMapper.unassignedStation,
      status: KitchenTicketStatus.newTicket,
      orderNumber: '#ABC123',
      orderType: orderType,
      tableLabel: orderType == 'dine_in' ? '7' : null,
      customerName: 'Saleh',
      submittedAt: submittedAt,
      items: const [
        KdsItemView(
          name: 'Classic Burger',
          quantity: 2,
          modifiers: ['240g', 'cheese', 'lettuce', 'tomato', 'onion'],
          linePosition: 1,
        ),
      ],
    );

List<String> _texts(PrintDocument doc) => [
  for (final line in doc.lines) line.left ?? line.right ?? '',
];

void main() {
  group('C. service-mode badge', () {
    test('a TAKEAWAY ticket prints the takeaway badge as a LARGE title line '
        'directly under the order code', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(orderType: 'takeaway'),
        labels: _labels(),
      );
      final code = doc.lines.indexWhere((l) => l.left == '#ABC123');
      final badge = doc.lines[code + 1];
      expect(badge.kind, PrintLineKind.title);
      expect(badge.left, kitchenServiceModeBadge(_labels(), 'takeaway'));
      expect(badge.left, contains('Takeaway'));
      expect(badge.left, isNot(contains('Dine-in')));
    });

    test('a DINE-IN ticket prints the dine-in badge under the order code', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(orderType: 'dine_in'),
        labels: _labels(),
      );
      final code = doc.lines.indexWhere((l) => l.left == '#ABC123');
      final badge = doc.lines[code + 1];
      expect(badge.kind, PrintLineKind.title);
      expect(badge.left, kitchenServiceModeBadge(_labels(), 'dine_in'));
      expect(badge.left, contains('Dine-in'));
    });

    test('the two badges are visually distinct and ASCII-framed (text + raster '
        'safe)', () {
      final a = kitchenServiceModeBadge(_labels(), 'takeaway')!;
      final b = kitchenServiceModeBadge(_labels(), 'dine_in')!;
      expect(a, isNot(b));
      for (final s in [a, b]) {
        expect(s.codeUnits.every((c) => c < 128), isTrue, reason: 'ASCII: $s');
        expect(s.length, greaterThan(8));
      }
    });

    test('an unknown order type prints no badge line', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(orderType: 'weird'),
        labels: _labels(),
      );
      expect(
        _texts(
          doc,
        ).where((t) => t.contains('Takeaway') || t.contains('Dine-in')),
        isEmpty,
      );
    });
  });

  group('B. creation timestamp', () {
    test(
      'formatKitchenTicketTimestamp is compact date + time, zero-padded',
      () {
        expect(formatKitchenTicketTimestamp(_createdAt), '25/08/2026 14:07');
        expect(
          formatKitchenTicketTimestamp(DateTime(2026, 1, 3, 9, 5)),
          '03/01/2026 09:05',
        );
      },
    );

    test('the header meta block carries the CREATION time, before the rule '
        'that precedes the counts/items', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(submittedAt: _createdAt),
        labels: _labels(),
      );
      final texts = _texts(doc);
      final ts = texts.indexOf('25/08/2026 14:07');
      expect(ts, greaterThan(texts.indexOf('#ABC123')));
      expect(ts, lessThan(texts.indexWhere((t) => t.startsWith('2 × '))));
      expect(doc.lines[ts].kind, PrintLineKind.center);
    });

    test('no timestamp when the creation time is unknown', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: _ticket(),
        labels: _labels(),
      );
      expect(
        _texts(doc).any((t) => RegExp(r'\d\d/\d\d/\d{4}').hasMatch(t)),
        isFalse,
      );
    });

    test('the adapter takes the DISPATCH created_at (order creation, not print '
        'time) and converts it to local time', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#ABC123',
        orderType: 'takeaway',
        createdAt: '2026-08-25T11:07:00+00:00',
        items: [KitchenDispatchItem(qty: 1, name: 'X')],
      );
      final t = kdsTicketViewFromKitchenDispatch(doc);
      expect(t.submittedAt, DateTime.parse('2026-08-25T11:07:00Z').toLocal());
      expect(t.submittedAt!.isUtc, isFalse);
    });

    test('a dispatch without created_at yields no timestamp', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#ABC123',
        orderType: 'takeaway',
        items: [KitchenDispatchItem(qty: 1, name: 'X')],
      );
      expect(kdsTicketViewFromKitchenDispatch(doc).submittedAt, isNull);
    });
  });

  group('A. ordering — the adapter preserves the authoritative sequence', () {
    test(
      'modifier sub-lines keep the exact dispatch order (non-alphabetical)',
      () {
        final doc = KitchenDispatchDocument(
          serverPayloadVersion: 1,
          kind: KitchenSpoolDispatchType.initialOrder,
          orderCode: '#ABC123',
          orderType: 'takeaway',
          items: [
            KitchenDispatchItem(
              qty: 2,
              name: 'Classic Burger',
              modifiers: [
                KitchenDispatchModifier(qty: 1, name: '240g'),
                KitchenDispatchModifier(qty: 1, name: 'cheese'),
                KitchenDispatchModifier(qty: 1, name: 'lettuce'),
                KitchenDispatchModifier(qty: 1, name: 'tomato'),
                KitchenDispatchModifier(qty: 1, name: 'onion'),
              ],
            ),
          ],
        );
        final t = kdsTicketViewFromKitchenDispatch(doc);
        expect(t.items.single.modifiers, [
          '240g',
          'cheese',
          'lettuce',
          'tomato',
          'onion',
        ]);
        final texts = _texts(
          buildKdsTicketPrintDocument(ticket: t, labels: _labels()),
        );
        final subs = texts.where((x) => x.startsWith('+ ')).toList();
        expect(subs, [
          '+ 240g',
          '+ cheese',
          '+ lettuce',
          '+ tomato',
          '+ onion',
        ]);
      },
    );
  });
}
