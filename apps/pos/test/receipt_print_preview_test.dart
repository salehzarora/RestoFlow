import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/print/print_service.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Captures the printed document instead of opening a real browser print.
class _FakePrintService implements PrintService {
  PrintDocument? lastDocument;
  @override
  void printDocument(PrintDocument document) => lastDocument = document;
}

Future<void> _pump(WidgetTester tester, {PrintService? printService}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (printService != null)
          printServiceProvider.overrideWithValue(printService),
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
      expect(
        find.descendant(of: dialog, matching: find.textContaining('PROV-0001')),
        findsOneWidget,
      );
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
      expect(
        find.descendant(of: dialog, matching: find.text(l10n.printPreviewHint)),
        findsOneWidget,
      );
    },
  );

  testWidgets('Print uses the isolated service with only the receipt document', (
    tester,
  ) async {
    final l10n = await _en();
    final fake = _FakePrintService();
    await _pump(tester, printService: fake);
    await _payAndOpenPreview(tester, l10n);

    await tester.tap(find.byKey(const Key('preview-print-button')));
    await tester.pump();

    // The print service received a receipt document (not a global page print).
    expect(fake.lastDocument, isNotNull);
    final html = documentToHtml(fake.lastDocument!);
    // The printable HTML carries the receipt details…
    expect(html, contains('PROV-0001')); // receipt number
    expect(html, contains('DEMO-0001')); // order number
    expect(html, contains('Classic Burger')); // item
    expect(html, contains('₪42.00')); // total + cash
    expect(html, contains('₪0.00')); // change
    expect(html, contains(l10n.posPaymentMethodCash)); // payment method
    // …and NOT the surrounding POS menu/app (isolation).
    expect(html, isNot(contains('Espresso'))); // an unordered menu item
    expect(html, isNot(contains(l10n.posMenuHeading))); // POS chrome
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
