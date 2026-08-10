/// DASHBOARD-VISUAL-RANGE-REFRESH-F3 — the top-selling-items result.
///
/// A SEPARATE result type from [DashboardReport], for the same reason
/// [OwnerSalesSeries] is separate: this comes from its own RPC
/// (`public.owner_top_items`), it can be UNAVAILABLE independently of the
/// report, and folding it into the report would mean one failed card takes the
/// KPIs down with it.
///
/// [supported] carries the capability answer. A database where the RPC is not
/// deployed answers PGRST202, which is "this feature is not here" — genuinely
/// different from "this window had no sales", which is a successful empty list.
/// Collapsing the two would tell an owner their best day sold nothing.
library;

import 'demo_report.dart' show TopItem;

/// The top-selling items for one window.
class OwnerTopItems {
  const OwnerTopItems({
    required this.currencyCode,
    required this.rangeWire,
    required this.items,
    this.supported = true,
  });

  /// The RPC is not deployed on this database. Distinct from an empty [items].
  const OwnerTopItems.unavailable(this.rangeWire)
    : currencyCode = '',
      items = const <TopItem>[],
      supported = false;

  final String currencyCode;

  /// The range token the server ECHOED, kept as the raw string.
  ///
  /// Not narrowed to `AnalyticsRange`: the server legitimately answers `custom`,
  /// which has no enum value — the same reasoning [OwnerSalesSeries.rangeWire]
  /// documents.
  final String rangeWire;

  /// Ranked highest-revenue first, exactly as the server ordered them. The
  /// client never re-sorts: the server's tie-break (revenue desc, quantity desc,
  /// name asc, menu_item_id asc) is total, and a second sort here could only
  /// disagree with it.
  final List<TopItem> items;

  final bool supported;

  bool get isEmpty => items.isEmpty;

  /// The largest revenue in the set, for the share bars. Zero when empty.
  ///
  /// Read from the FIRST row rather than by scanning: the server returns them
  /// revenue-descending, so the first is the maximum by construction.
  int get topRevenueMinor => items.isEmpty ? 0 : items.first.lineRevenueMinor;
}
