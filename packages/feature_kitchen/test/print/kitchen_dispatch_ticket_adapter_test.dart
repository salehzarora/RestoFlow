import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_local/kitchen_dispatch_document.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView, KdsTicketMapper, KdsTicketView;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

/// KIOSK-PRINT-114B.5A — the CANONICAL dispatch → ticket adapter.
///
/// A `KitchenDispatchDocument` (the server's money-free dispatch payload the
/// POS printer-only drain and the kiosk claimed print consume) is adapted into
/// the SAME `KdsTicketView` the POS direct print and the KDS render, so every
/// kitchen paper is the one canonical ticket: whole-order counts at the top
/// (per-unit prep × line quantity, modifier prep × modifier units × line
/// quantity — each factor applied EXACTLY once), then the items.
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

/// The OWNER FIXTURE: `qty × Classic Burger 240g` — the 240g size option
/// contributes 2 meat per modifier unit (meat_snapshot), the item itself needs
/// 1 bun per unit (prep_snapshot). Persisted PER UNIT, exactly as 114B.1 stores
/// it and as `kitchen_dispatch_payload_initial` forwards it.
KitchenDispatchDocument _classic({int qty = 2, int modifierQty = 1}) =>
    KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#ABC123',
      orderType: 'takeaway',
      customerDisplayName: 'Saleh',
      orderNote: 'no sauce on the side',
      createdAt: '2026-08-25T10:00:00Z',
      items: [
        KitchenDispatchItem(
          qty: qty,
          name: 'Classic Burger',
          note: 'well done',
          prep: [
            KitchenDispatchPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
          ],
          modifiers: [
            KitchenDispatchModifier(
              qty: modifierQty,
              name: '240g',
              prep: KitchenDispatchModifierPrep(quantity: 2, unit: 'meat'),
            ),
          ],
        ),
      ],
    );

KitchenCount? _count(KdsTicketView t, String label) =>
    t.kitchenCounts.where((c) => c.label == label).firstOrNull;

List<String> _texts(PrintDocument doc) => [
  for (final line in doc.lines) line.left ?? line.right ?? '',
];

