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
    final semantic = tone?.styleOf(theme);
    final change = delta;
    final changeColor = change == null
        ? null
        : (change.positive ? RestoflowTone.success : RestoflowTone.danger)
              .styleOf(theme)
              .accent;
    return _MetricSurface(
      onTap: onTap,
      tinted: tone == RestoflowTone.success,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: style == RestoflowMetricCardStyle.kpi ? 108 : 0,
        ),
        child: Padding(
          padding: const EdgeInsets.all(OverviewVisuals.metricPadding),
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
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: semantic?.container ?? OverviewVisuals.softMint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: semantic?.accent ?? OverviewVisuals.deep,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // No ellipsis or forced text scaling: a large amount may reflow.
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: OverviewVisuals.ink,
                ),
              ),
              if (change != null) ...[
                const SizedBox(height: 4),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricSurface extends StatefulWidget {
  const _MetricSurface({required this.child, required this.tinted, this.onTap});
  final Widget child;
  final bool tinted;
  final VoidCallback? onTap;

  @override
  State<_MetricSurface> createState() => _MetricSurfaceState();
}

class _MetricSurfaceState extends State<_MetricSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: OverviewVisuals.radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: widget.tinted
              ? const [Colors.white, OverviewVisuals.paleMint]
              : const [Colors.white, Color(0xFFFCFEFD)],
        ),
      ),
      child: widget.onTap == null
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
    ),
  );
}
