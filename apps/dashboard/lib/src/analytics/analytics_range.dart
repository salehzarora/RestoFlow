/// DASHBOARD-OWNER-ANALYTICS-F0 — the ONE analytics date range.
///
/// Before this, the Dashboard carried two structurally identical range enums
/// that had drifted apart in behaviour: [ReportRange] (Overview/reports, which
/// knows `isSingleDay` because only single-day ranges carry an hourly curve)
/// and [OrderHistoryRange] (Orders history, which does not). Every new analytics
/// surface had to pick one and then translate at the boundary, and a
/// drill-down that carried a range from a report to a history list had to hop
/// between two types that agreed on the wire but not in Dart.
///
/// [AnalyticsRange] is that single canonical type. It is deliberately NOT a
/// rewrite:
///
///   * the wire tokens are IDENTICAL to both existing enums (`today`,
///     `yesterday`, `last7`, `last30`), so no RPC contract moves;
///   * conversions to and from both legacy enums are total and lossless, so the
///     two can be retired incrementally instead of in one risky sweep.
///
/// Window arithmetic that the SERVER owns is deliberately absent. The report
/// RPCs compute their windows in BRANCH-LOCAL time from
/// `COALESCE(branch.timezone, restaurant.timezone)`; reproducing that in Dart
/// would create a second, quietly-wrong definition of "today" the moment a
/// branch sits in a different zone from the device. What lives here is only
/// what is safe client-side: identity, wire mapping, and the SHAPE of a
/// comparison label.
library;

import '../data/demo_report.dart' show ReportRange;
import '../data/order_history_models.dart' show OrderHistoryRange;

/// The canonical analytics range.
///
/// Values and wire tokens match the server's `p_range` contract exactly.
enum AnalyticsRange {
  today('today'),
  yesterday('yesterday'),
  last7('last7'),
  last30('last30');

  const AnalyticsRange(this.wire);

  /// The exact `p_range` token the owner RPCs expect. Never localize this.
  final String wire;

  /// True for the single-day ranges, which are the only ones that carry an
  /// hourly curve. A multi-day hourly average would misrepresent a quiet
  /// Tuesday and a busy Saturday as the same day, so the reports intentionally
  /// omit it — this getter is what keeps that decision in one place.
  bool get isSingleDay => this == today || this == yesterday;

  /// How many whole days the window spans. Used only for labelling and for
  /// bounding a client-side series length — never to compute a window
  /// boundary, which is the server's job.
  int get days => switch (this) {
    today || yesterday => 1,
    last7 => 7,
    last30 => 30,
  };

  /// Parses a wire token; unknown/malformed input falls back to [today] so a
  /// bad echo from the server can never throw in the UI. Both legacy enums
  /// already behaved this way.
  static AnalyticsRange fromWire(String? wire) {
    for (final r in AnalyticsRange.values) {
      if (r.wire == wire) return r;
    }
    return today;
  }

  /// The kind of comparison this range is shown against.
  ///
  /// This is the honesty seam for the Phase-A "today" decision: `today` is a
  /// PARTIAL day compared against a COMPLETE yesterday, and the UI must say so
  /// rather than implying an elapsed-time-matched comparison that the backend
  /// does not compute. Every other range compares equal-length windows.
  AnalyticsComparisonKind get comparisonKind => switch (this) {
    today => AnalyticsComparisonKind.partialVsCompletePriorDay,
    yesterday => AnalyticsComparisonKind.equalLengthPriorWindow,
    last7 || last30 => AnalyticsComparisonKind.equalLengthPriorWindow,
  };

  // --- Legacy interop. Total and lossless in both directions. ---------------

  /// The equivalent legacy reports enum.
  ReportRange get asReportRange => switch (this) {
    today => ReportRange.today,
    yesterday => ReportRange.yesterday,
    last7 => ReportRange.last7,
    last30 => ReportRange.last30,
  };

  /// The equivalent legacy order-history enum.
  OrderHistoryRange get asOrderHistoryRange => switch (this) {
    today => OrderHistoryRange.today,
    yesterday => OrderHistoryRange.yesterday,
    last7 => OrderHistoryRange.last7,
    last30 => OrderHistoryRange.last30,
  };

  /// Adopts a legacy reports range.
  static AnalyticsRange fromReportRange(ReportRange r) => switch (r) {
    ReportRange.today => today,
    ReportRange.yesterday => yesterday,
    ReportRange.last7 => last7,
    ReportRange.last30 => last30,
  };

  /// Adopts a legacy order-history range.
  static AnalyticsRange fromOrderHistoryRange(OrderHistoryRange r) =>
      switch (r) {
        OrderHistoryRange.today => today,
        OrderHistoryRange.yesterday => yesterday,
        OrderHistoryRange.last7 => last7,
        OrderHistoryRange.last30 => last30,
      };
}

/// What a range's "vs …" comparison actually means.
///
/// Kept as a type rather than a bool so the UI cannot accidentally render one
/// wording for the other, and so a future elapsed-matched mode can be added as
/// a THIRD value instead of silently changing what the existing two mean.
enum AnalyticsComparisonKind {
  /// An in-progress window compared against a COMPLETE prior window. Today is
  /// the only such range today: a partial day measured against all of
  /// yesterday. The label must state this outright.
  partialVsCompletePriorDay,

  /// Two windows of the same length — the honest like-for-like case.
  equalLengthPriorWindow,
}