void main() {
  group('A1/A2/A4 — the owner fixture aggregates per-unit prep × line qty', () {
    test('A1. 2 × Classic 240g => 4 meat / 2 bun', () {
      final t = kdsTicketViewFromKitchenDispatch(_classic(qty: 2));
      expect(_count(t, 'meat')?.quantity, 4);
      expect(_count(t, 'Bun pcs')?.quantity, 2);
    });

    test('A2. 1 × Classic 240g => 2 meat / 1 bun', () {
      final t = kdsTicketViewFromKitchenDispatch(_classic(qty: 1));
      expect(_count(t, 'meat')?.quantity, 2);
      expect(_count(t, 'Bun pcs')?.quantity, 1);
    });

    test(
      'A4. modifier units scale ONCE: 2 × (240g ×2) => 8 meat, still 2 bun',
      () {
        final t = kdsTicketViewFromKitchenDispatch(
          _classic(qty: 2, modifierQty: 2),
        );
        expect(_count(t, 'meat')?.quantity, 8);
        expect(_count(t, 'Bun pcs')?.quantity, 2);
      },
    );
  });

  test('A3. a mixed order sums lineQty × prepQty across items', () {
    final doc = KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#MIX001',
      orderType: 'dine_in',
      tableLabel: '7',
      items: [
        KitchenDispatchItem(
          qty: 2,
          name: 'Item A',
          prep: [
            KitchenDispatchPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
          ],
          modifiers: [
            KitchenDispatchModifier(
              qty: 1,
              name: 'Double',
              prep: KitchenDispatchModifierPrep(quantity: 2, unit: 'meat'),
            ),
          ],
        ),
        KitchenDispatchItem(
          qty: 1,
          name: 'Item B',
          prep: [
            KitchenDispatchPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
            KitchenDispatchPrepComponent(
              name: 'Wrap',
              quantity: 2,
              unit: 'pcs',
            ),
          ],
          modifiers: [
            KitchenDispatchModifier(
              qty: 1,
              name: 'Single',
              prep: KitchenDispatchModifierPrep(quantity: 1, unit: 'meat'),
            ),
          ],
        ),
      ],
    );
    final t = kdsTicketViewFromKitchenDispatch(doc);
    // meat: 2×1×2 + 1×1×1 = 5; bun: 1×2 + 1×1 = 3; wrap: 2×1 = 2
    expect(_count(t, 'meat')?.quantity, 5);
    expect(_count(t, 'Bun pcs')?.quantity, 3);
    expect(_count(t, 'Wrap pcs')?.quantity, 2);
    // Items keep the dispatch order + quantities + modifier strings + notes.
    expect(t.items.map((i) => i.name), ['Item A', 'Item B']);
    expect(t.items.map((i) => i.quantity), [2, 1]);
    expect(t.items.first.modifiers, ['Double']);
  });

  test('A4b. a classified modifier prep keeps its with/without split '
      'and is never double-multiplied', () {
    final doc = KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#CLS001',
      orderType: 'takeaway',
      items: [
        KitchenDispatchItem(
          qty: 3,
          name: 'Shawarma',
          prep: [
            KitchenDispatchPrepComponent(
              name: 'Laffa',
              quantity: 1,
              unit: 'pcs',
              classifierOptionId: 'opt-xl',
              classifierOptionName: 'XL',
              classifierSelected: true,
            ),
          ],
          modifiers: [
            KitchenDispatchModifier(
              qty: 2,
              name: 'Extra meat',
              prep: KitchenDispatchModifierPrep(
                quantity: 1,
                unit: 'meat',
                classifierOptionId: 'opt-xl',
                classifierOptionName: 'XL',
                classifierSelected: false,
              ),
            ),
          ],
        ),
      ],
    );
    final t = kdsTicketViewFromKitchenDispatch(doc);
    final laffa = _count(t, 'Laffa pcs');
    expect(laffa?.quantity, 3);
    expect(laffa?.classifier, 'XL');
    expect(laffa?.classifierSelected, isTrue);
    final meat = _count(t, 'meat');
    expect(meat?.quantity, 6); // 1 × 2 units × 3 items — exactly once
    expect(meat?.classifier, 'XL');
    expect(meat?.classifierSelected, isFalse);
  });

  test('A5. adapter counts EQUAL the canonical aggregator over the same '
      'neutral inputs the POS/KDS mappers build', () {
    final t = kdsTicketViewFromKitchenDispatch(_classic(qty: 2));
    final expected = aggregateOrderKitchenCounts([
      const KitchenCountItemInput(
        quantity: 2,
        meats: [KitchenMeat(quantity: 2, unit: 'meat')],
        prepComponents: [
          KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
        ],
        linePosition: 1,
      ),
    ]);
    expect(t.kitchenCounts, expected);
  });

  group('A6 — document/byte parity with the canonical POS ticket', () {
    KdsTicketView canonical() => KdsTicketView(
      kitchenTicketId: '#ABC123',
      stationId: KdsTicketMapper.unassignedStation,
      status: KitchenTicketStatus.newTicket,
      orderNumber: '#ABC123',
      orderType: 'takeaway',
      customerName: 'Saleh',
      notes: 'no sauce on the side',
      // 114B.6: the dispatch fixture's created_at, as the adapter carries it.
      submittedAt: DateTime.parse('2026-08-25T10:00:00Z').toLocal(),
      items: const [
        KdsItemView(
          name: 'Classic Burger',
          quantity: 2,
          modifiers: ['240g'],
          note: 'well done',
          prepComponents: [
            KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
          ],
          linePosition: 1,
        ),
      ],
      kitchenCounts: aggregateOrderKitchenCounts(const [
        KitchenCountItemInput(
          quantity: 2,
          meats: [KitchenMeat(quantity: 2, unit: 'meat')],
          prepComponents: [
            KitchenPrepComponent(name: 'Bun', quantity: 1, unit: 'pcs'),
          ],
          linePosition: 1,
        ),
      ]),
    );

    test(
      'the adapted view renders BYTE-IDENTICAL to the canonical view',
      () async {
        final adapted = await renderKitchenTicketBytes(
          ticket: kdsTicketViewFromKitchenDispatch(_classic(qty: 2)),
          labels: _labels(),
        );
        final direct = await renderKitchenTicketBytes(
          ticket: canonical(),
          labels: _labels(),
        );
        expect(adapted, direct);
      },
    );

    test('the count titles sit ABOVE the first item line', () {
      final doc = buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromKitchenDispatch(_classic(qty: 2)),
        labels: _labels(),
      );
      final texts = _texts(doc);
      final meat = texts.indexWhere((t) => t == 'Kitchen total: 4 meat');
      final bun = texts.indexWhere((t) => t == 'Kitchen total: 2 Bun pcs');
      final item = texts.indexWhere((t) => t.startsWith('2 × Classic Burger'));
      expect(meat, greaterThanOrEqualTo(0));
      expect(bun, greaterThanOrEqualTo(0));
      expect(item, greaterThan(meat));
      expect(item, greaterThan(bun));
      expect(texts, contains('+ 240g'));
      expect(texts, contains('» Note: well done'));
    });
  });

  test('A7. the canonical dispatch ticket is MONEY-FREE', () async {
    final bytes = await renderKitchenTicketBytes(
      ticket: kdsTicketViewFromKitchenDispatch(_classic(qty: 2)),
      labels: _labels(),
    );
    final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    for (final token in [
      'subtotal',
      'grand total',
      'tax',
      'discount',
      '₪',
      r'$',
      '€',
    ]) {
      expect(text.contains(token), isFalse, reason: 'no "$token"');
    }
    expect(RegExp(r'\d+\.\d{2}').hasMatch(text), isFalse, reason: 'no amounts');
    expect(text, contains('classic burger'));
  });

  test('A8. numbers print through the canonical formatter (2, never 2.0)', () {
    final doc = KitchenDispatchDocument(
      serverPayloadVersion: 1,
      kind: KitchenSpoolDispatchType.initialOrder,
      orderCode: '#FMT001',
      orderType: 'takeaway',
      items: [
        KitchenDispatchItem(
          qty: 1,
          name: 'Half portion',
          prep: [
            KitchenDispatchPrepComponent(
              name: 'Rice',
              quantity: 2.0,
              unit: 'cup',
            ),
            KitchenDispatchPrepComponent(
              name: 'Sauce',
              quantity: 0.5,
              unit: 'cup',
            ),
          ],
        ),
      ],
    );
    final texts = _texts(
      buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromKitchenDispatch(doc),
        labels: _labels(),
      ),
    );
    expect(texts, contains('Kitchen total: 2 Rice cup'));
    expect(texts, contains('Kitchen total: 0.5 Sauce cup'));
    expect(texts.any((t) => t.contains('2.0 ')), isFalse);
  });

  group('metadata + degradation', () {
    test('order metadata, phone override, round and note carry over', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.serviceRound,
        orderCode: '#RND002',
        orderType: 'dine_in',
        tableLabel: '12',
        customerDisplayName: 'Dana',
        orderNote: 'birthday',
        roundId: 'round-2',
        roundNumber: 2,
        items: [KitchenDispatchItem(qty: 1, name: 'Extra bread')],
      );
      final t = kdsTicketViewFromKitchenDispatch(
        doc,
        customerPhoneOverride: '+972500000000',
      );
      expect(t.orderNumber, '#RND002');
      expect(t.kitchenTicketId, '#RND002');
      expect(t.orderType, 'dine_in');
      expect(t.tableLabel, '12');
      expect(t.customerName, 'Dana');
      expect(t.customerPhone, '+972500000000');
      expect(t.notes, 'birthday');
      expect(t.roundId, 'round-2');
      expect(t.roundNumber, 2);
      expect(t.stationId, KdsTicketMapper.unassignedStation);
      expect(t.kitchenCounts, isEmpty);
    });

    test('a historical dispatch with NO prep degrades to no count block '
        '(never re-derived, never crashes)', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#OLD001',
        orderType: 'takeaway',
        items: [
          KitchenDispatchItem(
            qty: 2,
            name: 'Legacy Burger',
            modifiers: [KitchenDispatchModifier(qty: 1, name: '240g')],
          ),
        ],
      );
      final t = kdsTicketViewFromKitchenDispatch(doc);
      expect(t.kitchenCounts, isEmpty);
      final texts = _texts(
        buildKdsTicketPrintDocument(ticket: t, labels: _labels()),
      );
      expect(texts.any((x) => x.startsWith('Kitchen total')), isFalse);
      expect(texts, contains('2 × Legacy Burger'));
    });

    test('unit-less or non-positive contributions are dropped exactly like '
        'the KDS mapper drops them', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#DRP001',
        orderType: 'takeaway',
        items: [
          KitchenDispatchItem(
            qty: 2,
            name: 'Odd',
            prep: [
              KitchenDispatchPrepComponent(name: '', quantity: 1, unit: 'x'),
              KitchenDispatchPrepComponent(name: 'Zero', quantity: 0),
            ],
            modifiers: [
              KitchenDispatchModifier(
                qty: 1,
                name: 'Nothing',
                prep: KitchenDispatchModifierPrep(quantity: 0, unit: 'meat'),
              ),
            ],
          ),
        ],
      );
      expect(kdsTicketViewFromKitchenDispatch(doc).kitchenCounts, isEmpty);
    });
  });

  group('CanonicalKitchenDispatchRenderer', () {
    test('a normal dispatch renders the canonical bytes', () async {
      final renderer = CanonicalKitchenDispatchRenderer(
        labels: _labels(),
        restaurantName: 'Burger Maps',
      );
      final bytes = await renderer.renderToBytes(_classic(qty: 2));
      final expected = await renderKitchenTicketBytes(
        ticket: kdsTicketViewFromKitchenDispatch(_classic(qty: 2)),
        labels: _labels(),
        restaurantName: 'Burger Maps',
      );
      expect(bytes, expected);
      final text = utf8.decode(bytes, allowMalformed: true);
      expect(text, contains('Kitchen total: 4 meat'));
      expect(text, contains('Kitchen total: 2 Bun pcs'));
      expect(text, contains('Burger Maps'));
    });

    test('a VOID dispatch keeps the legacy frame byte-for-byte', () async {
      final voidDoc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.voidNotice,
        orderCode: '#ABC123',
        orderType: 'dine_in',
        reason: 'entry_error',
        voidMarker: true,
        affectedItemCount: 3,
      );
      final renderer = CanonicalKitchenDispatchRenderer(labels: _labels());
      final bytes = await renderer.renderToBytes(voidDoc);
      final legacy = await const KitchenTicketRenderer().renderToBytes(voidDoc);
      expect(bytes, legacy);
      expect(utf8.decode(bytes, allowMalformed: true), contains('VOID'));
    });

    test('implements the data_local seam the drain/kiosk inject', () {
      expect(
        CanonicalKitchenDispatchRenderer(labels: _labels()),
        isA<KitchenDispatchBytesRenderer>(),
      );
      expect(
        const KitchenTicketRenderer(),
        isA<KitchenDispatchBytesRenderer>(),
      );
    });
  });

  test('pp import is only for the render-neutral document type', () {
    expect(pp.PrinterProfile.escPos80mm, isNotNull);
  });
}
