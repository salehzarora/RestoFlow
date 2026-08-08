/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the daily sales-series seam.
///
/// A SIBLING of [OwnerReportsRepository], not an extension of it. The two answer
/// different questions from different RPCs — "what happened in this window" vs
/// "what happened on each day of it" — and only the multi-day ranges ask the
/// second one. Folding the series into `loadReport` would make every Overview
/// load pay for a call the today view never renders.
library;

import '../analytics/analytics_range.dart';
import '../analytics/dashboard_analytics_scope.dart';
import 'demo_report.dart' show kDemoCurrencyCode;
import 'owner_sales_series.dart';
import 'report_calculator.dart' show demoDaySales;

/// Loads the per-day sales series for a [range].
///
/// Implementations may fail (network, auth, RLS) — the UI renders that as a
/// section-level error, never as zeros.
abstract class OwnerSalesSeriesRepository {
  /// Loads the per-day series for [range] within [scope].
  ///
  /// CODEX F-1A — [scope] comes from the family key, so the ids on the wire are
  /// the ids the cached entry is filed under. Null means "use whatever the
  /// membership covers".
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    DashboardAnalyticsScope? analyticsScope,
  });
}

/// The demo daily series, computed from the SAME per-day generator the demo
/// range report aggregates.
///
/// That shared source is the point: in demo mode the daily trend sums exactly to
/// the "Net sales" KPI above it, so the demo cannot teach an owner to distrust
/// the two surfaces. Nothing here is randomised and nothing is invented — the
/// order-type split is left EMPTY rather than fabricating a dine-in/takeaway
/// ratio the demo dataset does not model, and the tender breakdown carries only
/// cash, which is exactly what the demo range report reports as collected.
class DemoOwnerSalesSeriesRepository implements OwnerSalesSeriesRepository {
  const DemoOwnerSalesSeriesRepository({this.clock, this.failureMessage});

  /// Supplies "now" for the calendar labels. Mirrors `activeOrdersClockProvider`
  /// so tests can pin a date instead of racing midnight. Null uses the device
  /// clock.
  final DateTime Function()? clock;

  /// When non-null, [loadSeries] throws [OwnerSalesSeriesException] (drives the
  /// error state in tests).
  final String? failureMessage;

  @override
  Future<OwnerSalesSeries> loadSeries({
    required AnalyticsRange range,
    // The demo generator has no branch dimension; accepted and ignored.
    DashboardAnalyticsScope? analyticsScope,
  }) async {
    final message = failureMessage;
    if (message != null) throw OwnerSalesSeriesException(message);

    final now = (clock ?? DateTime.now)();
    final buckets = <OwnerSalesSeriesBucket>[];
    // Ascending by day, matching the server's contract: oldest first, today last.
    for (var offset = range.days - 1; offset >= 0; offset--) {
      // Date-only arithmetic through the DateTime CONSTRUCTOR, which normalises
      // an out-of-range day (e.g. "the 0th of March") into the previous month.
      // `subtract(Duration(days: n))` would be wrong here: it removes 24-hour
      // spans, so across a DST transition it can land on the same calendar day
      // twice or skip one entirely.
      final date = DateTime(now.year, now.month, now.day - offset);
      final day = BusinessDay.tryParse(_isoDate(date));
      if (day == null) continue;
      final figures = demoDaySales(offset);
      buckets.add(
        OwnerSalesSeriesBucket(
          day: day,
          orderCount: figures.orders,
          // The demo dataset has no discount engine, so gross == net; saying so
          // explicitly is more honest than inventing a discount to look richer.
          grossMinor: figures.netMinor,
          discountMinor: 0,
          netMinor: figures.netMinor,
          voidCount: 0,
          voidTotalMinor: 0,
          collectedMinor: figures.cashMinor,
          cashMinor: figures.cashMinor,
          byMethod: [
            OwnerSalesSeriesPaymentMethod(
              method: 'cash',
              count: figures.orders,
              totalMinor: figures.cashMinor,
            ),
          ],
        ),
      );
    }
    return OwnerSalesSeries(
      currencyCode: kDemoCurrencyCode,
      rangeWire: range.wire,
      buckets: List.unmodifiable(buckets),
    );
  }

  /// `YYYY-MM-DD` from a local calendar date. Never `toIso8601String()`, which
  /// appends a time and invites a later reader to parse it back into an instant.
  static String _isoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// A failure loading the daily sales series.
///
/// Its own type rather than reusing `OwnerReportsException`: the two load
/// independently and the Overview must be able to show a healthy report with a
/// failed trend beside it, which means the states cannot share an identity.
class OwnerSalesSeriesException implements Exception {
  const OwnerSalesSeriesException(this.message);

  final String message;

  @override
  String toString() => 'OwnerSalesSeriesException: $message';
}
