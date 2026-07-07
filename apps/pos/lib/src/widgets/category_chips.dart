import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../pos_palette.dart';
import '../state/menu_filter.dart';

/// Horizontal category filter chips (DESIGN-004): All + each category of the
/// ACTIVE menu. 44px pills — icon + name + a count badge — selected fills brand
/// green with a soft glow; unselected is white with a warm hairline. Selecting
/// a chip updates [selectedCategoryProvider], which filters the menu grid.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({required this.categories, this.itemCounts, super.key});

  final List<DemoCategory> categories;

  /// Optional per-category item counts (keyed by category id, plus
  /// [kAllCategoriesId] for the total). Null hides the count badges.
  final Map<String, int>? itemCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedCategoryProvider);
    final counts = itemCounts;

    void select(String id) =>
        ref.read(selectedCategoryProvider.notifier).state = id;

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.lg),
        children: [
          _CategoryChip(
            label: l10n.posCategoryAll,
            icon: Icons.apps,
            count: counts?[kAllCategoriesId],
            selected: selected == kAllCategoriesId,
            onSelected: () => select(kAllCategoriesId),
          ),
          for (final category in categories)
            _CategoryChip(
              label: category.name,
              icon: category.icon,
              count: counts?[category.id],
              selected: selected == category.id,
              onSelected: () => select(category.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimary : kRestoflowInk2;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: RestoflowSpacing.sm),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(
              color: selected ? scheme.primary : kRestoflowHairline,
            ),
            boxShadow: selected ? kPosGreenGlow : RestoflowShadows.xs,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onSelected,
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              child: Container(
                height: 44,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: RestoflowSpacing.md,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: RestoflowIconSizes.sm, color: foreground),
                    const SizedBox(width: RestoflowSpacing.sm),
                    // The label Text stays the tap target the tests use
                    // (find.text(<category name>)).
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: RestoflowSpacing.sm),
                      _CountBadge(count: count!, selected: selected),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected ? Colors.white.withValues(alpha: 0.22) : kPosChipBg;
    final fg = selected ? theme.colorScheme.onPrimary : kRestoflowInk3;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
