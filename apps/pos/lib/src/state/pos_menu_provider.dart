import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/demo_menu.dart';
import 'pos_session.dart';

/// The menu the POS sells from: categories + items + the currency.
///
/// DEMO mode (default): the in-memory demo menu, unchanged. REAL mode: the
/// backend menu via `public.pos_menu` (session-scoped; prices integer minor —
/// D-007), fetched ONLY once an authenticated PIN session exists. Fail-closed:
/// real mode with no session/transport throws [PosMenuUnavailable] — the POS
/// never sells from a fake menu in real mode.
class PosMenuData {
  const PosMenuData({
    required this.categories,
    required this.items,
    required this.currencyCode,
    this.modifierGroups = const <PosModifierGroup>[],
  });

  final List<DemoCategory> categories;
  final List<DemoMenuItem> items;
  final String currencyCode;

  /// Modifier groups across all items (demo-readiness sprint) — burger
  /// toppings, doneness, extras. Price deltas are integer minor units (D-007;
  /// SIGNED — a delta may be free or paid).
  final List<PosModifierGroup> modifierGroups;

  DemoCategory? categoryOf(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  /// The (display-ordered) modifier groups attached to [menuItemId].
  List<PosModifierGroup> groupsForItem(String menuItemId) => [
    for (final group in modifierGroups)
      if (group.menuItemId == menuItemId && group.options.isNotEmpty) group,
  ];
}

/// One selectable option inside a [PosModifierGroup]. [priceDeltaMinor] is a
/// SIGNED integer minor-unit delta (0 = free).
class PosModifierOption {
  const PosModifierOption({
    required this.id,
    required this.name,
    required this.priceDeltaMinor,
  });

  final String id;
  final String name;
  final int priceDeltaMinor;
}

/// A modifier group on a menu item (mirrors the RF-109 `modifiers` +
/// `modifier_options` rows the backend serves through `pos_menu`).
class PosModifierGroup {
  const PosModifierGroup({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.options,
    this.singleSelect = false,
    this.minSelect = 0,
    this.maxSelect,
    this.isRequired = false,
  });

  final String id;
  final String menuItemId;
  final String name;
  final List<PosModifierOption> options;

  /// `selection_type == 'single'` — exactly one choice (radio behaviour).
  final bool singleSelect;
  final int minSelect;
  final int? maxSelect;
  final bool isRequired;

  /// The minimum selections the cashier must make before adding the item.
  int get effectiveMin =>
      singleSelect ? 1 : (isRequired && minSelect == 0 ? 1 : minSelect);

