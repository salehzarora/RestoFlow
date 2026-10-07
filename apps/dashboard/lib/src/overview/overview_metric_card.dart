import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import 'overview_visuals.dart';

/// Local rendering of the established presentation-only metric contract.
/// Values, deltas and callbacks remain supplied by the existing callers.
class OverviewMetricCard extends RestoflowMetricCard {
  const OverviewMetricCard({
    required super.label,
    required super.value,
    super.caption,
    super.icon,
    super.tone,
    super.delta,
    super.onTap,
    super.style = RestoflowMetricCardStyle.kpi,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = OverviewVisuals.compactPhone(context);
    final palette = _metricPalette(icon, tone, theme);
    final change = delta;
    final changeColor = change == null
        ? null
        : (change.positive ? RestoflowTone.success : RestoflowTone.danger)
              .styleOf(theme)
              .accent;
    return _MetricSurface(
      onTap: onTap,
      palette: palette,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: style == RestoflowMetricCardStyle.kpi
              ? (compact ? 104 : 120)
              : 0,
        ),
        child: Padding(
          padding: EdgeInsets.all(
            OverviewVisuals.metricContentPadding(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF3E554D),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: compact ? 28 : 36,
                      height: compact ? 28 : 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                          colors: [
                            palette.iconBackground,
                            Color.alphaBlend(
                              palette.accent.withValues(alpha: 0.08),
                              palette.iconBackground,
                            ),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: palette.accent.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        size: compact ? 20 : 21,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: compact ? 2 : 3),
              // The full formatted value may grow; never shrink or ellipsise it.
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: OverviewVisuals.ink,
                ),
              ),
              if (change != null || caption != null)
                Container(
                  margin: EdgeInsets.only(top: compact ? 4 : 6),
                  padding: EdgeInsets.only(top: compact ? 3 : 5),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: palette.accent.withValues(alpha: 0.13),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (change != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              change.positive
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 14,
                              color: changeColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                change.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: changeColor,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (caption != null) ...[
                        if (change != null) const SizedBox(height: 4),
                        Text(
                          caption!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _MetricPalette = ({Color accent, Color surface, Color iconBackground});

/// Existing metric icons identify the visual families; semantic deltas keep
/// their supplied success/danger meaning independently of these accents.
_MetricPalette _metricPalette(
  IconData? icon,
  RestoflowTone? tone,
  ThemeData theme,
) {
  if (icon == Icons.trending_up) {
    return (
      accent: const Color(0xFF7C3AED),
      surface: const Color(0xFFF8F3FF),
      iconBackground: const Color(0xFFEBDDFF),
    );
  }
  if (icon == Icons.receipt_long_outlined) {
    return (
      accent: const Color(0xFF2563EB),
      surface: const Color(0xFFF0F6FF),
      iconBackground: const Color(0xFFD9E9FF),
    );
  }
  if (icon == Icons.task_alt) {
    return (
      accent: const Color(0xFF15803D),
      surface: const Color(0xFFF0FAF2),
      iconBackground: const Color(0xFFD7F3DC),
    );
  }
  if (icon == Icons.point_of_sale_outlined ||
      icon == Icons.payments_outlined ||
      icon == Icons.account_balance_wallet_outlined) {
    return (
      accent: const Color(0xFF00815E),
      surface: icon == Icons.payments_outlined
          ? const Color(0xFFE7F8EF)
          : const Color(0xFFF0FCF6),
      iconBackground: const Color(0xFFC6F2DE),
    );
  }
  final semantic = tone?.styleOf(theme);
  return (
    accent: semantic?.accent ?? OverviewVisuals.deep,
    surface: OverviewVisuals.paleMint,
    iconBackground: semantic?.container ?? OverviewVisuals.softMint,
  );
}

class _MetricSurface extends StatefulWidget {
  const _MetricSurface({
    required this.child,
    required this.palette,
    this.onTap,
  });
  final Widget child;
  final _MetricPalette palette;
  final VoidCallback? onTap;

  @override
  State<_MetricSurface> createState() => _MetricSurfaceState();
}

class _MetricSurfaceState extends State<_MetricSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 1.5,
    shadowColor: widget.palette.accent.withValues(alpha: 0.16),
    shape: RoundedRectangleBorder(
      borderRadius: OverviewVisuals.radius,
      side: BorderSide(color: widget.palette.accent.withValues(alpha: 0.15)),
    ),
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: OverviewVisuals.radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Colors.white,
            Color.alphaBlend(
              widget.palette.surface.withValues(alpha: 0.45),
              Colors.white,
            ),
            widget.palette.surface,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            top: 18,
            bottom: 18,
            width: 3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.palette.accent.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          widget.onTap == null
              ? widget.child
              : Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: OverviewVisuals.radius,
                    border: _focused
                        ? Border.all(color: OverviewVisuals.deep, width: 2)
                        : null,
                  ),
                  child: InkWell(
                    borderRadius: OverviewVisuals.radius,
                    onTap: widget.onTap,
                    onFocusChange: (value) => setState(() => _focused = value),
                    child: widget.child,
                  ),
                ),
        ],
      ),
    ),
  );
}
