import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A small rounded pill label used for menu status badges (RF-111).
class MenuPill extends StatelessWidget {
  const MenuPill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// The status badges for a menu entry: an "Inactive" badge when not active, plus
/// a branch / "all branches" (global) scope badge.
class MenuEntityBadges extends StatelessWidget {
  const MenuEntityBadges({
    required this.isActive,
    required this.branchId,
    super.key,
  });

  final bool isActive;
  final String? branchId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: RestoflowSpacing.xs,
      runSpacing: RestoflowSpacing.xs,
      children: [
        if (!isActive)
          MenuPill(
            label: l10n.menuInactiveBadge,
            icon: Icons.visibility_off_outlined,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
        MenuPill(
          label: branchId == null ? l10n.menuGlobalBadge : l10n.menuBranchBadge,
          icon: branchId == null
              ? Icons.account_tree_outlined
              : Icons.storefront_outlined,
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
        ),
      ],
    );
  }
}

/// A larger scope chip for the page header (the menu's active branch/global
/// scope).
class MenuScopeChip extends StatelessWidget {
  const MenuScopeChip({required this.branchId, super.key});

  final String? branchId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return MenuPill(
      label: branchId == null ? l10n.menuGlobalBadge : l10n.menuBranchBadge,
      icon: branchId == null
          ? Icons.account_tree_outlined
          : Icons.storefront_outlined,
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );
  }
}
