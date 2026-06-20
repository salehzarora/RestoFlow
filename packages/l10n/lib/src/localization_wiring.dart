import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/app_localizations.dart';

/// The localizations delegates every RestoFlow app installs in its `MaterialApp`
/// (RF-020, DECISION D-014).
///
/// Includes the generated [AppLocalizations] delegate plus the Flutter SDK
/// global delegates. `GlobalWidgetsLocalizations` supplies the per-locale text
/// direction that drives RTL (ar, he) vs LTR (en) automatically — no manual
/// directionality handling is needed.
const List<LocalizationsDelegate<dynamic>> restoflowLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

/// Resolves an incoming [deviceLocale] to one of [supported] by language code,
/// falling back to English — the technical default/fallback locale (RF-020 A2,
/// PRODUCT_SPEC §6) — when there is no match. Intended for
/// `MaterialApp.localeResolutionCallback`.
Locale restoflowResolveLocale(
  Locale? deviceLocale,
  Iterable<Locale> supported,
) {
  if (deviceLocale != null) {
    for (final locale in supported) {
      if (locale.languageCode == deviceLocale.languageCode) return locale;
    }
  }
  return const Locale('en');
}
