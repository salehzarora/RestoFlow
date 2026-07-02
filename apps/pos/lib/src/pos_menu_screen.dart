import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'state/cart_controller.dart';
import 'state/menu_filter.dart';
import 'state/pos_menu_provider.dart';
import 'widgets/category_chips.dart';
import 'widgets/cart_panel.dart';
import 'widgets/language_selector.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_selection_sheet.dart';

/// The RF-100 POS demo screen: a filterable menu grid beside a live cart panel.
///
/// In-memory only (Riverpod + the domain Cart) — no Supabase, no auth, no order
/// submission, no payments, no persistence. All chrome comes from
/// `AppLocalizations`; menu item names are data. Responsive: a two-pane layout
/// on wide screens (the `flutter run -d chrome` case), stacked when narrow.
class PosMenuScreen extends StatelessWidget {
  const PosMenuScreen({super.key});

  static const double _cartPanelWidth = 400;
  static const double _twoPaneBreakpoint = 820;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale, color: theme.colorScheme.primary),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(l10n.posAppTitle),
          ],
        ),
        actions: const [LanguageSelector()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _twoPaneBreakpoint;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(child: _MenuPane()),
                VerticalDivider(width: 1),
                SizedBox(width: _cartPanelWidth, child: CartPanel()),
              ],
            );
          }
          return Column(
            children: const [
              Expanded(flex: 3, child: _MenuPane()),
              Divider(height: 1),
              Expanded(flex: 2, child: CartPanel()),
            ],
          );
        },
      ),
    );
  }
}

/// The menu side: heading, category filter chips, and the filtered item grid.
/// Sells from the ACTIVE menu ([posMenuProvider]): the demo consts in demo
/// mode, the real backend menu in real mode — with honest loading/error/empty
/// states (never a fake menu).
class _MenuPane extends ConsumerWidget {
  const _MenuPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final menuAsync = ref.watch(posMenuProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            RestoflowSpacing.sm,
          ),
          child: Text(
            l10n.posMenuHeading,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: menuAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                _MenuLoadError(onRetry: () => ref.invalidate(posMenuProvider)),
            data: (menu) => _MenuGrid(menu: menu),
          ),
        ),
      ],
    );
  }
}

class _MenuLoadError extends StatelessWidget {
  const _MenuLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: RestoflowSpacing.md),
            Text(l10n.posMenuLoadError, textAlign: TextAlign.center),
            const SizedBox(height: RestoflowSpacing.md),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.authTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid({required this.menu});

  final PosMenuData menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final items = menuItemsForCategory(menu.items, selectedCategory);

    if (menu.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.restaurant_menu_outlined, size: 40),
              const SizedBox(height: RestoflowSpacing.md),
              Text(l10n.posMenuEmptyTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: RestoflowSpacing.xs),
              Text(l10n.posMenuEmptyBody, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryChips(categories: menu.categories),
        const SizedBox(height: RestoflowSpacing.sm),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 176,
              crossAxisSpacing: RestoflowSpacing.md,
              mainAxisSpacing: RestoflowSpacing.md,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              // An item WITH modifier groups opens the option picker first
              // (required groups enforced there); plain items add directly.
              final groups = menu.groupsForItem(item.id);
              return MenuItemCard(
                item: item,
                category: menu.categoryOf(item.categoryId),
                currencyCode: menu.currencyCode,
                onAdd: groups.isEmpty
                    ? () => controller.addItem(item)
                    : () => ModifierSelectionSheet.show(
                        context,
                        item: item,
                        groups: groups,
                        currencyCode: menu.currencyCode,
                        onConfirm: (selections) =>
                            controller.addItemWithModifiers(item, selections),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
