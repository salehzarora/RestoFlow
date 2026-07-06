import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// One readiness statistic for a [RestoflowReadinessStrip]: an [icon], a [label]
/// (localized by the caller), a [done]/[total] count, and an optional [onTap]
/// (e.g. jump to the owning tab) with a stable [tapKey] for testing.
class RestoflowReadinessStat {
  const RestoflowReadinessStat({
    required this.icon,
    required this.label,
    required this.done,
    required this.total,
    this.onTap,
    this.tapKey,
  });

  final IconData icon;
  final String label;
  final int done;
  final int total;

  /// Optional tap handler — when set, the chip becomes tappable (ripple/hover).
  final VoidCallback? onTap;

  /// A stable key for the tappable chip (locale-independent testing).
  final Key? tapKey;

  /// True when this metric is fully satisfied.
  bool get complete => total > 0 && done >= total;
}

/// A compact readiness strip (Dashboard "1c") that replaces the bulky setup
/// card: a status check + headline, a wrap of small `label done/total` stat
/// chips, and a thin progress bar with a percent. Presentation-only — the caller
/// (setup center) computes [ready], the [stats], and [percent] from the SAME
/// real readiness sources; this widget invents nothing. RTL-safe (Rows/Wrap +
/// directional padding) and animation-free.
class RestoflowReadinessStrip extends StatelessWidget {
  const RestoflowReadinessStrip({
    required this.ready,
    required this.readyLabel,
    required this.pendingLabel,
    required this.stats,
    required this.percent,
    this.trailing,
    super.key,
  });

  /// Whether the branch is fully ready (drives the check icon + tone).
  final bool ready;

  /// Headline when [ready] (e.g. "Branch ready for service").
  final String readyLabel;

  /// Headline when not [ready] (e.g. "Finishing branch setup").
  final String pendingLabel;

  /// The per-area readiness stats (Menu / Devices / Printers / PINs …).
  final List<RestoflowReadinessStat> stats;

  /// Overall completion percent (0..100), computed by the caller.
  final int percent;

  /// Optional trailing action in the headline row (e.g. a refresh button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final successStyle = RestoflowTone.success.styleOf(theme);
    final clamped = percent.clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  ready ? Icons.check_circle : Icons.pending_outlined,
                  size: RestoflowIconSizes.lg,
                  color: ready ? successStyle.accent : kRestoflowInk3,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    ready ? readyLabel : pendingLabel,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  '$clamped%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: successStyle.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing case final t?) ...[
                  const SizedBox(width: RestoflowSpacing.xs),
                  t,
                ],
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: RestoflowSpacing.md),
              Wrap(
                spacing: RestoflowSpacing.sm,
                runSpacing: RestoflowSpacing.xs,
                children: [for (final s in stats) _StatChip(stat: s)],
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(RestoflowRadii.pill),
              child: LinearProgressIndicator(
                value: clamped / 100,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(successStyle.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One `icon  label  done/total` readiness chip; a subtle success tint when the
/// metric is complete, otherwise a quiet neutral surface.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.stat});

  final RestoflowReadinessStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final successStyle = RestoflowTone.success.styleOf(theme);
    final complete = stat.complete;
    final bg = complete
        ? successStyle.container
        : scheme.surfaceContainerHighest;
    final fg = complete ? successStyle.onContainer : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(RestoflowRadii.pill);
    final content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stat.icon, size: RestoflowIconSizes.xs, color: fg),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            '${stat.label} ${stat.done}/${stat.total}',
            style: theme.textTheme.labelMedium?.copyWith(color: fg),
          ),
        ],
      ),
    );
    final onTap = stat.onTap;
    return Material(
      key: stat.tapKey,
      color: bg,
      borderRadius: radius,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}
