/// RestoFlow localization framework (RF-020, DECISION D-014).
///
/// Single localization owner for the monorepo: ar/he/en ARB resources compiled
/// by Flutter gen-l10n into [AppLocalizations] (committed output), the shared
/// [restoflowLocalizationsDelegates] + [restoflowResolveLocale] wiring, and the
/// neutral [kSupportedLocales] list. Apps consume this package; they must not
/// build a separate localization system. Directionality (RTL ar/he, LTR en) is
/// data-driven via the Flutter global delegates — no manual direction handling.
library;

export 'src/generated/app_localizations.dart';
export 'src/localization_wiring.dart';
export 'src/supported_locales.dart';
