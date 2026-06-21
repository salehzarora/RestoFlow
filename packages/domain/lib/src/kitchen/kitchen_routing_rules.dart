/// Pure-Dart, injectable kitchen routing rules (RF-033): the "configured rule"
/// that maps an order item to a station. Mirrors the canonical
/// `menu_items.default_station_id` mechanism (DOMAIN_MODEL.md §4.2) WITHOUT
/// touching the menu Drift schema — it is a fixture supplied at routing time.
///
/// Precedence per item: (1) explicit item rule -> (2) default station ->
/// (3) unroutable. Category-based routing is NOT modeled in RF-033. Rules carry
/// no tenant fields — tenant scope comes from the routed `LocalOrder`.
library;

class KitchenRoutingRules {
  KitchenRoutingRules({
    Map<String, String> itemStation = const {},
    this.defaultStationId,
  }) : itemStation = Map.unmodifiable(itemStation);

  /// Explicit `menuItemId -> stationId` rules (highest precedence).
  final Map<String, String> itemStation;

  /// Optional fallback station applied when no explicit item rule matches.
  final String? defaultStationId;

  /// Resolves the station for [menuItemId], or null if the item is unroutable
  /// (no explicit rule and no default station).
  String? stationFor(String menuItemId) =>
      itemStation[menuItemId] ?? defaultStationId;
}
