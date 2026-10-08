import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:test/test.dart';

/// ORDER-EDIT-001C (D-044, design §7.3, O-5) — the printer-only CHANGE SLIP on
/// the ONE shared kitchen print layer.
///
/// A sent-order edit on a printer-only branch prints ONE money-free slip: the
/// header, REMOVED / CHANGE / ADD, the full ORDER NOW list and the footer
/// "Replaces earlier tickets for #code". This suite pins:
///  * A — the typed [KitchenTicketDocumentKind.orderChange] can never be
///    derived from a ticket, and the ticket builder refuses it;
///  * B — the header lines and their order (never a phone);
///  * C — how each edit op lands in REMOVED / CHANGE / ADD;
///  * D — ORDER NOW in input order and the exact footer;
///  * E — money-free and REMAKE-free;
///  * F — the reason line;
///  * G — the ESC/POS style snapshot (the golden-equivalent: this package has
///    no image goldens);
///  * the bytes path (text fallback, throwing rasterizer, label pagination).

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
  changeNumberLabel: (n) => 'Change $n',
);

KitchenChangeSlipLabels _changeLabels() => KitchenChangeSlipLabels(
  orderChanged: 'ORDER CHANGED',
  changeNumber: (n) => 'Change $n',
  removedSection: 'REMOVED',
  changeSection: 'CHANGE',
  addSection: 'ADD',
  orderNowSection: 'ORDER NOW',
  wasLabel: 'Was',
  nowLabel: 'Now',
  staffLabel: 'Staff',
  reasonLabel: 'Reason',
  replacesFooter: (code) => 'Replaces earlier tickets for $code',
  reasonCustomerChangedMind: 'Customer changed mind',
  reasonEntryMistake: 'Order entry mistake',
  reasonItemUnavailable: 'Item unavailable',
  reasonKitchenIssue: 'Kitchen issue',
  reasonOther: 'Other',
);

const _burgerWas = KdsItemView(
  name: 'Burger',
  quantity: 1,
  modifiers: ['tomato', 'cucumber'],
);
const _burgerNow = KdsItemView(
  name: 'Burger',
  quantity: 1,
  modifiers: ['cucumber'],
);
const _fries = KdsItemView(name: 'Fries', quantity: 1, note: 'no salt');
const _cola3 = KdsItemView(name: 'Cola', quantity: 3);
const _lemonade1 = KdsItemView(name: 'Lemonade', quantity: 1);
const _water = KdsItemView(name: 'Water', quantity: 1);

/// The canonical fixture: the real server scenario (modify, remove, reduce,
/// increase, add) on a dine-in order, in REQUEST order.
OrderChangeSlipView _slip({
  String? orderType = 'dine_in',
  String? tableLabel = 'T7',
  String? customerName = 'Noa',
  String? orderNote = 'Allergy: nuts',
  DateTime? editedAt,
  String? reasonCode = 'customer_changed_mind',
  String? reasonText,
  String? staffFirstName = 'Ahmad',
  List<OrderChangeSlipEntry>? changes,
  List<KdsItemView>? orderNow,
}) => OrderChangeSlipView(
  orderCode: '#A1B2C3',
  editNumber: 2,
  orderType: orderType,
  tableLabel: tableLabel,
  customerName: customerName,
  orderNote: orderNote,
  editedAt: editedAt ?? DateTime(2026, 10, 8, 12, 41),
  reasonCode: reasonCode,
  reasonText: reasonText,
  staffFirstName: staffFirstName,
  changes:
      changes ??
      const [
        OrderChangeModified(was: _burgerWas, now: [_burgerNow]),
        OrderChangeRemoved(_fries),
        OrderChangeQuantity(was: _cola3, nowQuantity: 1),
        OrderChangeQuantity(was: _lemonade1, nowQuantity: 3),
        OrderChangeAdded([_water]),
      ],
  orderNow:
      orderNow ??
      const [
        _burgerNow,
        KdsItemView(name: 'Cola', quantity: 1),
        KdsItemView(name: 'Lemonade', quantity: 1),
        KdsItemView(name: 'Lemonade', quantity: 2),
        _water,
      ],
);

