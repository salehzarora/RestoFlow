/// MENU-CATEGORY-ICON-PICKER-OPS-044 Phase 3 — the visual category icon picker.
///
/// It performs NO provider lookups, for the reason documented on
/// [showMenuCopySourcePicker]: `showDialog` builds under the ROOT navigator,
/// ABOVE the menu feature's nested `ProviderScope`, so a Riverpod read from
/// inside resolves against the wrong container and throws mid-save.
/// Everything it needs arrives as plain arguments; it returns a plain
/// selection and writes nothing. The caller owns state and persistence.
///
/// (`AppLocalizations.of` is fine here — `Localizations` is an inherited widget
/// installed by `MaterialApp`, above the root navigator, not a provider.)
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// What the picker hands back.
///
/// A distinct type rather than a bare `String?` because "the owner chose
/// Automatic" and "the owner cancelled" are different outcomes and a nullable
/// string cannot tell them apart — the dialog pops null on cancel and a
/// [MenuCategoryIconSelection] (whose [iconKey] may itself be null) on confirm.
@immutable
class MenuCategoryIconSelection {
  const MenuCategoryIconSelection(this.iconKey);

  /// The chosen registry key, or null for "Automatic" (no explicit icon).
  final String? iconKey;

  @override
  bool operator ==(Object other) =>
      other is MenuCategoryIconSelection && other.iconKey == iconKey;

  @override
  int get hashCode => iconKey.hashCode;
}

/// Filters the registry for [query].
///
/// Matching is deliberately three-way so the box works in every locale: the
/// LOCALIZED name (an Arabic or Hebrew owner types their own language), the
/// stable [MenuCategoryIconDefinition.key], and the ASCII
/// [MenuCategoryIconDefinition.searchTokens] synonyms ("sandwich" finds the
/// burger). An empty query returns everything, in registry order.
List<MenuCategoryIconDefinition> filterMenuCategoryIcons(
  String query,
  String Function(String key) nameOf,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return MenuCategoryIcons.all;
  return <MenuCategoryIconDefinition>[
    for (final definition in MenuCategoryIcons.all)
      if (nameOf(definition.key).toLowerCase().contains(needle) ||
          definition.key.toLowerCase().contains(needle) ||
          definition.searchTokens.any((t) => t.contains(needle)))
        definition,
  ];
}

/// Shows the picker. Returns null when the owner cancels.
Future<MenuCategoryIconSelection?> showMenuCategoryIconPicker(
  BuildContext context, {
  required String? selectedKey,
}) {
  return showDialog<MenuCategoryIconSelection>(
    context: context,
    builder: (_) => _MenuCategoryIconPickerDialog(selectedKey: selectedKey),
  );
}

class _MenuCategoryIconPickerDialog extends StatefulWidget {
  const _MenuCategoryIconPickerDialog({required this.selectedKey});

  final String? selectedKey;

  @override
  State<_MenuCategoryIconPickerDialog> createState() =>
      _MenuCategoryIconPickerDialogState();
}

class _MenuCategoryIconPickerDialogState
    extends State<_MenuCategoryIconPickerDialog> {
  late final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _choose(String? key) =>
      Navigator.of(context).pop(MenuCategoryIconSelection(key));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matches = filterMenuCategoryIcons(_query, l10n.menuCategoryIconName);
    final searching = _query.trim().isNotEmpty;

    // A key stored by a NEWER build than this one. It is offered as a selected
    // tile so the owner can SEE that something is set and choose to keep it —
    // silently dropping it here is how a forward-compatible value gets wiped.
    final unknownSelected =
        widget.selectedKey != null &&
        !MenuCategoryIcons.isKnownCategoryIconKey(widget.selectedKey);

    return AlertDialog(
      title: Text(l10n.menuCategoryIconPickerTitle),
      contentPadding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.lg,
        0,
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('menu-category-icon-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.menuCategoryIconSearchHint,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        l10n.menuCategoryIconNoResults,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        // "Automatic" stays reachable while browsing; hiding it
                        // during a search would strand an owner who typed
                        // something before deciding to clear the icon.
                        if (!searching) ...[
                          _AutomaticTile(
                            selected: widget.selectedKey == null,
                            onTap: () => _choose(null),
                          ),
                          if (unknownSelected) ...[
                            const SizedBox(height: RestoflowSpacing.xs),
                            _CustomKeyTile(
                              onTap: () => _choose(widget.selectedKey),
                            ),
                          ],
                          const SizedBox(height: RestoflowSpacing.md),
                        ],
                        for (final group in MenuCategoryIconGroup.values)
                          ..._section(context, group, matches),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.menuCancelAction),
        ),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    MenuCategoryIconGroup group,
    List<MenuCategoryIconDefinition> matches,
  ) {
    final rows = matches.where((d) => d.group == group).toList();
    if (rows.isEmpty) return const <Widget>[];
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(
          start: RestoflowSpacing.xxs,
          bottom: RestoflowSpacing.xs,
          top: RestoflowSpacing.xs,
        ),
        child: Text(
          l10n.menuCategoryIconGroupLabel(group.name),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Wrap(
        spacing: RestoflowSpacing.xs,
        runSpacing: RestoflowSpacing.xs,
        children: [
          for (final definition in rows)
            _IconTile(
              definition: definition,
              label: l10n.menuCategoryIconName(definition.key),
              selected: definition.key == widget.selectedKey,
              onTap: () => _choose(definition.key),
            ),
        ],
      ),
      const SizedBox(height: RestoflowSpacing.md),
    ];
  }
}

/// The reset-to-default choice, first in the list and visually distinct.
class _AutomaticTile extends StatelessWidget {
  const _AutomaticTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        key: const ValueKey('menu-category-icon-automatic'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: RestoflowIconSizes.md),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  l10n.menuCategoryIconAutomatic,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: RestoflowIconSizes.md,
                  color: scheme.primary,
                  semanticLabel: l10n.menuCategoryIconSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The currently stored key when THIS build has no glyph for it.
class _CustomKeyTile extends StatelessWidget {
  const _CustomKeyTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: InkWell(
        key: const ValueKey('menu-category-icon-custom'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.extension, size: RestoflowIconSizes.md),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Text(
                  l10n.menuCategoryIconCustom,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Icon(
                Icons.check_circle,
                size: RestoflowIconSizes.md,
                color: scheme.primary,
                semanticLabel: l10n.menuCategoryIconSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pickable glyph. Fixed width so the grid stays even across locales while
/// the label wraps rather than overflowing.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.definition,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MenuCategoryIconDefinition definition;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 108,
      height: 92,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          side: selected
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          key: ValueKey('menu-category-icon-${definition.key}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          child: Semantics(
            selected: selected,
            label: selected
                ? '$label — ${l10n.menuCategoryIconSelected}'
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.xxs,
                vertical: RestoflowSpacing.xs,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    definition.icon,
                    size: RestoflowIconSizes.lg,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
