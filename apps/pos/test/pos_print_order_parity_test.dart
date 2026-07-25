import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketMapper;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show
        kdsTicketViewFromCartLines,
        kdsTicketViewFromSubmittedOrder,
        kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' as pos;
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartLineView, SelectedModifier;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// PRINT-LAYOUT-001D — CROSS-SURFACE ITEM-ORDER PARITY.
///
/// The cashier receipt prints items in the cart INSERTION order (pure list
/// order, no sort). This proves all four print surfaces reproduce that EXACT
/// sequence for the same order:
///   * the cashier receipt (buildReceiptDocument);
///   * the POS AUTOMATIC kitchen print (built from the cart lines);
///   * the POS MANUAL kitchen print (built from the submitted-order view); and
///   * the KDS kitchen ticket / reprint — the KDS builds from `sync_pull` rows
///     delivered `ORDER BY (updated_at, id)` (effectively random for a fresh
///     order), but each row now carries the cart ordinal `order_items
///     .line_position`, and KdsTicketMapper sorts items by it, so even a SHUFFLED
///     wire order reassembles into cart order.
/// Complete item blocks (modifier + note) stay attached to the right item on
/// every surface.

Future<AppLocalizations> _l10n(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#100',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 5000,
  tenderedMinor: 5000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-INTERNAL-1',
  paidAt: DateTime.utc(2026, 7, 24, 12, 0),
);

/// One intentionally INTERLEAVED order: (name, modifier?, note?). Food and drinks
/// alternate, exactly the sequence the physical test flagged.
const _spec = <(String, String?, String?)>[
  ('Burger A', 'no onion', 'A note'),
  ('Cola', null, null),
  ('Burger B', null, 'B note'),
  ('Side A', 'extra sauce', null),
  ('Fanta', null, null),
];

const _expectedSequence = <String>[
  '1 × Burger A',
  '1 × Cola',
  '1 × Burger B',
  '1 × Side A',
  '1 × Fanta',
];

List<CartLineView> _cartLines() => [
  for (var i = 0; i < _spec.length; i++)
    CartLineView(
      lineId: 'l$i',
      menuItemId: 'm$i',
      name: _spec[i].$1,
      quantity: 1,
      unitPriceMinor: 1000,
      lineTotalMinor: 1000,
      currencyCode: 'ILS',
      modifiers: _spec[i].$2 == null
          ? const <SelectedModifier>[]
          : [
              SelectedModifier(
                optionId: 'o$i',
                groupName: 'Extras',
                optionName: _spec[i].$2!,
                priceDeltaMinor: 0,
              ),
            ],
      note: _spec[i].$3,
    ),
];

SubmittedOrderView _submitted() => SubmittedOrderView(
  orderNumber: '#100',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 5000,
  lines: [
    for (final it in _spec)
      SubmittedLineView(
        name: it.$1,
        quantity: 1,
        lineTotalMinor: 1000,
        currencyCode: 'ILS',
        // Modifier snapshots on the submitted view are already pre-formatted.
        modifiers: it.$2 == null ? const <String>[] : [it.$2!],
        note: it.$3,
      ),
  ],
);

/// Item-identity sequence (the `qty × name` left column) from a RECEIPT document.
List<String> _receiptItems(pos.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == pos.PrintLineKind.item) l.left ?? '',
];

/// Item-identity sequence from a KITCHEN document.
List<String> _kitchenItems(kit.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == kit.PrintLineKind.item) l.left ?? '',
];

