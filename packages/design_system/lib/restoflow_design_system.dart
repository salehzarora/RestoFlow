/// RestoFlow design system - shared, themeable UI foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package owns the shared theme and
/// design tokens (DECISION D-014). RF-100 promotes the former RF-011 shell into
/// a real seeded Material 3 [restoflowBaseTheme] plus the [RestoflowSpacing] /
/// [RestoflowRadii] tokens and the [kRestoflowSeedColor] brand seed. RF-141A
/// adds a small SHARED COMPONENT layer ([RestoflowSectionCard],
/// [RestoflowMetricCard], [RestoflowStatusPill], [RestoflowNoticeBanner]) on a
/// single semantic [RestoflowTone] vocabulary, so the four apps can drop their
/// duplicated cards/pills/banners onto one themeable, RTL-friendly set.
library;

export 'src/components/metric_card.dart';
export 'src/components/notice_banner.dart';
export 'src/components/section_card.dart';
export 'src/components/status_pill.dart';
export 'src/theme.dart';
export 'src/tokens.dart';
export 'src/tone.dart';
