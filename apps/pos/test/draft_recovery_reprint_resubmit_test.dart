import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show
        kdsTicketViewFromCartLines,
        kdsTicketViewFromSubmittedOrder,
        kitchenTicketPrintLabelsFromL10n;
import 'package:restoflow_pos/src/print/print_document.dart' as pos;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// MENU-ORDER-001 (Codex 4th pass, #9): the COMPLETE restart -> restore ->
/// receipt/kitchen order -> correct -> resubmit flow, through the REAL cart
/// controller and the REAL print builders. A permanently-rejected (item_unavailable)
/// order's durable draft — built in a sequence DIFFERENT from Dashboard order, with
/// quantities, notes, modifiers, and STABLE line ids — is restored, prints in exact
/// Dashboard order on both the customer receipt and the POS kitchen ticket (modifier
/// + note stay attached to the right item), then the unavailable item is removed and
/// the corrected order resubmits with NO duplicate lines/modifiers, the survivors'
/// ORIGINAL line ids, and their quantities/notes/modifiers intact.

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

CashPayment _payment() => CashPayment(
  paymentId: 'pay-1',
  orderNumber: '#100',
  deviceId: 'd1',
  localOperationId: 'op1',
  method: PaymentMethod.cash,
  status: PaymentStatus.completed,
  amountMinor: 7000,
  tenderedMinor: 7000,
  changeMinor: 0,
  currencyCode: 'ILS',
  receiptNumber: 'R-1',
  paidAt: DateTime.utc(2026, 7, 26, 12, 0),
);

/// The captured draft — CART (insertion) order deliberately != Dashboard order.
/// Dashboard config: Meals(1)[Burger B(1), Burger A(2)], Sides(2)[Fries(1)],
/// Drinks(3)[Fanta(1), Cola(2)]. Cola carries a note; Burger A a modifier + note;
/// Fries quantity 2. Every line has a STABLE id.
CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      lineId: 'line-10',
      menuItemId: 'cola',
      name: 'Cola',
      basePriceMinor: 1000,
      quantity: 1,
      note: 'no ice',
      categoryDisplayOrder: 3,
      itemDisplayOrder: 2,
    ),
    CartDraftLine(
      lineId: 'line-11',
      menuItemId: 'burger-a',
      name: 'Burger A',
      basePriceMinor: 2000,
      quantity: 1,
      modifiers: [
        SelectedModifier(
          optionId: 'o-noonion',
          groupName: 'Extras',
          optionName: 'no onion',
          priceDeltaMinor: 0,
        ),
      ],
      note: 'well done',
      categoryDisplayOrder: 1,
      itemDisplayOrder: 2,
    ),
    CartDraftLine(
      lineId: 'line-12',
      menuItemId: 'fries',
      name: 'Fries',
      basePriceMinor: 1000,
      quantity: 2,
      categoryDisplayOrder: 2,
      itemDisplayOrder: 1,
    ),
    CartDraftLine(
      lineId: 'line-13',
      menuItemId: 'fanta',
      name: 'Fanta',
      basePriceMinor: 1000,
      quantity: 1,
      categoryDisplayOrder: 3,
      itemDisplayOrder: 1,
    ),
    CartDraftLine(
      lineId: 'line-14',
      menuItemId: 'burger-b',
      name: 'Burger B',
      basePriceMinor: 2000,
      quantity: 1,
      categoryDisplayOrder: 1,
      itemDisplayOrder: 1,
    ),
  ],
);

List<String> _receiptItems(pos.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == pos.PrintLineKind.item) l.left ?? '',
];

List<String> _kitchenItems(kit.PrintDocument doc) => [
  for (final l in doc.lines)
    if (l.kind == kit.PrintLineKind.item) l.left ?? '',
];

ProviderContainer _container() => ProviderContainer(
  overrides: [
    runtimeConfigProvider.overrideWithValue(
      RuntimeConfig.test(isDemoMode: true),
    ),
  ],
);

