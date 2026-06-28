import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds Classic Burger (₪42.00) and sends a takeaway order.
Future<void> _submitTakeaway(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
}

Future<void> _openPaySheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pay-cash-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pay Cash appears on the confirmation after submit', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);

    expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    expect(find.text(l10n.posPayCash), findsWidgets);
  });

  testWidgets('the payment sheet shows the amount due', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);

    expect(find.text(l10n.posPaymentTitle), findsOneWidget);
    expect(find.text(l10n.posAmountDue), findsOneWidget);
    expect(find.text('₪42.00'), findsWidgets); // amount due
  });

  testWidgets('paying the exact amount marks the order Paid and shows a '
      'receipt', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);

    await tester.tap(find.byKey(const Key('quick-cash-exact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    // Sheet closed; the order is paid with a receipt preview.
    expect(find.text(l10n.posPaymentTitle), findsNothing);
    final receipt = find.byKey(const Key('receipt-preview-card'));
    expect(receipt, findsOneWidget);
    expect(find.text(l10n.posPaidChip), findsWidgets);
    expect(find.textContaining('PROV-0001'), findsOneWidget); // receipt no.
    expect(find.byKey(const Key('pay-cash-button')), findsNothing);

    // The receipt itemises the order, names the method, and shows ₪0.00 change.
    expect(
      find.descendant(
        of: receipt,
        matching: find.textContaining('Classic Burger'),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.posPaymentMethodCash), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const Key('receipt-change')));
    expect(change.data, '₪0.00');

    // Honest demo / no-printer / provisional labelling (a hard RF-116 rule).
    expect(find.text(l10n.posReceiptDemoNote), findsOneWidget);
    expect(find.text(l10n.posReceiptProvisionalNote), findsOneWidget);
    final printButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('print-receipt-button')),
    );
    expect(printButton.onPressed, isNull); // demo — never prints
  });

  testWidgets('an overpayment shows change due and records it on the receipt', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);

    await tester.enterText(find.byKey(const Key('cash-received-field')), '50');
    await tester.pumpAndSettle();

    final change = tester.widget<Text>(
      find.byKey(const Key('change-due-amount')),
    );
    expect(change.data, '₪8.00'); // 50.00 - 42.00

    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-preview-card')), findsOneWidget);
    // Total (order amount), Cash received (tender), and Change are distinct and
    // not swapped: ₪42.00 / ₪50.00 / ₪8.00.
    expect(
      tester.widget<Text>(find.byKey(const Key('receipt-total'))).data,
      '₪42.00',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('receipt-cash'))).data,
      '₪50.00',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('receipt-change'))).data,
      '₪8.00',
    );
  });

  testWidgets('insufficient cash keeps Confirm disabled with a message', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);

    await tester.enterText(find.byKey(const Key('cash-received-field')), '10');
    await tester.pumpAndSettle();

    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-payment-button')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text(l10n.posCashInsufficient), findsOneWidget);
  });

  testWidgets('invalid cash input keeps Confirm disabled with a message', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);

    await tester.enterText(
      find.byKey(const Key('cash-received-field')),
      '5.555',
    );
    await tester.pumpAndSettle();

    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-payment-button')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text(l10n.posCashInvalid), findsOneWidget);
  });

  testWidgets('the shift cash-drawer total updates after a payment', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    // Opening float is ₪200.00 before any payment.
    expect(find.textContaining('₪200.00'), findsOneWidget);

    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);
    // Overpay (₪50.00 for a ₪42.00 order) so this proves the drawer grows by the
    // ORDER amount (→ ₪242.00), not the tender (which would wrongly give ₪250.00).
    await tester.enterText(find.byKey(const Key('cash-received-field')), '50');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('cash-in-drawer')),
        matching: find.textContaining('₪242.00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('payment keeps the RF-115 sync status visible', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);
    await tester.tap(find.byKey(const Key('quick-cash-exact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-status-card')), findsOneWidget);
  });

  testWidgets('New order resets the payment UI back to an empty cart', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitTakeaway(tester, l10n);
    await _openPaySheet(tester);
    await tester.tap(find.byKey(const Key('quick-cash-exact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receipt-preview-card')), findsOneWidget);

    await tester.tap(find.text(l10n.posNewOrder));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-preview-card')), findsNothing);
    expect(find.byKey(const Key('pay-cash-button')), findsNothing);
    expect(find.text(l10n.posCartEmpty), findsOneWidget);
    // The drawer total persists across orders (the shift is not reset).
    expect(
      find.descendant(
        of: find.byKey(const Key('cash-in-drawer')),
        matching: find.textContaining('₪242.00'),
      ),
      findsOneWidget,
    );
  });
}
