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
  });

  final List<DemoCategory> categories;
  final List<DemoMenuItem> items;
  final String currencyCode;

  DemoCategory? categoryOf(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    return null;
  }
}

/// Real mode without a transport/session (or a rejected response) — the POS
/// shows a safe error state instead of a fake menu.
class PosMenuUnavailable implements Exception {
  const PosMenuUnavailable();
}

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

  final currency = (raw['currency_code'] ?? '').toString();
  return PosMenuData(
    categories: categories,
    items: items,
    currencyCode: currency.length == 3 ? currency : kDemoCurrencyCode,
  );
});
