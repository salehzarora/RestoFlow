import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/menu_config_copy.dart';
import '../data/minor_money.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import '../models/menu_snapshot.dart';

/// OPS-043 Phase 4 — the "copy settings from an existing item" source picker.
///
/// Two steps in one dialog: a SEARCHABLE list of the restaurant's other items,
/// then a PREVIEW of exactly what the copy would bring over. Pressing the copy
/// action returns a [MenuCopiedConfig] — a LOCAL DRAFT. It writes nothing: this
/// widget holds no writer, no controller and no provider, so "Apply performs
/// zero server writes" is a property of the code, not of a code path.
///
/// TENANCY: the candidate list comes from the [MenuSnapshot] the caller already
/// loaded for the ACTIVE scope (`MenuManagementRepository.load(scope)` filters
/// on organization + restaurant). Nothing here queries anything, so an item of
/// another restaurant or another organization is unreachable by construction.
///
/// It performs NO provider lookups on purpose: `showDialog` builds under the
/// ROOT navigator, ABOVE the menu feature's nested `ProviderScope`, where the
/// menu seams throw `UnimplementedError` — the documented "Save stuck forever"
/// regression. Everything it needs is passed in.
Future<MenuCopiedConfig?> showMenuCopySourcePicker(
  BuildContext context, {
  required MenuSnapshot snapshot,
  required String currencyCode,
  String? excludeItemId,
}) {
  return showDialog<MenuCopiedConfig>(
    context: context,
    builder: (_) => _MenuCopySourceDialog(
      snapshot: snapshot,
      currencyCode: currencyCode,
      excludeItemId: excludeItemId,
    ),
  );
}

/// The candidate source items: every non-deleted item of the loaded (already
/// scoped) snapshot except [excludeItemId] — an item can never be copied onto
/// itself. Ordered by category, then by the category's own item order.
List<MenuItem> menuCopySourceCandidates(
  MenuSnapshot snapshot, {
  String? excludeItemId,
}) {
  return <MenuItem>[
    for (final category in snapshot.visibleCategories())
      for (final item in snapshot.itemsForCategory(category.id))
        if (item.id != excludeItemId) item,
  ];
}

/// Case-insensitive name/category search over the candidates.
List<MenuItem> filterMenuCopySources(
  List<MenuItem> candidates,
  Map<String, String> categoryNames,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return candidates;
  return <MenuItem>[
    for (final item in candidates)
      if (item.name.toLowerCase().contains(needle) ||
          (categoryNames[item.menuCategoryId] ?? '').toLowerCase().contains(
            needle,
          ))
        item,
  ];
}

class _MenuCopySourceDialog extends StatefulWidget {
  const _MenuCopySourceDialog({
    required this.snapshot,
    required this.currencyCode,
    required this.excludeItemId,
  });

  final MenuSnapshot snapshot;
  final String currencyCode;
  final String? excludeItemId;

  @override
  State<_MenuCopySourceDialog> createState() => _MenuCopySourceDialogState();
}

class _MenuCopySourceDialogState extends State<_MenuCopySourceDialog> {
  final TextEditingController _search = TextEditingController();

  /// null => the list step; non-null => the preview step for that item.
  MenuItem? _selected;

  late final List<MenuItem> _candidates = menuCopySourceCandidates(
    widget.snapshot,
    excludeItemId: widget.excludeItemId,
  );

