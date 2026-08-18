import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// MENU-ADMIN-CURRENCY-SIMPLIFICATION-OPS-043 Phase 1, D1 — the item editor
/// stops asking for a currency.
///
/// One restaurant operates in ONE currency, so a per-item currency field was
/// only ever a way to get items out of step with the restaurant they belong to.
/// It is gone; the inherited operating currency is shown read-only next to the
/// price.
///
/// The two things that must NOT change:
///   * `p_currency_code` is still sent on every upsert (the server argument is
///     validated NOT NULL and ISO-shaped — a missing code is a 42501);
///   * the price is PARSED with the same currency's exponent it is displayed
///     and saved with, so a 3-decimal tenant cannot type 1.234 into a field
///     that stores 12.34.
class _RecordingStore extends InMemoryMenuStore {
  _RecordingStore({super.categories, super.items});

  int upsertItemCalls = 0;
  String? lastCurrencyCode;
  int? lastBasePriceMinor;

  @override
  Future<MenuWriteOutcome> upsertItem({
    required MenuScope scope,
    String? id,
    required String menuCategoryId,
    required String name,
    String? description,
    required int basePriceMinor,
    required String currencyCode,
    String? defaultStationId,
    int? displayOrder,
    bool isActive = true,
    String? imagePath,
    String? itemType,
    List<String> tags = const [],
    int? prepMinutes,
    String? sku,
    String? kitchenNote,
    Map<String, dynamic> attributes = const {},
  }) {
    upsertItemCalls++;
    lastCurrencyCode = currencyCode;
    lastBasePriceMinor = basePriceMinor;
    return super.upsertItem(
      scope: scope,
      id: id,
      menuCategoryId: menuCategoryId,
      name: name,
      description: description,
      basePriceMinor: basePriceMinor,
      currencyCode: currencyCode,
      defaultStationId: defaultStationId,
      displayOrder: displayOrder,
      isActive: isActive,
      imagePath: imagePath,
      itemType: itemType,
      tags: tags,
      prepMinutes: prepMinutes,
      sku: sku,
      kitchenNote: kitchenNote,
      attributes: attributes,
    );
  }
}

MenuScope _scope(String currency) => MenuScope(
  organizationId: demoOrganizationId,
  restaurantId: demoRestaurantId,
  branchId: demoBranchId,
  currencyCode: currency,
);

_RecordingStore _store({String itemCurrency = 'ILS', int priceMinor = 4800}) =>
    _RecordingStore(
      categories: const [
        MenuCategory(
          id: 'cat-1',
          organizationId: demoOrganizationId,
          restaurantId: demoRestaurantId,
          branchId: demoBranchId,
          name: 'Grill',
          displayOrder: 0,
          isActive: true,
        ),
      ],
      items: [
        MenuItem(
          id: 'item-1',
          organizationId: demoOrganizationId,
          restaurantId: demoRestaurantId,
          branchId: demoBranchId,
          menuCategoryId: 'cat-1',
          name: 'House Burger',
          description: null,
          basePriceMinor: priceMinor,
          currencyCode: itemCurrency,
          defaultStationId: null,
          displayOrder: 0,
          isActive: true,
        ),
      ],
    );

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingStore store, {
  String currency = 'ILS',
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: menuFeatureOverrides(
        scope: _scope(currency),
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

Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-item-save')));
  await tester.pumpAndSettle();
}

void main() {
  group('A. the selector is gone', () {
    testWidgets('A1. the pricing card no longer contains an EDITABLE currency '
        'field — the only text input left in it is the price', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'House Burger');

      final card = find.ancestor(
        of: find.text(l10n.menuPricingSection),
        matching: find.byType(Card),
      );
      expect(card, findsWidgets);
      final inputs = find.descendant(
        of: card.first,
        matching: find.byType(TextField),
      );
      expect(
        inputs,
        findsOneWidget,
        reason: 'the price field, and nothing else editable',
      );
      expect(find.byKey(const ValueKey('menu-item-price')), findsOneWidget);
    });

    testWidgets('A2. no editable field is labelled with the currency label any '
        'more', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'House Burger');

      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(
          field.decoration?.labelText,
          isNot(l10n.menuCurrencyLabel),
          reason: 'the per-item currency selector must be gone',
        );
      }
    });
  });

  group('B. the inherited currency is SHOWN instead', () {
    testWidgets('B1. the read-only row names the currency and says it comes '
        'from the restaurant settings', (tester) async {
      final store = _store();
      final l10n = await _pump(tester, store);
      await _open(tester, 'House Burger');

      expect(
        find.byKey(const ValueKey('menu-item-currency-inherited')),
        findsOneWidget,
      );
      expect(find.textContaining(l10n.menuCurrencyInherited), findsOneWidget);
      expect(find.textContaining('ILS'), findsWidgets);
    });

    testWidgets('B2. it follows the SCOPE, so a restaurant on EUR shows EUR '
        'even for an item stored under an older code', (tester) async {
      final store = _store(itemCurrency: 'ILS');
      await _pump(tester, store, currency: 'EUR');
      await _open(tester, 'House Burger');

      final row = find.descendant(
        of: find.byKey(const ValueKey('menu-item-currency-inherited')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(row.first).data, contains('EUR'));
    });
  });

  group(
    'C. p_currency_code is STILL sent — the server argument is NOT NULL',
    () {
      testWidgets('C1. saving an unchanged item sends the scope currency', (
        tester,
      ) async {
        final store = _store();
        await _pump(tester, store);
        await _open(tester, 'House Burger');
        await _save(tester);

        expect(store.upsertItemCalls, 1);
        expect(store.lastCurrencyCode, 'ILS');
      });

      testWidgets('C2. a restaurant that has moved to EUR re-stamps the item — '
          'denomination only, the NUMBER is untouched (D2 forbids FX)', (
        tester,
      ) async {
        final store = _store(itemCurrency: 'ILS', priceMinor: 4800);
        await _pump(tester, store, currency: 'EUR');
        await _open(tester, 'House Burger');
        await _save(tester);

        expect(store.lastCurrencyCode, 'EUR');
        expect(
          store.lastBasePriceMinor,
          4800,
          reason: '4800 minor units stay 4800 — no conversion, ever',
        );
      });

      testWidgets('C3. an edited price is parsed with the SAME currency it is '
          'saved under', (tester) async {
        final store = _store();
        await _pump(tester, store, currency: 'EUR');
        await _open(tester, 'House Burger');
        await tester.enterText(
          find.byKey(const ValueKey('menu-item-price')),
          '12.34',
        );
        await tester.pumpAndSettle();
        await _save(tester);

        expect(store.lastCurrencyCode, 'EUR');
        expect(store.lastBasePriceMinor, 1234);
      });
    },
  );
}
