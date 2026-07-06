import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Reusable, polished menu-UI building blocks (RF-111). Feature-local (shared
/// `design_system` component additions are their own ticket, M5). All are
/// Material 3 + design tokens, RTL-safe via directional spacing, and take
/// localized strings from the caller (or read AppLocalizations where noted).

/// The active/inactive view filter.
enum MenuActiveFilter { all, active, inactive }

/// Returns true if a row with [isActive] should be shown under [filter].
bool menuFilterAllows(MenuActiveFilter filter, bool isActive) =>
    switch (filter) {
      MenuActiveFilter.all => true,
      MenuActiveFilter.active => isActive,
      MenuActiveFilter.inactive => !isActive,
    };

/// A page header: a strong title, a muted subtitle, and optional trailing
/// content (e.g. a scope badge). Dashboard "1c": the full-bleed brand-gradient
/// [RestoflowGradientHeader], matching every other dashboard screen; the
/// trailing badge rides the header's action slot.
class MenuPageHeader extends StatelessWidget {
  const MenuPageHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RestoflowGradientHeader(
      icon: Icons.restaurant_menu,
      title: title,
      subtitle: subtitle,
      actions: [if (trailing case final t?) t],
    );
  }
}

/// A grouped section card with a header (icon + title + optional trailing action)
/// and content, used to give the editor and panels visual structure.
class MenuSectionCard extends StatelessWidget {
  const MenuSectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.contentPadding = const EdgeInsets.all(RestoflowSpacing.lg),
    super.key,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.sm,
              RestoflowSpacing.md,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: RestoflowSpacing.sm),
                ],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(padding: contentPadding, child: child),
        ],
      ),
    );
  }
}

/// A rich empty / error / no-results state: a tinted circular icon, a title, an
/// optional body, and an optional action.
class MenuStateView extends StatelessWidget {
  const MenuStateView({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: RestoflowSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: RestoflowSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: RestoflowSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A monospace, code-style container (e.g. the storage path preview).
class MenuCodeBlock extends StatelessWidget {
  const MenuCodeBlock(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// The menu toolbar: a search field, an active/inactive segmented filter, and an
/// optional trailing action (e.g. "Add category"). Wraps on narrow widths.
class MenuToolbar extends StatelessWidget {
  const MenuToolbar({
    required this.query,
    required this.onQueryChanged,
    required this.filter,
    required this.onFilterChanged,
    this.trailing,
    super.key,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final MenuActiveFilter filter;
  final ValueChanged<MenuActiveFilter> onFilterChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final search = SizedBox(
      width: 280,
      child: TextField(
        onChanged: onQueryChanged,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: l10n.menuSearchHint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RestoflowRadii.pill),
          ),
        ),
      ),
    );
    final segmented = SegmentedButton<MenuActiveFilter>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: MenuActiveFilter.all,
          label: Text(l10n.menuFilterAll),
        ),
        ButtonSegment(
          value: MenuActiveFilter.active,
          label: Text(l10n.menuFilterActive),
        ),
        ButtonSegment(
          value: MenuActiveFilter.inactive,
          label: Text(l10n.menuFilterInactive),
        ),
      ],
      selected: {filter},
      onSelectionChanged: (selection) => onFilterChanged(selection.first),
    );
    return Wrap(
      spacing: RestoflowSpacing.md,
      runSpacing: RestoflowSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        search,
        Wrap(
          spacing: RestoflowSpacing.md,
          runSpacing: RestoflowSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [segmented, if (trailing != null) trailing!],
        ),
      ],
    );
  }
}

/// A subtle outlined surface panel used for the master/detail columns.
class MenuSurfacePanel extends StatelessWidget {
  const MenuSurfacePanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
