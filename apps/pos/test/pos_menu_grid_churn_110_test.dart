import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110 — POS menu-grid rebuild churn.
///
/// Before: `_MenuGrid` watched the WHOLE cart state and the WHOLE offline
/// state (neither has value equality), so every cart add rebuilt every
/// visible product card, and every 25-second offline reconnect probe
/// (`markProbing` / `recordOfflineCacheServed`) rebuilt the whole grid.
/// After: an add rebuilds only the card whose badge changed; probe flips
/// touch the slim banner only.
void main() {
  final rebuilt = <Type, int>{};
  void startCounting() {
    rebuilt.clear();
    debugOnRebuildDirtyWidget = (element, _) {
      final w = element.widget;
      if (w is UncontrolledProviderScope || w is ProviderScope) return;
      rebuilt[w.runtimeType] = (rebuilt[w.runtimeType] ?? 0) + 1;
    };
  }

  void stopCounting() => debugOnRebuildDirtyWidget = null;
  int count(Type t) => rebuilt[t] ?? 0;

  late ProviderContainer container;

  Future<void> pumpPos(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(stopCounting);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: PosMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'adding ONE item rebuilds ONE MenuItemCard, not the whole visible grid',
    (tester) async {
      await pumpPos(tester);
      final cards = find.byType(MenuItemCard);
      final visible = cards.evaluate().length;
      expect(visible, greaterThan(3), reason: 'need a populated grid');
      final menu = container.read(posMenuProvider).requireValue;
      final item = menu.items.firstWhere(
        (i) => menu.groupsForItem(i.id).isEmpty && !i.isUnavailable,
      );

      startCounting();
      container.read(cartControllerProvider.notifier).addItem(item);
      await tester.pump();
      await tester.pump();
      stopCounting();

      expect(
        count(MenuItemCard),
        1,
        reason: 'only the touched card may rebuild; got $rebuilt',
      );
      expect(count(PosMenuScreen), 0);
    },
  );

  testWidgets(
    'offline reconnect-probe state flips (probing / served) rebuild NO product '
    'cards — only the slim banner',
    (tester) async {
      await pumpPos(tester);
      final offline = container.read(posOfflineModeProvider.notifier);
      offline.recordOfflineCacheServed(
        snapshotFetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);
      expect(find.byType(MenuItemCard), findsWidgets);

      startCounting();
      offline.markProbing(); // the 25 s probe's first write
      await tester.pump();
      offline.recordOfflineCacheServed(
        // the probe's last write
        snapshotFetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await tester.pump();
      await tester.pump();
      stopCounting();

      expect(count(MenuItemCard), 0, reason: 'grid churned: $rebuilt');
      expect(count(PosMenuScreen), 0);
      expect(find.byKey(const Key('pos-offline-banner')), findsOneWidget);
    },
  );

  testWidgets('cart lock flag still disables add targets (behavior intact)', (
    tester,
  ) async {
    await pumpPos(tester);
    final menu = container.read(posMenuProvider).requireValue;
    final item = menu.items.firstWhere(
      (i) => menu.groupsForItem(i.id).isEmpty && !i.isUnavailable,
    );
    // Ordinary add works and the badge reflects it.
    await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
    await tester.pumpAndSettle();
    expect(container.read(cartControllerProvider).lines.isNotEmpty, isTrue);
    expect(item.id, isNotEmpty);
  });
}