  /// The maximum selections allowed (single => 1; null => unlimited).
  int? get effectiveMax => singleSelect ? 1 : maxSelect;
}

/// Real mode without a transport/session (or a rejected response) — the POS
/// shows a safe error state instead of a fake menu.
class PosMenuUnavailable implements Exception {
  const PosMenuUnavailable();
}

/// Demo modifier groups (demo-readiness sprint) so the modifier flow is
/// visible without a backend (attached to the Cheeseburger so the FIRST
/// grid item stays a plain one-tap add): toppings (free + paid), a REQUIRED
/// single-select doneness, and paid extras. Names are demo DATA (not chrome).
const List<PosModifierGroup> kDemoModifierGroups = <PosModifierGroup>[
  PosModifierGroup(
    id: 'demo-mod-toppings',
    menuItemId: 'cheeseburger',
    name: 'Toppings',
    options: [
      PosModifierOption(
        id: 'demo-opt-onion',
        name: 'Onion',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-lettuce',
        name: 'Lettuce',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-tomato',
        name: 'Tomato',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-cheese',
        name: 'Cheese',
        priceDeltaMinor: 300,
      ),
    ],
  ),
  PosModifierGroup(
    id: 'demo-mod-doneness',
    menuItemId: 'cheeseburger',
    name: 'Doneness',
    singleSelect: true,
    isRequired: true,
    options: [
      PosModifierOption(id: 'demo-opt-rare', name: 'Rare', priceDeltaMinor: 0),
      PosModifierOption(
        id: 'demo-opt-medium',
        name: 'Medium',
        priceDeltaMinor: 0,
      ),
      PosModifierOption(
        id: 'demo-opt-well',
        name: 'Well done',
        priceDeltaMinor: 0,
      ),
    ],
  ),
  PosModifierGroup(
    id: 'demo-mod-extras',
    menuItemId: 'cheeseburger',
    name: 'Extras',
    maxSelect: 2,
    options: [
      PosModifierOption(
        id: 'demo-opt-extra-cheese',
        name: 'Extra cheese',
        priceDeltaMinor: 300,
      ),
      PosModifierOption(
        id: 'demo-opt-extra-patty',
        name: 'Extra patty',
        priceDeltaMinor: 900,
      ),
    ],
  ),
];

/// A stable, data-driven icon/colour palette for REAL categories (the backend
/// carries no iconography). Assigned by category order — presentation only.
const List<(IconData, Color)> _kCategoryPalette = [
  (Icons.lunch_dining, Color(0xFFE8590C)),
  (Icons.dinner_dining, Color(0xFF0F766E)),
  (Icons.fastfood, Color(0xFFB45309)),
  (Icons.local_bar, Color(0xFF1D4ED8)),
  (Icons.local_cafe, Color(0xFF6F4E37)),
  (Icons.icecream, Color(0xFF9D174D)),
];

final posMenuProvider = FutureProvider<PosMenuData>((ref) async {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) {
    return const PosMenuData(
      categories: kDemoCategories,
      items: kDemoMenu,
      currencyCode: kDemoCurrencyCode,
      modifierGroups: kDemoModifierGroups,
    );
  }
  final transport = ref.watch(posAuthTransportProvider);
  final session = ref.watch(posSyncSessionProvider);
  if (transport == null || session == null) {
    throw const PosMenuUnavailable();
  }
  final Object? raw;
  try {
    raw = await transport.invoke('pos_menu', <String, dynamic>{
      'p_pin_session_id': session.pinSessionId,
      'p_device_id': session.deviceId,
    });
  } on SyncTransportException {
    throw const PosMenuUnavailable();
  }
  if (raw is! Map || raw['ok'] != true) throw const PosMenuUnavailable();

  final categories = <DemoCategory>[];
  var paletteIndex = 0;
  final names = <String, String>{};
  for (final row in (raw['categories'] as List?) ?? const []) {
    if (row is! Map) continue;
    final id = (row['id'] ?? '').toString();
    final name = (row['name'] ?? '').toString();
    final (icon, color) =
        _kCategoryPalette[paletteIndex % _kCategoryPalette.length];
    paletteIndex++;
    names[id] = name;
    categories.add(DemoCategory(id: id, name: name, icon: icon, color: color));
  }

  final items = <DemoMenuItem>[];
  for (final row in (raw['items'] as List?) ?? const []) {
    if (row is! Map) continue;
    // base_price_minor is present for cashier/manager sessions (a POS is never
    // a kitchen_staff surface); if it is ever absent, skip the item rather
    // than inventing a zero price.
    final price = row['base_price_minor'];
    if (price is! int) continue;
    final categoryId = (row['menu_category_id'] ?? '').toString();
    items.add(
      DemoMenuItem(
        id: (row['id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        priceMinor: price,
        categoryId: categoryId,
        categoryName: names[categoryId] ?? '',
      ),
    );
  }

  // Modifier groups + their options (pos_menu v2, demo-readiness sprint).
  // price_delta_minor is present for cashier/manager sessions; an option
  // without one is skipped rather than sold at an invented price.
  final optionsByGroup = <String, List<PosModifierOption>>{};
  for (final row in (raw['modifier_options'] as List?) ?? const []) {
    if (row is! Map) continue;
    final delta = row['price_delta_minor'];
    if (delta is! int) continue;
    final groupId = (row['modifier_id'] ?? '').toString();
    (optionsByGroup[groupId] ??= <PosModifierOption>[]).add(
      PosModifierOption(
        id: (row['id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        priceDeltaMinor: delta,
      ),
    );
  }
  final groups = <PosModifierGroup>[];
  for (final row in (raw['modifiers'] as List?) ?? const []) {
    if (row is! Map) continue;
    final id = (row['id'] ?? '').toString();
    final minSelect = row['min_select'];
    final maxSelect = row['max_select'];
    groups.add(
      PosModifierGroup(
        id: id,
        menuItemId: (row['menu_item_id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        options: optionsByGroup[id] ?? const <PosModifierOption>[],
        singleSelect: row['selection_type'] == 'single',
        minSelect: minSelect is int ? minSelect : 0,
        maxSelect: maxSelect is int ? maxSelect : null,
        isRequired: row['is_required'] == true,
      ),
    );
  }

  final currency = (raw['currency_code'] ?? '').toString();
  return PosMenuData(
    categories: categories,
    items: items,
    currencyCode: currency.length == 3 ? currency : kDemoCurrencyCode,
    modifierGroups: groups,
  );
});
