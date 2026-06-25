import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/minor_money.dart';
import '../models/menu_entity_type.dart';
import '../models/menu_item.dart';
import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../screens/item_editor_screen.dart';
import '../state/menu_providers.dart';
import 'menu_badges.dart';
import 'menu_entity_forms.dart';
import 'menu_panel_header.dart';
import 'menu_state_views.dart';

/// The items detail panel for the selected category (RF-111): add / open / edit
/// / soft-delete items. Opening an item raises [onOpenEditor] (the in-place
/// editor), never a pushed route.
class MenuItemList extends ConsumerWidget {
  const MenuItemList({
    required this.snapshot,
    required this.categoryId,
    required this.scope,
    required this.onOpenEditor,
    super.key,
  });

  final MenuSnapshot snapshot;
  final String categoryId;
  final MenuScope scope;
  final ValueChanged<MenuEditorTarget> onOpenEditor;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MenuItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!await showMenuDeleteConfirm(context)) return;
    final outcome = await ref
        .read(menuWriteControllerProvider)
        .softDelete(entity: MenuEntityType.item, id: item.id);
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
    final items = snapshot.itemsForCategory(categoryId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanelHeader(
          title: l10n.menuItemsHeading,
          actionLabel: l10n.menuAddItem,
          onAction: () =>
              onOpenEditor(MenuEditorTarget(categoryId: categoryId)),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? MenuMessageView(
                  icon: Icons.restaurant_menu_outlined,
                  message: l10n.menuEmptyItems,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: RestoflowSpacing.sm,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: RestoflowSpacing.xs),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: RestoflowSpacing.xs,
                        ),
                        child: Wrap(
                          spacing: RestoflowSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatMinorUnits(
                                item.basePriceMinor,
                                item.currencyCode,
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            MenuEntityBadges(
                              isActive: item.isActive,
                              branchId: item.branchId,
                            ),
                          ],
                        ),
                      ),
                      onTap: () => onOpenEditor(MenuEditorTarget(item: item)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            onOpenEditor(MenuEditorTarget(item: item));
                          }
                          if (value == 'delete') _delete(context, ref, item);
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
