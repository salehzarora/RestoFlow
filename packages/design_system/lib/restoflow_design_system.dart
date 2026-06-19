/// RestoFlow design system - shared, themeable UI foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package will own themed widgets and
/// RTL/LTR-aware layout primitives (DECISION D-014). RF-011 provides only a
/// neutral shell (a base theme placeholder); real design tokens, widgets, and
/// bidi primitives land in later UI tickets. No feature/business UI here.
library;

export 'src/theme.dart';
