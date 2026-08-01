@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        KitchenCount,
        KitchenPrepComponent,
        OrderType,
        kitchenCountDisplayLabel;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show KitchenTicketPrintLabels, PrintLineKind, buildKdsTicketPrintDocument;
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier, classifiedPrepForLine;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// KITCHEN-PREP-RESOURCE-MODIFIER-SPLIT-016 — the POS side of the split.
///
/// Saleh's configuration throughout: a 240g burger whose per-unit preparation
/// resources are 1 Bread + 2 Meat pieces, with the "Cheese" option configured to
/// CLASSIFY the Meat pieces. Three burgers — two with cheese, one without — must
/// print 3 Bread, 4 Meat pieces with Cheese, 2 Meat pieces without Cheese, on
/// EVERY kitchen surface: the initial direct print, an Add-items round ticket,
/// the manual reprint and the wire payload the KDS reads.
void main() {
  const cheeseId = 'opt-cheese';
  const onionId = 'opt-onion';

  /// The MENU configuration for the 240g burger (what the Dashboard persisted).
  const configuredPrep = <KitchenPrepComponent>[
    KitchenPrepComponent(name: 'Bread', quantity: 1),
    KitchenPrepComponent(
      name: 'Meat pieces',
      quantity: 2,
      classifierOptionId: cheeseId,
      classifierOptionName: 'Cheese',
    ),
  ];

  SelectedModifier cheese({int quantity = 1}) => SelectedModifier(
    optionId: cheeseId,
    groupName: 'Extras',
    optionName: 'Cheese',
    priceDeltaMinor: 300,
    quantity: quantity,
  );

  const onion = SelectedModifier(
    optionId: onionId,
    groupName: 'Toppings',
    optionName: 'Onion',
    priceDeltaMinor: 0,
  );

  CartLineView burgerLine({
    required String lineId,
    required int quantity,
    List<SelectedModifier> modifiers = const <SelectedModifier>[],
  }) => CartLineView(
    lineId: lineId,
    menuItemId: 'burger-240',
    name: 'Burger 240g',
    quantity: quantity,
    unitPriceMinor: 4500,
    lineTotalMinor: 4500 * quantity,
    currencyCode: 'ILS',
    modifiers: modifiers,
  );

  const prepByItemId = <String, List<KitchenPrepComponent>>{
    'burger-240': configuredPrep,
  };

  /// The count rows as `(quantity, label, classifier, selected)`.
  List<(num, String, String, bool)> rows(List<KitchenCount> counts) => [
    for (final c in counts)
      (c.quantity, c.label, c.classifier, c.classifierSelected),
  ];

  KitchenTicketPrintLabels labels() => KitchenTicketPrintLabels(
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
    // The Arabic wording an ar ticket carries, supplied by the caller's l10n —
    // never hardcoded inside shared logic.
    prepWithOption: (resource, option) => '$resource مع $option',
    prepWithoutOption: (resource, option) => '$resource بدون $option',
  );

  /// The kitchen-count lines as they are PRINTED.
  List<String> printedCountLines(KdsTicketView ticket) {
    final doc = buildKdsTicketPrintDocument(ticket: ticket, labels: labels());
    return [
      for (final line in doc.lines)
        if (line.kind == PrintLineKind.title &&
            (line.left ?? '').startsWith('KTotal '))
          line.left!,
    ];
  }

  group('A. the exact 3-burger example, on the initial kitchen ticket', () {
    test('3 Bread, 4 Meat with Cheese, 2 Meat without Cheese', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [cheese()]),
          burgerLine(lineId: 'l2', quantity: 1),
        ],
      );

      expect(rows(ticket.kitchenCounts), [
        (3, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('and prints them with the localized with/without wording', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [cheese()]),
          burgerLine(lineId: 'l2', quantity: 1),
        ],
      );

      expect(printedCountLines(ticket), [
        'KTotal 3 Bread',
        'KTotal 4 Meat pieces مع Cheese',
        'KTotal 2 Meat pieces بدون Cheese',
      ]);
    });

    test('no duplicate unsplit Meat row, and no Cheese count of its own', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [cheese()]),
          burgerLine(lineId: 'l2', quantity: 1),
        ],
      );
      // Exactly three rows: no bare "Meat pieces" total beside the split, and
      // no separate "Cheese" line (its preparation-count toggle is off).
      expect(ticket.kitchenCounts.length, 3);
      expect(
        ticket.kitchenCounts.where(
          (c) => c.label == 'Meat pieces' && !c.isClassified,
        ),
        isEmpty,
      );
      expect(
        ticket.kitchenCounts.map((c) => c.label),
        isNot(contains('Cheese')),
      );
    });
  });

  group('B/C. all-selected and none-selected', () {
    test('all three with cheese -> only the with bucket', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#1',
        orderType: OrderType.takeaway,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 3, modifiers: [cheese()]),
        ],
      );
      expect(rows(ticket.kitchenCounts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', 'Cheese', true),
      ]);
      expect(printedCountLines(ticket), [
        'KTotal 3 Bread',
        'KTotal 6 Meat pieces مع Cheese',
      ]);
    });

    test('none with cheese -> only the without bucket', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#2',
        orderType: OrderType.takeaway,
        prepByItemId: prepByItemId,
        lines: [burgerLine(lineId: 'l1', quantity: 3)],
      );
      expect(rows(ticket.kitchenCounts), [
        (3, 'Bread', '', false),
        (6, 'Meat pieces', 'Cheese', false),
      ]);
    });
  });

  group('D. an unconfigured product keeps the old unsplit line', () {
    test('no classifier -> one "Meat pieces" total of 6', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#3',
        orderType: OrderType.takeaway,
        prepByItemId: const {
          'burger-240': [
            KitchenPrepComponent(name: 'Meat pieces', quantity: 2),
          ],
        },
        lines: [
          burgerLine(lineId: 'l1', quantity: 3, modifiers: [cheese()]),
        ],
      );
      expect(rows(ticket.kitchenCounts), [(6, 'Meat pieces', '', false)]);
      expect(printedCountLines(ticket), ['KTotal 6 Meat pieces']);
    });
  });

  group('F/G. modifier quantity and unrelated options', () {
    test('Cheese x4 classifies the two pieces once — never eight', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#4',
        orderType: OrderType.takeaway,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(
            lineId: 'l1',
            quantity: 1,
            modifiers: [cheese(quantity: 4)],
          ),
        ],
      );
      expect(rows(ticket.kitchenCounts), [
        (1, 'Bread', '', false),
        (2, 'Meat pieces', 'Cheese', true),
      ]);
    });

    test('onion alone leaves the burger in the without bucket', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#5',
        orderType: OrderType.takeaway,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [onion]),
        ],
      );
      expect(rows(ticket.kitchenCounts), [
        (2, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('onion + cheese together still classify once', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#6',
        orderType: OrderType.takeaway,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [onion, cheese()]),
        ],
      );
      expect(rows(ticket.kitchenCounts), [
        (2, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
      ]);
    });
  });

  group('I. an Add-items round ticket classifies its own new items', () {
    test('a round of one cheese burger reports 2 Meat with Cheese', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        roundId: 'round-2',
        roundNumber: 2,
        lines: [
          burgerLine(lineId: 'a1', quantity: 1, modifiers: [cheese()]),
        ],
      );
      expect(ticket.roundNumber, 2, reason: 'still an addition ticket');
      expect(rows(ticket.kitchenCounts), [
        (1, 'Bread', '', false),
        (2, 'Meat pieces', 'Cheese', true),
      ]);
    });

    test('the addition payload carries the resolved snapshot to the KDS', () {
      // The exact shape addition_controller serializes for the wire.
      final json = OrderSubmissionItem(
        menuItemId: 'burger-240',
        nameSnapshot: 'Burger 240g',
        quantity: 1,
        unitPriceMinorSnapshot: 4500,
        lineTotalMinor: 4500,
        prepComponents: classifiedPrepForLine(configuredPrep, [cheese()]),
      ).toJson();

      expect(json['prep_snapshot'], [
        {'name': 'Bread', 'quantity': 1, 'unit': ''},
        {
          'name': 'Meat pieces',
          'quantity': 2,
          'unit': '',
          'classifier_option_id': cheeseId,
          'classifier_option_name': 'Cheese',
          'classifier_selected': true,
        },
      ]);
      // Still money-free (D-007).
      for (final row in (json['prep_snapshot'] as List).cast<Map>()) {
        expect(row.keys.any((k) => '$k'.contains('minor')), isFalse);
      }
    });

    test('an unclassified item still serializes the pre-feature shape', () {
      final json = OrderSubmissionItem(
        menuItemId: 'fries',
        nameSnapshot: 'Fries',
        quantity: 1,
        unitPriceMinorSnapshot: 1200,
        lineTotalMinor: 1200,
        prepComponents: classifiedPrepForLine(const [
          KitchenPrepComponent(name: 'Potato', quantity: 1, unit: 'g'),
        ], const <SelectedModifier>[]),
      ).toJson();

      expect(json['prep_snapshot'], [
        {'name': 'Potato', 'quantity': 1, 'unit': 'g'},
      ]);
    });
  });

  group('J. reprint and preview agree with the automatic ticket', () {
    SubmittedOrderView submitted() => SubmittedOrderView(
      orderNumber: '#000042',
      orderType: OrderType.dineIn,
      currencyCode: 'ILS',
      subtotalMinor: 13500,
      lines: [
        SubmittedLineView(
          name: 'Burger 240g',
          quantity: 2,
          lineTotalMinor: 9000,
          currencyCode: 'ILS',
          modifiers: const ['Cheese'],
          // What cart_controller stored at submit: the RESOLVED snapshot.
          prepComponents: classifiedPrepForLine(configuredPrep, [cheese()]),
        ),
        SubmittedLineView(
          name: 'Burger 240g',
          quantity: 1,
          lineTotalMinor: 4500,
          currencyCode: 'ILS',
          prepComponents: classifiedPrepForLine(
            configuredPrep,
            const <SelectedModifier>[],
          ),
        ),
      ],
    );

    test('the manual reprint reproduces the same split', () {
      expect(rows(kdsTicketViewFromSubmittedOrder(submitted()).kitchenCounts), [
        (3, 'Bread', '', false),
        (4, 'Meat pieces', 'Cheese', true),
        (2, 'Meat pieces', 'Cheese', false),
      ]);
    });

    test('reprint and automatic ticket print byte-identical count lines', () {
      final automatic = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [cheese()]),
          burgerLine(lineId: 'l2', quantity: 1),
        ],
      );
      final reprint = kdsTicketViewFromSubmittedOrder(submitted());

      expect(printedCountLines(reprint), printedCountLines(automatic));
      expect(reprint.kitchenCounts, automatic.kitchenCounts);
    });

    test('the preview document and the printed document are the same', () {
      // Preview and print build the SAME document from the SAME view, so a
      // split shown on screen is exactly what the paper carries.
      final ticket = kdsTicketViewFromSubmittedOrder(submitted());
      final a = buildKdsTicketPrintDocument(ticket: ticket, labels: labels());
      final b = buildKdsTicketPrintDocument(ticket: ticket, labels: labels());
      expect(
        [for (final l in a.lines) '${l.kind}|${l.left}|${l.right}'],
        [for (final l in b.lines) '${l.kind}|${l.left}|${l.right}'],
      );
      expect(
        printedCountLines(ticket),
        contains('KTotal 4 Meat pieces مع Cheese'),
      );
    });
  });

  group('the shared resolver is the one order-time authority', () {
    test('presence-based: quantity of the option is irrelevant', () {
      final once = classifiedPrepForLine(configuredPrep, [cheese()]);
      final many = classifiedPrepForLine(configuredPrep, [cheese(quantity: 7)]);
      expect(once, many);
      expect(once[1].quantity, 2, reason: 'base quantity untouched');
    });

    test('a zero-unit selection does not classify', () {
      final resolved = classifiedPrepForLine(configuredPrep, [
        cheese(quantity: 0),
      ]);
      expect(resolved[1].classifierSelected, isFalse);
    });

    test('re-resolving an already-resolved snapshot is idempotent', () {
      final first = classifiedPrepForLine(configuredPrep, [cheese()]);
      final second = classifiedPrepForLine(first, [cheese()]);
      expect(second, first);
    });

    test('a restored parked draft re-resolves from its own modifiers', () {
      // Parked with cheese, restored, then submitted without it: the resolution
      // follows the CURRENT line, never a stale answer baked into the draft.
      final parked = classifiedPrepForLine(configuredPrep, [cheese()]);
      final resubmitted = classifiedPrepForLine(
        parked,
        const <SelectedModifier>[],
      );
      expect(resubmitted[1].classifierSelected, isFalse);
      expect(resubmitted[1].classifierOptionName, 'Cheese');
    });
  });

  group('unrelated ticket content is untouched', () {
    test('items, modifier lines and notes render exactly as before', () {
      final ticket = kdsTicketViewFromCartLines(
        orderCode: '#000042',
        orderType: OrderType.dineIn,
        prepByItemId: prepByItemId,
        orderNote: 'call when ready',
        lines: [
          burgerLine(lineId: 'l1', quantity: 2, modifiers: [cheese()]),
        ],
      );
      final doc = buildKdsTicketPrintDocument(ticket: ticket, labels: labels());
      final text = [for (final l in doc.lines) l.left].join('\n');

      expect(text, contains('2 × Burger 240g'));
      expect(text, contains('+ Cheese'));
      expect(text, contains('call when ready'));
      // No money reaches a kitchen ticket (SECURITY T-003).
      for (final token in ['4500', '9000', '₪', 'price']) {
        expect(text.toLowerCase(), isNot(contains(token.toLowerCase())));
      }
    });

    test('the display composer leaves an unsplit row alone', () {
      expect(
        kitchenCountDisplayLabel(
          const KitchenCount(quantity: 3, label: 'Bread'),
          withOption: (r, o) => '$r مع $o',
          withoutOption: (r, o) => '$r بدون $o',
        ),
        'Bread',
      );
    });
  });
}
