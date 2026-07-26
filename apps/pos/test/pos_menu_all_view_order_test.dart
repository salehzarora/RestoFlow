import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/state/menu_filter.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// MENU-ORDER-001 (Codex #12): the POS browse menu must present categories AND
/// items in the owner's DASHBOARD order — category display_order, then item
/// display_order within the category. Before the fix the "All" view rendered raw
/// pos_menu RPC row order, so a rank-1 item in one category could interleave
/// ahead of a rank-2 item in another, mixing categories.

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

/// A pos_menu payload with categories + items DELIBERATELY out of Dashboard order.
/// Dashboard config: Meals(1)[Burger(1), Fries(2)], Drinks(2)[Cola(1), Water(2)].
class _ScrambledMenuTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    return <String, dynamic>{
      'ok': true,
      'entity': 'menu',
      'currency_code': 'ILS',
      // Categories out of order (Drinks before Meals).
      'categories': [
        {'id': 'drinks', 'name': 'Drinks', 'display_order': 2},
        {'id': 'meals', 'name': 'Meals', 'display_order': 1},
      ],
      // Items shuffled across categories + within them.
      'items': [
        {
          'id': 'water',
          'menu_category_id': 'drinks',
          'name': 'Water',
          'base_price_minor': 500,
          'display_order': 2,
        },
        {
          'id': 'fries',
          'menu_category_id': 'meals',
          'name': 'Fries',
          'base_price_minor': 1500,
          'display_order': 2,
        },
        {
          'id': 'cola',
          'menu_category_id': 'drinks',
          'name': 'Cola',
          'base_price_minor': 1000,
          'display_order': 1,
        },
        {
          'id': 'burger',
          'menu_category_id': 'meals',
          'name': 'Burger',
          'base_price_minor': 4200,
          'display_order': 1,
        },
      ],
      'sizes': const [],
      'variants': const [],
      'modifiers': const [],
      'modifier_options': const [],
      'server_ts': '2026-07-31T09:00:00Z',
    };
  }
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_ScrambledMenuTransport()),
      posSyncSessionProvider.overrideWithValue(_session),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('categories are presented in Dashboard display_order', () async {
    final menu = await _container().read(posMenuProvider.future);
    expect(
      [for (final c in menu.categories) c.id],
      const ['meals', 'drinks'],
      reason: 'Meals(1) before Drinks(2), not RPC row order',
    );
  });

  test('the ALL view groups items by category rank, then item rank', () async {
    final menu = await _container().read(posMenuProvider.future);
    // filterMenuItems with the "All" sentinel is exactly what the grid renders.
    final all = filterMenuItems(menu.items, kAllCategoriesId, '');
    expect(
      [for (final i in all) i.name],
      const ['Burger', 'Fries', 'Cola', 'Water'],
      reason:
          'category order first (Meals then Drinks), item order within — '
          'NOT interleaved by item rank alone',
    );
  });

  test(
    'a single-category view orders items by their item display_order',
    () async {
      final menu = await _container().read(posMenuProvider.future);
      final meals = filterMenuItems(menu.items, 'meals', '');
      expect([for (final i in meals) i.name], const ['Burger', 'Fries']);
    },
  );
}
