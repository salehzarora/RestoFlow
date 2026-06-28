import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';
import 'package:restoflow_kds/src/print/print_document.dart';
import 'package:restoflow_kds/src/print/print_service.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Captures the printed document instead of opening a real browser print.
class _FakePrintService implements PrintService {
  PrintDocument? lastDocument;
  @override
  void printDocument(PrintDocument document) => lastDocument = document;
}

Future<void> _pump(WidgetTester tester, {PrintService? printService}) async {
  tester.view.physicalSize = const Size(720, 2600);
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
        home: KitchenOrdersHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('preview-ticket-K-1001')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each kitchen card offers a Preview ticket action', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const Key('preview-ticket-K-1001')), findsOneWidget);
    expect(find.byKey(const Key('preview-ticket-K-1003')), findsOneWidget);
  });

  testWidgets('opening the preview shows the kitchen ticket details', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);
    await _openPreview(tester);

    final dialog = find.byKey(const Key('kitchen-ticket-preview'));
    expect(dialog, findsOneWidget);
    expect(find.text(l10n.kdsTicketPreviewTitle), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('K-1001')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.posOrderTypeDineIn)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('${l10n.posTableLabel} T3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('2×')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('No pickles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.printPreviewHint)),
      findsOneWidget,
    );
  });

  testWidgets('Print uses the isolated service with only the ticket document', (
    tester,
  ) async {
    final fake = _FakePrintService();
    await _pump(tester, printService: fake);
    await _openPreview(tester);

    await tester.tap(find.byKey(const Key('ticket-preview-print-button')));
    await tester.pump();

    expect(fake.lastDocument, isNotNull);
    final html = documentToHtml(fake.lastDocument!);
    // The printable HTML carries this ticket's content…
    expect(html, contains('K-1001')); // order/ticket number
    expect(html, contains('Classic Burger')); // item
    expect(html, contains('2×')); // big quantity
    expect(html, contains('No pickles')); // modifier
    expect(html, contains('new')); // status (canonical)
    // …and NOT other tickets / the board (isolation).
    expect(html, isNot(contains('Margherita Pizza'))); // a different ticket
  });

  testWidgets('Close dismisses the kitchen-ticket preview', (tester) async {
    await _pump(tester);
    await _openPreview(tester);

    expect(find.byKey(const Key('kitchen-ticket-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-preview-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kitchen-ticket-preview')), findsNothing);
  });
}
