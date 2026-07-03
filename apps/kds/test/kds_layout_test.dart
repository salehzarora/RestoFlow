import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/kds_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-102: on a wide surface the board lays stations out as side-by-side
/// columns; all station headers and item lines remain rendered (money-free).
List<KdsTicketView> _tickets() => [
  KdsTicketView(
    kitchenTicketId: 'o1:grill',
    stationId: 'grill',
    items: const [KdsItemView(name: 'Classic Burger', quantity: 2)],
  ),
  KdsTicketView(
    kitchenTicketId: 'o2:fryer',
    stationId: 'fryer',
    items: const [KdsItemView(name: 'French Fries', quantity: 3)],
  ),
];

void main() {
  testWidgets('wide layout renders station columns with all tickets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsScreen(tickets: _tickets()),
      ),
    );
    await tester.pumpAndSettle();

    // Both stations and their items are present in the wide board.
    expect(find.textContaining('grill'), findsWidgets);
    expect(find.textContaining('fryer'), findsWidgets);
    expect(find.text('Classic Burger ×2'), findsOneWidget);
    expect(find.text('French Fries ×3'), findsOneWidget);
  });

  testWidgets('narrow stacked layout keys every status column and marks empty '
      'columns with a placeholder', (tester) async {
    tester.view.physicalSize = const Size(720, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: KdsScreen(tickets: _tickets()),
      ),
    );
    await tester.pumpAndSettle();

    // Design-polish sprint: the narrow path keys its columns too (parity with
    // KitchenBoard), and cards stay widget-descendants of their column.
    for (final key in ['new', 'preparing', 'ready', 'cleared']) {
      expect(find.byKey(Key('kds-col-$key')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('kds-col-ready')),
        matching: find.text('Classic Burger ×2'),
      ),
      findsOneWidget,
    );
    // Both tickets default to ready — the other three columns are empty and
    // say so instead of rendering a floating header.
    expect(find.text(l10n.kdsColumnEmpty), findsNWidgets(3));
  });
}
