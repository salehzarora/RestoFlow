import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1100, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addAnItem(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('order-type selector renders both options for the active order', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    expect(find.text(l10n.posOrderTypeLabel), findsOneWidget);
    expect(find.text(l10n.posOrderTypeDineIn), findsWidgets);
    expect(find.text(l10n.posOrderTypeTakeaway), findsWidgets);
  });

  testWidgets('takeaway (default) shows a no-table hint and no warning', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    expect(find.text(l10n.posTableNotNeeded), findsOneWidget);
    expect(find.byKey(const Key('table-required-warning')), findsNothing);
    expect(find.byKey(const Key('assign-table-button')), findsNothing);
  });

  testWidgets('choosing dine-in shows the table-required warning and disables '
      'Send', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addAnItem(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('table-required-warning')), findsOneWidget);
    expect(find.text(l10n.posTableRequiredWarning), findsOneWidget);
    expect(find.byKey(const Key('assign-table-button')), findsOneWidget);

    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.posSendOrder),
    );
    expect(send.onPressed, isNull); // dine-in without a table can't submit
  });

  testWidgets('the picker shows table statuses and a clear demo notice', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posTablePickerTitle), findsOneWidget);
    expect(find.text(l10n.posTablesDemoNotice), findsOneWidget);
    // The seed has available, occupied, and blocked tables.
    expect(find.text(l10n.posTableStatusAvailable), findsWidgets);
    expect(find.text(l10n.posTableStatusOccupied), findsWidgets);
    expect(find.text(l10n.posTableStatusBlocked), findsWidgets);
  });

  testWidgets(
    'assigning an available table clears the warning, shows it in the '
    'summary, and enables Send',
    (tester) async {
      final l10n = await _en();
      await _pump(tester);
      await _addAnItem(tester);

      await tester.tap(find.text(l10n.posOrderTypeDineIn));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-table-button')));
      await tester.pumpAndSettle();

      // T1 is an available seed table.
      await tester.tap(find.text('T1'));
      await tester.pumpAndSettle();

      // Sheet closed; the assignment is now visible on the active order.
      expect(find.text(l10n.posTablePickerTitle), findsNothing);
      expect(find.byKey(const Key('assigned-table-card')), findsOneWidget);
      expect(find.byKey(const Key('table-required-warning')), findsNothing);
      // The cart summary carries the table chip ("Table T1").
      expect(find.byKey(const Key('summary-table')), findsOneWidget);

      final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.posSendOrder),
      );
      expect(send.onPressed, isNotNull);
    },
  );

  testWidgets('the DISABLED Send button explains itself: a needs-table hint '
      'sits above it for dine-in-without-table, and only then (Part G '
      'cashier polish)', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    // Empty cart, takeaway: no hint (the empty state explains that case).
    expect(find.byKey(const Key('send-needs-table-hint')), findsNothing);

    // Items + takeaway: still no hint — Send is enabled.
    await _addAnItem(tester);
    expect(find.byKey(const Key('send-needs-table-hint')), findsNothing);

    // Items + dine-in without a table: the hint appears right above Send.
    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-needs-table-hint')), findsOneWidget);
    expect(find.text(l10n.posSendNeedsTableHint), findsOneWidget);

    // Assigning a table resolves the block — the hint leaves with it.
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send-needs-table-hint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an occupied table cannot be assigned', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();

    // T3 is a seeded occupied table — tapping it must not assign.
    await tester.tap(find.text('T3'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posTablePickerTitle), findsOneWidget); // still open
    expect(find.byKey(const Key('assigned-table-card')), findsNothing);
  });

  testWidgets('a blocked (out-of-service) table cannot be assigned', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();

    // T10 is a seeded blocked table in the lower Patio zone — bring it on-screen
    // then tap it; it must not assign.
    final t10 = find.byKey(const ValueKey('table-tile-t10'));
    await tester.ensureVisible(t10);
    await tester.pumpAndSettle();
    await tester.tap(t10);
    await tester.pumpAndSettle();

    expect(find.text(l10n.posTablePickerTitle), findsOneWidget); // still open
    expect(find.byKey(const Key('assigned-table-card')), findsNothing);
  });

  testWidgets('switching back to takeaway clears the assigned table', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assigned-table-card')), findsOneWidget);

    await tester.tap(find.text(l10n.posOrderTypeTakeaway));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assigned-table-card')), findsNothing);
    expect(find.text(l10n.posTableNotNeeded), findsOneWidget);
  });

  testWidgets('a submitted dine-in order shows its type and table on the '
      'confirmation', (tester) async {
    final l10n = await _en();
    await _pump(tester);
    await _addAnItem(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.posSendOrder));
    await tester.pumpAndSettle();

    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
    expect(find.text(l10n.posOrderTypeDineIn), findsOneWidget); // the chip
    expect(find.text('${l10n.posTableLabel} T1'), findsOneWidget); // table chip
  });

  testWidgets('renders localized RTL chrome in Arabic', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await _pump(tester, locale: const Locale('ar'));

    expect(find.text(ar.posOrderTypeLabel), findsOneWidget); // "نوع الطلب"
    expect(find.text(ar.posOrderTypeDineIn), findsWidgets);
    expect(find.text(ar.posTableNotNeeded), findsOneWidget);
  });

  testWidgets('the picker reads like a floor map: area zones, a walkway, a '
      'legend, and a future-editor hint', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();

    // Tables are grouped into named area zones.
    expect(find.text(l10n.posTableAreaMain), findsOneWidget);
    expect(find.text(l10n.posTableAreaPatio), findsOneWidget);
    // A labelled walkway separates the zones.
    expect(find.text(l10n.posTablesAisleLabel), findsOneWidget);
    // Spatial edge labels give the sheet a map feel.
    expect(find.text(l10n.posTablesEdgeEntrance), findsOneWidget);
    expect(find.text(l10n.posTablesEdgeCounter), findsOneWidget);
    // The legend explains the colours (incl. the Selected swatch).
    expect(find.text(l10n.posTableStatusSelected), findsWidgets);
    // A non-intrusive future-layout-editor hint, not a broken element.
    expect(find.text(l10n.posTablesLayoutEditorHint), findsOneWidget);
  });

  testWidgets('occupied and blocked tiles are visibly disabled with status '
      'icons', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    await tester.tap(find.text(l10n.posOrderTypeDineIn));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-table-button')));
    await tester.pumpAndSettle();

    // t3 is seeded occupied; t10 is seeded blocked (inactive).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('table-tile-t3')),
        matching: find.byIcon(Icons.do_not_disturb_on),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('table-tile-t10')),
        matching: find.byIcon(Icons.block),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the assigned table is highlighted as Selected when the picker is '
    'reopened',
    (tester) async {
      final l10n = await _en();
      await _pump(tester);

      await tester.tap(find.text(l10n.posOrderTypeDineIn));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-table-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('T1'));
      await tester.pumpAndSettle();

      // Reopen the picker via "Change table".
      await tester.tap(find.text(l10n.posChangeTable));
      await tester.pumpAndSettle();

      final t1 = find.byKey(const ValueKey('table-tile-t1'));
      expect(t1, findsOneWidget);
      expect(
        find.descendant(of: t1, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: t1,
          matching: find.text(l10n.posTableStatusSelected),
        ),
        findsOneWidget,
      );
    },
  );
}
