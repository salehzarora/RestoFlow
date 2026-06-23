/// RestoFlow design system - shared, themeable UI foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package owns the shared theme and
/// design tokens (DECISION D-014). RF-100 promotes the former RF-011 shell into
/// a real seeded Material 3 [restoflowBaseTheme] plus the [RestoflowSpacing] /
/// [RestoflowRadii] tokens and the [kRestoflowSeedColor] brand seed. Richer
/// shared widgets and RTL/LTR primitives still land in later UI tickets.
library;

export 'src/theme.dart';
export 'src/tokens.dart';
