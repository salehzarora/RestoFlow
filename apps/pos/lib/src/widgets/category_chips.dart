import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../design/pos_motion.dart';
import '../design/pos_visual_tokens.dart' show kPosTabPillBg, kPosTrackRadius;
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

    // The 56px rail centres the 34px pills; each pill's InkWell carries a
    // 5px transparent vertical pad, so the touch target stays 44dp while
    // the pill reads compact (approved v4 icon pills).
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
                  // v4: the unselected pill's icon carries the category's
                  // own hue (existing per-category palette data).
                  categoryTint: category.color,
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
    this.categoryTint,
  });

  final String label;
  final IconData icon;
  final int? count;
  final bool selected;

  /// This terminal's secondary accent — the active-pill tint colour.
  final Color accent;

  final VoidCallback onSelected;

  /// The category's own hue for the unselected duotone icon (v4: category-
  /// colored icon pills). Falls back to the muted ink for the "All" tab.
  final Color? categoryTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the approved v4 ICON PILLS
    // (tokens §10) — unselected is a quiet warm pill with the CATEGORY-
    // colored icon; selected is the device-accent TINT pill (replaces the
    // old underline marker; the frozen marker key now rides the tint pill).
    // The label weight is deliberately CONSTANT so selection never changes
    // tab geometry under the cashier's finger (the frozen width-stability
    // contract), and the pill fill is identical in size either way.
    final foreground = selected ? kRestoflowInk : kRestoflowInk2;
    final iconColor = selected ? accent : (categoryTint ?? kRestoflowInk2);

    return Padding(
      // 6px between tabs — the rail is a set, not a row of cards.
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Center(
        // The InkWell wraps a transparent 5px vertical pad around the 34px
        // pill, so the TOUCH target stays 44dp while the pill keeps the
        // approved compact silhouette.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onSelected,
            hoverColor: kPosChipBg,
            borderRadius: BorderRadius.circular(kPosTrackRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: DecoratedBox(
                key: selected ? const Key('category-chip-active-marker') : null,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.13)
                      : kPosTabPillBg,
                  borderRadius: BorderRadius.circular(kPosTrackRadius),
                ),
                child: Container(
                  height: 34,
                  constraints: const BoxConstraints(minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: RestoflowIconSizes.sm, color: iconColor),
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
                        _CountBadge(
                          count: count!,
                          selected: selected,
                          accent: accent,
                        ),
                      ],
                    ],
                  ),
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
  const _CountBadge({
    required this.count,
    required this.selected,
    required this.accent,
  });

  final int count;
  final bool selected;

  /// The device accent — v4: the selected pill's count reads in the accent.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A compact bare count — no badge box. Selected counts read in the
    // device accent (v4 tokens §10); unselected stay muted.
    final fg = selected ? accent : kRestoflowInk3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
