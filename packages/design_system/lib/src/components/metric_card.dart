import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A KPI metric tile: a small label, a prominent value, and an optional caption
/// (RF-141A). Optionally tappable (RF-141D): when [onTap] is set the tile gets
/// an [InkWell] with hover/pressed/ripple feedback (clipped to the card radius);
/// with no [onTap] it stays display-only and unchanged.
///
/// Replaces the per-app metric cards. Pure presentation — [value]/[caption] are
/// pre-built strings (money is already formatted from integer minor units by the
/// caller; this widget does no number/money formatting). [label] is localized
/// chrome. The optional [tone] gives the icon + value a semantic accent on the
/// card surface; with no tone they use the brand primary. RTL-friendly.
class RestoflowMetricCard extends StatelessWidget {
  const RestoflowMetricCard({
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Optional semantic accent for the icon + value. Null => brand primary.
  final RestoflowTone? tone;

  /// Optional tap handler (RF-141D). When non-null the tile becomes an
  /// [InkWell] with hover/pressed/ripple feedback; null keeps it display-only.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = tone == null ? scheme.primary : tone!.style(scheme).accent;
    final captionText = caption;

    final content = Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: RestoflowSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (captionText != null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              captionText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    final tap = onTap;
    return Card(
      child: tap == null
          ? content
          : InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(RestoflowRadii.lg),
              child: content,
            ),
    );
  }
}
