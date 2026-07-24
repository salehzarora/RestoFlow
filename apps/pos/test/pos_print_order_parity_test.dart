import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
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

/// PRINT-LAYOUT-001D — CROSS-SURFACE ITEM-ORDER PARITY (POS surfaces).
///
/// The cashier receipt prints items in the cart INSERTION order (pure list
/// order, no sort). This proves the two POS-side kitchen surfaces reproduce that
/// EXACT sequence from the same order: the automatic kitchen print (built from
/// the cart lines) and the manual kitchen print (built from the submitted-order
/// view). All three iterate the same client `_cart` order, so their printed item
/// identity sequence is identical — and complete item blocks (modifier + note)
/// stay attached to the right item.
///
/// (The KDS-produced kitchen ticket is NOT covered here: it derives item order
/// from the `sync_pull` wire, which is `ORDER BY (updated_at, id)` over rows with
/// a batch-identical timestamp and a random uuid `id`, and `order_items` carries
/// no persisted line ordinal — so it cannot reproduce cart order without an
/// additive `order_items.line_position` migration. That is a documented,
/// out-of-scope blocker for this phase.)

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
