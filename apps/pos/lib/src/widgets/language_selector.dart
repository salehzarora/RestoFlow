import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/locale_controller.dart';

/// A compact EN / AR / HE language selector for the app bar (RF-118 fix B).
/// Selecting a language updates [localeControllerProvider] immediately, which
/// the app's MaterialApp watches — switching the whole app (and to RTL for
/// Arabic/Hebrew). Endonym labels (English / العربية / עברית) come from l10n.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeControllerProvider);
    return PopupMenuButton<Locale>(
      key: const Key('language-selector'),
      icon: const Icon(Icons.translate),
      tooltip: l10n.languageSelectorTooltip,
      initialValue: current,
      onSelected: (locale) =>
          ref.read(localeControllerProvider.notifier).setLocale(locale),
      itemBuilder: (context) => <PopupMenuEntry<Locale>>[
        PopupMenuItem<Locale>(
          value: const Locale('en'),
          child: Text(l10n.languageEnglish),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('ar'),
          child: Text(l10n.languageArabic),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('he'),
          child: Text(l10n.languageHebrew),
        ),
      ],
    );
  }
}
