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
import 'menu_components.dart';
import 'menu_entity_forms.dart';
import 'menu_item_thumbnail.dart';
import 'menu_panel_header.dart';

/// The items detail panel for the selected category (RF-111 + menu/media
/// sprint Part F — a product-catalog read): rows carry a real image thumbnail
/// (signed-URL via the surface's storage seam, placeholder fallback), the
/// name, a prominent price, active/scope badges, localized tag tone pills,
/// and a compact modifier-group count. Opening an item raises [onOpenEditor]
/// (the in-place editor), never a route.
class MenuItemList extends ConsumerWidget {
  const MenuItemList({
    required this.snapshot,
    required this.categoryId,
    required this.scope,
    required this.onOpenEditor,
    required this.query,
    required this.filter,
    super.key,
  });

  final MenuSnapshot snapshot;
  final String categoryId;
  final MenuScope scope;
  final ValueChanged<MenuEditorTarget> onOpenEditor;
  final String query;
  final MenuActiveFilter filter;

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
    final all = snapshot.itemsForCategory(categoryId);
    final needle = query.trim().toLowerCase();
    final items = all
        .where(
          (i) =>
              menuFilterAllows(filter, i.isActive) &&
              (needle.isEmpty || i.name.toLowerCase().contains(needle)),
        )
        .toList();

    final Widget body;
    if (all.isEmpty) {
      body = MenuStateView(
        icon: Icons.restaurant_menu_outlined,
        title: l10n.menuEmptyItems,
        body: l10n.menuEmptyItemsBody,
        action: FilledButton.icon(
          onPressed: () =>
              onOpenEditor(MenuEditorTarget(categoryId: categoryId)),
          icon: const Icon(Icons.add),
          label: Text(l10n.menuAddItem),
        ),
      );
    } else if (items.isEmpty) {
      body = MenuStateView(
        icon: Icons.search_off,
        title: l10n.menuNoResults,
        body: l10n.menuNoResultsBody,
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(RestoflowSpacing.sm),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: RestoflowSpacing.xs),
        itemBuilder: (context, index) {
          final item = items[index];
          return _ItemTile(
            item: item,
            // Live (non-deleted) modifier groups from the snapshot the screen
            // already holds — no extra read.
            modifierGroupCount: snapshot.modifiersForItem(item.id).length,
            onTap: () => onOpenEditor(MenuEditorTarget(item: item)),
            onEdit: () => onOpenEditor(MenuEditorTarget(item: item)),
            onDelete: () => _delete(context, ref, item),
          );
        },
      );
    }

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
        Expanded(child: body),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.modifierGroupCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final MenuItem item;

  /// Live modifier groups on this item (0 = no indicator).
  final int modifierGroupCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.sm),
          child: Row(
            children: [
              // Real thumbnail when this surface has image storage wired and
              // the item carries an image; the familiar placeholder otherwise.
              MenuItemThumbnail(item: item),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description != null &&
                        item.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: RestoflowSpacing.xxs),
                      Text(
                        item.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: RestoflowSpacing.xs),
                    // One wrapping strip: status/scope badges, tag tone pills,
                    // and the compact modifier-group count — pills WRAP so the
                    // row never overflows at narrow detail-pane widths.
                    Wrap(
                      spacing: RestoflowSpacing.xs,
                      runSpacing: RestoflowSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MenuEntityBadges(
                          isActive: item.isActive,
                          branchId: item.branchId,
                        ),
                        ...buildMenuTagPills(context, item.tags),
                        if (modifierGroupCount > 0)
                          Tooltip(
                            message: l10n.menuModifierGroupCount(
                              modifierGroupCount,
                            ),
                            child: MenuPill(
                              label: modifierGroupCount.toString(),
                              icon: Icons.tune,
                              background: scheme.surfaceContainerHighest,
                              foreground: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(
                formatMinorUnits(item.basePriceMinor, item.currencyCode),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
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
