import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A small trend delta for a [RestoflowMetricCard] (DESIGN-002): a
/// pre-formatted [label] (e.g. "9% vs yesterday") rendered with an up/down
/// arrow in the success (up) or danger (down) tone. Pure presentation — the
/// caller computes the direction and formats the text; this carries no numbers.
class RestoflowMetricDelta {
  const RestoflowMetricDelta({required this.label, required this.positive});

  /// Pre-formatted change text WITHOUT the arrow (the card adds ▲/▼).
  final String label;

  /// True renders the up-arrow + success tone; false the down-arrow + danger.
  final bool positive;
}

/// The visual variant of a [RestoflowMetricCard] (RF-132).
enum RestoflowMetricCardStyle {
  /// The original RF-141A tile: inline leading icon + an accent-coloured value.
  classic,

  /// The RF-132 reference KPI tile: a white card with a soft tinted icon tile
  /// at the reading end of the label row, a prominent dark-ink value, and a
  /// reserved trend slot so a row of KPI cards keeps one consistent height
  /// whether or not each card has a delta/caption (the reservation is empty
  /// spacing — never a fake trend).
  kpi,
}

/// A KPI metric tile: a small label, a prominent value, and an optional caption
/// (RF-141A). Optionally tappable (RF-141D): when [onTap] is set the tile gets
/// an [InkWell] with hover/pressed/ripple feedback (clipped to the card radius);
/// with no [onTap] it stays display-only and unchanged.
///
/// Replaces the per-app metric cards. Pure presentation — [value]/[caption] are
/// pre-built strings (money is already formatted from integer minor units by the
/// caller; this widget does no number/money formatting). [label] is localized
/// chrome. The optional [tone] gives the icon + value a semantic accent on the
/// card surface; with no tone they use the brand primary. The optional [delta]
/// adds a trend line (DESIGN-002). RTL-friendly.
class RestoflowMetricCard extends StatelessWidget {
  const RestoflowMetricCard({
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone,
    this.delta,
    this.onTap,
    this.filled = false,
    this.fillStyle,
    this.style = RestoflowMetricCardStyle.classic,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Optional semantic accent for the icon + value. Null => brand primary.
  final RestoflowTone? tone;

  /// Dashboard "1c" tinted variant: when true AND a [tone] (or [fillStyle]) is
  /// set, the tile is painted in the tone's container with a white rounded icon
  /// box holding the tone accent icon, a dark value, and an on-container label.
  /// Without a tone/fillStyle (or when false) the tile keeps the plain
  /// white-card look.
  final bool filled;

  /// An explicit fill palette that overrides [tone] for the [filled] variant —
  /// used for the terracotta "accent" tile, which is a semantic colour rather
  /// than one of the five [RestoflowTone]s.
  final RestoflowToneStyle? fillStyle;

  /// Optional trend delta (DESIGN-002) rendered under the value.
  final RestoflowMetricDelta? delta;

  /// Optional tap handler (RF-141D). When non-null the tile becomes an
  /// [InkWell] with hover/pressed/ripple feedback; null keeps it display-only.
  final VoidCallback? onTap;

  /// The visual variant (RF-132). Defaults to [RestoflowMetricCardStyle.classic]
  /// so existing consumers are unchanged. Ignored by the [filled] variant.
  final RestoflowMetricCardStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final toneStyle = tone?.styleOf(theme);
    final resolvedFill = fillStyle ?? toneStyle;

    // Dashboard "1c" tinted tile: a coloured container + white icon box.
    if (filled && resolvedFill != null) {
      return _FilledTile(
        label: label,
        value: value,
        caption: caption,
        icon: icon,
        delta: delta,
        onTap: onTap,
        toneStyle: resolvedFill,
      );
    }

    // RF-132 reference KPI tile: white card + tinted icon tile + dark value.
    if (style == RestoflowMetricCardStyle.kpi) {
      return _KpiTile(
        label: label,
        value: value,
        caption: caption,
        icon: icon,
        delta: delta,
        onTap: onTap,
        toneStyle: toneStyle,
      );
    }

    final accent = tone == null ? scheme.primary : toneStyle!.accent;
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
          if (delta case final d?) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            _DeltaLine(delta: d),
          ],
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

/// The Dashboard "1c" tinted KPI tile: `tone.container` background, a white
/// rounded icon box holding the `tone.accent` icon at the reading end of the
/// label row, a dark value, and (optionally) the delta + a muted caption.
class _FilledTile extends StatelessWidget {
  const _FilledTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.delta,
    required this.onTap,
    required this.toneStyle,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final RestoflowMetricDelta? delta;
  final VoidCallback? onTap;
  final RestoflowToneStyle toneStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captionText = caption;
    final iconData = icon;
    final content = Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: toneStyle.onContainer,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (iconData != null) ...[
                const SizedBox(width: RestoflowSpacing.sm),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(iconData, size: 18, color: toneStyle.accent),
                ),
              ],
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: kRestoflowInk,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (delta case final d?) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            _DeltaLine(delta: d),
          ],
          if (captionText != null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              captionText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: toneStyle.onContainer.withValues(alpha: 0.82),
              ),
            ),
          ],
        ],
      ),
    );
    final tap = onTap;
    final radius = BorderRadius.circular(RestoflowRadii.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: toneStyle.container,
        borderRadius: radius,
      ),
      child: tap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: tap, borderRadius: radius, child: content),
            ),
    );
  }
}

