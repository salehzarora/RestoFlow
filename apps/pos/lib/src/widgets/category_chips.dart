import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_menu.dart';
import '../state/menu_filter.dart';

/// Horizontal category filter chips (All + each demo category). Selecting a chip
/// updates [selectedCategoryProvider], which filters the menu grid.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedCategoryProvider);

    void select(String id) =>
        ref.read(selectedCategoryProvider.notifier).state = id;

    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.lg),
        child: Row(
          children: [
            _CategoryChip(
              label: l10n.posCategoryAll,
              icon: Icons.apps,
              selected: selected == kAllCategoriesId,
              onSelected: () => select(kAllCategoriesId),
            ),
            for (final category in kDemoCategories)
              _CategoryChip(
                label: category.name,
                icon: category.icon,
                selected: selected == category.id,
                onSelected: () => select(category.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: RestoflowSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        avatar: Icon(icon, size: 18),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
