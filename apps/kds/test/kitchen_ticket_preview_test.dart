import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';
import 'package:restoflow_kds/src/print/browser_print.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(WidgetTester tester, {VoidCallback? onPrint}) async {
  tester.view.physicalSize = const Size(720, 2600);
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

    // Order/ticket number, type, table, station, item + big quantity + modifier.
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
      find.descendant(
        of: dialog,
        matching: find.textContaining('Classic Burger'),
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
    // Honest demo note + print hint.
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.kdsDemoFeedBanner)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(l10n.printPreviewHint)),
      findsOneWidget,
    );
  });

  testWidgets('the Print button triggers the (mockable) browser print action', (
    tester,
  ) async {
    var printed = false;
    await _pump(tester, onPrint: () => printed = true);
    await _openPreview(tester);

    await tester.tap(find.byKey(const Key('ticket-preview-print-button')));
    await tester.pump();
    expect(printed, isTrue);
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