PrintDocument _build(
  OrderChangeSlipView slip, {
  String? restaurantName = 'Burger Maps',
}) => buildOrderChangeSlipPrintDocument(
  slip: slip,
  labels: _labels(),
  changeLabels: _changeLabels(),
  restaurantName: restaurantName,
);

List<String> _texts(PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

/// The lines of the section headed [heading]: from its title up to (not
/// including) the next rule.
List<PrintLine> _section(PrintDocument doc, String heading) {
  final start = doc.lines.indexWhere(
    (l) => l.kind == PrintLineKind.title && l.left == heading,
  );
  if (start < 0) return const [];
  final out = <PrintLine>[];
  for (var i = start + 1; i < doc.lines.length; i++) {
    final line = doc.lines[i];
    if (line.kind == PrintLineKind.rule) break;
    out.add(line);
  }
  return out;
}

List<(PrintLineKind, String)> _shape(List<PrintLine> lines) => [
  for (final l in lines) (l.kind, l.left ?? ''),
];

KdsTicketView _ticket({int? roundNumber, int? openedByEditNumber}) =>
    KdsTicketView(
      kitchenTicketId: 'kt-1',
      stationId: KdsTicketMapper.unassignedStation,
      items: const [KdsItemView(name: 'Burger', quantity: 1)],
      status: KitchenTicketStatus.newTicket,
      orderNumber: '#A1B2C3',
      orderType: 'dine_in',
      roundId: roundNumber == null ? null : 'r-$roundNumber',
      roundNumber: roundNumber,
      openedByEditNumber: openedByEditNumber,
    );

String _pad(String text) => text.padRight(48);

final _rule = '-' * 48;
final _band = '*' * 48;

void main() {
  group('A. the typed document kind', () {
    test('A1 the kind enum is exactly initialOrder, orderAddition, '
        'orderChange', () {
      expect(KitchenTicketDocumentKind.values, [
        KitchenTicketDocumentKind.initialOrder,
        KitchenTicketDocumentKind.orderAddition,
        KitchenTicketDocumentKind.orderChange,
      ]);
    });

    test('A2 forTicket never returns orderChange, whatever the round or the '
        'edit that opened it', () {
      for (final round in [null, 2, 3, 17]) {
        for (final opened in [null, 1, 4]) {
          expect(
            KitchenTicketDocumentKind.forTicket(
              _ticket(roundNumber: round, openedByEditNumber: opened),
            ),
            isNot(KitchenTicketDocumentKind.orderChange),
            reason: 'round $round opened by $opened',
          );
        }
      }
    });

    test('A3 the ticket builder REFUSES orderChange (a change slip printed '
        'as a ticket would make the kitchen cook the whole order again)', () {
      for (final round in [null, 2]) {
        expect(
          () => buildKdsTicketPrintDocument(
            ticket: _ticket(roundNumber: round),
            labels: _labels(),
            kind: KitchenTicketDocumentKind.orderChange,
          ),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'kind')
                .having(
                  (e) => e.message.toString(),
                  'message',
                  contains('buildOrderChangeSlipPrintDocument'),
                ),
          ),
        );
      }
    });
  });

  group('B. the header', () {
    test('B1 band, brand, ORDER CHANGED · Change N, the ORIGINAL code, badge, '
        'then type, table, customer, the EDIT time, staff and reason', () {
      final doc = _build(_slip());
      expect(doc.title, 'ORDER CHANGED #A1B2C3');
      expect(_shape(doc.lines.take(13).toList()), [
        (PrintLineKind.banner, ''),
        (PrintLineKind.subtitle, 'Burger Maps'),
        (PrintLineKind.title, '*** ORDER CHANGED · Change 2 ***'),
        (PrintLineKind.title, '#A1B2C3'),
        (PrintLineKind.title, '=== Dine-in ==='),
        (PrintLineKind.rule, ''),
        (PrintLineKind.center, 'Dine-in'),
        (PrintLineKind.center, 'Table T7'),
        (PrintLineKind.center, 'Customer: Noa'),
        (PrintLineKind.center, '08/10/2026 12:41'),
        (PrintLineKind.center, 'Staff: Ahmad'),
        (PrintLineKind.note, '» Reason: Customer changed mind'),
        (PrintLineKind.rule, ''),
      ]);
      // A dine-in slip also CLOSES with the band.
      expect(doc.lines.last.kind, PrintLineKind.banner);
    });

    test('B2 the time line is the EDIT instant, shown in local time', () {
      final editedAt = DateTime.utc(2026, 10, 8, 9, 5);
      final doc = _build(_slip(editedAt: editedAt));
      expect(_texts(doc), contains(formatKitchenTicketTimestamp(editedAt)));
      final noTime = _build(
        OrderChangeSlipView(
          orderCode: '#A1B2C3',
          editNumber: 1,
          orderType: 'takeaway',
          changes: const [
            OrderChangeAdded([_water]),
          ],
        ),
      );
      expect(
        _texts(noTime).where((t) => RegExp(r'\d\d/\d\d/\d{4}').hasMatch(t)),
        isEmpty,
        reason: 'no edit time => no time line (never the print time)',
      );
    });

    test(
      'B3 a takeaway slip prints its badge and type, no band and no table',
      () {
        final doc = _build(_slip(orderType: 'takeaway', tableLabel: null));
        final texts = _texts(doc);
        expect(doc.lines.where((l) => l.kind == PrintLineKind.banner), isEmpty);
        expect(texts, contains('>>> Takeaway >>>'));
        expect(texts, contains('Takeaway'));
        expect(texts.where((t) => t.startsWith('Table')), isEmpty);
        expect(doc.lines.first.kind, PrintLineKind.subtitle);
      },
    );

    test('B4 absent or blank staff and reason print no line', () {
      for (final staff in [null, '', '   ']) {
        final doc = _build(
          _slip(staffFirstName: staff, reasonCode: null, reasonText: '  '),
        );
        final texts = _texts(doc);
        expect(texts.where((t) => t.startsWith('Staff')), isEmpty);
        expect(texts.where((t) => t.contains('Reason')), isEmpty);
      }
    });

    test('B5 the brand falls back to the localized word; there is never a '
        'phone line (the view has no phone)', () {
      final doc = _build(_slip(), restaurantName: '  ');
      expect(doc.lines[1].kind, PrintLineKind.subtitle);
      expect(doc.lines[1].left, 'Restaurant');
      expect(_texts(doc).where((t) => t.contains('Phone')), isEmpty);
    });
  });

  group('C. section mapping', () {
    test('C1 REMOVED prints the removed line as its full item block', () {
      expect(_shape(_section(_build(_slip()), 'REMOVED')), [
        (PrintLineKind.item, '1 × Fries'),
        (PrintLineKind.note, '» Note: no salt'),
      ]);
    });

    test('C2 CHANGE: a modify prints Was (lighter) then every Now line '
        '(bold); a reduction is Was / Now of the same line', () {
      expect(_shape(_section(_build(_slip()), 'CHANGE')), [
        (PrintLineKind.sub, 'Was: 1 × Burger'),
        (PrintLineKind.sub, '+ tomato'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.item, 'Now: 1 × Burger'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.spacer, ''),
        (PrintLineKind.sub, 'Was: 3 × Cola'),
        (PrintLineKind.item, 'Now: 1 × Cola'),
      ]);
    });

    test('C3 ADD: an increase prints "+N × name" with the line\'s modifiers '
        'and note; an added line prints its item block', () {
      final doc = _build(
        _slip(
          changes: const [
            OrderChangeQuantity(
              was: KdsItemView(
                name: 'Burger',
                quantity: 1,
                modifiers: ['cheese ×2'],
                note: 'well done',
              ),
              nowQuantity: 3,
            ),
            OrderChangeAdded([_water]),
          ],
        ),
      );
      expect(_shape(_section(doc, 'ADD')), [
        (PrintLineKind.item, '+2 × Burger'),
        (PrintLineKind.sub, '+ cheese ×2'),
        (PrintLineKind.note, '» Note: well done'),
        (PrintLineKind.spacer, ''),
        (PrintLineKind.item, '1 × Water'),
      ]);
    });

    test('C4 a modify with a continuation AND a replacement prints every now '
        'line', () {
      final doc = _build(
        _slip(
          changes: const [
            OrderChangeModified(
              was: KdsItemView(
                name: 'Burger',
                quantity: 2,
                modifiers: ['cucumber'],
              ),
              now: [
                KdsItemView(
                  name: 'Burger',
                  quantity: 1,
                  modifiers: ['cucumber'],
                ),
                KdsItemView(
                  name: 'Burger',
                  quantity: 1,
                  modifiers: ['cucumber', 'cheese'],
                  note: 'extra crispy',
                ),
              ],
            ),
          ],
        ),
      );
      expect(_shape(_section(doc, 'CHANGE')), [
        (PrintLineKind.sub, 'Was: 2 × Burger'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.item, 'Now: 1 × Burger'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.item, 'Now: 1 × Burger'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.sub, '+ cheese'),
        (PrintLineKind.note, '» Note: extra crispy'),
      ]);
    });

    test('C5 a note-only modify still shows the OLD note on the Was side', () {
      final doc = _build(
        _slip(
          changes: const [
            OrderChangeModified(
              was: KdsItemView(name: 'Steak', quantity: 1, note: 'rare'),
              now: [KdsItemView(name: 'Steak', quantity: 1, note: 'medium')],
            ),
          ],
        ),
      );
      expect(_shape(_section(doc, 'CHANGE')), [
        (PrintLineKind.sub, 'Was: 1 × Steak'),
        (PrintLineKind.sub, '» Note: rare'),
        (PrintLineKind.item, 'Now: 1 × Steak'),
        (PrintLineKind.note, '» Note: medium'),
      ]);
    });

    test(
      'C6 entries keep REQUEST order inside each section (never sorted)',
      () {
        final doc = _build(
          _slip(
            changes: const [
              OrderChangeRemoved(KdsItemView(name: 'Zucchini', quantity: 1)),
              OrderChangeAdded([KdsItemView(name: 'Yogurt', quantity: 1)]),
              OrderChangeRemoved(KdsItemView(name: 'Apple pie', quantity: 2)),
              OrderChangeAdded([
                KdsItemView(name: 'Bread', quantity: 1),
                KdsItemView(name: 'Avocado', quantity: 1),
              ]),
            ],
          ),
        );
        List<String> items(String heading) => [
          for (final l in _section(doc, heading))
            if (l.kind == PrintLineKind.item) l.left!,
        ];
        expect(items('REMOVED'), ['1 × Zucchini', '2 × Apple pie']);
        expect(items('ADD'), ['1 × Yogurt', '1 × Bread', '1 × Avocado']);
      },
    );

    test('C7 empty sections print no header: an add-only slip has no REMOVED '
        'and no CHANGE', () {
      final doc = _build(
        _slip(
          changes: const [
            OrderChangeAdded([_water]),
          ],
        ),
      );
      final titles = [
        for (final l in doc.lines)
          if (l.kind == PrintLineKind.title) l.left,
      ];
      expect(titles, isNot(contains('REMOVED')));
      expect(titles, isNot(contains('CHANGE')));
      expect(titles, containsAllInOrder(['ADD', 'ORDER NOW']));
    });

    test('C8 a defensive EQUAL quantity lands under CHANGE and is never '
        'dropped', () {
      final doc = _build(
        _slip(
          changes: const [OrderChangeQuantity(was: _cola3, nowQuantity: 3)],
        ),
      );
      expect(_shape(_section(doc, 'CHANGE')), [
        (PrintLineKind.sub, 'Was: 3 × Cola'),
        (PrintLineKind.item, 'Now: 3 × Cola'),
      ]);
      expect(_section(doc, 'ADD'), isEmpty);
    });

    test('C9 the sections print in the fixed order REMOVED, CHANGE, ADD, '
        'ORDER NOW whatever the request order', () {
      final titles = [
        for (final l in _build(_slip()).lines)
          if (l.kind == PrintLineKind.title) l.left,
      ];
      expect(titles.sublist(3), ['REMOVED', 'CHANGE', 'ADD', 'ORDER NOW']);
    });

    test('C10 the quantity entry exposes an integer signed delta', () {
      const reduce = OrderChangeQuantity(was: _cola3, nowQuantity: 1);
      const increase = OrderChangeQuantity(was: _lemonade1, nowQuantity: 3);
      expect(reduce.delta, -2);
      expect(reduce.isIncrease, isFalse);
      expect(increase.delta, 2);
      expect(increase.isIncrease, isTrue);
    });
  });

  group('D. ORDER NOW and the footer', () {
    test('D1 every ORDER NOW line prints in INPUT order (no re-sort), split '
        'lines as given, then the order note', () {
      final doc = _build(
        _slip(
          orderNow: const [
            KdsItemView(name: 'Water', quantity: 1),
            KdsItemView(name: 'Burger', quantity: 1, modifiers: ['cucumber']),
            KdsItemView(name: 'Lemonade', quantity: 1),
            KdsItemView(name: 'Lemonade', quantity: 2, note: 'no ice'),
          ],
        ),
      );
      expect(_shape(_section(doc, 'ORDER NOW')), [
        (PrintLineKind.item, '1 × Water'),
        (PrintLineKind.spacer, ''),
        (PrintLineKind.item, '1 × Burger'),
        (PrintLineKind.sub, '+ cucumber'),
        (PrintLineKind.spacer, ''),
        (PrintLineKind.item, '1 × Lemonade'),
        (PrintLineKind.spacer, ''),
        (PrintLineKind.item, '2 × Lemonade'),
        (PrintLineKind.note, '» Note: no ice'),
      ]);
      final texts = _texts(doc);
      expect(
        texts.indexOf('» Note: Allergy: nuts'),
        greaterThan(texts.indexOf('2 × Lemonade')),
      );
    });

    test('D2 the footer is exactly "Replaces earlier tickets for #A1B2C3" '
        '(the code already carries its #) and closes the slip', () {
      final doc = _build(_slip());
      final footer = doc.lines.lastWhere((l) => l.kind == PrintLineKind.center);
      expect(footer.left, 'Replaces earlier tickets for #A1B2C3');
      expect(_texts(doc).where((t) => t.contains('##')), isEmpty);
      // Footer, then the closing dine-in band — nothing after.
      expect(doc.lines[doc.lines.length - 2], same(footer));
    });

    test('D3 an EMPTY orderNow omits ORDER NOW and the footer (a change chit) '
        'but keeps the changes and the order note', () {
      final doc = _build(_slip(orderNow: const []));
      final texts = _texts(doc);
      expect(texts, isNot(contains('ORDER NOW')));
      expect(texts.where((t) => t.startsWith('Replaces')), isEmpty);
      expect(texts, containsAllInOrder(['REMOVED', 'CHANGE', 'ADD']));
      expect(texts, contains('» Note: Allergy: nuts'));
    });
  });

  group('E. safety', () {
    test('E1 the slip is MONEY-FREE: no money token, every right column '
        'empty, no total style', () {
      final doc = _build(_slip(reasonText: 'Guest asked twice'));
      final blob = '${doc.title}\n${_texts(doc).join('\n')}'.toLowerCase();
      for (final token in _moneyTokens) {
        expect(blob, isNot(contains(token)), reason: 'money token: $token');
      }
      for (final l in doc.lines) {
        expect(l.right ?? '', isEmpty, reason: 'no money right column');
      }
      final escPos = kitchenTicketToEscPosDocument(doc);
      for (final l in escPos.lines.whereType<pp.PrintTextLine>()) {
        expect(l.style, isNot(pp.PrintLineStyle.total));
      }
    });

    test('E2 the paper never prints REMAKE, an "instead of" line or the '
        'kitchen counts', () {
      final blob = _texts(_build(_slip())).join('\n');
      expect(blob, isNot(contains('REMAKE')));
      expect(blob.toLowerCase(), isNot(contains('instead of')));
      expect(blob, isNot(contains('KTotal')));
    });

    test('E3 the builder is a PURE function of the view', () {
      expect(_shape(_build(_slip()).lines), _shape(_build(_slip()).lines));
    });
  });

  group('F. the reason line', () {
    String? reasonLine(String? code, [String? text]) {
      final doc = _build(_slip(reasonCode: code, reasonText: text));
      for (final t in _texts(doc)) {
        if (t.startsWith('» Reason: ')) return t.substring('» Reason: '.length);
      }
      return null;
    }

    test('F1 each known code prints its label', () {
      expect(reasonLine('customer_changed_mind'), 'Customer changed mind');
      expect(reasonLine('entry_mistake'), 'Order entry mistake');
      expect(reasonLine('item_unavailable'), 'Item unavailable');
      expect(reasonLine('kitchen_issue'), 'Kitchen issue');
      expect(reasonLine('other'), 'Other');
    });

    test('F2 a known code with a text prints "label · text"', () {
      expect(
        reasonLine('item_unavailable', '  No more fish  '),
        'Item unavailable · No more fish',
      );
    });

    test('F3 "other" with a text prints the text alone', () {
      expect(reasonLine('other', 'Guest asked twice'), 'Guest asked twice');
    });

    test('F4 an UNKNOWN code never prints its wire value', () {
      expect(reasonLine('customer_left_angry'), isNull);
      expect(reasonLine('customer_left_angry', 'Left'), 'Left');
      expect(reasonLine(null, 'Just text'), 'Just text');
      expect(reasonLine(null), isNull);
      final blob = _texts(
        _build(_slip(reasonCode: 'customer_left_angry')),
      ).join('\n');
      expect(blob, isNot(contains('customer_left_angry')));
    });

    test('F5 reasonCodeLabel maps the five wire codes and nothing else', () {
      final labels = _changeLabels();
      expect(labels.reasonCodeLabel('kitchen_issue'), 'Kitchen issue');
      for (final unknown in [null, '', 'Other', ' other', 'voided']) {
        expect(labels.reasonCodeLabel(unknown), isNull, reason: '$unknown');
      }
    });
  });

  group('G. ESC/POS conversion', () {
    test('G1 the canonical English slip, line by line, with its raster '
        'styles (the golden-equivalent snapshot)', () {
      final escPos = kitchenTicketToEscPosDocument(_build(_slip()));
      final texts = escPos.lines.whereType<pp.PrintTextLine>().toList();
      expect(
        [for (final l in texts) (l.text, l.style)],
        [
          (_band, pp.PrintLineStyle.normal),
          ('Burger Maps', pp.PrintLineStyle.subheading),
          ('*** ORDER CHANGED · Change 2 ***', pp.PrintLineStyle.headingLarge),
          ('#A1B2C3', pp.PrintLineStyle.headingLarge),
          ('=== Dine-in ===', pp.PrintLineStyle.headingLarge),
          (_rule, pp.PrintLineStyle.separator),
          ('Dine-in', pp.PrintLineStyle.centered),
          ('Table T7', pp.PrintLineStyle.centered),
          ('Customer: Noa', pp.PrintLineStyle.centered),
          ('08/10/2026 12:41', pp.PrintLineStyle.centered),
          ('Staff: Ahmad', pp.PrintLineStyle.centered),
          ('» Reason: Customer changed mind', pp.PrintLineStyle.kitchenNote),
          (_rule, pp.PrintLineStyle.separator),
          ('REMOVED', pp.PrintLineStyle.headingLarge),
          (_pad('1 × Fries'), pp.PrintLineStyle.kitchenItem),
          ('» Note: no salt', pp.PrintLineStyle.kitchenNote),
          (_rule, pp.PrintLineStyle.separator),
          ('CHANGE', pp.PrintLineStyle.headingLarge),
          ('  Was: 1 × Burger', pp.PrintLineStyle.kitchenModifier),
          ('  + tomato', pp.PrintLineStyle.kitchenModifier),
          ('  + cucumber', pp.PrintLineStyle.kitchenModifier),
          (_pad('Now: 1 × Burger'), pp.PrintLineStyle.kitchenItem),
          ('  + cucumber', pp.PrintLineStyle.kitchenModifier),
          ('', pp.PrintLineStyle.spacer),
          ('  Was: 3 × Cola', pp.PrintLineStyle.kitchenModifier),
          (_pad('Now: 1 × Cola'), pp.PrintLineStyle.kitchenItem),
          (_rule, pp.PrintLineStyle.separator),
          ('ADD', pp.PrintLineStyle.headingLarge),
          (_pad('+2 × Lemonade'), pp.PrintLineStyle.kitchenItem),
          ('', pp.PrintLineStyle.spacer),
          (_pad('1 × Water'), pp.PrintLineStyle.kitchenItem),
          (_rule, pp.PrintLineStyle.separator),
          ('ORDER NOW', pp.PrintLineStyle.headingLarge),
          (_pad('1 × Burger'), pp.PrintLineStyle.kitchenItem),
          ('  + cucumber', pp.PrintLineStyle.kitchenModifier),
          ('', pp.PrintLineStyle.spacer),
          (_pad('1 × Cola'), pp.PrintLineStyle.kitchenItem),
          ('', pp.PrintLineStyle.spacer),
          (_pad('1 × Lemonade'), pp.PrintLineStyle.kitchenItem),
          ('', pp.PrintLineStyle.spacer),
          (_pad('2 × Lemonade'), pp.PrintLineStyle.kitchenItem),
          ('', pp.PrintLineStyle.spacer),
          (_pad('1 × Water'), pp.PrintLineStyle.kitchenItem),
          (_rule, pp.PrintLineStyle.separator),
          ('» Note: Allergy: nuts', pp.PrintLineStyle.kitchenNote),
          (_rule, pp.PrintLineStyle.separator),
          ('Replaces earlier tickets for #A1B2C3', pp.PrintLineStyle.centered),
          (_band, pp.PrintLineStyle.normal),
        ],
      );
      expect(escPos.lines[escPos.lines.length - 2], isA<pp.PrintFeedLine>());
      expect(
        (escPos.lines[escPos.lines.length - 2] as pp.PrintFeedLine).lines,
        3,
      );
      expect(escPos.lines.last, isA<pp.PrintCutLine>());
    });

    test('G2 every slip needs raster (the "·" and "×" are non-ASCII), so an '
        'injected rasterizer always renders it', () {
      final ascii = _build(
        OrderChangeSlipView(orderCode: '#A1B2C3', editNumber: 1),
      );
      expect(
        pp.printDocumentNeedsRaster(kitchenTicketToEscPosDocument(ascii)),
        isTrue,
      );
      expect(
        pp.printDocumentNeedsRaster(
          kitchenTicketToEscPosDocument(_build(_slip())),
        ),
        isTrue,
      );
    });

    test('G3 the HTML preview renders the slip with escaped data', () {
      final html = documentToHtml(_build(_slip(customerName: '<b>Noa</b>')));
      expect(html, contains('ORDER CHANGED'));
      expect(html, contains('&lt;b&gt;Noa&lt;/b&gt;'));
      expect(html, isNot(contains('<b>Noa</b>')));
    });
  });

  group('bytes (renderOrderChangeSlipBytes)', () {
    Future<Uint8List> render({
      pp.ReceiptRasterizer? rasterizer,
      pp.MediaProfile? mediaProfile,
      pp.PageLineLabel? pageLabel,
      pp.PageLineLabel? continuationHeader,
    }) => renderOrderChangeSlipBytes(
      slip: _slip(),
      labels: _labels(),
      changeLabels: _changeLabels(),
      rasterizer: rasterizer,
      mediaProfile: mediaProfile,
      restaurantName: 'Burger Maps',
      pageLabel: pageLabel,
      continuationHeader: continuationHeader,
    );

    test('with no rasterizer the slip is ESC/POS TEXT: the ASCII chrome '
        'survives and non-ASCII degrades to "?"', () async {
      final bytes = await render();
      final expected = const pp.EscPosPrintAdapter().encode(
        kitchenTicketToEscPosDocument(_build(_slip())),
        pp.PrinterProfile.escPos80mm,
      );
      expect(bytes, expected);
      final text = utf8.decode(bytes, allowMalformed: true);
      expect(text, contains('*** ORDER CHANGED ? Change 2 ***'));
      expect(text, contains('Replaces earlier tickets for #A1B2C3'));
      expect(text, contains('1 ? Fries'));
      expect(text, contains('Was: 3 ? Cola'));
    });

    test('a THROWING rasterizer falls back to the text slip', () async {
      expect(await render(rasterizer: _ExplodingRasterizer()), await render());
    });

    test(
      'an injected rasterizer renders the slip as raster on the roll',
      () async {
        final fake = pp.FakeReceiptRasterizer();
        final bytes = await render(rasterizer: fake);
        expect(bytes, isNot(await render()));
        expect(fake.requests, hasLength(1));
        expect(
          fake.requests.single.lines,
          contains('*** ORDER CHANGED · Change 2 ***'),
        );
      },
    );

    test('a FIXED label paginates with the page label and continuation '
        'header, through the SAME encode tail as the ticket', () async {
      String pageLabel(int p, int t) => 'PAGE $p/$t';
      String cont(int p, int t) => 'CONT $p';
      final fake = pp.FakeReceiptRasterizer();
      final bytes = await render(
        rasterizer: fake,
        mediaProfile: pp.MediaProfile.label80x80,
        pageLabel: pageLabel,
        continuationHeader: cont,
      );
      final expectedFake = pp.FakeReceiptRasterizer();
      final expected = const pp.EscPosPrintAdapter().encode(
        await pp.rasterizeForMediaProfile(
          kitchenTicketToEscPosDocument(
            _build(_slip()),
            columns: pp.MediaProfile.label80x80.columns,
          ),
          rasterizer: expectedFake,
          profile: pp.MediaProfile.label80x80,
          pageLabel: pageLabel,
          continuationHeader: cont,
        ),
        pp.PrinterProfile.escPos80mm,
      );
      expect(bytes, expected);
      final pages = fake.requests.where(
        (r) => r.lines.any((l) => l.startsWith('PAGE ')),
      );
      expect(pages.length, greaterThan(1), reason: 'a long slip paginates');
      expect(
        fake.requests.any((r) => r.lines.any((l) => l.contains('CONT 2'))),
        isTrue,
      );
    });
  });
}

class _ExplodingRasterizer implements pp.ReceiptRasterizer {
  @override
  Future<pp.ReceiptRasterImage> rasterize(pp.ReceiptRasterRequest request) =>
      throw StateError('raster exploded');
}
