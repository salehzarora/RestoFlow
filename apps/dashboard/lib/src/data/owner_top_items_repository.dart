/// DASHBOARD-VISUAL-RANGE-REFRESH-F3 — the top-selling-items seam.
///
/// A SIBLING of [OwnerReportsRepository] and [OwnerSalesSeriesRepository], not an
/// extension of either: it answers a third question ("what sold best in this
/// window") from a third RPC, and folding it into the report would make every
/// Overview load pay for a call the card may not even be showing.
library;

import '../analytics/analytics_range.dart';
import '../analytics/analytics_window.dart';
import '../analytics/dashboard_analytics_scope.dart';
import '../analytics/owner_top_items_query_key.dart';
import 'demo_report.dart';
import 'owner_report_source.dart' show demoOwnerReportDataset;
import 'owner_top_items.dart';
import 'report_calculator.dart' show demoDaySales;

/// Loads the top-selling items for a window within a scope.
abstract class OwnerTopItemsRepository {
  /// Loads the ranked items for [range] (or [customWindow]) within [scope].
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  });
}

/// A failure loading top items.
///
/// Its own type rather than reusing `OwnerReportsException`: the two load
/// independently and the Overview must be able to show healthy KPIs with a
/// failed top-items card beside them, which means the states cannot share an
/// identity.
class OwnerTopItemsException implements Exception {
  const OwnerTopItemsException(this.message);

  final String message;

  @override
  String toString() => 'OwnerTopItemsException: $message';
}

/// The demo top-selling items, synthesised from the SAME per-day generator the
/// demo KPIs and the demo daily series already use.
///
/// WHY SYNTHESISED. The demo dataset is a single day of orders — it has no date
/// dimension at all, so there is nothing to filter by window. The choice was
/// therefore between three options, and only one of them is honest:
///
///   * return the same numbers for every window — which is what shipped before
///     F3 for `today` and an EMPTY LIST for everything else, so a 90-day demo
///     silently claimed nothing sold;
///   * fabricate per-item history — inventing product-level facts the demo does
///     not model;
///   * scale the one real day's item split by the SAME deterministic day weights
///     [demoDaySales] already produces for the KPI totals.
///
/// The third is what this does, so the demo's top items grow with the window and
/// stay coherent with the net-sales figure above them. Integer arithmetic
/// throughout (D-007) — no floating point touches money.
class DemoOwnerTopItemsRepository implements OwnerTopItemsRepository {
  const DemoOwnerTopItemsRepository({this.clock, this.failureMessage});

  /// Supplies "today" for a CUSTOM window, which is the one selection expressed
  /// in absolute dates while the demo fixtures are expressed as day offsets.
  /// Injected so demo custom windows are deterministic in tests instead of
  /// rotting the moment a suite runs across midnight.
  final DateTime Function()? clock;

  /// When non-null, [loadTopItems] throws (drives the error state in tests).
  final String? failureMessage;

  @override
  Future<OwnerTopItems> loadTopItems({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
    CustomAnalyticsWindow? customWindow,
    int limit = kOverviewTopItemsLimit,
  }) async {
    final message = failureMessage;
    if (message != null) throw OwnerTopItemsException(message);

    final window = customWindow ?? AnalyticsWindow.preset(range);
    final (int startOffset, int endOffset) = _offsets(window);

    // The one real day's item split, grouped and ranked from the demo dataset.
    final base = _baseItems();
    final baseNet = base.fold<int>(0, (s, i) => s + i.lineRevenueMinor);

    // The window's weight, from the same generator the KPI totals use.
    var weight = 0;
    for (var d = endOffset; d >= startOffset; d--) {
      weight += demoDaySales(d).netMinor;
    }

    final scaled = <TopItem>[
      for (final item in base)
        TopItem(
          menuItemId: item.menuItemId,
          name: item.name,
          // Integer scaling, truncating — never a double, and never a
          // rounding that could make the parts exceed the whole.
          quantity: baseNet == 0
              ? item.quantity
              : (item.quantity * weight) ~/ baseNet,
          lineRevenueMinor: baseNet == 0
              ? item.lineRevenueMinor
              : (item.lineRevenueMinor * weight) ~/ baseNet,
          currencyCode: item.currencyCode,
          orderCount: item.orderCount,
        ),
    ];

    // The SERVER's total tie-break, so demo and real rank identically:
    // revenue desc, quantity desc, name asc, id asc.
    scaled.sort((a, b) {
      final byRevenue = b.lineRevenueMinor.compareTo(a.lineRevenueMinor);
      if (byRevenue != 0) return byRevenue;
      final byQty = b.quantity.compareTo(a.quantity);
      if (byQty != 0) return byQty;
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return (a.menuItemId ?? '').compareTo(b.menuItemId ?? '');
    });

    return OwnerTopItems(
      currencyCode: kDemoCurrencyCode,
      // Echo what was asked for — a custom window reports `custom`.
      rangeWire: window.wire,
      items: List.unmodifiable(scaled.take(limit)),
    );
  }

  /// The window as inclusive day offsets back from today, where 0 is today.
  ///
  /// Presets reuse the exact mapping `demoRangeReport` uses, so the card and the
  /// KPI totals above it describe the same days. A custom window is converted
  /// once, against the injected clock — O(1), no per-day date rebuild.
  (int, int) _offsets(AnalyticsWindow window) {
    switch (window) {
      case PresetAnalyticsWindow(:final range):
        return switch (range) {
          AnalyticsRange.today => (0, 0),
          AnalyticsRange.yesterday => (1, 1),
          AnalyticsRange.last7 => (0, 6),
          AnalyticsRange.last30 => (0, 29),
          AnalyticsRange.last60 => (0, 59),
          AnalyticsRange.last90 => (0, 89),
        };
      case CustomAnalyticsWindow(:final startDay, :final endDay):
        final today = CustomAnalyticsWindow.normalizeDay(
          (clock ?? DateTime.now)(),
        );
        // startDay is the OLDER date, so it is the LARGER offset.
        return (
          today.difference(endDay).inDays,
          today.difference(startDay).inDays,
        );
    }
  }

  /// The demo dataset's one-day item split, grouped by item name.
  ///
  /// The name doubles as the stable id here because the demo dataset carries no
  /// menu-item ids. That is a property of the FIXTURE, not a disagreement with
  /// the server, which groups by `menu_item_id` — noted so nobody later
  /// "corrects" the real repository to match the demo.
  static List<TopItem> _baseItems() {
    final qty = <String, int>{};
    final revenue = <String, int>{};
    for (final order in demoOwnerReportDataset().orders) {
      if (!order.status.isSale) continue;
      for (final line in order.lines) {
        qty[line.itemName] = (qty[line.itemName] ?? 0) + line.quantity;
        revenue[line.itemName] = (revenue[line.itemName] ?? 0) + line.netMinor;
      }
    }
    return [
      for (final name in qty.keys)
        TopItem(
          menuItemId: name,
          name: name,
          quantity: qty[name]!,
          lineRevenueMinor: revenue[name]!,
          currencyCode: kDemoCurrencyCode,
        ),
    ];
  }
}
