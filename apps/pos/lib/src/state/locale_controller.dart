import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-local locale controller (RF-118 fix B): the user-selected UI language,
/// defaulting to English. Session-only — no backend/preference persistence. The
/// app's `MaterialApp.locale` watches this so a change applies immediately
/// (Arabic/Hebrew switch the app to RTL via the shared localization delegates).
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void setLocale(Locale locale) => state = locale;
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
