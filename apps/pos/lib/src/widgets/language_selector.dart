import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/locale_controller.dart';

/// A compact EN / AR / HE language selector for the app bar (RF-118 fix B).
/// Thin app wrapper over the shared [RestoflowLanguageSelector] (consistency
/// cleanup — this file was byte-identical in all four apps): it wires the
/// app-local [localeControllerProvider], which the app's MaterialApp watches —
/// switching the whole app (and to RTL for Arabic/Hebrew). Endonym labels
/// (English / العربية / עברית) come from l10n.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return RestoflowLanguageSelector(
      tooltip: l10n.languageSelectorTooltip,
      current: ref.watch(localeControllerProvider),
      entries: [
        (const Locale('en'), l10n.languageEnglish),
        (const Locale('ar'), l10n.languageArabic),
        (const Locale('he'), l10n.languageHebrew),
      ],
      onSelected: (locale) =>
          ref.read(localeControllerProvider.notifier).setLocale(locale),
    );
  }
}