void main() {
  test(
    'restore -> the customer receipt AND POS kitchen ticket both print exact '
    'Dashboard order, with the modifier + note attached to the right item',
    () async {
      final l10n = await _l10n();
      final labels = kitchenTicketPrintLabelsFromL10n(l10n);
      final c = _container();
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);

      // Restore the rejected order's durable draft into the cart.
      cart.restoreDraft(_draft());
      final restored = c.read(cartControllerProvider);
      // The stable ids survived (no re-mint), in cart order.
      expect(restored.lines.map((l) => l.lineId), const [
        'line-10',
        'line-11',
        'line-12',
        'line-13',
        'line-14',
      ]);

      const dashboardOrder = <String>[
        '1 × Burger B',
        '1 × Burger A',
        '2 × Fries',
        '1 × Fanta',
        '1 × Cola',
      ];

      // 1) POS kitchen ticket from the restored cart lines -> Dashboard order.
      final kitchen = kit.buildKdsTicketPrintDocument(
        ticket: kdsTicketViewFromCartLines(
          orderCode: '#100',
          orderType: OrderType.dineIn,
          lines: restored.lines,
        ),
        labels: labels,
      );
      expect(_kitchenItems(kitchen), dashboardOrder);

      // The modifier + notes stay with their parent item on the kitchen ticket.
      final kText = [for (final l in kitchen.lines) l.left ?? ''];
      int at(String needle) => kText.indexWhere((t) => t.contains(needle));
      expect(at('Burger A') < at('no onion'), isTrue);
      expect(at('no onion') < at('Fries'), isTrue); // before the next item
      expect(
        at('well done') > at('Burger A') && at('well done') < at('Fries'),
        isTrue,
      );
      expect(
        at('no ice') > at('Cola'),
        isTrue,
      ); // Cola is last; its note follows

      // 2) Customer receipt from the restored draft -> the SAME Dashboard order.
      final receipt = buildReceiptDocument(
        l10n,
        cart.viewFromDraft(draft: _draft(), orderType: OrderType.dineIn),
        _payment(),
        isDemo: false,
      );
      expect(_receiptItems(receipt), dashboardOrder);
    },
  );

  test('remove the unavailable item -> the corrected order resubmits with NO '
      'duplicate lines/modifiers, the survivors\' ORIGINAL ids, and their '
      'quantities/notes/modifiers intact', () async {
    final l10n = await _l10n();
    final labels = kitchenTicketPrintLabelsFromL10n(l10n);
    final c = _container();
    addTearDown(c.dispose);
    final cart = c.read(cartControllerProvider.notifier);

    cart.restoreDraft(_draft());
    // Cola (line-10) is the item that was unavailable — correct the order.
    cart.removeLine('line-10');

    // Capture the corrected draft (what a resubmit sends).
    final corrected = cart.captureDraft();
    expect(
      corrected.lines.map((l) => l.lineId),
      const ['line-11', 'line-12', 'line-13', 'line-14'],
      reason: 'Cola is gone; survivors keep their ORIGINAL stable ids',
    );
    // No duplicates; the removed item is not present.
    expect(corrected.lines.map((l) => l.menuItemId).toSet().length, 4);
    expect(corrected.lines.any((l) => l.menuItemId == 'cola'), isFalse);
    // Quantities, notes, and modifiers survive on the corrected lines.
    final fries = corrected.lines.firstWhere((l) => l.menuItemId == 'fries');
    expect(fries.quantity, 2);
    final burgerA = corrected.lines.firstWhere(
      (l) => l.menuItemId == 'burger-a',
    );
    expect(burgerA.note, 'well done');
    expect(burgerA.modifiers.single.optionName, 'no onion');

    // The corrected resubmit view prints the Dashboard order MINUS Cola, once each.
    final resubmit = cart.viewFromDraft(
      draft: corrected,
      orderType: OrderType.dineIn,
    );
    final kitchen = kit.buildKdsTicketPrintDocument(
      ticket: kdsTicketViewFromSubmittedOrder(resubmit),
      labels: labels,
    );
    expect(_kitchenItems(kitchen), const [
      '1 × Burger B',
      '1 × Burger A',
      '2 × Fries',
      '1 × Fanta',
    ]);
    // Every surviving item appears exactly once (no loss, no duplication).
    for (final name in const ['Burger B', 'Burger A', 'Fries', 'Fanta']) {
      expect(
        _kitchenItems(kitchen).where((t) => t.contains(name)).length,
        1,
        reason: '$name appears exactly once after the correction',
      );
    }
  });
}
