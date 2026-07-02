import 'package:flutter/material.dart';

import '../tokens.dart';

/// The shared page header (design-polish sprint): icon badge + title +
/// optional subtitle, with trailing [actions] that wrap on narrow widths.
///
/// Replaces the AdminPageHeader/MenuPageHeader near-duplicates. RTL-safe:
/// Row-based (mirrors automatically), directional padding only.
class RestoflowPageHeader extends StatelessWidget {
  const RestoflowPageHeader({
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.padding = EdgeInsetsDirectional.zero,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Optional leading icon rendered in a soft rounded badge.
  final IconData? icon;

  /// Trailing header actions (e.g. the page's primary button).
  final List<Widget> actions;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitleText = subtitle;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
              ),
              child: Icon(
                icon,
                size: RestoflowIconSizes.lg,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitleText != null) ...[
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Text(
                    subtitleText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: RestoflowSpacing.md),
            Wrap(
              spacing: RestoflowSpacing.sm,
              runSpacing: RestoflowSpacing.sm,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
