import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RESTAURANT-OPERATIONS-V1-001 — the per-branch availability control on the
/// dashboard menu item list: the reason-first badge, the three one-tap states
/// in the row menu (branch-scoped surfaces only), the honest disabled hint on
/// an unscoped surface, and the in-memory store's server-mirroring rules.
InMemoryMenuStore _store({String? itemAvailability, String? itemReason}) {
  MenuItem item(String id, String name) => MenuItem(
    id: id,
    organizationId: demoOrganizationId,
    restaurantId: demoRestaurantId,
    // GLOBAL (restaurant-scoped) rows: visible under BOTH the branch-scoped
    // and the unscoped surface, so every test sees the same item.
    branchId: null,
    menuCategoryId: 'cat-1',
    name: name,
    description: null,
    basePriceMinor: 4200,
    currencyCode: demoCurrencyCode,
    defaultStationId: null,
    displayOrder: 0,
    isActive: true,
    availability: itemAvailability,
    availabilityReason: itemReason,
  );

  return InMemoryMenuStore(
    categories: const [
      MenuCategory(
        id: 'cat-1',
        organizationId: demoOrganizationId,
        restaurantId: demoRestaurantId,
        branchId: null,
        name: 'Grill',
        displayOrder: 0,
        isActive: true,
      ),
    ],
    items: [item('item-1', 'House Burger')],
  );
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  InMemoryMenuStore store, {
  MenuScope? scope,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: scope ?? demoMenuScope,
        readSource: store,
        writer: store,
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const MenuManagementScreen();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  group('A. the row control (branch-scoped surface)', () {
    testWidgets('A1 marking an item SOLD OUT badges the row + snackbars', (
      tester,
    ) async {
      final store = _store(itemAvailability: 'available');
      final l10n = await _pump(tester, store);
      expect(find.text(l10n.menuAvailabilitySoldOut), findsNothing);

      await tester.tap(find.byKey(const Key('menu-item-menu-item-1')));
      await tester.pumpAndSettle();
      // The three states are offered; the current one is checked.
      expect(find.text(l10n.menuAvailabilityAvailable), findsOneWidget);
      expect(find.text(l10n.menuAvailabilityPaused), findsOneWidget);
      await tester.tap(find.text(l10n.menuAvailabilitySoldOut));
      await tester.pumpAndSettle();

      // Non-optimistic: the reload reflects the store's new truth.
      expect(find.text(l10n.menuAvailabilityUpdated), findsOneWidget);
      expect(
        find.byKey(const Key('menu-availability-pill-item-1')),
        findsOneWidget,
      );
      expect(find.text(l10n.menuAvailabilitySoldOut), findsOneWidget);
    });

    testWidgets('A2 re-enabling clears the badge', (tester) async {
      final store = _store(
        itemAvailability: 'unavailable',
        itemReason: 'paused',
      );
      final l10n = await _pump(tester, store);
      expect(
        find.byKey(const Key('menu-availability-pill-item-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('menu-item-menu-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuAvailabilityAvailable));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('menu-availability-pill-item-1')),
        findsNothing,
      );
    });

    testWidgets('A3 an UNSCOPED surface shows the honest hint, no control', (
      tester,
    ) async {
      const restaurantScope = MenuScope(
        organizationId: demoOrganizationId,
        restaurantId: demoRestaurantId,
        branchId: null,
        currencyCode: demoCurrencyCode,
      );
      final l10n = await _pump(tester, _store(), scope: restaurantScope);

      await tester.tap(find.byKey(const Key('menu-item-menu-item-1')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.menuAvailabilityNeedsBranch), findsOneWidget);
      expect(find.text(l10n.menuAvailabilitySoldOut), findsNothing);
    });
  });

  group('B. the in-memory store mirrors the server rules', () {
    test('B1 unavailable REQUIRES a structured reason', () async {
      final store = _store();
      final outcome = await store.setItemAvailability(
        scope: demoMenuScope,
        menuItemId: 'item-1',
        availability: 'unavailable',
      );
      expect(outcome, isA<Failure<MenuWriteResult, MenuWriteFailure>>());
    });

    test('B2 available never stores a stray reason', () async {
      final store = _store(
        itemAvailability: 'unavailable',
        itemReason: 'sold_out',
      );
      final outcome = await store.setItemAvailability(
        scope: demoMenuScope,
        menuItemId: 'item-1',
        availability: 'available',
        reason: 'sold_out',
      );
      expect(outcome.isSuccess, isTrue);
      final snapshot = await store.load(demoMenuScope);
      final item = snapshot.items.single;
      expect(item.availability, 'available');
      expect(item.availabilityReason, isNull);
    });

    test('B3 an unknown item is not_found', () async {
      final outcome = await _store().setItemAvailability(
        scope: demoMenuScope,
        menuItemId: 'nope',
        availability: 'unavailable',
        reason: 'sold_out',
      );
      expect(outcome, isA<Failure<MenuWriteResult, MenuWriteFailure>>());
    });
  });
}
