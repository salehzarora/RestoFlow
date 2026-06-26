import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../state/order_setup_controller.dart';

/// Modal table picker (RF-114): a labelled-demo grid of the branch's tables with
/// their derived status. Only AVAILABLE tables are tappable; occupied/blocked
/// are shown disabled. Tapping an available table assigns it to the active
/// dine-in order and closes the sheet.
class TablePickerSheet extends ConsumerWidget {
  const TablePickerSheet({super.key});

  /// Opens the picker as a modal bottom sheet.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TablePickerSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tablesAsync = ref.watch(tablesProvider);
    final assignedId = ref.watch(
      orderSetupControllerProvider.select((s) => s.assignedTable?.tableId),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_restaurant, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  l10n.posTablePickerTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            _DemoNotice(message: l10n.posTablesDemoNotice),
            const SizedBox(height: RestoflowSpacing.md),
            Flexible(
              child: tablesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(RestoflowSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => _PickerMessage(
                  icon: Icons.error_outline,
                  message: l10n.posTablesError,
                ),
                data: (tables) => tables.isEmpty
                    ? _PickerMessage(
                        icon: Icons.table_restaurant_outlined,
                        message: l10n.posTablesEmpty,
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: RestoflowSpacing.md,
                          runSpacing: RestoflowSpacing.md,
                          children: [
                            for (final t in tables)
                              _TableTile(
                                table: t,
                                selected: t.tableId == assignedId,
                                onTap: t.isAssignable
                                    ? () {
                                        ref
                                            .read(
                                              orderSetupControllerProvider
                                                  .notifier,
                                            )
                                            .assignTable(t);
                                        Navigator.of(context).pop();
                                      }
                                    : null,
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status visual (colour + localized label) for a table tile.
({Color color, Color onColor, String label}) _statusVisual(
  TableStatusKind kind,
  ThemeData theme,
  AppLocalizations l10n,
) {
  final scheme = theme.colorScheme;
  switch (kind) {
    case TableStatusKind.available:
      return (
        color: scheme.secondaryContainer,
        onColor: scheme.onSecondaryContainer,
        label: l10n.posTableStatusAvailable,
      );
    case TableStatusKind.occupied:
      return (
        color: scheme.tertiaryContainer,
        onColor: scheme.onTertiaryContainer,
        label: l10n.posTableStatusOccupied,
      );
    case TableStatusKind.blocked:
      return (
        color: scheme.errorContainer,
        onColor: scheme.onErrorContainer,
        label: l10n.posTableStatusBlocked,
      );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.selected,
    required this.onTap,
  });

  final DemoTable table;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visual = _statusVisual(table.status, theme, l10n);
    final disabled = onTap == null;

    return SizedBox(
      width: 150,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          child: Opacity(
            opacity: disabled ? 0.55 : 1,
            child: Padding(
              padding: const EdgeInsets.all(RestoflowSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_seat,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: RestoflowSpacing.xs),
                      Text(
                        table.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (selected) ...[
                        const Spacer(),
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (table.seats != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.posTableSeats(table.seats!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (table.area != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      table.area!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: RestoflowSpacing.sm),
                  _StatusChip(
                    label: visual.label,
                    color: visual.color,
                    onColor: visual.onColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
