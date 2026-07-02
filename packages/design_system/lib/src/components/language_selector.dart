import 'package:flutter/material.dart';

/// The shared language switcher (design-polish sprint): one implementation
/// for the four apps (the audit found a byte-identical copy in each).
///
/// Parameterized so this package stays l10n- and state-free: callers pass the
/// localized [tooltip], the `(locale, endonym)` [entries], the [current]
/// locale, and an [onSelected] callback wired to their app's locale
/// controller. Keeps the test contract: `Key('language-selector')` and
/// [Icons.translate], with endonym menu items.
class RestoflowLanguageSelector extends StatelessWidget {
  const RestoflowLanguageSelector({
    required this.entries,
    required this.onSelected,
    this.current,
    this.tooltip,
    super.key = const Key('language-selector'),
  });

  /// `(locale, endonym)` pairs, e.g. `(Locale('ar'), 'العربية')`.
  final List<(Locale, String)> entries;

  final ValueChanged<Locale> onSelected;

  /// The active locale — its entry gets a leading check.
  final Locale? current;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.translate),
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final (locale, endonym) in entries)
          PopupMenuItem<Locale>(
            value: locale,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: locale == current
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                Text(endonym),
              ],
            ),
          ),
      ],
    );
  }
}
