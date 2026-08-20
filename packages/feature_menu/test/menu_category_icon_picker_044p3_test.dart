import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// MENU-CATEGORY-ICON-PICKER-OPS-044 Phase 3 — the Dashboard side.
///
/// The assertions that matter most are the DATA-LOSS ones. `menu_upsert_category`
/// is a full-state upsert, so a form that sent "no icon" whenever the owner had
/// not touched the icon field would quietly erase a chosen glyph on an unrelated
/// rename — and would erase a key from a NEWER build every single time, because
/// this binary cannot even draw it. Both are pinned below.
void main() {
  const scope = demoMenuScope;

  MenuCategory category({
    String id = 'cat-1',
    String name = 'Drinks',
    String? iconKey,
    int displayOrder = 1,
    bool isActive = true,
  }) => MenuCategory(
    id: id,
    organizationId: scope.organizationId,
    restaurantId: scope.restaurantId,
    branchId: scope.branchId,
    name: name,
    displayOrder: displayOrder,
    isActive: isActive,
    iconKey: iconKey,
  );

  // ==========================================================================
  // A. MODEL + DECODER
  // ==========================================================================
  group('A. decoding icon_key', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'id': 'c1',
      'organization_id': scope.organizationId,
      'restaurant_id': scope.restaurantId,
      'branch_id': null,
      'name': 'Drinks',
      'display_order': 1,
      'is_active': true,
      ...extra,
    };

    test('A1. a valid key is read', () {
      expect(
        MenuCategory.fromJson(row({'icon_key': 'coffee'})).iconKey,
        'coffee',
      );
    });

    test('A2. an ABSENT field decodes to null, not an error', () {
      // list_menu from a server that predates the column omits the key.
      expect(MenuCategory.fromJson(row(const {})).iconKey, isNull);
    });

    test('A3. JSON null decodes to null', () {
      expect(MenuCategory.fromJson(row({'icon_key': null})).iconKey, isNull);
    });

    test('A4. a key this build does not know is preserved RAW', () {
      // Forward compatibility: a newer dashboard chose it, and collapsing it to
      // null here is exactly how the next save would wipe it.
      final decoded = MenuCategory.fromJson(
        row({'icon_key': 'future_food_icon'}),
      );
      expect(decoded.iconKey, 'future_food_icon');
      expect(
        MenuCategoryIcons.isKnownCategoryIconKey(decoded.iconKey),
        isFalse,
      );
    });

    test('A5. a non-string value FAILS CLOSED, like every other optional field '
        'on this model', () {
      // `optString` throws and RpcMenuReadSource turns that into an honest
      // load error. Degrading to null here would hide a malformed payload —
      // and then let the next save persist the hidden default.
      expect(
        () => MenuCategory.fromJson(row({'icon_key': 42})),
        throwsA(isA<FormatException>()),
      );
    });

    test('A6. copyWith carries iconKey through reorder and soft-delete', () {
      final row = category(iconKey: 'coffee');
      expect(row.copyWith(displayOrder: 9).iconKey, 'coffee');
      expect(row.copyWith(deletedAt: DateTime(2026)).iconKey, 'coffee');
    });
  });

  // ==========================================================================
  // B. THE THREE-STATE WRITE INSTRUCTION
  // ==========================================================================
  group('B. MenuIconKeyWrite', () {
    test('B1. the wire values are null / empty / key', () {
      expect(const MenuIconKeyWrite.preserve().wireValue, isNull);
      expect(const MenuIconKeyWrite.reset().wireValue, '');
      expect(const MenuIconKeyWrite.set('coffee').wireValue, 'coffee');
    });

    test('B2. preserve and reset are NOT the same value', () {
      // The whole point of the type: a plain String? invites collapsing these.
      expect(
        const MenuIconKeyWrite.preserve(),
        isNot(const MenuIconKeyWrite.reset()),
      );
    });

    test('B3. applyTo mirrors the server rule', () {
      expect(const MenuIconKeyWrite.preserve().applyTo('coffee'), 'coffee');
      expect(const MenuIconKeyWrite.reset().applyTo('coffee'), isNull);
      expect(const MenuIconKeyWrite.set('tea').applyTo('coffee'), 'tea');
    });

    test('B4. fromSelection: unchanged -> preserve', () {
      expect(
        MenuIconKeyWrite.fromSelection(selected: 'coffee', original: 'coffee'),
        const MenuIconKeyWrite.preserve(),
      );
      expect(
        MenuIconKeyWrite.fromSelection(selected: null, original: null),
        const MenuIconKeyWrite.preserve(),
      );
    });

    test('B5. fromSelection: cleared -> reset, changed -> set', () {
      expect(
        MenuIconKeyWrite.fromSelection(selected: null, original: 'coffee'),
        const MenuIconKeyWrite.reset(),
      );
      expect(
        MenuIconKeyWrite.fromSelection(selected: 'tea', original: 'coffee'),
        const MenuIconKeyWrite.set('tea'),
      );
      expect(
        MenuIconKeyWrite.fromSelection(selected: 'tea', original: null),
        const MenuIconKeyWrite.set('tea'),
      );
    });

    test('B6. an UNCHANGED unknown key resolves to preserve — it is never '
        're-sent by a build that cannot draw it', () {
      expect(
        MenuIconKeyWrite.fromSelection(
          selected: 'future_food_icon',
          original: 'future_food_icon',
        ),
        const MenuIconKeyWrite.preserve(),
      );
    });
  });

  // ==========================================================================
  // C. THE STORE MIRRORS THE SERVER
  // ==========================================================================
  group('C. in-memory store', () {
    test(
      'C1. create with a key stores it; create without stays null',
      () async {
        final store = InMemoryMenuStore();
        await store.upsertCategory(
          scope: scope,
          name: 'Drinks',
          iconKey: const MenuIconKeyWrite.set('coffee'),
        );
        await store.upsertCategory(scope: scope, name: 'Food');
        final snapshot = await store.load(scope);
        expect(
          snapshot.categories.firstWhere((c) => c.name == 'Drinks').iconKey,
          'coffee',
        );
        expect(
          snapshot.categories.firstWhere((c) => c.name == 'Food').iconKey,
          isNull,
        );
      },
    );

    test('C2. an edit that omits the icon PRESERVES it', () async {
      final store = InMemoryMenuStore();
      final created = await store.upsertCategory(
        scope: scope,
        name: 'Drinks',
        iconKey: const MenuIconKeyWrite.set('coffee'),
      );
      final id = created.fold((r) => r.id, (_) => throw StateError('create'));
      await store.upsertCategory(scope: scope, id: id, name: 'Renamed');
      final snapshot = await store.load(scope);
      final row = snapshot.categories.firstWhere((c) => c.id == id);
      expect(row.name, 'Renamed');
      expect(row.iconKey, 'coffee', reason: 'a rename must not wipe the icon');
    });

    test('C3. reset clears it; set replaces it', () async {
      final store = InMemoryMenuStore();
      final created = await store.upsertCategory(
        scope: scope,
        name: 'Drinks',
        iconKey: const MenuIconKeyWrite.set('coffee'),
      );
      final id = created.fold((r) => r.id, (_) => throw StateError('create'));

      await store.upsertCategory(
        scope: scope,
        id: id,
        name: 'Drinks',
        iconKey: const MenuIconKeyWrite.set('tea'),
      );
      expect(
        (await store.load(
          scope,
        )).categories.firstWhere((c) => c.id == id).iconKey,
        'tea',
      );

      await store.upsertCategory(
        scope: scope,
        id: id,
        name: 'Drinks',
        iconKey: const MenuIconKeyWrite.reset(),
      );
      expect(
        (await store.load(
          scope,
        )).categories.firstWhere((c) => c.id == id).iconKey,
        isNull,
      );
    });

    test('C4. an active toggle and a REORDER both preserve the icon', () async {
      final store = InMemoryMenuStore();
      final a = await store.upsertCategory(
        scope: scope,
        name: 'A',
        iconKey: const MenuIconKeyWrite.set('coffee'),
      );
      final b = await store.upsertCategory(
        scope: scope,
        name: 'B',
        iconKey: const MenuIconKeyWrite.set('pizza'),
      );
      final idA = a.fold((r) => r.id, (_) => throw StateError('a'));
      final idB = b.fold((r) => r.id, (_) => throw StateError('b'));

      await store.upsertCategory(
        scope: scope,
        id: idA,
        name: 'A',
        isActive: false,
      );
      await store.reorder(
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        branchId: scope.branchId,
        entity: MenuEntityType.category,
        orderedIds: [idB, idA],
      );

      final rows = (await store.load(scope)).categories;
      // The headline promise of the whole ticket: once chosen, an icon is
      // immune to the ordering that used to decide it.
      expect(rows.firstWhere((c) => c.id == idA).iconKey, 'coffee');
      expect(rows.firstWhere((c) => c.id == idB).iconKey, 'pizza');
      expect(rows.firstWhere((c) => c.id == idA).isActive, isFalse);
    });
  });

  // ==========================================================================
  // D. THE RPC WRITER SENDS THE RIGHT WIRE VALUE
  // ==========================================================================
  group('D. RPC writer payload', () {
    Future<Object?> capture(MenuIconKeyWrite iconKey) async {
      final transport = _FakeTransport();
      await RpcMenuWriter(transport).upsertCategory(
        scope: scope,
        id: 'c1',
        name: 'Drinks',
        iconKey: iconKey,
      );
      return transport.lastParams?['p_icon_key'];
    }

    test('D1. preserve sends null', () async {
      expect(await capture(const MenuIconKeyWrite.preserve()), isNull);
    });

    test('D2. reset sends the empty string', () async {
      expect(await capture(const MenuIconKeyWrite.reset()), '');
    });

    test('D3. set sends the exact registry key — never a Material name or '
        'codepoint', () async {
      final sent = await capture(const MenuIconKeyWrite.set('ice_cream'));
      expect(sent, 'ice_cream');
      expect(sent.toString(), isNot(contains('Icons.')));
      expect(int.tryParse(sent.toString()), isNull);
    });

    test('D4. the default is preserve — a caller that knows nothing about '
        'icons cannot clear one', () async {
      final transport = _FakeTransport();
      await RpcMenuWriter(
        transport,
      ).upsertCategory(scope: scope, id: 'c1', name: 'Drinks');
      expect(transport.lastParams?.containsKey('p_icon_key'), isTrue);
      expect(transport.lastParams?['p_icon_key'], isNull);
    });
  });

  // ==========================================================================
  // E. THE PICKER
  // ==========================================================================
  group('E. picker filtering', () {
    String enName(String key) => _EnNames.of(key);

    test('E1. an empty query returns all 49, in registry order', () {
      final all = filterMenuCategoryIcons('', enName);
      expect(all, hasLength(49));
      expect(all.first.key, MenuCategoryIcons.all.first.key);
    });

    test('E2. matches the localized name', () {
      expect(
        filterMenuCategoryIcons('coffee', enName).map((d) => d.key),
        contains('coffee'),
      );
    });

    test('E3. matches the stable key', () {
      expect(
        filterMenuCategoryIcons('ice_cream', enName).map((d) => d.key),
        contains('ice_cream'),
      );
    });

    test('E4. matches a search token the label does not contain', () {
      // "sandwich" is nowhere in the burger label or key.
      final hits = filterMenuCategoryIcons(
        'sandwich',
        enName,
      ).map((d) => d.key);
      expect(hits, contains('burger'));
    });

    test('E5. no match returns empty, never throws', () {
      expect(filterMenuCategoryIcons('zzzzzz', enName), isEmpty);
    });
  });

  // ==========================================================================
  // F. FORM + TILE + END-TO-END THROUGH THE REAL SCREEN
  // ==========================================================================
  group('F. the real menu screen', () {
    Future<AppLocalizations> pump(
      WidgetTester tester,
      InMemoryMenuStore store, {
      Locale locale = const Locale('en'),
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late AppLocalizations l10n;
      await tester.pumpWidget(
        ProviderScope(
          overrides: menuFeatureOverrides(
            scope: scope,
            readSource: store,
            writer: store,
          ),
          child: MaterialApp(
            locale: locale,
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

    Future<void> openEdit(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuEditAction).last);
      await tester.pumpAndSettle();
    }

    InMemoryMenuStore storeWith(String? iconKey) =>
        InMemoryMenuStore(categories: [category(iconKey: iconKey)]);

    testWidgets('F1. the tile shows the chosen glyph', (tester) async {
      final store = storeWith('coffee');
      await pump(tester, store);
      expect(find.byIcon(Icons.local_cafe), findsWidgets);
      expect(find.byIcon(Icons.local_dining_outlined), findsNothing);
    });

    testWidgets('F2. an unset key keeps the neutral dashboard default', (
      tester,
    ) async {
      await pump(tester, storeWith(null));
      expect(find.byIcon(Icons.local_dining_outlined), findsWidgets);
    });

    testWidgets('F3. an UNKNOWN key falls back neutrally and never shows the '
        'raw key to the owner', (tester) async {
      await pump(tester, storeWith('future_food_icon'));
      expect(find.byIcon(Icons.local_dining_outlined), findsWidgets);
      expect(find.textContaining('future_food_icon'), findsNothing);
    });

    testWidgets('F4. the form opens on Automatic for a category with no icon', (
      tester,
    ) async {
      final store = storeWith(null);
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      expect(find.text(l10n.menuCategoryIconAutomatic), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-category-icon-reset')),
        findsNothing,
      );
    });

    testWidgets('F5. the form previews a known icon and offers Reset', (
      tester,
    ) async {
      final store = storeWith('coffee');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      expect(find.text(l10n.menuCategoryIconName('coffee')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-category-icon-reset')),
        findsOneWidget,
      );
    });

    testWidgets('F6. the form labels an unknown key as a custom icon', (
      tester,
    ) async {
      final store = storeWith('future_food_icon');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      expect(find.text(l10n.menuCategoryIconCustom), findsOneWidget);
      expect(find.textContaining('future_food_icon'), findsNothing);
    });

    testWidgets(
      'F7. pick an icon -> save -> it persists and the tile updates',
      (tester) async {
        final store = storeWith(null);
        final l10n = await pump(tester, store);
        await openEdit(tester, l10n);

        await tester.tap(
          find.byKey(const ValueKey('menu-category-icon-change')),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.menuCategoryIconPickerTitle), findsOneWidget);
        // Narrow to the target first: later groups sit below the fold of the
        // picker's scroll view, exactly as they do for a real owner.
        await tester.enterText(
          find.byKey(const ValueKey('menu-category-icon-search')),
          l10n.menuCategoryIconName('pizza'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('menu-category-icon-pizza')),
        );
        await tester.pumpAndSettle();

        // The preview updated locally; nothing is written until Save.
        expect(find.text(l10n.menuCategoryIconName('pizza')), findsOneWidget);
        expect(
          (await store.load(scope)).categories.first.iconKey,
          isNull,
          reason: 'picking must not write',
        );

        await tester.tap(find.text(l10n.menuSaveAction));
        await tester.pumpAndSettle();
        expect((await store.load(scope)).categories.first.iconKey, 'pizza');
        expect(find.byIcon(Icons.local_pizza), findsWidgets);
      },
    );

    testWidgets('F8. Cancel in the picker leaves the selection alone', (
      tester,
    ) async {
      final store = storeWith('coffee');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-category-icon-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuCancelAction).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.menuCategoryIconName('coffee')), findsOneWidget);
    });

    testWidgets('F9. DATA LOSS GUARD — renaming without touching the icon '
        'preserves it', (tester) async {
      final store = storeWith('coffee');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-name')),
        'Renamed',
      );
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();

      final row = (await store.load(scope)).categories.first;
      expect(row.name, 'Renamed');
      expect(row.iconKey, 'coffee');
    });

    testWidgets('F10. DATA LOSS GUARD — an unrelated save preserves an '
        'UNKNOWN key', (tester) async {
      final store = storeWith('future_food_icon');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-name')),
        'Renamed',
      );
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      expect(
        (await store.load(scope)).categories.first.iconKey,
        'future_food_icon',
      );
    });

    testWidgets('F11. Reset clears the stored key', (tester) async {
      final store = storeWith('coffee');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-category-icon-reset')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.menuCategoryIconAutomatic), findsOneWidget);
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      expect((await store.load(scope)).categories.first.iconKey, isNull);
    });

    testWidgets('F12. an owner may replace an unknown key with a known one', (
      tester,
    ) async {
      final store = storeWith('future_food_icon');
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-category-icon-change')));
      await tester.pumpAndSettle();
      // The unknown current value is offered as a selected tile rather than
      // silently dropped.
      expect(
        find.byKey(const ValueKey('menu-category-icon-custom')),
        findsOneWidget,
      );
      // Later groups sit below the fold; search to reach the target, as an
      // owner would.
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-icon-search')),
        l10n.menuCategoryIconName('burger'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-category-icon-burger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      expect((await store.load(scope)).categories.first.iconKey, 'burger');
    });

    testWidgets('F13. creating a category defaults to Automatic', (
      tester,
    ) async {
      final store = InMemoryMenuStore();
      final l10n = await pump(tester, store);
      await tester.tap(find.text(l10n.menuAddCategory).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.menuCategoryIconAutomatic), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('menu-category-name')),
        'Fresh',
      );
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      expect((await store.load(scope)).categories.single.iconKey, isNull);
    });

    testWidgets('F14. a failed write does not leave the UI claiming success', (
      tester,
    ) async {
      final store = InMemoryMenuStore(
        categories: [category(iconKey: 'coffee')],
        readOnly: true,
      );
      final l10n = await pump(tester, store);
      await openEdit(tester, l10n);
      await tester.tap(find.byKey(const ValueKey('menu-category-icon-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.menuSaveAction));
      await tester.pumpAndSettle();
      // The dialog stays open on failure and the store is untouched.
      expect(find.text(l10n.menuSaveAction), findsOneWidget);
      expect((await store.load(scope)).categories.first.iconKey, 'coffee');
    });

    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets('F15-${locale.languageCode}. the picker renders without '
          'overflow and searches in this locale', (tester) async {
        final store = storeWith('coffee');
        final l10n = await pump(tester, store, locale: locale);
        await openEdit(tester, l10n);
        await tester.tap(
          find.byKey(const ValueKey('menu-category-icon-change')),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.menuCategoryIconPickerTitle), findsOneWidget);
        expect(find.text(l10n.menuCategoryIconAutomatic), findsWidgets);

        // Search using this locale's own label for pizza.
        await tester.enterText(
          find.byKey(const ValueKey('menu-category-icon-search')),
          l10n.menuCategoryIconName('pizza'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('menu-category-icon-pizza')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('menu-category-icon-search')),
          'zzzzzz',
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.menuCategoryIconNoResults), findsOneWidget);
      });
    }
  });
}

/// The repo convention: fake the SyncRpcTransport seam, never the Supabase SDK.
class _FakeTransport implements SyncRpcTransport {
  Map<String, dynamic>? lastParams;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    lastParams = params;
    return const {
      'ok': true,
      'entity': 'menu_category',
      'id': 'c1',
      'action': 'updated',
    };
  }
}

/// English labels for the pure filter tests, so they need no widget tree.
abstract final class _EnNames {
  static String of(String key) => switch (key) {
    'coffee' => 'Coffee',
    'ice_cream' => 'Ice cream',
    'burger' => 'Burger',
    'pizza' => 'Pizza',
    _ => key,
  };
}
