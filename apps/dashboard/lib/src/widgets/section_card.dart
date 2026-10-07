import 'package:flutter/material.dart';

import '../overview/overview_visuals.dart';

/// A simple leading-label / trailing-value row for a section card (RF-141C: the
/// section container uses Overview-local chrome). [label] and
/// [trailingValue] are pre-built data strings; [secondary] is an optional muted
/// sub-line under the label (e.g. an item quantity).
class SectionRow extends StatelessWidget {
  const SectionRow({
    required this.label,
    required this.trailingValue,
    this.secondary,
    this.icon,
    super.key,
  });

  final String label;
  final String trailingValue;
  final String? secondary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = OverviewValueRow(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (secondary != null)
            Text(
              secondary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      value: Text(
        trailingValue,
        textAlign: TextAlign.end,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OverviewVisuals.border),
        ),
        child: icon == null
            ? content
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: OverviewVisuals.softMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: OverviewVisuals.deep),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }
}
