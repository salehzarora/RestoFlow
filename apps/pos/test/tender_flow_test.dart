import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

/// RF-117 (A): choosing a NON-CASH tender (Card / Bit / External) hides the
/// cash-received field + change, records the payment with change 0, and shows
/// the tender type on the receipt. Cash keeps its cash-received + change flow.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2200);
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

Future<void> _submitAndOpenPay(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pay-cash-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selecting Card hides the cash-received field and shows the '
      'external note', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitAndOpenPay(tester, l10n);

    // Cash is the default: the cash field is present.
    expect(find.byKey(const Key('cash-received-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tender-card')));
    await tester.pumpAndSettle();

    // Non-cash: the cash field/keypad/change are gone; the honest note shows.
    expect(find.byKey(const Key('cash-received-field')), findsNothing);
    expect(find.byKey(const Key('change-due-amount')), findsNothing);
    expect(find.byKey(const Key('non-cash-note')), findsOneWidget);
    expect(find.text(l10n.posNonCashNote), findsOneWidget);
  });

  testWidgets('confirming a Card tender records it with change 0 and names the '
      'tender on the receipt', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitAndOpenPay(tester, l10n);

    await tester.tap(find.byKey(const Key('tender-card')));
    await tester.pumpAndSettle();
    // No cash to type — Confirm is enabled immediately.
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-payment-button')),
    );
    expect(confirm.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    // Paid: the receipt names the CARD tender and shows NO cash/change lines.
    expect(find.byKey(const Key('receipt-preview-card')), findsOneWidget);
    expect(find.text(l10n.posPaymentMethodCard), findsOneWidget);
    expect(find.byKey(const Key('receipt-cash')), findsNothing);
    expect(find.byKey(const Key('receipt-change')), findsNothing);
    // The receipt total is the order total (₪42.00) — no change was given.
    expect(
      tester.widget<Text>(find.byKey(const Key('receipt-total'))).data,
      '₪42.00',
    );
  });

  testWidgets('Bit and External are offered as tenders too', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _submitAndOpenPay(tester, l10n);
    expect(find.byKey(const Key('tender-bit')), findsOneWidget);
    expect(find.byKey(const Key('tender-external')), findsOneWidget);
    expect(find.text(l10n.posPaymentMethodBit), findsWidgets);
    expect(find.text(l10n.posPaymentMethodExternal), findsWidgets);
  });
}