  late final Map<String, String> _categoryNames = <String, String>{
    for (final MenuCategory category in widget.snapshot.visibleCategories())
      category.id: category.name,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = _selected;
    return AlertDialog(
      title: Text(
        selected == null ? l10n.menuCopyFromItemTitle : selected.name,
      ),
      content: SizedBox(
        width: 460,
        child: selected == null
            ? _listStep(context, l10n)
            : _previewStep(context, l10n, selected),
      ),
      actions: selected == null
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.menuCancelAction),
              ),
            ]
          : _previewActions(context, l10n, selected),
    );
  }

  Widget _listStep(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Text(
          l10n.menuCopyFromItemEmpty,
          key: const ValueKey('menu-copy-source-empty'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final matches = filterMenuCopySources(
      _candidates,
      _categoryNames,
      _search.text,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('menu-copy-source-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.menuCopyFromItemSearch,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            child: Text(
              l10n.menuCopyFromItemNoMatch,
              key: const ValueKey('menu-copy-source-no-match'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (context, index) =>
                  _sourceTile(context, l10n, matches[index]),
            ),
          ),
      ],
    );
  }

  Widget _sourceTile(
    BuildContext context,
    AppLocalizations l10n,
    MenuItem item,
  ) {
    final groups = widget.snapshot.modifiersForItem(item.id);
    final options = groups.fold(
      0,
      (int total, group) =>
          total + widget.snapshot.optionsForModifier(group.id).length,
    );
    final category = _categoryNames[item.menuCategoryId] ?? '';
    final price = formatMinorUnits(item.basePriceMinor, widget.currencyCode);
    return ListTile(
      key: ValueKey('menu-copy-source-${item.id}'),
      leading: const Icon(Icons.content_copy_outlined),
      title: Text(item.name),
      // Enough identity to tell two similarly-named items apart: where it
      // lives, what it costs, and how much configuration it carries.
      subtitle: Text(
        <String>[
          if (category.isNotEmpty) category,
          price,
          '${l10n.menuCopyPreviewGroups(groups.length)} · '
              '${l10n.menuCopyPreviewOptions(options)}',
        ].join(' · '),
      ),
      onTap: () => setState(() => _selected = item),
    );
  }

  Widget _previewStep(
    BuildContext context,
    AppLocalizations l10n,
    MenuItem item,
  ) {
    final theme = Theme.of(context);
    final config = buildMenuCopiedConfig(
      snapshot: widget.snapshot,
      source: item,
    );
    final lines = <String>[
      l10n.menuCopyPreviewBasePrice(
        formatMinorUnits(config.basePriceMinor, widget.currencyCode),
      ),
      l10n.menuCopyPreviewGroups(config.groupCount),
      l10n.menuCopyPreviewOptions(config.optionCount),
      l10n.menuCopyPreviewPrepRows(config.prepComponents.length),
      if (config.kitchenCountOptionCount > 0)
        l10n.menuCopyPreviewKitchenCounts(config.kitchenCountOptionCount),
      if (config.classifierLinkCount > 0)
        l10n.menuCopyPreviewClassifiers(config.classifierLinkCount),
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.menuCopyPreviewTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: RestoflowSpacing.sm),
          if (config.isEmpty)
            Text(
              l10n.menuCopyPreviewNothing,
              key: const ValueKey('menu-copy-preview-nothing'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: RestoflowSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check,
                      size: RestoflowIconSizes.sm,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: RestoflowSpacing.xs),
                    Expanded(
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: RestoflowSpacing.md),
          // The other half of the contract, said out loud: identity is never
          // copied, so nobody has to discover it by saving.
          Text(
            l10n.menuCopyPreviewExcluded,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            l10n.menuCopyDraftNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _previewActions(
    BuildContext context,
    AppLocalizations l10n,
    MenuItem item,
  ) {
    final config = buildMenuCopiedConfig(
      snapshot: widget.snapshot,
      source: item,
    );
    return <Widget>[
      TextButton(
        key: const ValueKey('menu-copy-preview-back'),
        onPressed: () => setState(() => _selected = null),
        child: Text(l10n.menuCopyFromItemChange),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.menuCancelAction),
      ),
      FilledButton.icon(
        key: const ValueKey('menu-copy-preview-apply'),
        onPressed: config.isEmpty
            ? null
            : () => Navigator.of(context).pop(config),
        icon: const Icon(Icons.content_copy, size: RestoflowIconSizes.sm),
        label: Text(l10n.menuCopyApplyAction),
      ),
    ];
  }
}
