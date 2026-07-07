import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'pos_palette.dart';
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
import 'widgets/pos_bottom_bar.dart';

/// The RestoFlow POS cashier screen (DESIGN-004 Warm/Bento): a warm-canvas
/// menu grid + search beside a live cart. Responsive from the ACTUAL available
/// width (never the platform): desktop/tablet/compact-landscape show a side
/// cart; phone shows a full-width menu with a dark bottom cart bar + slide-up
/// sheet. Sells from the ACTIVE menu ([posMenuProvider]) with honest
/// loading/error/empty states — all chrome is localized; item names are data.
class PosMenuScreen extends StatelessWidget {
  const PosMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: kRestoflowCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: kRestoflowHairline)),
        titleSpacing: RestoflowSpacing.lg,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The gradient brand tile (§6.1).
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: kRestoflowBrandGradient,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
              ),
              child: const Icon(
                Icons.point_of_sale,
                color: Colors.white,
                size: RestoflowIconSizes.md,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Flexible(
              child: Text(
                l10n.posAppTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: kRestoflowInk,
                ),
              ),
            ),
          ],
        ),
        actions: const [
          OutboxStatusIndicator(),
          LanguageSelector(),
          DeviceSettingsMenu(),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mode = posLayoutModeFor(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          );

          if (mode == PosLayoutMode.phone) {
            return const Column(
              children: [
                Expanded(child: _MenuPane()),
                PosBottomBar(),
              ],
            );
          }

          final compact = mode == PosLayoutMode.compactLandscape;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _MenuPane()),
              SizedBox(
                width: posCartWidthFor(mode),
                child: CartPanel(compact: compact),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The menu side: a header (title + item count + search) and the filtered grid.
class _MenuPane extends ConsumerWidget {
  const _MenuPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(posMenuProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MenuHeader(itemCount: menuAsync.valueOrNull?.items.length),
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

/// The menu header: "Menu" + live item count + the search field (§6.2).
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.itemCount});

  final int? itemCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            l10n.posMenuHeading,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: kRestoflowInk,
            ),
          ),
          if (itemCount != null) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            Text(
              l10n.posMenuItemCount(itemCount!),
              style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk3),
            ),
          ],
          const SizedBox(width: RestoflowSpacing.md),
          const Expanded(child: _MenuSearchField()),
        ],
      ),
    );
  }
}

/// A lightweight client-side search field (§6.2) — filters the ALREADY-LOADED
/// menu by name via [searchQueryProvider]. No backend call.
class _MenuSearchField extends ConsumerStatefulWidget {
  const _MenuSearchField();

  @override
  ConsumerState<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends ConsumerState<_MenuSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasText = _controller.text.isNotEmpty;
    return SizedBox(
      height: 44,
      child: TextField(
        key: const Key('menu-search-field'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (value) =>
            ref.read(searchQueryProvider.notifier).state = value,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.posMenuSearchHint,
          prefixIcon: const Icon(Icons.search, size: RestoflowIconSizes.md),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: RestoflowIconSizes.sm),
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  onPressed: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            borderSide: const BorderSide(color: kRestoflowHairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            borderSide: const BorderSide(color: kRestoflowHairline),
          ),
        ),
      ),
    );
  }
}

/// A static skeleton of the chips strip + item grid while the menu loads.
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
                  height: 44,
                  radius: RestoflowRadii.md,
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
              maxCrossAxisExtent: 230,
              mainAxisExtent: 240,
              crossAxisSpacing: RestoflowSpacing.md,
              mainAxisSpacing: RestoflowSpacing.md,
            ),
            itemCount: 8,
            itemBuilder: (_, _) =>
                const RestoflowSkeleton(height: 240, radius: RestoflowRadii.lg),
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
    final query = ref.watch(searchQueryProvider);
    final items = filterMenuItems(menu.items, selectedCategory, query);

    // In-cart quantities per item id (presentation only — for the card badge).
    final cart = ref.watch(cartControllerProvider);
    final inCart = <String, int>{};
    for (final line in cart.lines) {
      inCart[line.menuItemId] = (inCart[line.menuItemId] ?? 0) + line.quantity;
    }

    // Per-category counts for the chip badges (All = total).
    final counts = <String, int>{kAllCategoriesId: menu.items.length};
    for (final category in menu.categories) {
      counts[category.id] = menu.items
          .where((i) => i.categoryId == category.id)
          .length;
    }

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
        CategoryChips(categories: menu.categories, itemCounts: counts),
        const SizedBox(height: RestoflowSpacing.xs),
        Expanded(
          child: items.isEmpty
              ? RestoflowStateView(
                  icon: Icons.search_off_outlined,
                  title: l10n.posSearchNoResults,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Size the grid cell so a fixed 4:3 image band + the card
                    // body fit exactly (no overflow, no gap) at every width.
                    const maxExtent = 230.0;
                    const spacing = RestoflowSpacing.md;
                    const bodyHeight = 104.0;
                    final contentWidth =
                        constraints.maxWidth - 2 * RestoflowSpacing.lg;
                    final cols = (contentWidth / (maxExtent + spacing))
                        .ceil()
                        .clamp(1, 999);
                    final cellWidth =
                        (contentWidth - (cols - 1) * spacing) / cols;
                    final mainAxisExtent = cellWidth * 3 / 4 + bodyHeight;
                    return GridView.builder(
                      padding: const EdgeInsets.all(RestoflowSpacing.lg),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisExtent: mainAxisExtent,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final groups = menu.groupsForItem(item.id);
                        return MenuItemCard(
                          item: item,
                          category: menu.categoryOf(item.categoryId),
                          currencyCode: menu.currencyCode,
                          optionGroupCount: groups.length,
                          inCartQuantity: inCart[item.id] ?? 0,
                          onAdd: groups.isEmpty
                              ? () => controller.addItem(item)
                              : () => ModifierSelectionSheet.show(
                                  context,
                                  item: item,
                                  groups: groups,
                                  currencyCode: menu.currencyCode,
                                  category: menu.categoryOf(item.categoryId),
                                  onConfirm: (selections, note) =>
                                      controller.addItemWithModifiers(
                                        item,
                                        selections,
                                        note: note,
                                      ),
                                ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
