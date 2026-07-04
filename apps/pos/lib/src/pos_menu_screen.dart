import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'state/cart_controller.dart';
import 'state/menu_filter.dart';
import 'state/pos_menu_provider.dart';
import 'widgets/category_chips.dart';
import 'widgets/cart_panel.dart';
import 'widgets/device_settings_menu.dart';
import 'widgets/language_selector.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/modifier_selection_sheet.dart';
import 'widgets/outbox_status_indicator.dart';

/// The RF-100 POS demo screen: a filterable menu grid beside a live cart panel.
///
/// In-memory only (Riverpod + the domain Cart) — no Supabase, no auth, no order
/// submission, no payments, no persistence. All chrome comes from
/// `AppLocalizations`; menu item names are data. Responsive: a two-pane layout
/// on wide screens (the `flutter run -d chrome` case), stacked when narrow.
class PosMenuScreen extends StatelessWidget {
  const PosMenuScreen({super.key});

  static const double _cartPanelWidth = RestoflowPanelWidths.cartPanel;
  static const double _twoPaneBreakpoint = RestoflowBreakpoints.posTwoPane;

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
        // Device settings sprint: the ⋮ device menu rides beside the language
        // switcher — operational staff controls, never owner/admin actions.
        // RF-114: a compact order-outbox sync indicator (pending/syncing/failed/
        // synced) sits first so the cashier sees sync state while ringing orders.
        actions: const [
          OutboxStatusIndicator(),
          LanguageSelector(),
          DeviceSettingsMenu(),
        ],
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
        // Design-polish: a tighter heading row — the menu is a work surface,
        // not a landing page, so the title spends less vertical space.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            RestoflowSpacing.xs,
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
            loading: () => const _MenuSkeleton(),
            error: (_, _) =>
                _MenuLoadError(onRetry: () => ref.invalidate(posMenuProvider)),
            data: (menu) => _MenuGrid(menu: menu),
          ),
        ),
      ],
    );
  }
}

/// A static skeleton of the chips strip + item grid while the menu loads
/// (design-polish sprint): shows the layout that is coming instead of a bare
/// spinner. Deliberately non-animated (test harnesses pumpAndSettle) and free
/// of CircularProgressIndicator (spinner-count assertions elsewhere).
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.sm,
            RestoflowSpacing.lg,
            RestoflowSpacing.sm,
          ),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                const RestoflowSkeleton(
                  width: 96,
                  height: 40,
                  radius: RestoflowRadii.sm,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
              ],
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 188,
              crossAxisSpacing: RestoflowSpacing.md,
              mainAxisSpacing: RestoflowSpacing.md,
            ),
            itemCount: 8,
            itemBuilder: (_, _) =>
                const RestoflowSkeleton(height: 188, radius: RestoflowRadii.md),
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
    return RestoflowStateView(
      icon: Icons.cloud_off_outlined,
      tone: RestoflowTone.danger,
      message: l10n.posMenuLoadError,
      actions: [
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.authTryAgain),
        ),
      ],
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid({required this.menu});

  final PosMenuData menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final items = menuItemsForCategory(menu.items, selectedCategory);

    if (menu.items.isEmpty) {
      return RestoflowStateView(
        icon: Icons.restaurant_menu_outlined,
        title: l10n.posMenuEmptyTitle,
        message: l10n.posMenuEmptyBody,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryChips(categories: menu.categories),
        const SizedBox(height: RestoflowSpacing.xs),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 188,
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
                // Part F: the card marks configurable items (tune icon +
                // count) so the cashier knows this add opens the sheet.
                optionGroupCount: groups.length,
                onAdd: groups.isEmpty
                    ? () => controller.addItem(item)
                    : () => ModifierSelectionSheet.show(
                        context,
                        item: item,
                        groups: groups,
                        currencyCode: menu.currencyCode,
                        // The ACTIVE menu's category — the sheet header's
                        // thumbnail icon fallback (real ids never resolve via
                        // the demo lookup).
                        category: menu.categoryOf(item.categoryId),
                        onConfirm: (selections, note) => controller
                            .addItemWithModifiers(item, selections, note: note),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