void main() {
  group('PRINT-LAYOUT-001D — POS cross-surface item-order parity', () {
    test(
      'the receipt, POS auto kitchen, and POS manual kitchen print the EXACT '
      'same item sequence (cart insertion order)',
      () async {
        final l10n = await _l10n('en');
        final labels = kitchenTicketPrintLabelsFromL10n(l10n);

        final receipt = buildReceiptDocument(
          l10n,
          _submitted(),
          _payment(),
          isDemo: false,
        );
        final autoKitchen = kit.buildKdsTicketPrintDocument(
          ticket: kdsTicketViewFromCartLines(
            orderCode: '#100',
            orderType: OrderType.dineIn,
            lines: _cartLines(),
          ),
          labels: labels,
        );
        final manualKitchen = kit.buildKdsTicketPrintDocument(
          ticket: kdsTicketViewFromSubmittedOrder(_submitted()),
          labels: labels,
        );

        // Every surface prints exactly the interleaved cart order — not sorted,
        // not grouped, not drinks-last.
        expect(_receiptItems(receipt), _expectedSequence);
        expect(_kitchenItems(autoKitchen), _expectedSequence);
        expect(_kitchenItems(manualKitchen), _expectedSequence);
      },
    );

    test('the KDS kitchen ticket (mapped from a SHUFFLED sync_pull wire that '
        'carries line_position) reassembles into the SAME sequence as the '
        'cashier receipt', () async {
      final l10n = await _l10n('en');
      final labels = kitchenTicketPrintLabelsFromL10n(l10n);

      // The cart ordinal for each item (1-based, in _spec / receipt order).
      final positionByName = {
        for (var i = 0; i < _spec.length; i++) _spec[i].$1: i + 1,
      };
      // Deliver the order_items rows in a SHUFFLED wire order (as sync_pull's
      // (updated_at, id) does), each carrying its cart line_position.
      final shuffled = [_spec[1], _spec[3], _spec[0], _spec[4], _spec[2]];
      final tickets = KdsTicketMapper.map(
        orders: const [
          {
            'id': 'o1',
            'status': 'submitted',
            'order_type': 'dine_in',
            'created_at': '2026-07-24T10:00:00Z',
          },
        ],
        orderItems: [
          for (final s in shuffled)
            {
              'id': 'i-${s.$1}',
              'order_id': 'o1',
              'quantity': 1,
              'menu_item_name_snapshot': s.$1,
              'line_position': positionByName[s.$1],
            },
        ],
        modifiers: const [],
      );
      final kdsDoc = kit.buildKdsTicketPrintDocument(
        ticket: tickets.single,
        labels: labels,
      );
      expect(_kitchenItems(kdsDoc), _expectedSequence);
    });

    test(
      'no item is lost or duplicated across the surfaces (quantities kept)',
      () async {
        final l10n = await _l10n('en');
        final labels = kitchenTicketPrintLabelsFromL10n(l10n);
        final auto = _kitchenItems(
          kit.buildKdsTicketPrintDocument(
            ticket: kdsTicketViewFromCartLines(
              orderCode: '#100',
              orderType: OrderType.dineIn,
              lines: _cartLines(),
            ),
            labels: labels,
          ),
        );
        expect(auto.length, _spec.length);
        expect(auto.toSet().length, _spec.length, reason: 'no duplicates');
        for (final name in const [
          'Burger A',
          'Cola',
          'Burger B',
          'Side A',
          'Fanta',
        ]) {
          expect(
            auto.where((t) => t.contains(name)).length,
            1,
            reason: '$name appears exactly once',
          );
        }
      },
    );

    test('each item block keeps its modifier + note attached to the correct '
        'parent item, in order', () async {
      final l10n = await _l10n('en');
      final labels = kitchenTicketPrintLabelsFromL10n(l10n);
      final doc = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#100',
          orderType: OrderType.dineIn,
          lines: _cartLines(),
        ),
        labels: labels,
      );
      final texts = [for (final l in doc.lines) l.left ?? ''];
      int at(String needle) => texts.indexWhere((t) => t.contains(needle));

      // Burger A's modifier + note sit between it and the next item (Cola).
      expect(at('Burger A') < at('no onion'), isTrue);
      expect(at('no onion') < at('Cola'), isTrue);
      expect(
        at('A note') > at('Burger A') && at('A note') < at('Cola'),
        isTrue,
      );
      // Burger B's note is between Burger B and Side A.
      expect(
        at('B note') > at('Burger B') && at('B note') < at('Side A'),
        isTrue,
      );
      // Side A's modifier is between Side A and Fanta.
      expect(
        at('extra sauce') > at('Side A') && at('extra sauce') < at('Fanta'),
        isTrue,
      );
    });
  });
}
