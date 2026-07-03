import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/menu_category.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_snapshot.dart';
import '../state/menu_providers.dart';
import 'menu_badges.dart';
import 'menu_components.dart';
import 'menu_entity_forms.dart';
import 'menu_panel_header.dart';

/// The categories master panel (RF-111): a polished, search/filter-aware list of
/// categories. Add / edit / soft-delete and select-to-drive-the-items-panel.
class MenuCategoryList extends ConsumerWidget {
  const MenuCategoryList({
    required this.snapshot,
    required this.selectedCategoryId,
    required this.onSelect,
    required this.query,
    required this.filter,
    super.key,
  });

  final MenuSnapshot snapshot;
  final String? selectedCategoryId;
  final ValueChanged<String> onSelect;
  final String query;
  final MenuActiveFilter filter;

  Future<void> _add(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (await showCategoryFormDialog(context) && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
    }
  }

  Future<void> _edit(BuildContext context, MenuCategory category) async {
    final l10n = AppLocalizations.of(context);
    if (await showCategoryFormDialog(context, existing: category) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MenuCategory category,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!await showMenuDeleteConfirm(context)) return;
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .softDelete(entity: MenuEntityType.category, id: category.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.fold(
            (_) => l10n.menuDeletedSnack,
            (_) => l10n.menuWriteProblem,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = snapshot.visibleCategories();
    final needle = query.trim().toLowerCase();
    final categories = all
        .where(
          (c) =>
              menuFilterAllows(filter, c.isActive) &&
              (needle.isEmpty || c.name.toLowerCase().contains(needle)),
        )
        .toList();

    final Widget body;
    if (all.isEmpty) {
      body = MenuStateView(
        icon: Icons.category_outlined,
        title: l10n.menuEmptyCategories,
        body: l10n.menuEmptyCategoriesBody,
        action: FilledButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: Text(l10n.menuAddCategory),
        ),
      );
    } else if (categories.isEmpty) {
      body = MenuStateView(
        icon: Icons.search_off,
        title: l10n.menuNoResults,
        body: l10n.menuNoResultsBody,
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(RestoflowSpacing.sm),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(height: RestoflowSpacing.xs),
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryTile(
            category: category,
            itemCount: snapshot.itemsForCategory(category.id).length,
            selected: category.id == selectedCategoryId,
            onTap: () => onSelect(category.id),
            onEdit: () => _edit(context, category),
            onDelete: () => _delete(context, ref, category),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanelHeader(title: l10n.menuCategoriesHeading),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.itemCount,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final MenuCategory category;
  final int itemCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(RestoflowRadii.md);
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                ),
                child: Icon(
                  Icons.local_dining_outlined,
                  size: RestoflowIconSizes.md,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RestoflowSpacing.xxs),
                    Wrap(
                      spacing: RestoflowSpacing.sm,
                      runSpacing: RestoflowSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.menuItemCount(itemCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        MenuEntityBadges(
                          isActive: category.isActive,
                          branchId: category.branchId,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(l10n.menuEditAction),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.menuDeleteAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
