import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/menu_category.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_snapshot.dart';
import '../state/menu_providers.dart';
import 'menu_badges.dart';
import 'menu_entity_forms.dart';
import 'menu_panel_header.dart';
import 'menu_state_views.dart';

/// The categories master panel (RF-111): add / edit / soft-delete categories and
/// select one to drive the items detail panel.
class MenuCategoryList extends ConsumerWidget {
  const MenuCategoryList({
    required this.snapshot,
    required this.selectedCategoryId,
    required this.onSelect,
    super.key,
  });

  final MenuSnapshot snapshot;
  final String? selectedCategoryId;
  final ValueChanged<String> onSelect;

  Future<void> _add(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final saved = await showCategoryFormDialog(context);
    if (saved && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
    }
  }

  Future<void> _edit(BuildContext context, MenuCategory category) async {
    final l10n = AppLocalizations.of(context);
    final saved = await showCategoryFormDialog(context, existing: category);
    if (saved && context.mounted) {
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
            (failure) => l10n.menuWriteProblem,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = snapshot.visibleCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanelHeader(
          title: l10n.menuCategoriesHeading,
          actionLabel: l10n.menuAddCategory,
          onAction: () => _add(context),
        ),
        const Divider(height: 1),
        Expanded(
          child: categories.isEmpty
              ? MenuMessageView(
                  icon: Icons.category_outlined,
                  message: l10n.menuEmptyCategories,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: RestoflowSpacing.sm,
                  ),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: RestoflowSpacing.xs),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final count = snapshot.itemsForCategory(category.id).length;
                    final selected = category.id == selectedCategoryId;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      title: Text(category.name),
                      subtitle: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: RestoflowSpacing.xs,
                        ),
                        child: Wrap(
                          spacing: RestoflowSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(l10n.menuItemCount(count)),
                            MenuEntityBadges(
                              isActive: category.isActive,
                              branchId: category.branchId,
                            ),
                          ],
                        ),
                      ),
                      onTap: () => onSelect(category.id),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _edit(context, category);
                          if (value == 'delete')
                            _delete(context, ref, category);
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}
