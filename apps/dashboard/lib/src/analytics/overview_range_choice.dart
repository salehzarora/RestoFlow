/// DASHBOARD-VISUAL-RANGE-REFRESH-F2 — what the Overview range selector offers.
///
/// The selector shows seven things, and only six of them are a [ReportRange].
/// "Custom" is not a range — it is an INVITATION to choose one — so it cannot be
/// a value of the range enum without making every `switch` over that enum answer
/// a question it has no data for ("how many days is custom?").
///
/// F1 deleted the temporary four-item list this replaces. The rule it encoded
/// survives here: the visible choices are written out explicitly, never derived
/// from `ReportRange.values`, so adding a range to the domain can never silently
/// change what the Overview offers.
library;

import '../data/demo_report.dart' show ReportRange;

/// One selectable item in the Overview range selector.
sealed class OverviewRangeChoice {
  const OverviewRangeChoice();

  /// A named preset.
  const factory OverviewRangeChoice.preset(ReportRange range) =
      PresetRangeChoice;

  /// The Custom affordance. Selecting it opens the From/To sheet; it does NOT
  /// by itself commit a window, which is why it carries no dates.
  const factory OverviewRangeChoice.custom() = CustomRangeChoice;

  /// A stable key fragment for widget keys and tests.
  String get id;
}

/// A preset choice.
final class PresetRangeChoice extends OverviewRangeChoice {
  const PresetRangeChoice(this.range);

  final ReportRange range;

  @override
  String get id => range.wire;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresetRangeChoice && other.range == range;

  @override
  int get hashCode => Object.hash(PresetRangeChoice, range);

  @override
  String toString() => 'OverviewRangeChoice.preset(${range.wire})';
}

/// The Custom choice.
final class CustomRangeChoice extends OverviewRangeChoice {
  const CustomRangeChoice();

  @override
  String get id => 'custom';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CustomRangeChoice;

  @override
  int get hashCode => (CustomRangeChoice).hashCode;

  @override
  String toString() => 'OverviewRangeChoice.custom()';
}

/// The seven choices, in display order.
///
/// EXPLICIT, not `ReportRange.values` + custom: the order is a design decision
/// (shortest window first, Custom last because it is the escape hatch), and a
/// derived list would reorder itself the moment the enum grew.
const List<OverviewRangeChoice> kOverviewRangeChoices = <OverviewRangeChoice>[
  OverviewRangeChoice.preset(ReportRange.today),
  OverviewRangeChoice.preset(ReportRange.yesterday),
  OverviewRangeChoice.preset(ReportRange.last7),
  OverviewRangeChoice.preset(ReportRange.last30),
  OverviewRangeChoice.preset(ReportRange.last60),
  OverviewRangeChoice.preset(ReportRange.last90),
  OverviewRangeChoice.custom(),
];
