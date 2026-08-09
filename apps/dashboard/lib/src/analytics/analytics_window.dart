/// DASHBOARD-VISUAL-RANGE-REFRESH-F1 — the COMMITTED analytics selection.
///
/// [AnalyticsRange] answers "which preset", and that was enough while every
/// window had a name. A custom From/To window has no name, so something has to
/// represent "the user picked these two dates" without pretending to be a
/// preset.
///
/// WHY THIS IS NOT AN `AnalyticsRange.custom` CASE. The enum is used as a map
/// key, as a segmented-control value, and as a field inside two cache keys, and
/// every one of those uses assumes a value with a FIXED identity and a fixed
/// length. A `custom` case would have neither: two different custom windows
/// would be the same enum value, so they would collide in one cache entry and
/// silently show one window's numbers under the other's dates. It would also
/// have to answer `days`, which it cannot. A separate type makes those bugs
/// unrepresentable instead of merely unlikely.
///
/// PRESET IS NOT CUSTOM, EVEN WHEN THE DATES AGREE. `last60` and a hand-picked
/// 60-day window that happens to end today are DIFFERENT requests: the preset is
/// resolved per branch in branch-local time on the server and moves at midnight,
/// while the custom window is fixed calendar dates that are the same for every
/// branch. They are different subclasses here, so they can never compare equal —
/// which is exactly what stops one being served from the other's cache.
///
/// DATE-ONLY BY CONSTRUCTION. Custom bounds are normalised to UTC midnight, so
/// a picker that hands back a local noon and a picker that hands back a local
/// midnight produce the SAME window. UTC is used purely as a neutral calendar
/// carrier — no timezone conversion is implied and none is performed. The
/// server still owns what "day" means per branch; these are the two calendar
/// dates the owner typed, sent verbatim as `p_start` / `p_end`.
library;

import 'analytics_range.dart';

/// The wire token the server echoes for a custom window.
const String kCustomRangeWire = 'custom';

/// The largest custom window the server accepts, inclusive of both endpoints.
///
/// Mirrors the guard in `20260812090000_dashboard_owner_analytics_range_top_items.sql`
/// (`(p_end - p_start) > 91` raises 22023). Kept in sync deliberately: the
/// client refuses the window before the round trip, and the server refuses it
/// again if the client is ever wrong.
const int kMaxCustomWindowDays = 92;

/// One committed analytics selection: either a preset or a custom date window.
sealed class AnalyticsWindow {
  const AnalyticsWindow();

  /// A preset window.
  const factory AnalyticsWindow.preset(AnalyticsRange range) =
      PresetAnalyticsWindow;

  /// A custom window. Throws [ArgumentError] when the bounds are invalid —
  /// see [CustomAnalyticsWindow.tryCreate] for the non-throwing form.
  factory AnalyticsWindow.custom(DateTime startDay, DateTime endDay) =
      CustomAnalyticsWindow;

  /// The preset, or null when this is a custom window.
  AnalyticsRange? get presetRange;

  /// Inclusive start / end, or null when this is a preset window. A preset has
  /// no client-side dates ON PURPOSE: its bounds are branch-local and resolved
  /// by the server.
  DateTime? get startDay;
  DateTime? get endDay;

  bool get isPreset => presetRange != null;
  bool get isCustom => !isPreset;

  /// How many whole days the window spans, inclusive of both endpoints.
  int get inclusiveDayCount;

  /// The `p_range` token to send. Custom windows send [kCustomRangeWire] only
  /// as an identity/label; the RPCs select custom by receiving both dates.
  String get wire;
}

/// The window-selecting RPC parameters for [window].
///
/// ONE mapper for every owner analytics RPC, because the failure this prevents
/// is subtle: a surface that sent `p_range: 'last60'` alongside `p_start`/
/// `p_end` would look correct and quietly ask a different question, and a
/// surface that emulated `last60` as client-computed dates would resolve
/// "today" on the DEVICE rather than per branch on the server. So:
///
///   * a PRESET sends only `p_range`, and never dates;
///   * a CUSTOM window sends only the two dates, and omits `p_range` entirely —
///     supplying both bounds is exactly how the RPCs select custom, and the
///     token is not read in that branch.
Map<String, dynamic> analyticsWindowParams(AnalyticsWindow window) =>
    switch (window) {
      PresetAnalyticsWindow(:final range) => <String, dynamic>{
        'p_range': range.wire,
      },
      CustomAnalyticsWindow(:final startWire, :final endWire) =>
        <String, dynamic>{'p_start': startWire, 'p_end': endWire},
    };

