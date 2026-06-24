import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// A titled section card holding a vertical list of rows (used for the
/// sales-by-branch and top-items lists).
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            const Divider(height: 1),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A simple leading-label / trailing-value row for a [SectionCard]. [label] and
/// [trailingValue] are pre-built data strings; [secondary] is an optional muted
/// sub-line under the label (e.g. an item quantity).
class SectionRow extends StatelessWidget {
  const SectionRow({
    required this.label,
    required this.trailingValue,
    this.secondary,
    super.key,
  });

  final String label;
  final String trailingValue;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RestoflowSpacing.md),
          Text(
            trailingValue,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
