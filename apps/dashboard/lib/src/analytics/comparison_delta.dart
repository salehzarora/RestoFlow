/// DASHBOARD-OWNER-ANALYTICS-F0 — the ONE prior-period comparison.
///
/// The Dashboard already had `deltaPercent(current, prior)` in demo_report.dart:
/// correct, but a bare `int?` with the reasoning living at each call site. Every
/// new KPI had to re-decide what a null meant, what to render for it, and
/// whether "no change" is different from "no basis for comparison". Those are
/// different facts and the UI must not blur them.
///
/// [ComparisonDelta] makes that one decision once:
///
///   * a prior of null or 0 yields [ComparisonState.noBasis] — NOT 0%, and not
///     "+100%". A percentage against nothing is a fabricated number; the
///     Dashboard renders an em dash for it (the zero-baseline rule);
///   * otherwise the state is increase / decrease / flat, with both the
///     absolute and the percentage delta available.
///
/// INTEGER MONEY ONLY (D-007). `current` and `prior` are integer minor units or
/// plain counts; the percentage is computed with truncating integer division,
/// exactly as `deltaPercent` did, so no floating-point value ever enters a
/// money path. This class deliberately exposes no double.
library;

/// Whether a comparison can be made at all, and which way it went.
enum ComparisonState {
  /// No honest basis: the prior window is absent (null) or zero. The UI shows
  /// an em dash, never a percentage.
  noBasis,

  /// Current is strictly greater than prior.
  increase,

  /// Current is strictly less than prior.
  decrease,

  /// Identical values — a real, measured "no change", which is NOT the same
  /// fact as [noBasis] and must not render the same way.
  flat,
}

/// A pure, display-ready comparison of a current value against a prior one.
///
/// Deliberately free of Flutter, localization and formatting so it can be unit
/// tested exhaustively and reused by every KPI, chart and tile.
class ComparisonDelta {
  const ComparisonDelta._({
    required this.current,
    required this.prior,
    required this.state,
    required this.absolute,
    required this.percent,
  });

  /// Builds a comparison. [prior] is nullable because "we have no prior window"
  /// is a real and common case (a brand-new branch, or a range the server could
  /// not compute a prior for).
  factory ComparisonDelta.of(int current, int? prior) {
    // A zero prior is treated exactly like a missing one. Growth "from zero" has
    // no meaningful percentage — every such change is infinite — so the honest
    // answer is that there is no basis, not a large number that looks like
    // insight.
    if (prior == null || prior == 0) {
      return ComparisonDelta._(
        current: current,
        prior: prior,
        state: ComparisonState.noBasis,
        absolute: null,
        percent: null,
      );
    }
    final absolute = current - prior;
    // Truncating integer division, matching the pre-existing deltaPercent()
    // semantics byte for byte so migrating a call site cannot shift a number.
    final percent = absolute * 100 ~/ prior;
    return ComparisonDelta._(
      current: current,
      prior: prior,
      state: absolute > 0
          ? ComparisonState.increase
          : absolute < 0
          ? ComparisonState.decrease
          : ComparisonState.flat,
      absolute: absolute,
      percent: percent,
    );
  }

  /// The value being reported.
  final int current;

  /// The prior-window value, or null when none exists.
  final int? prior;

  final ComparisonState state;

  /// Signed absolute change, or null when there is no basis. Same unit as
  /// [current] — integer minor units for money, a plain count otherwise.
  final int? absolute;

  /// Signed integer percentage change, or null when there is no basis.
  /// Truncated toward zero.
  final int? percent;

  /// True when a percentage may be rendered at all.
  bool get hasBasis => state != ComparisonState.noBasis;

  /// True when the change is a real measured increase.
  bool get isIncrease => state == ComparisonState.increase;

  /// True when the change is a real measured decrease.
  bool get isDecrease => state == ComparisonState.decrease;

  @override
  bool operator ==(Object other) =>
      other is ComparisonDelta &&
      other.current == current &&
      other.prior == prior &&
      other.state == state &&
      other.absolute == absolute &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(current, prior, state, absolute, percent);

  @override
  String toString() =>
      'ComparisonDelta(current: $current, prior: $prior, state: $state, '
      'absolute: $absolute, percent: $percent)';
}
