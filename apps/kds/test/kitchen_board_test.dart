import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/src/data/kitchen_orders_repository.dart';
import 'package:restoflow_kds/src/kitchen_orders_home.dart';
import 'package:restoflow_kds/src/state/kitchen_orders_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  KitchenOrdersRepository? repo,
  Locale locale = const Locale('en'),
}) async {
  // Narrow + tall: the board stacks its status columns into one scroll view so
  // every card + action is laid out.
  tester.view.physicalSize = const Size(720, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null)
          kitchenOrdersRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const KitchenOrdersHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inColumn(String columnKey, String ticketId) => find.descendant(
  of: find.byKey(Key('kds-col-$columnKey')),
  matching: find.byKey(Key('kitchen-card-$ticketId')),
);

Future<void> _tapAction(
  WidgetTester tester,
  String ticketId,
  String label,
) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(Key('kitchen-card-$ticketId')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the demo feed banner and order tickets', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    expect(find.text(l10n.kdsDemoFeedBanner), findsOneWidget);
    expect(find.text('K-1001'), findsOneWidget); // order number
    expect(find.textContaining('Classic Burger'), findsOneWidget); // item
    expect(find.byKey(const Key('elapsed-K-1001')), findsOneWidget); // elapsed
  });

  testWidgets('shows order type, table, and item quantities on a card', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    final card = find.byKey(const Key('kitchen-card-K-1001'));
    expect(
      find.descendant(of: card, matching: find.text(l10n.posOrderTypeDineIn)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('${l10n.posTableLabel} T3'),
      ),
      findsOneWidget,
    );
    // Item line shows the quantity ("Classic Burger ×2").
    expect(
      find.descendant(of: card, matching: find.textContaining('×2')),
      findsOneWidget,
    );
  });

  testWidgets('tickets sit in their status columns', (tester) async {
    await _pump(tester);
    expect(_inColumn('new', 'K-1001'), findsOneWidget); // newTicket
    expect(_inColumn('preparing', 'K-1003'), findsOneWidget); // inPreparation
    expect(_inColumn('ready', 'K-1005'), findsOneWidget); // ready
  });

  testWidgets('Start moves a new order into Preparing', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    expect(_inColumn('new', 'K-1001'), findsOneWidget);
    await _tapAction(tester, 'K-1001', l10n.kdsStartAction);

    expect(_inColumn('new', 'K-1001'), findsNothing);
    expect(_inColumn('preparing', 'K-1001'), findsOneWidget);
  });

  testWidgets('Mark ready moves a preparing order into Ready', (tester) async {
    final l10n = await _en();
    await _pump(tester);

    await _tapAction(tester, 'K-1003', l10n.kdsReadyAction);
    expect(_inColumn('ready', 'K-1003'), findsOneWidget);
    expect(_inColumn('preparing', 'K-1003'), findsNothing);
  });

  testWidgets('Complete clears a ready order off the active board', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(tester);

    // K-1005 is DINE-IN: the ready-stage action reads Served
    // (RESTAURANT-OPERATIONS-V1-001 type-aware wording).
    await _tapAction(tester, 'K-1005', l10n.kdsServedAction);
    expect(_inColumn('ready', 'K-1005'), findsNothing);
    expect(_inColumn('cleared', 'K-1005'), findsOneWidget);

    // A cleared order can be recalled back to Preparing.
    await _tapAction(tester, 'K-1005', l10n.kdsRecallAction);
    expect(_inColumn('preparing', 'K-1005'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no orders', (tester) async {
    final l10n = await _en();
    await _pump(tester, repo: DemoKitchenOrdersStore(seed: const []));

    expect(find.text(l10n.kdsEmptyState), findsOneWidget);
    expect(find.byKey(const Key('kitchen-card-K-1001')), findsNothing);
  });

  testWidgets('renders localized RTL chrome in Arabic', (tester) async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await _pump(tester, locale: const Locale('ar'));

    expect(find.text(ar.kdsDemoFeedBanner), findsOneWidget);
    expect(find.text(ar.kdsColNew), findsWidgets); // column header (ar)
    expect(
      Directionality.of(tester.element(find.text(ar.kdsColNew).first)),
      TextDirection.rtl,
    );
  });
}
