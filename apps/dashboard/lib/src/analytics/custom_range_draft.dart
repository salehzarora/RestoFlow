/// DASHBOARD-VISUAL-RANGE-REFRESH-F2 — the custom-range DRAFT.
///
/// A draft is what the owner is currently typing; the committed window is what
/// the Dashboard is currently showing. Keeping them in one place is how a
/// half-picked range becomes a request: the moment a From date lands in query
/// state, something loads. So the draft lives here, is never read by any query
/// key, and only ever reaches the committed provider through Apply.
///
/// The draft is also the only place a half-supplied or invalid range can EXIST.
/// [CustomAnalyticsWindow] refuses to be constructed out of range, so the draft
/// holds two independent nullable dates and reports why they are not yet a
/// window — which is exactly what the Apply button and the inline message need.
library;

import 'analytics_window.dart';

/// Why a draft is not yet a committable window.
enum CustomRangeDraftError {
  /// One or both bounds are missing. Both are required, matching the server:
  /// supplying one raises 22023 rather than assuming an open end.
  incomplete,

  /// The end date precedes the start date. NEVER silently swapped — a reversed
  /// range is a mistake to show, not a preference to infer.
  reversed,

  /// Longer than [kMaxCustomWindowDays] inclusive days. NEVER silently
  /// truncated, for the same reason.
  tooLong,
}

/// The in-progress custom range.
class CustomRangeDraft {
  const CustomRangeDraft({this.startDay, this.endDay});

  /// An empty draft — nothing picked yet.
  static const CustomRangeDraft empty = CustomRangeDraft();

  /// A draft seeded from an already-valid window (reopening the sheet).
  factory CustomRangeDraft.fromWindow(CustomAnalyticsWindow window) =>
      CustomRangeDraft(startDay: window.startDay, endDay: window.endDay);

  final DateTime? startDay;
  final DateTime? endDay;

  /// True when nothing has been picked.
  bool get isEmpty => startDay == null && endDay == null;

  /// The window this draft would commit, or null when it is not valid yet.
  ///
  /// Built through the F1 validation seam rather than re-checking the rules
  /// here, so the client can never accept a window the domain would refuse.
  CustomAnalyticsWindow? get window =>
      CustomAnalyticsWindow.tryCreate(startDay, endDay);

  /// True when [window] is non-null — i.e. Apply may be enabled.
  bool get isValid => window != null;

  /// Why this draft cannot be committed, or null when it can.
  CustomRangeDraftError? get error {
    final start = startDay;
    final end = endDay;
    if (start == null || end == null) return CustomRangeDraftError.incomplete;
    final s = CustomAnalyticsWindow.normalizeDay(start);
    final e = CustomAnalyticsWindow.normalizeDay(end);
    if (e.isBefore(s)) return CustomRangeDraftError.reversed;
    if (CustomAnalyticsWindow.inclusiveDaysBetween(s, e) >
        kMaxCustomWindowDays) {
      return CustomRangeDraftError.tooLong;
    }
    return null;
  }

  CustomRangeDraft copyWith({
    DateTime? startDay,
    DateTime? endDay,
    bool clear = false,
  }) => clear
      ? CustomRangeDraft.empty
      : CustomRangeDraft(
          startDay: startDay ?? this.startDay,
          endDay: endDay ?? this.endDay,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomRangeDraft &&
          other.startDay == startDay &&
          other.endDay == endDay;

  @override
  int get hashCode => Object.hash(startDay, endDay);

  @override
  String toString() => 'CustomRangeDraft($startDay..$endDay)';
}
