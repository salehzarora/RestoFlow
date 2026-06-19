import 'package:flutter/widgets.dart';

/// The locales RestoFlow targets (DECISION D-014): Arabic, Hebrew, English.
///
/// Declaration only - ARB resources, message lookup, and RTL/LTR handling are
/// implemented in RF-020. Order here is not significant.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('ar'),
  Locale('he'),
  Locale('en'),
];
