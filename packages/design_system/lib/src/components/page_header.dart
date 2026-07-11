import 'package:flutter/material.dart';

import '../tokens.dart';

/// The shared, calm page header (RF-125): an optional restrained brand-accent
/// icon badge + a strong title + an optional muted subtitle, with trailing
/// [actions] that wrap — or, at narrow widths, stack safely below the title.
///
/// RF-125 makes this the ONE calm page-header pattern for the dashboard
/// surfaces (Admin/Menu via their wrappers, Orders, Activity), replacing the
/// full-bleed brand-gradient header as default page chrome. It is deliberately
/// NOT a card: it sits on the page surface and — when [bordered] — adds a single
/// warm hairline ([kRestoflowHairline]) along its bottom edge so the header band
/// reads as distinct from the scrolling body, without wrapping every heading in
/// another framed surface.
///
/// Accessibility: the whole header is exposed as a semantic header
/// (`Semantics(header: true)`); the [actions] keep their own button semantics.
/// RTL-safe: Row/Column based (mirrors automatically) with directional padding
/// and a directional border only. No animation (`pumpAndSettle`-safe).
class RestoflowPageHeader extends StatelessWidget {
  const RestoflowPageHeader({
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.padding = EdgeInsetsDirectional.zero,
    this.bordered = false,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Optional leading icon rendered in a soft rounded badge (the restrained
  /// brand accent — a primary-container tint, not a full-bleed gradient).
  final IconData? icon;

  /// Trailing header actions (e.g. the page's primary button / refresh).
  final List<Widget> actions;

  final EdgeInsetsGeometry padding;

  /// When true, draws a single warm hairline ([kRestoflowHairline]) along the
  /// bottom edge so the header reads as a distinct band above the page body.
  /// Off by default so existing bare consumers are unchanged.
  final bool bordered;

  /// Below this content width the trailing [actions] stack in a full-width
  /// cluster under the title instead of sitting at the reading-end, so a long
  /// title + actions never overflow horizontally.
  static const double _stackActionsBelow = 480;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: _content(context));
    return Semantics(
      header: true,
      child: bordered
          ? DecoratedBox(
              decoration: const BoxDecoration(
                border: BorderDirectional(
                  bottom: BorderSide(color: kRestoflowHairline),
                ),
              ),
              child: content,
            )
          : content,
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitleText = subtitle;

    final titleBlock = Row(
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
            mainAxisSize: MainAxisSize.min,
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
      ],
    );

    if (actions.isEmpty) return titleBlock;

    final actionCluster = Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the actions under the title on narrow pages; keep them at the
        // reading-end on wide ones. Falls back to the wide layout when the
        // width is unbounded (same Expanded-based behaviour as before).
        final stack =
            constraints.hasBoundedWidth &&
            constraints.maxWidth < _stackActionsBelow;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleBlock,
              const SizedBox(height: RestoflowSpacing.md),
              actionCluster,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: RestoflowSpacing.md),
            actionCluster,
          ],
        );
      },
    );
  }
}
