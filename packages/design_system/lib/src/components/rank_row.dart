import 'package:flutter/material.dart';

import '../semantic_colors.dart';
import '../tokens.dart';

/// A ranked "top sellers" row (Dashboard "1c"): a small numbered badge (the top
/// three coloured green / mint / terracotta), a name, a muted [meta] line
/// (`×qty · amount` — the caller formats the money via MoneyFormatter), and a
/// thin progress bar whose [fraction] is this item's share of the top item's
/// revenue. Presentation-only, money-free, RTL-safe, and animation-free.
class RestoflowRankRow extends StatelessWidget {
  const RestoflowRankRow({
    required this.rank,
    required this.name,
    required this.meta,
    required this.fraction,
    super.key,
  });

  /// 1-based rank (drives the badge colour: 1 green, 2 mint, 3 terracotta).
  final int rank;

  /// Item name (data).
  final String name;

  /// Pre-formatted `×qty · amount` meta (money already formatted upstream).
  final String meta;

  /// Share of the top item's revenue, 0..1, for the mini bar.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    final accent = semantic.accent;
    final rankColor = switch (rank) {
      1 => kRestoflowSeedColor,
      2 => const Color(0xFF2AA46E),
      3 => accent,
      _ => scheme.surfaceContainerHighest,
    };
    final onBadge = rank <= 3 ? Colors.white : scheme.onSurfaceVariant;
    final barColor = rank <= 3 ? rankColor : scheme.outline;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: RestoflowSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankColor,
              borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            ),
            child: Text(
              '$rank',
              style: theme.textTheme.labelMedium?.copyWith(
                color: onBadge,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    // Flexible + ellipsis (RF-132): at large OS text scales
                    // the meta run must give way instead of overflowing the
                    // row horizontally.
                    Flexible(
                      child: Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RestoflowSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(RestoflowRadii.pill),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
