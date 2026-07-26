import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show kdsTicketViewFromSubmittedOrder, kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' as pos;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// MENU-ORDER-001 (Codex 4th pass, #11): HISTORICAL MODIFIER A/B renderer parity.
///
/// An OLD order (snapshot A) and a NEW order (snapshot B, after the modifier group
/// + options were reordered in the Dashboard) must each render their OWN immutable
/// modifier sequence on every print surface — the customer receipt, the POS kitchen
/// ticket, the POS server-backed reprint, and the KDS ticket/reprint — from the
/// order-time SNAPSHOTS, never a live-menu read. Order A stays A; order B uses B;
/// each modifier appears exactly once, attached to the right item; the kitchen stays
/// money-free.
///
/// Options: Alpha, Bravo, Charlie.
///   Snapshot A: group rank 4; option ranks Alpha=1, Bravo=2, Charlie=3
///       -> render order A = [Alpha, Bravo, Charlie].
///   Snapshot B (after reorder): group rank 1; option ranks Charlie=1, Bravo=2,
///       Alpha=3 -> render order B = [Charlie, Bravo, Alpha].

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

const _orderA = <String>['Alpha', 'Bravo', 'Charlie'];
const _orderB = <String>['Charlie', 'Bravo', 'Alpha'];

/// The option's (group rank, option rank) under snapshot A and B.
const _ranksA = <String, (int, int)>{
  'Alpha': (4, 1),
  'Bravo': (4, 2),
  'Charlie': (4, 3),
};
const _ranksB = <String, (int, int)>{
  'Charlie': (1, 1),
  'Bravo': (1, 2),
  'Alpha': (1, 3),
};

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#100',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 1000,
  tenderedMinor: 1000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.utc(2026, 7, 26, 12, 0),
);

/// The relative order of [names] in the sequence of line texts [texts].
List<String> _sequenceOf(List<String> texts, List<String> names) {
  final indexed = <(int, String)>[
    for (final n in names) (texts.indexWhere((t) => t.contains(n)), n),
  ];
  indexed.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in indexed) e.$2];
}

/// The KDS ticket's modifier sequence for a single item whose modifier rows
/// carry the given [ranks], delivered in a SHUFFLED wire order (as sync_pull's
/// (updated_at, id) does) — the mapper must reassemble the snapshot order.
List<String> _kdsModifierSequence(
  AppLocalizations l10n,
  Map<String, (int, int)> ranks, {
  required List<String> shuffledWire,
}) {
  final tickets = KdsTicketMapper.map(
    orders: const [
      {
        'id': 'o1',
        'status': 'submitted',
        'order_type': 'dine_in',
        'created_at': '2026-07-26T10:00:00Z',
      },
    ],
    orderItems: const [
      {
        'id': 'it1',
        'order_id': 'o1',
        'quantity': 1,
        'menu_item_name_snapshot': 'Burger',
        'line_position': 1,
      },
    ],
    modifiers: [
      for (var i = 0; i < shuffledWire.length; i++)
        {
          'id': 'm-${shuffledWire[i]}',
          'order_item_id': 'it1',
          'quantity': 1,
          'option_name_snapshot': shuffledWire[i],
          'modifier_group_display_order_snapshot': ranks[shuffledWire[i]]!.$1,
          'modifier_option_display_order_snapshot': ranks[shuffledWire[i]]!.$2,
          // A misleading wire ordinal — the snapshot keys, not this, drive order.
          'line_position': i + 1,
        },
    ],
  );
  final doc = kit.buildKdsTicketPrintDocument(
    ticket: tickets.single,
    labels: kitchenTicketPrintLabelsFromL10n(l10n),
  );
  return _sequenceOf(
    [for (final l in doc.lines) l.left ?? ''],
    const ['Alpha', 'Bravo', 'Charlie'],
  );
}

/// A single-line order whose modifiers are already in [modifierOrder] (the order
/// the DB delivers from the immutable snapshots).
SubmittedOrderView _submitted(List<String> modifierOrder) => SubmittedOrderView(
  orderNumber: '#100',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
      modifiers: modifierOrder,
      linePosition: 1,
    ),
  ],
);

/// The server-backed reprint source: a detail row whose modifiers are in
/// [modifierOrder] (pos_order_detail returns them snapshot-ordered).
PosOrderDetail _detail(List<String> modifierOrder) => PosOrderDetail(
  orderId: 'o1',
  orderCode: '#100',
  orderType: 'dine_in',
  status: 'served',
  revision: 1,
  currencyCode: 'ILS',
  subtotalMinor: 1000,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: 1000,
  rounds: const [],
  items: [
    PosOrderDetailItem(
      name: 'Burger',
      quantity: 1,
      unitPriceMinor: 1000,
      lineDiscountMinor: 0,
      lineTotalMinor: 1000,
      linePosition: 1,
      modifiers: [
        for (final m in modifierOrder)
          PosOrderDetailModifier(optionName: m, priceMinor: 0, quantity: 1),
      ],
    ),
  ],
);

List<String> _receiptTexts(pos.PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];
List<String> _kitchenTexts(kit.PrintDocument doc) => [
  for (final l in doc.lines) l.left ?? '',
];

void main() {
  test('the KDS ticket/reprint reassembles each order\'s OWN modifier snapshot '
      'order from a SHUFFLED wire (A stays A; B uses B)', () async {
    final l10n = await _l10n();

    // Order A: wire delivered shuffled, A snapshots -> render A.
    expect(
      _kdsModifierSequence(
        l10n,
        _ranksA,
        shuffledWire: const ['Bravo', 'Charlie', 'Alpha'],
      ),
      _orderA,
    );
    // Order B: a DIFFERENT shuffle, B snapshots -> render B (reversed group/options).
    expect(
      _kdsModifierSequence(
        l10n,
        _ranksB,
        shuffledWire: const ['Bravo', 'Alpha', 'Charlie'],
      ),
      _orderB,
    );
  });

  test('the customer receipt, POS kitchen ticket, and POS server-backed reprint '
      'each render order A in A order and order B in B order', () async {
    final l10n = await _l10n();
    final labels = kitchenTicketPrintLabelsFromL10n(l10n);

    for (final (order, expected) in [(_orderA, _orderA), (_orderB, _orderB)]) {
      // Customer receipt (from the submitted view).
      final receipt = buildReceiptDocument(
        l10n,
        _submitted(order),
        _payment(),
        isDemo: false,
      );
      expect(_sequenceOf(_receiptTexts(receipt), _orderA), expected);

      // POS kitchen ticket (from the submitted view).
      final kitchen = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromSubmittedOrder(_submitted(order)),
        labels: labels,
      );
      final kTexts = _kitchenTexts(kitchen);
      expect(_sequenceOf(kTexts, _orderA), expected);
      // Each modifier appears exactly once, attached to the single Burger item.
      for (final name in _orderA) {
        expect(kTexts.where((t) => t.contains(name)).length, 1);
      }
      // Kitchen stays money-free: no currency amount rides a modifier line.
      expect(kTexts.any((t) => t.contains('ILS') || t.contains('₪')), isFalse);

      // POS server-backed reprint (from pos_order_detail -> combined view).
      final reprint = buildReceiptDocument(
        l10n,
        submittedOrderViewFromDetail(_detail(order)),
        _payment(),
        isDemo: false,
      );
      expect(_sequenceOf(_receiptTexts(reprint), _orderA), expected);
    }
  });
}
