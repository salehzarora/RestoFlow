import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shared-preferences key for the persisted UI language (a NON-SECRET
/// two-letter language code — never a token).
const String kLocalePrefsKey = 'restoflow.locale';

/// Reads the persisted UI language, or null on first launch / any storage
/// failure. Called by `main()` BEFORE `runApp` so the first frame is already
/// in the right language.
Future<Locale?> readPersistedLocale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(kLocalePrefsKey);
    if (code == null) return null;
    for (final locale in kSupportedLocales) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// The locale the app STARTS in. Production `main()` overrides this with the
/// persisted choice, falling back to ARABIC — the official default language
/// (demo-readiness sprint) — on first launch. The un-overridden default stays
/// English so the existing widget-test corpus is unaffected.
final initialLocaleProvider = Provider<Locale>((ref) => const Locale('en'));

/// App-local locale controller (RF-118 fix B + sprint persistence): the
/// user-selected UI language. Starts from [initialLocaleProvider]; selecting a
/// language applies immediately AND persists per device/browser, so the next
/// launch restores it. `MaterialApp.locale` watches this (ar/he flip to RTL
/// via the shared localization delegates).
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => ref.watch(initialLocaleProvider);

  void setLocale(Locale locale) {
    state = locale;
    // Best-effort persistence — the in-session switch never waits on storage.
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLocalePrefsKey, locale.languageCode);
      } catch (_) {}
    });
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
