import 'package:flutter/material.dart';

import '../tokens.dart';

/// A titled section container with consistent padding, border and radius
/// (RF-141A).
///
/// Replaces the per-app section cards. When [title] is set it renders a header
/// (title + optional [subtitle] + optional trailing [action]) and a divider
/// above [children]; with no [title] it is just a padded, bordered card around
/// [children]. The card border/radius come from the theme's card styling so it
/// matches every surface. RTL-friendly: the header is a [Row] (mirrors), and
/// padding is direction-agnostic.
class RestoflowSectionCard extends StatelessWidget {
  const RestoflowSectionCard({
    required this.children,
    this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  /// Optional section heading. With no title, no header/divider is shown.
  final String? title;

  /// Optional muted sub-line under [title].
  final String? subtitle;

  /// Optional trailing header widget (e.g. a "view all" button or refresh).
  final Widget? action;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title;
    final subtitleText = subtitle;
    final actionWidget = action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titleText != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitleText != null)
                          Text(
                            subtitleText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (actionWidget != null) actionWidget,
                ],
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              const Divider(height: 1),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
