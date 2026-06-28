import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'state/cart_controller.dart';
import 'state/menu_filter.dart';
import 'widgets/category_chips.dart';
import 'widgets/cart_panel.dart';
import 'widgets/language_selector.dart';
import 'widgets/menu_item_card.dart';

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
class _MenuPane extends ConsumerWidget {
  const _MenuPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final items = menuItemsForCategory(selectedCategory);

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
        const CategoryChips(),
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
              return MenuItemCard(
                item: item,
                onAdd: () => controller.addItem(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