/// The RF-132 reference KPI tile: a plain white card whose label row carries a
/// soft tinted icon tile at the reading END, a prominent dark-ink value, then
/// the delta and/or caption. When the card has NEITHER, an equally-sized empty
/// slot keeps a row of KPI tiles at one height (plain spacing — it renders
/// nothing and can never be mistaken for a trend).
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.delta,
    required this.onTap,
    required this.toneStyle,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final RestoflowMetricDelta? delta;
  final VoidCallback? onTap;

  /// The tone styling for the icon tile; null uses the brand primary container.
  final RestoflowToneStyle? toneStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconData = icon;
    final captionText = caption;
    final d = delta;
    final tileBg = toneStyle?.container ?? scheme.primaryContainer;
    final tileFg = toneStyle?.accent ?? scheme.primary;
    final valueInk = theme.brightness == Brightness.light
        ? kRestoflowInk
        : scheme.onSurface;

    final content = Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: RestoflowSpacing.xs,
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    // One line, like the reference — keeps every KPI tile's
                    // label row (and therefore the whole row of tiles) at one
                    // consistent height.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (iconData != null) ...[
                const SizedBox(width: RestoflowSpacing.sm),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, size: 18, color: tileFg),
                ),
              ],
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueInk,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (d != null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            _DeltaLine(delta: d),
          ],
          if (captionText != null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              captionText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (d == null && captionText == null) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            // The empty trend slot: an icon-height box beside an empty
            // bodySmall line reproduces the delta row's exact metrics (at any
            // font/text scale) while rendering nothing — spacing only, never
            // mistakable for a trend.
            Row(
              children: [
                const SizedBox(height: RestoflowIconSizes.xs),
                Text('', style: theme.textTheme.bodySmall),
              ],
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

/// The trend line under a metric value (DESIGN-002): an up/down arrow + the
/// pre-formatted change text, toned success (up) or danger (down).
class _DeltaLine extends StatelessWidget {
  const _DeltaLine({required this.delta});

  final RestoflowMetricDelta delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = delta.positive ? RestoflowTone.success : RestoflowTone.danger;
    final color = tone.styleOf(theme).accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delta.positive ? Icons.arrow_upward : Icons.arrow_downward,
          size: RestoflowIconSizes.xs,
          color: color,
        ),
        const SizedBox(width: RestoflowSpacing.xxs),
        Flexible(
          child: Text(
            delta.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
