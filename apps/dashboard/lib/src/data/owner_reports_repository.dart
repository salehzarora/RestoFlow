/// The owner-reports data SEAM (RF-119).
///
/// The single place owner-report data is sourced. The demo implementation
/// COMPUTES the report from a structured in-memory dataset (no Supabase, no
/// report view, no backend). A future ticket can drop in a Supabase-backed
/// implementation that reads the real RF-075/RF-092 report views — same return
/// type, so the UI does not change. [loadReport] is async so the UI has honest
/// loading / error / empty states.
library;

import 'demo_report.dart';
import 'owner_report_source.dart';
import 'report_calculator.dart';

/// Loads the owner [DashboardReport] for a [range] (RF-REPORT-004; defaults to
/// today). Implementations may fail (network, auth, RLS) — the UI renders that
/// as an error state.
abstract class OwnerReportsRepository {
  Future<DashboardReport> loadReport({ReportRange range = ReportRange.today});
}

/// Computes the owner report from a structured demo dataset. There is no
/// backend: this is honest demo data, calculated locally.
class DemoOwnerReportsRepository implements OwnerReportsRepository {
  const DemoOwnerReportsRepository({this.dataset, this.failureMessage});

  /// Overrides the source dataset (e.g. an empty day in tests). Null uses the
  /// standard demo dataset.
  final OwnerReportDataset? dataset;

  /// When non-null, [loadReport] throws an [OwnerReportsException] with this
  /// message (used to drive/test the error state).
  final String? failureMessage;

  @override
  Future<DashboardReport> loadReport({
    ReportRange range = ReportRange.today,
  }) async {
    final message = failureMessage;
    if (message != null) {
      throw OwnerReportsException(message);
    }
    // An explicitly injected dataset (tests: an empty day, a custom day) is
    // honoured verbatim for the requested range; otherwise the standard demo
    // computes the range (RF-REPORT-004 — deterministic multi-day demo figures).
    final injected = dataset;
    if (injected != null) return computeOwnerReport(injected, range: range);
    return demoRangeReport(range);
  }
}

/// A failure loading the owner report.
class OwnerReportsException implements Exception {
  const OwnerReportsException(this.message);

  final String message;

  @override
  String toString() => 'OwnerReportsException: $message';
}
