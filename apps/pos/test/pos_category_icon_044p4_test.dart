import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_codec.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/widgets/category_chips.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MENU-CATEGORY-ICON-PICKER-OPS-044 Phase 4 — the POS finally consumes the
/// owner's choice.
///
/// The bug this closes: a category's icon was picked purely by its POSITION in
/// the fetched list, so drag-reordering categories in the Dashboard silently
/// reassigned every glyph — a Drinks category could end up wearing the burger.
///
/// Two invariants carry the whole phase and are asserted from several angles:
///   * a CHOSEN icon follows the category, not the slot;
///   * an unset or unrecognised key changes NOTHING about today's rendering,
///     and COLOUR stays positional in every case.
void main() {
  const session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

  // ==========================================================================
  // A. THE ONE RESOLUTION RULE
  // ==========================================================================
  group('A. resolvePosCategoryStyle', () {
    test('A1. a known key wins the icon; colour stays positional', () {
      for (var index = 0; index < kPosCategoryPalette.length; index++) {
        final style = resolvePosCategoryStyle(index: index, iconKey: 'coffee');
        expect(style.icon, Icons.local_cafe, reason: 'index $index');
        expect(
          style.color,
          kPosCategoryPalette[index].$2,
          reason: 'colour must still come from the slot at index $index',
        );
      }
    });

    test('A2. null falls back to the legacy pair at every slot', () {
      for (var index = 0; index < kPosCategoryPalette.length * 2; index++) {
        final slot = kPosCategoryPalette[index % kPosCategoryPalette.length];
        final style = resolvePosCategoryStyle(index: index, iconKey: null);
        expect(style.icon, slot.$1, reason: 'index $index');
        expect(style.color, slot.$2, reason: 'index $index');
      }
    });

    test('A3. a key only a NEWER build knows falls back — never blank', () {
      final style = resolvePosCategoryStyle(
        index: 3,
        iconKey: 'future_food_icon',
      );
      expect(style.icon, kPosCategoryPalette[3].$1);
      expect(style.color, kPosCategoryPalette[3].$2);
    });

    test('A4. the wraparound is unchanged for unset keys', () {
      expect(
        resolvePosCategoryStyle(index: 6, iconKey: null).icon,
        resolvePosCategoryStyle(index: 0, iconKey: null).icon,
      );
    });

    test('A5. REORDER IMMUNITY — a chosen glyph follows the category', () {
      // The headline promise. Same key, four different slots, one glyph.
      final glyphs = <IconData>{
        for (final index in [0, 1, 3, 5, 7])
          resolvePosCategoryStyle(index: index, iconKey: 'pizza').icon,
      };
      expect(glyphs, {Icons.local_pizza});
      // ...while the legacy behaviour it replaced would have produced several.
      final legacy = <IconData>{
        for (final index in [0, 1, 3, 5, 7])
          resolvePosCategoryStyle(index: index, iconKey: null).icon,
      };
      expect(legacy.length, greaterThan(1));
    });
  });

  // ==========================================================================
  // B. THE LIVE pos_menu PARSE
  // ==========================================================================
  group('B. pos_menu parse boundary', () {
    ProviderContainer containerFor(List<Map<String, dynamic>> categories) {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(
            _MenuTransport(categories),
          ),
          posSyncSessionProvider.overrideWithValue(session),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<List<DemoCategory>> parse(
      List<Map<String, dynamic>> categories,
    ) async {
      final menu = await containerFor(categories).read(posMenuProvider.future);
      return menu.categories;
    }

    Map<String, dynamic> cat(String id, {Object? iconKey, int order = 1}) => {
      'id': id,
      'name': id,
      'display_order': order,
      if (iconKey != null) 'icon_key': iconKey,
    };

    test(
      'B1. a known key resolves to the owner glyph and keeps slot colour',
      () async {
        final rows = await parse([cat('drinks', iconKey: 'coffee')]);
        expect(rows.single.icon, Icons.local_cafe);
        expect(rows.single.color, kPosCategoryPalette[0].$2);
        expect(rows.single.iconKey, 'coffee');
      },
    );

    test(
      'B2. an ABSENT icon_key keeps today\'s positional rendering exactly',
      () async {
        final rows = await parse([cat('a'), cat('b'), cat('c')]);
        for (var i = 0; i < rows.length; i++) {
          expect(rows[i].icon, kPosCategoryPalette[i].$1);
          expect(rows[i].color, kPosCategoryPalette[i].$2);
          expect(rows[i].iconKey, isNull);
        }
      },
    );

    test('B3. an explicit JSON null is the same as absent', () async {
      final rows = await parse([
        {'id': 'a', 'name': 'a', 'display_order': 1, 'icon_key': null},
      ]);
      expect(rows.single.icon, kPosCategoryPalette[0].$1);
      expect(rows.single.iconKey, isNull);
    });

    test(
      'B4. an unknown key is kept RAW but renders the legacy glyph',
      () async {
        final rows = await parse([cat('a', iconKey: 'future_food_icon')]);
        expect(rows.single.iconKey, 'future_food_icon');
        expect(rows.single.icon, kPosCategoryPalette[0].$1);
      },
    );

    test('B5. a malformed (non-string) key never crashes the menu', () async {
      // One bad optional field must not drop a sellable category.
      final rows = await parse([cat('a', iconKey: 42), cat('b', order: 2)]);
      expect(rows, hasLength(2));
      expect(rows.first.iconKey, isNull);
      expect(rows.first.icon, kPosCategoryPalette[0].$1);
    });

    test('B6. REORDER IMMUNITY through the real parse', () async {
      // The same category, first at slot 0 and then at slot 3.
      final first = await parse([cat('drinks', iconKey: 'coffee')]);
      final moved = await parse([
        cat('a'),
        cat('b', order: 2),
        cat('c', order: 3),
        cat('drinks', iconKey: 'coffee', order: 4),
      ]);
      final movedDrinks = moved.firstWhere((c) => c.id == 'drinks');
      expect(movedDrinks.icon, first.single.icon);
      expect(movedDrinks.icon, Icons.local_cafe);
      // Colour is allowed to follow the new slot — that is the documented
      // contract, not an accident.
      expect(movedDrinks.color, kPosCategoryPalette[3].$2);
    });

    test(
      'B7. two explicit categories swapping slots keep their own glyphs',
      () async {
        final swapped = await parse([
          cat('food', iconKey: 'pizza'),
          cat('drinks', iconKey: 'coffee', order: 2),
        ]);
        final back = await parse([
          cat('drinks', iconKey: 'coffee'),
          cat('food', iconKey: 'pizza', order: 2),
        ]);
        expect(
          swapped.firstWhere((c) => c.id == 'food').icon,
          Icons.local_pizza,
        );
        expect(back.firstWhere((c) => c.id == 'food').icon, Icons.local_pizza);
        expect(
          swapped.firstWhere((c) => c.id == 'drinks').icon,
          Icons.local_cafe,
        );
        expect(back.firstWhere((c) => c.id == 'drinks').icon, Icons.local_cafe);
      },
    );

    test('B8. a mixed menu resolves each category independently', () async {
      final rows = await parse([
        cat('chosen', iconKey: 'pizza'),
        cat('plain', order: 2),
        cat('future', iconKey: 'future_food_icon', order: 3),
      ]);
      expect(rows[0].icon, Icons.local_pizza);
      expect(rows[1].icon, kPosCategoryPalette[1].$1);
      expect(rows[2].icon, kPosCategoryPalette[2].$1);
    });
  });

  // ==========================================================================
  // C. THE OFFLINE SNAPSHOT CODEC
  // ==========================================================================
  group('C. operational snapshot codec', () {
    PosMenuData menuWith(List<DemoCategory> categories) => PosMenuData(
      categories: categories,
      items: const <DemoMenuItem>[],
      currencyCode: 'ILS',
      modifierGroups: const <PosModifierGroup>[],
    );

    DemoCategory category(String id, int index, {String? iconKey}) {
      final style = resolvePosCategoryStyle(index: index, iconKey: iconKey);
      return DemoCategory(
        id: id,
        name: id,
        icon: style.icon,
        color: style.color,
        iconKey: iconKey,
      );
    }

    test(
      'C1. a chosen key is encoded — and nothing else about the icon is',
      () {
        final encoded = encodePosMenuData(
          menuWith([category('drinks', 0, iconKey: 'coffee')]),
        );
        final row =
            (encoded['categories'] as List).single as Map<String, Object?>;
        expect(row['icon_key'], 'coffee');
        // Never a codepoint, an IconData or a Material name.
        expect(row.keys, unorderedEquals(<String>['id', 'name', 'icon_key']));
        expect(row.values.whereType<int>(), isEmpty);
      },
    );

    test('C2. an unset key writes NO field at all', () {
      final encoded = encodePosMenuData(menuWith([category('drinks', 0)]));
      final row =
          (encoded['categories'] as List).single as Map<String, Object?>;
      expect(row.containsKey('icon_key'), isFalse);
    });

    test('C3. a chosen key round-trips and resolves to the owner glyph', () {
      final decoded = decodePosMenuData(
        encodePosMenuData(menuWith([category('drinks', 0, iconKey: 'coffee')])),
      );
      expect(decoded.categories.single.iconKey, 'coffee');
      expect(decoded.categories.single.icon, Icons.local_cafe);
      expect(decoded.categories.single.color, kPosCategoryPalette[0].$2);
    });

    test('C4. an OLD snapshot with no icon_key still decodes, unchanged', () {
      // Exactly what a snapshot written before this build looks like.
      final legacy = <String, Object?>{
        'currency_code': 'ILS',
        'categories': <Object?>[
          {'id': 'a', 'name': 'a'},
          {'id': 'b', 'name': 'b'},
        ],
        'items': <Object?>[],
        'modifier_groups': <Object?>[],
      };
      final decoded = decodePosMenuData(legacy);
      expect(decoded.categories, hasLength(2));
      for (var i = 0; i < decoded.categories.length; i++) {
        expect(decoded.categories[i].iconKey, isNull);
        expect(decoded.categories[i].icon, kPosCategoryPalette[i].$1);
        expect(decoded.categories[i].color, kPosCategoryPalette[i].$2);
      }
    });

    test('C5. an unknown key survives the round trip and renders the legacy '
        'glyph', () {
      final decoded = decodePosMenuData(
        encodePosMenuData(
          menuWith([category('a', 0, iconKey: 'future_food_icon')]),
        ),
      );
      expect(decoded.categories.single.iconKey, 'future_food_icon');
      expect(decoded.categories.single.icon, kPosCategoryPalette[0].$1);
    });

    test('C6. a malformed stored value degrades to unset, never throws', () {
      final decoded = decodePosMenuData(<String, Object?>{
        'currency_code': 'ILS',
        'categories': <Object?>[
          {'id': 'a', 'name': 'a', 'icon_key': 42},
          {'id': 'b', 'name': 'b', 'icon_key': ''},
        ],
        'items': <Object?>[],
        'modifier_groups': <Object?>[],
      });
      expect(decoded.categories[0].iconKey, isNull);
      expect(decoded.categories[1].iconKey, isNull);
      expect(decoded.categories[0].icon, kPosCategoryPalette[0].$1);
    });

    test('C7. REORDER IMMUNITY survives the snapshot', () {
      final decoded = decodePosMenuData(
        encodePosMenuData(
          menuWith([
            category('a', 0),
            category('b', 1),
            category('c', 2),
            category('drinks', 3, iconKey: 'coffee'),
          ]),
        ),
      );
      expect(decoded.categories.last.icon, Icons.local_cafe);
      expect(decoded.categories.last.color, kPosCategoryPalette[3].$2);
    });

    test(
      'C8. the envelope keys are unchanged — icon_key is purely additive',
      () {
        final encoded = encodePosMenuData(
          menuWith([category('drinks', 0, iconKey: 'coffee')]),
        );
        expect(
          encoded.keys,
          unorderedEquals(<String>[
            'currency_code',
            'categories',
            'items',
            'modifier_groups',
          ]),
        );
      },
    );

    test('C9. schemaVersion is NOT bumped — a cached menu must survive the '
        'upgrade', () {
      // A version change is refused on load, so bumping it would discard every
      // till's snapshot and strand any till that was offline at upgrade time.
      expect(PosOperationalSnapshot.schemaVersion, 1);
    });
  });

  // ==========================================================================
  // D. THE POS SURFACES
  // ==========================================================================
  group('D. rendering surfaces', () {
    DemoCategory build(String id, int index, {String? iconKey}) {
      final style = resolvePosCategoryStyle(index: index, iconKey: iconKey);
      return DemoCategory(
        id: id,
        name: id,
        icon: style.icon,
        color: style.color,
        iconKey: iconKey,
      );
    }

    Future<void> pumpRail(
      WidgetTester tester,
      List<DemoCategory> categories, {
      Locale locale = const Locale('en'),
    }) async {
      // A representative till viewport.
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(body: CategoryChips(categories: categories)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('D1. the REAL chip rail shows the chosen glyph', (
      tester,
    ) async {
      await pumpRail(tester, [
        build('drinks', 0, iconKey: 'coffee'),
        build('food', 1),
      ]);
      expect(find.byIcon(Icons.local_cafe), findsOneWidget);
      expect(find.byIcon(kPosCategoryPalette[1].$1), findsOneWidget);
      // The legacy slot-0 glyph is NOT drawn for the category that overrode it.
      expect(find.byIcon(kPosCategoryPalette[0].$1), findsNothing);
    });

    testWidgets('D2. REORDER IMMUNITY in the real rail', (tester) async {
      await pumpRail(tester, [build('drinks', 0, iconKey: 'coffee')]);
      final before = tester.widget<Icon>(find.byIcon(Icons.local_cafe));

      await pumpRail(tester, [
        build('a', 0),
        build('b', 1),
        build('c', 2),
        build('drinks', 3, iconKey: 'coffee'),
      ]);
      expect(find.byIcon(Icons.local_cafe), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.local_cafe)).icon,
        before.icon,
      );
      // Documented contract: colour is still positional, so it MAY differ. The
      // fixture must actually change slot colour for this to mean anything.
      expect(kPosCategoryPalette[3].$2, isNot(kPosCategoryPalette[0].$2));
    });

    testWidgets('D3. an unset category renders exactly the legacy glyph', (
      tester,
    ) async {
      await pumpRail(tester, [build('a', 0), build('b', 1), build('c', 2)]);
      for (var i = 0; i < 3; i++) {
        expect(find.byIcon(kPosCategoryPalette[i].$1), findsOneWidget);
      }
    });

    testWidgets('D4. an unknown key renders the legacy glyph, never a blank', (
      tester,
    ) async {
      await pumpRail(tester, [build('a', 0, iconKey: 'future_food_icon')]);
      expect(find.byIcon(kPosCategoryPalette[0].$1), findsOneWidget);
    });

    for (final locale in const [Locale('ar'), Locale('he'), Locale('en')]) {
      testWidgets(
        'D5-${locale.languageCode}. the rail renders chosen glyphs without '
        'overflow in this locale',
        (tester) async {
          await pumpRail(tester, [
            build('drinks', 0, iconKey: 'coffee'),
            build('food', 1, iconKey: 'pizza'),
            build('plain', 2),
          ], locale: locale);
          expect(find.byIcon(Icons.local_cafe), findsOneWidget);
          expect(find.byIcon(Icons.local_pizza), findsOneWidget);
          expect(find.byIcon(kPosCategoryPalette[2].$1), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    test('D6. every surface reads the SAME resolved field — no widget looks a '
        'key up for itself', () {
      // categoryById and the item card / modifier sheet all consume
      // DemoCategory.icon; the parse boundary is the only resolver. Guard it
      // at the source so a future widget cannot quietly add a second path.
      final sources = <String>[
        'lib/src/widgets/category_chips.dart',
        'lib/src/widgets/menu_item_card.dart',
        'lib/src/widgets/modifier_selection_sheet.dart',
      ];
      for (final relative in sources) {
        final text = _posSource(relative);
        expect(
          text.contains('MenuCategoryIcons'),
          isFalse,
          reason: '$relative must not resolve an icon key itself',
        );
        expect(
          text.contains('iconKey'),
          isFalse,
          reason: '$relative must read the resolved DemoCategory.icon',
        );
      }
    });
  });

  // ==========================================================================
  // E. THE REAL SNAPSHOT STORE — cold boot and reconnect
  // ==========================================================================
  group('E. cold boot + reconnect through the real store', () {
    const scope = PosSyncScope(
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
      deviceId: 'dev-1',
    );

    DemoCategory build(String id, int index, {String? iconKey}) {
      final style = resolvePosCategoryStyle(index: index, iconKey: iconKey);
      return DemoCategory(
        id: id,
        name: id,
        icon: style.icon,
        color: style.color,
        iconKey: iconKey,
      );
    }

    PosOperationalSnapshot snapshotOf(List<DemoCategory> categories) =>
        PosOperationalSnapshot(
          organizationId: scope.organizationId,
          restaurantId: scope.restaurantId,
          branchId: scope.branchId,
          deviceId: scope.deviceId,
          menu: PosMenuData(
            categories: categories,
            items: const <DemoMenuItem>[],
            currencyCode: 'ILS',
            modifierGroups: const <PosModifierGroup>[],
          ),
          fetchedAt: DateTime.utc(2026, 8, 20, 9),
        );

    Future<PosMenuData> saveThenColdBoot(List<DemoCategory> categories) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SharedPrefsOperationalSnapshotStore().save(
        scope,
        snapshotOf(categories),
      );
      // A COLD BOOT: a brand-new store instance over the same durable bytes.
      final result = await SharedPrefsOperationalSnapshotStore().load(scope);
      expect(result, isA<PosOperationalSnapshotLoaded>());
      return (result as PosOperationalSnapshotLoaded).snapshot.menu;
    }

    test('E1. a chosen icon survives a cold boot', () async {
      final menu = await saveThenColdBoot([
        build('drinks', 0, iconKey: 'coffee'),
      ]);
      expect(menu.categories.single.iconKey, 'coffee');
      expect(menu.categories.single.icon, Icons.local_cafe);
    });

    test('E2. an unset category cold-boots to the legacy glyph', () async {
      final menu = await saveThenColdBoot([build('a', 0), build('b', 1)]);
      expect(menu.categories[0].icon, kPosCategoryPalette[0].$1);
      expect(menu.categories[1].icon, kPosCategoryPalette[1].$1);
      expect(menu.categories.every((c) => c.iconKey == null), isTrue);
    });

    test(
      'E3. an unknown key cold-boots raw and renders the legacy glyph',
      () async {
        final menu = await saveThenColdBoot([
          build('a', 0, iconKey: 'future_food_icon'),
        ]);
        expect(menu.categories.single.iconKey, 'future_food_icon');
        expect(menu.categories.single.icon, kPosCategoryPalette[0].$1);
      },
    );

    test('E4. a chosen icon cold-boots stably from a LATER slot', () async {
      final menu = await saveThenColdBoot([
        build('a', 0),
        build('b', 1),
        build('c', 2),
        build('drinks', 3, iconKey: 'coffee'),
      ]);
      expect(menu.categories.last.icon, Icons.local_cafe);
      expect(menu.categories.last.color, kPosCategoryPalette[3].$2);
    });

    test('E5. RECONNECT — the same key does not flip the glyph', () async {
      final cached = await saveThenColdBoot([
        build('drinks', 0, iconKey: 'coffee'),
      ]);
      // What a fresh pos_menu resolves to for the same category.
      final fresh = resolvePosCategoryStyle(index: 0, iconKey: 'coffee');
      expect(fresh.icon, cached.categories.single.icon);
      expect(fresh.color, cached.categories.single.color);
    });

    test('E6. RECONNECT — a CHANGED key updates the glyph', () async {
      final cached = await saveThenColdBoot([
        build('drinks', 0, iconKey: 'coffee'),
      ]);
      expect(cached.categories.single.icon, Icons.local_cafe);
      expect(
        resolvePosCategoryStyle(index: 0, iconKey: 'pizza').icon,
        Icons.local_pizza,
      );
    });

    test('E7. an envelope written with NO chosen key carries no field and '
        'still loads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SharedPrefsOperationalSnapshotStore().save(
        scope,
        snapshotOf([build('a', 0), build('b', 1)]),
      );
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().firstWhere((k) => k.contains('snapshot'));
      expect(prefs.getString(key)!.contains('icon_key'), isFalse);
      expect(
        await SharedPrefsOperationalSnapshotStore().load(scope),
        isA<PosOperationalSnapshotLoaded>(),
      );
    });
  });
}

/// Reads a POS source file, walking up so the suite runs from either the
/// package root or the repository root.
String _posSource(String relative) {
  const roots = <String>['', 'apps/pos/', '../', '../../apps/pos/'];
  for (final root in roots) {
    final file = _file('$root$relative');
    if (file != null) return file;
  }
  fail('could not locate $relative');
}

String? _file(String path) {
  try {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  } catch (_) {
    return null;
  }
}

class _MenuTransport implements SyncRpcTransport {
  _MenuTransport(this.categories);

  final List<Map<String, dynamic>> categories;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    return <String, dynamic>{
      'ok': true,
      'entity': 'menu',
      'currency_code': 'ILS',
      'categories': categories,
      'items': const <Map<String, dynamic>>[],
      'sizes': const [],
      'variants': const [],
      'modifiers': const [],
      'modifier_options': const [],
      'server_ts': '2026-08-20T09:00:00Z',
    };
  }
}
