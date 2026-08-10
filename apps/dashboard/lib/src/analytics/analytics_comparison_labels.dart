/// DASHBOARD-VISUAL-RANGE-REFRESH-F2.1 — what "compared with …" actually says.
///
/// THE BUG THIS EXISTS TO KILL. The Overview picked its comparison wording by
/// switching on [ReportRange]. That is fine while every window has a name, but a
/// CUSTOM window has none: the report still carries whatever preset token it was
/// built with, so a 14-day custom range confidently announced "Compared with the
/// previous 30 days". The number underneath was the server's real
/// immediately-preceding 14-day window, so the figure was right and the sentence
/// describing it was wrong — the worst combination, because nothing looks broken.
///
/// The wording is now derived from the CANONICAL committed [AnalyticsWindow],
/// which is the only thing that knows whether a window is a preset and how many
/// days it actually spans.
///
/// AND IT FINALLY CONSUMES [AnalyticsComparisonKind]. F0 introduced that type to
/// keep "partial day vs a complete one" from being confused with "two equal
/// windows", then no widget ever read it and every label switched on the enum
/// instead — exactly the drift it was created to prevent. The kind now chooses
/// the SHAPE of the sentence and the day count fills it in.
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'analytics_range.dart';
import 'analytics_window.dart';

/// What [window]'s comparison means.
///
/// A custom window is always an equal-length comparison: the server pairs it
/// with the immediately preceding window of the same length.
AnalyticsComparisonKind analyticsComparisonKindOf(AnalyticsWindow window) =>
    switch (window) {
      PresetAnalyticsWindow(:final range) => range.comparisonKind,
      CustomAnalyticsWindow() => AnalyticsComparisonKind.equalLengthPriorWindow,
    };

/// The heading of the period-comparison strip.
String analyticsComparisonTitle(
  AppLocalizations l10n,
  AnalyticsWindow window,
) => switch (analyticsComparisonKindOf(window)) {
  // TODAY, and only today: a partial day measured against a complete one. The
  // wording has to say so outright rather than implying like-for-like.
  AnalyticsComparisonKind.partialVsCompletePriorDay =>
    l10n.dashboardComparedVsYesterdayAll,
  AnalyticsComparisonKind.equalLengthPriorWindow =>
    switch (window.inclusiveDayCount) {
      1 => l10n.dashboardComparedVsDayBefore,
      7 => l10n.dashboardComparedVsPrev7,
      30 => l10n.dashboardComparedVsPrev30,
      60 => l10n.dashboardComparedVsPrev60,
      90 => l10n.dashboardComparedVsPrev90,
      // Any other length is a custom window, and the sentence states its REAL
      // span. Keying off the day count rather than off preset-vs-custom is what
      // makes a custom 30-day window say "previous 30 days" — which is true —
      // while a custom 14-day window says 14.
      final days => l10n.dashboardComparedVsPrevDays(days),
    },
};

/// The suffix on a KPI trend delta, e.g. "12% vs previous 60 days".
String analyticsComparisonDeltaLabel(
  AppLocalizations l10n,
  AnalyticsWindow window,
  int percent,
) => switch (analyticsComparisonKindOf(window)) {
  AnalyticsComparisonKind.partialVsCompletePriorDay =>
    l10n.dashboardDeltaVsYesterday(percent),
  AnalyticsComparisonKind.equalLengthPriorWindow =>
    switch (window.inclusiveDayCount) {
      1 => l10n.dashboardDeltaVsDayBefore(percent),
      7 => l10n.dashboardDeltaVsPrev7(percent),
      30 => l10n.dashboardDeltaVsPrev30(percent),
      60 => l10n.dashboardDeltaVsPrev60(percent),
      90 => l10n.dashboardDeltaVsPrev90(percent),
      final days => l10n.dashboardDeltaVsPrevDays(percent, days),
    },
};
