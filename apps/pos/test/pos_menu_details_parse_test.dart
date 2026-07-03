import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// Menu/media sprint (Part C): the REAL pos_menu parse consumes the rich item
/// attributes (item_type / tags / prep_minutes / kitchen_note / attributes) —
/// STORAGE ONLY this part (display lands in later parts). The parse is
/// tolerant: wrong-typed values degrade to unset, never dropping a sellable
/// item, and money handling is untouched (integer minor, skip-not-zero).
/// `sku` is never served to devices, so the POS never parses it.

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

class _MenuTransport implements SyncRpcTransport {
  _MenuTransport(this.items);

  final List<Map<String, dynamic>> items;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    return <String, dynamic>{
      'ok': true,
      'entity': 'menu',
      'currency_code': 'ILS',
      'categories': [
        {'id': 'cat-1', 'name': 'Food', 'display_order': 1},
      ],
      'items': items,
      'sizes': const [],
      'variants': const [],
      'modifiers': const [],
      'modifier_options': const [],
      'server_ts': '2026-07-03T09:00:00Z',
    };
  }
}

ProviderContainer _container(List<Map<String, dynamic>> items) {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_MenuTransport(items)),
      posSyncSessionProvider.overrideWithValue(_session),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('parses item_type/tags/prep_minutes/kitchen_note/attributes from the '
      'pos_menu payload', () async {
    final container = _container([
      {
        'id': 'item-1',
        'menu_category_id': 'cat-1',
        'name': 'Rich Burger',
        'base_price_minor': 4200,
        'item_type': 'food',
        'tags': ['spicy', 'popular'],
        'prep_minutes': 12,
        'kitchen_note': 'No onions on the grill.',
        'attributes': {
          'portion_label': 'Single',
          'patty_count': 1,
          'patty_weight_grams': 160,
        },
      },
    ]);

    final menu = await container.read(posMenuProvider.future);
    final burger = menu.items.single;

    expect(burger.priceMinor, 4200); // money handling untouched (D-007)
    expect(burger.itemType, 'food');
    expect(burger.tags, ['spicy', 'popular']);
    expect(burger.prepMinutes, 12);
    expect(burger.kitchenNote, 'No onions on the grill.');
    expect(burger.attributes, {
      'portion_label': 'Single',
      'patty_count': 1,
      'patty_weight_grams': 160,
    });
  });

  test(
    'missing rich keys parse to safe defaults (old backend payloads)',
    () async {
      final container = _container([
        {
          'id': 'item-2',
          'menu_category_id': 'cat-1',
          'name': 'Plain Tea',
          'base_price_minor': 900,
        },
      ]);

      final menu = await container.read(posMenuProvider.future);
      final tea = menu.items.single;

      expect(tea.itemType, isNull);
      expect(tea.tags, isEmpty);
      expect(tea.prepMinutes, isNull);
      expect(tea.kitchenNote, isNull);
      expect(tea.attributes, isEmpty);
    },
  );

  test(
    'wrong-typed rich values degrade to unset WITHOUT dropping the item',
    () async {
      final container = _container([
        {
          'id': 'item-3',
          'menu_category_id': 'cat-1',
          'name': 'Odd Row',
          'base_price_minor': 1000,
          'item_type': 7,
          'tags': 'spicy', // not a list
          'prep_minutes': -3, // negative — never trusted
          'kitchen_note': 42,
          'attributes': ['not', 'an', 'object'],
        },
      ]);

      final menu = await container.read(posMenuProvider.future);
      final odd = menu.items.single; // still sellable

      expect(odd.priceMinor, 1000);
      expect(odd.itemType, isNull);
      expect(odd.tags, isEmpty);
      expect(odd.prepMinutes, isNull);
      expect(odd.kitchenNote, isNull);
      expect(odd.attributes, isEmpty);
    },
  );

  test('mixed-type tags keep only the string entries', () async {
    final container = _container([
      {
        'id': 'item-4',
        'menu_category_id': 'cat-1',
        'name': 'Mixed Tags',
        'base_price_minor': 1500,
        'tags': ['vegetarian', 3, null, 'new'],
      },
    ]);

    final menu = await container.read(posMenuProvider.future);
    expect(menu.items.single.tags, ['vegetarian', 'new']);
  });

  test('the demo Cheeseburger carries sensible rich values (later parts demo '
      'them) and the demo stays otherwise unchanged', () {
    final cheeseburger = kDemoMenu.singleWhere((i) => i.id == 'cheeseburger');
    expect(cheeseburger.itemType, 'food');
    expect(cheeseburger.tags, ['popular']);
    expect(cheeseburger.prepMinutes, 12);
    expect(cheeseburger.kitchenNote, isNotEmpty);
    expect(cheeseburger.attributes['portion_label'], 'Single');
    expect(cheeseburger.attributes['patty_count'], 1);
    expect(cheeseburger.attributes['patty_weight_grams'], 160);

    // The FIRST grid item stays the plain, modifier-free Classic Burger with
    // its pinned price — the load-bearing test-corpus contract.
    expect(kDemoMenu.first.name, 'Classic Burger');
    expect(kDemoMenu.first.priceMinor, 4200);
    expect(kDemoMenu.first.tags, isEmpty);
    expect(kDemoMenu.first.attributes, isEmpty);
  });
}
