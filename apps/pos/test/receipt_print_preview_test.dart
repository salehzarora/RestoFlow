import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/print/browser_print.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, {VoidCallback? onPrint}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (onPrint != null) printActionProvider.overrideWithValue(onPrint),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds Classic Burger (₪42.00), sends takeaway, pays exact, and opens the
/// receipt print preview.
Future<void> _payAndOpenPreview(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pay-cash-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('quick-cash-exact')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-payment-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-print-preview-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the paid receipt offers a Print preview action', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-cash-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-cash-exact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-payment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-print-preview-button')), findsOneWidget);
    expect(find.text(l10n.printPreviewAction), findsWidgets);
  });

  testWidgets(
    'opening the preview shows a printable receipt with all details',
    (tester) async {
      final l10n = await _en();
      await _pump(tester);
      await _payAndOpenPreview(tester, l10n);

      final dialog = find.byKey(const Key('receipt-print-preview'));
      expect(dialog, findsOneWidget);
      expect(find.text(l10n.receiptDemoRestaurantName), findsOneWidget);

      // Order + receipt identity, scoped to the preview dialog.
      expect(
        find.descendant(of: dialog, matching: find.textContaining('PROV-0001')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('DEMO-0001')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Classic Burger'),
        ),
        findsOneWidget,
      );
      // Totals (distinct keys, not swapped).
      expect(
        tester.widget<Text>(find.byKey(const Key('preview-total'))).data,
        '₪42.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('preview-cash'))).data,
        '₪42.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('preview-change'))).data,
        '₪0.00',
      );
      // Payment method + honest demo/provisional notes.
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(l10n.posPaymentMethodCash),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(l10n.posReceiptProvisionalNote),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text(l10n.printPreviewHint)),
        findsOneWidget,
      );
    },
  );

  testWidgets('the Print button triggers the (mockable) browser print action', (
    tester,
  ) async {
    final l10n = await _en();
    var printed = false;
    await _pump(tester, onPrint: () => printed = true);
    await _payAndOpenPreview(tester, l10n);

    await tester.tap(find.byKey(const Key('preview-print-button')));
    await tester.pump();
    expect(printed, isTrue);
  });

  testWidgets('Close dismisses the print preview', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _payAndOpenPreview(tester, l10n);

    expect(find.byKey(const Key('receipt-print-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preview-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receipt-print-preview')), findsNothing);
  });
}
