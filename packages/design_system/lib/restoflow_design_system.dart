/// RestoFlow design system - shared, themeable UI foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package owns the shared theme and
/// design tokens (DECISION D-014). RF-100 promoted the former RF-011 shell into
/// a seeded Material 3 [restoflowBaseTheme]; RF-141A added the first shared
/// components on the semantic [RestoflowTone] vocabulary. The design-polish
/// sprint widens both: [RestoflowSemanticColors] (TRUE green/amber/red/blue
/// statuses + the warm restaurant accent + the dark-sidebar palette, light and
/// dark presets), a themed widget-family layer (inputs, dialogs, sheets,
/// navigation, snackbars, menus, ≥44dp buttons), expanded tokens (icon sizes,
/// breakpoints, panel widths, motion durations), and the shared component set
/// ([RestoflowPageHeader], [RestoflowStateView], [RestoflowSkeleton],
/// [RestoflowStepTile], [RestoflowNumericKeypad], [RestoflowBrandMark],
/// [RestoflowCodeBlock], [RestoflowLanguageSelector],
/// [RestoflowButtonStyles], [RestoflowInlineSpinner]).
library;

export 'src/buttons.dart';
export 'src/category_palette.dart';
export 'src/components/brand_mark.dart';
export 'src/components/code_block.dart';
export 'src/components/language_selector.dart';
export 'src/components/metric_card.dart';
export 'src/components/notice_banner.dart';
export 'src/components/numeric_keypad.dart';
export 'src/components/page_header.dart';
export 'src/components/section_card.dart';
export 'src/components/state_view.dart';
export 'src/components/status_pill.dart';
export 'src/components/step_tile.dart';
export 'src/theme.dart';
export 'src/tokens.dart';
export 'src/tone.dart';
export 'src/semantic_colors.dart';
