import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// A section header row: a title plus an optional leading-icon action button
/// (e.g. "Categories" + "Add category"). RTL-safe via directional padding.
class MenuPanelHeader extends StatelessWidget {
  const MenuPanelHeader({
    required this.title,
    this.actionLabel,
    this.actionIcon = Icons.add,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (actionLabel != null && onAction != null)
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
