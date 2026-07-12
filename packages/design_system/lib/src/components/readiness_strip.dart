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

/// A compact readiness strip (Dashboard "1c", recomposed to the approved
/// reference under RF-132): one card row holding the per-area stat boxes (icon
/// tile + label + `done/total`) at the reading start and the completion cluster
/// (status + headline + percent + progress bar) at the reading end, stacking
/// vertically on narrow widths. Presentation-only — the caller (setup center)
/// computes [ready], the [stats], and [percent] from the SAME real readiness
/// sources; this widget invents nothing. RTL-safe (Rows/Wrap + directional
/// padding) and animation-free.
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

  /// Optional trailing action in the completion cluster (e.g. a refresh
  /// button).
  final Widget? trailing;

  /// Below this content width the strip stacks (completion cluster above the
  /// stat boxes) instead of sitting on one row.
  static const double _stackBelow = 640;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);

    final statBoxes = Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.sm,
      children: [for (final s in stats) _StatBox(stat: s)],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.hasBoundedWidth &&
                constraints.maxWidth < _stackBelow;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CompletionCluster(
                    ready: ready,
                    headline: ready ? readyLabel : pendingLabel,
                    percent: clamped,
                    trailing: trailing,
                    barWidth: null,
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: RestoflowSpacing.md),
                    statBoxes,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: statBoxes),
                const SizedBox(width: RestoflowSpacing.lg),
                _CompletionCluster(
                  ready: ready,
                  headline: ready ? readyLabel : pendingLabel,
                  percent: clamped,
                  trailing: trailing,
                  barWidth: 170,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The completion cluster: status icon + headline + `NN%` + optional trailing
/// action over the thin progress bar. [barWidth] null stretches the bar to the
/// available width (stacked/narrow layout).
class _CompletionCluster extends StatelessWidget {
  const _CompletionCluster({
    required this.ready,
    required this.headline,
    required this.percent,
    required this.trailing,
    required this.barWidth,
  });

  final bool ready;
  final String headline;
  final int percent;
  final Widget? trailing;
  final double? barWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final successStyle = RestoflowTone.success.styleOf(theme);

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: 6,
        backgroundColor: scheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(successStyle.accent),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.check_circle : Icons.pending_outlined,
              size: RestoflowIconSizes.md,
              color: ready ? successStyle.accent : kRestoflowInk3,
            ),
            const SizedBox(width: RestoflowSpacing.xs),
            Flexible(
              child: Text(
                headline,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(
              '$percent%',
              style: theme.textTheme.titleMedium?.copyWith(
                color: successStyle.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (trailing case final t?) ...[
              const SizedBox(width: RestoflowSpacing.xs),
              t,
            ],
          ],
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        if (barWidth case final w?) SizedBox(width: w, child: bar) else bar,
      ],
    );
  }
}

/// One readiness stat box (RF-132 reference): a bordered white tile holding a
/// soft icon tile and the `label` over its `done/total` count. Success-tinted
/// icon tile when the metric is complete; quiet neutral otherwise. Tappable
/// when the stat carries [RestoflowReadinessStat.onTap].
class _StatBox extends StatelessWidget {
  const _StatBox({required this.stat});

  final RestoflowReadinessStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final successStyle = RestoflowTone.success.styleOf(theme);
    final complete = stat.complete;
    final tileBg = complete
        ? successStyle.container
        : theme.colorScheme.surfaceContainerHighest;
    final tileFg = complete ? successStyle.accent : kRestoflowInk3;
    final radius = BorderRadius.circular(RestoflowRadii.md);

    final content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            ),
            child: Icon(stat.icon, size: RestoflowIconSizes.sm, color: tileFg),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: kRestoflowInk2,
                ),
              ),
              Text(
                '${stat.done}/${stat.total}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final onTap = stat.onTap;
    return Material(
      key: stat.tapKey,
      color: Colors.white,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: kRestoflowHairline),
          borderRadius: radius,
        ),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
  }
}
