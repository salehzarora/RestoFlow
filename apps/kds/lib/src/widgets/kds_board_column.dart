import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Shared column chrome for BOTH KDS boards (design-polish sprint).
///
/// The live board ([KdsBoard]) and the RF-117 demo board ([KitchenBoard]) used
/// to carry near-duplicate `_ColumnHeader` implementations in identical brand
/// containers. This file owns the ONE semantic look for a workflow column so
/// the two boards cannot diverge visually: new = info (blue), preparing =
/// warning (amber), ready = success (green), cleared = neutral — resolved via
/// [RestoflowTone.styleOf], so the colours adapt to the dark kitchen theme and
/// stay renderable in bare test harnesses. Money-free (SECURITY T-003).

/// The semantic tone for a workflow column key ('new' / 'preparing' / 'ready'
/// / 'cleared').
RestoflowTone kdsColumnTone(String columnKey) => switch (columnKey) {
  'new' => RestoflowTone.info,
  'preparing' => RestoflowTone.warning,
  'ready' => RestoflowTone.success,
  _ => RestoflowTone.neutral,
};

/// The leading icon for a workflow column key (decorative — not test-pinned).
IconData kdsColumnIcon(String columnKey) => switch (columnKey) {
  'new' => Icons.fiber_new,
  'preparing' => Icons.timer_outlined,
  'ready' => Icons.check_circle_outline,
  _ => Icons.done_all,
};

/// The tinted, meaning-coloured column header: tone container fill, per-column
/// icon, kitchen-weight label, and a high-contrast (inverted) count badge.
class KdsColumnHeader extends StatelessWidget {
  const KdsColumnHeader({
    required this.columnKey,
    required this.label,
    required this.count,
    super.key,
  });

  /// The workflow column key ('new' / 'preparing' / 'ready' / 'cleared').
  final String columnKey;

  /// The localized column label.
  final String label;

  /// Number of tickets currently in the column.
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = kdsColumnTone(columnKey).styleOf(theme);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        children: [
          Icon(
            kdsColumnIcon(columnKey),
            size: RestoflowIconSizes.md,
            color: style.onContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: style.onContainer,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RestoflowSpacing.sm,
              vertical: RestoflowSpacing.xxs,
            ),
            decoration: BoxDecoration(
              // Inverted for at-a-glance contrast: the badge is the strongest
              // element of the header (the count is what the pass reads).
              color: style.onContainer,
              borderRadius: BorderRadius.circular(RestoflowRadii.pill),
            ),
            child: Text(
              count.toString(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: style.container,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The quiet placeholder rendered under an empty column's header so the column
/// reads as intentionally empty instead of a floating header. Compact on
/// purpose: the narrow stacked board must not push later columns' actions
/// off-screen.
class KdsEmptyColumnPlaceholder extends StatelessWidget {
  const KdsEmptyColumnPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: RestoflowIconSizes.sm, color: muted),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            l10n.kdsColumnEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
