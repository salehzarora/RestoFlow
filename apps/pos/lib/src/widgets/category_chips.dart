import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../design/pos_motion.dart';
import '../pos_palette.dart';
import '../state/menu_filter.dart';
import '../state/pos_device_accent.dart';

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
    // POS-PREMIUM-VISUAL-POLISH-001: the active-filter marker wears THIS
    // terminal's secondary accent (a non-critical highlight by contract).
    final accent = ref.watch(posDeviceAccentColorProvider);
    final counts = itemCounts;

    void select(String id) =>
        ref.read(selectedCategoryProvider.notifier).state = id;

    // The 56px rail keeps 40px chips centred, so the effective touch target
    // stays >= 44 while the chip itself reads lighter (spec §14).
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.lg),
        children: [
          PosEntrance(
            index: 0,
            child: PosTapBump(
              child: _CategoryChip(
                label: l10n.posCategoryAll,
                icon: Icons.apps,
                count: counts?[kAllCategoriesId],
                selected: selected == kAllCategoriesId,
                accent: accent,
                onSelected: () => select(kAllCategoriesId),
              ),
            ),
          ),
          for (final (i, category) in categories.indexed)
            PosEntrance(
              index: i + 1,
              child: PosTapBump(
                child: _CategoryChip(
                  label: category.name,
                  icon: category.icon,
                  count: counts?[category.id],
                  selected: selected == category.id,
                  accent: accent,
                  onSelected: () => select(category.id),
                ),
              ),
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
    required this.accent,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final int? count;
  final bool selected;

  /// This terminal's secondary accent — the active-marker colour.
  final Color accent;

  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimary : kRestoflowInk2;

    return Padding(
      // 6px between chips (spec §14) — the rail is a set, not a row of cards.
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Center(
        child: DecoratedBox(
          // POS-VISUAL-REDESIGN-PHASE-1-007: an UNSELECTED chip carries no
          // border and no shadow — it is a filter, not a card. The selected
          // chip is then the only chip on the rail with any elevation, which
          // is what makes the active filter unmistakable at a glance.
          decoration: BoxDecoration(
            color: selected ? scheme.primary : kPosChipBg,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            boxShadow: selected ? kPosChipSelectedShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onSelected,
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              child: Container(
                height: 40,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: RestoflowSpacing.md,
                ),
                child: Stack(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: RestoflowIconSizes.sm,
                          color: foreground,
                        ),
                        const SizedBox(width: 6),
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
                          const SizedBox(width: 6),
                          _CountBadge(count: count!, selected: selected),
                        ],
                      ],
                    ),
                    // UI-ORANGE-BALANCE-POLISH-001 → POS-PREMIUM-VISUAL-POLISH:
                    // the active filter earns a thin underline in THIS
                    // terminal's secondary accent (a non-critical highlight —
                    // the device-accent contract).
                    //
                    // The chip already had TWO non-colour signals — a shadow no
                    // other chip carries, and a w700 label — so this is a third
                    // cue rather than the only one, and the filter stays legible
                    // for anyone who cannot separate the hues.
                    //
                    // Positioned, so it contributes nothing to the measured
                    // size: the rail is a horizontally scrolling set and a chip
                    // that grew on selection would shove its neighbours sideways
                    // under the cashier's finger mid-tap.
                    if (selected)
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            key: const Key('category-chip-active-marker'),
                            height: 2,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(
                                RestoflowRadii.pill,
                              ),
                            ),
                          ),
                        ),
                      ),
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
    final bg = selected
        ? Colors.white.withValues(alpha: 0.24)
        : kPosCountBadgeBg;
    final fg = selected ? theme.colorScheme.onPrimary : kRestoflowInk3;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        // 7px, not a full pill — the spec's "excessive rounded pills" note.
        borderRadius: BorderRadius.circular(7),
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