/// A named, server-resolved window.
final class PresetAnalyticsWindow extends AnalyticsWindow {
  const PresetAnalyticsWindow(this.range);

  final AnalyticsRange range;

  @override
  AnalyticsRange? get presetRange => range;

  @override
  DateTime? get startDay => null;

  @override
  DateTime? get endDay => null;

  @override
  int get inclusiveDayCount => range.days;

  @override
  String get wire => range.wire;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresetAnalyticsWindow && other.range == range;

  @override
  int get hashCode => Object.hash(PresetAnalyticsWindow, range);

  @override
  String toString() => 'AnalyticsWindow.preset(${range.wire})';
}

/// A fixed inclusive calendar window the owner chose.
final class CustomAnalyticsWindow extends AnalyticsWindow {
  /// Normalises both bounds to a date and validates them.
  ///
  /// Throws [ArgumentError] when the window is reversed or longer than
  /// [kMaxCustomWindowDays]. Construction is the validation seam on purpose: if
  /// an invalid window cannot be built, it cannot be committed into query state
  /// and cannot reach the wire, so the 22023 the server would raise is
  /// unreachable by construction rather than merely unlikely.
  factory CustomAnalyticsWindow(DateTime startDay, DateTime endDay) {
    final start = normalizeDay(startDay);
    final end = normalizeDay(endDay);
    final invalid = describeInvalid(start, end);
    if (invalid != null) throw ArgumentError.value(invalid, 'window');
    return CustomAnalyticsWindow._(start, end);
  }

  const CustomAnalyticsWindow._(this.startDay, this.endDay);

  /// The non-throwing form: null when the bounds are invalid.
  static CustomAnalyticsWindow? tryCreate(
    DateTime? startDay,
    DateTime? endDay,
  ) {
    // BOTH-OR-NEITHER, matching the server. A half-supplied window is not a
    // partial selection to be helpfully completed — it has no defensible end,
    // and guessing one is how an unbounded historical scan gets requested.
    if (startDay == null || endDay == null) return null;
    final start = normalizeDay(startDay);
    final end = normalizeDay(endDay);
    if (describeInvalid(start, end) != null) return null;
    return CustomAnalyticsWindow._(start, end);
  }

  /// Strips time-of-day, carrying the calendar date on a neutral UTC anchor.
  static DateTime normalizeDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);

  /// Why this pair is unacceptable, or null when it is fine. Both bounds must
  /// already be normalised.
  static String? describeInvalid(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 'end precedes start';
    if (inclusiveDaysBetween(start, end) > kMaxCustomWindowDays) {
      return 'window exceeds $kMaxCustomWindowDays days';
    }
    return null;
  }

  /// Inclusive day count between two NORMALISED days.
  ///
  /// Both anchors are UTC midnight, so `inDays` is exact — no DST transition can
  /// make a day 23 or 25 hours long and round the count off by one.
  static int inclusiveDaysBetween(DateTime start, DateTime end) =>
      end.difference(start).inDays + 1;

  /// True when the pair would build a valid window.
  static bool isValidRange(DateTime? startDay, DateTime? endDay) =>
      tryCreate(startDay, endDay) != null;

  @override
  final DateTime startDay;

  @override
  final DateTime endDay;

  @override
  AnalyticsRange? get presetRange => null;

  @override
  int get inclusiveDayCount => inclusiveDaysBetween(startDay, endDay);

  @override
  String get wire => kCustomRangeWire;

  /// `YYYY-MM-DD`, the exact shape the `date` RPC parameters expect.
  String get startWire => _iso(startDay);
  String get endWire => _iso(endDay);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomAnalyticsWindow &&
          other.startDay == startDay &&
          other.endDay == endDay;

  @override
  int get hashCode => Object.hash(CustomAnalyticsWindow, startDay, endDay);

  @override
  String toString() => 'AnalyticsWindow.custom($startWire..$endWire)';
}
