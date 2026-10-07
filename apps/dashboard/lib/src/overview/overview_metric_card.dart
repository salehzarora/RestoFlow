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
                      height: 1.3,
                    ),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: semantic?.container ?? OverviewVisuals.softMint,
                      borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 6),
            // No ellipsis or forced text scaling: a large amount may reflow.
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: OverviewVisuals.ink,
              ),
            ),
            if (change != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    change.positive ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: changeColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      change.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricSurface extends StatefulWidget {
  const _MetricSurface({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_MetricSurface> createState() => _MetricSurfaceState();
}

class _MetricSurfaceState extends State<_MetricSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Ink(
      decoration: const BoxDecoration(
        borderRadius: OverviewVisuals.radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Colors.white, OverviewVisuals.paleMint],
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
