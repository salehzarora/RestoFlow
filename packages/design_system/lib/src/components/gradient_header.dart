import 'package:flutter/material.dart';

import '../tokens.dart';

/// The full-bleed brand-gradient page header (Dashboard "1c" / Warm-Bento).
///
/// Replaces [RestoflowPageHeader] at the top of each dashboard screen with a
/// full-width panel painted in [kRestoflowBrandGradient] (deep green → brand
/// green → a terracotta corner) plus a soft white highlight. Two modes:
///
///  * **Standard** — a rounded icon box + title (`headlineSmall`, white) +
///    optional subtitle (`bodyMedium`, white .82) at the reading start, and
///    trailing [actions] (use [whiteActionStyle] for the white primary button)
///    at the reading end. Every screen except the Overview uses this.
///  * **hero** — pass a [hero] widget to render a custom body (the Overview's
///    big-number + delta + range control + sparkline) in place of the title.
///
/// Presentation-only and RTL-safe: the gradient begins at the directional
/// top-start, padding is directional, and the icon sits INNER to the title so
/// the whole header mirrors with the layout. No animation (`pumpAndSettle`-safe).
class RestoflowGradientHeader extends StatelessWidget {
  const RestoflowGradientHeader({
    this.icon,
    this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.hero,
    super.key,
  }) : assert(
         hero != null || title != null,
         'RestoflowGradientHeader needs a title (standard) or a hero body',
       );

  /// Leading icon for the standard header's rounded box.
  final IconData? icon;

  /// Title (standard mode). Ignored when [hero] is provided.
  final String? title;

  /// Optional subtitle under the title (standard mode).
  final String? subtitle;

  /// Trailing actions (e.g. the page's primary button). Style buttons with
  /// [whiteActionStyle].
  final List<Widget> actions;

  /// A custom body (Overview hero). When non-null it replaces the standard
  /// icon/title/subtitle row entirely; [actions] are ignored.
  final Widget? hero;

  /// The white primary-button style for header actions: white fill, brand-dark
  /// (`#136343`) foreground — legible on the gradient.
  static ButtonStyle whiteActionStyle(BuildContext context) =>
      FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: kRestoflowBrandDark,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heroBody = hero;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kRestoflowBrandGradient),
      child: Stack(
        children: [
          // Soft white highlight near the directional top-end corner.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: AlignmentDirectional.topEnd,
                    radius: 1.1,
                    colors: [Color(0x21FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: RestoflowSpacing.xl,
              vertical: heroBody != null
                  ? RestoflowSpacing.xl
                  : RestoflowSpacing.lg,
            ),
            child: heroBody ?? _standard(theme),
          ),
        ],
      ),
    );
  }

  Widget _standard(ThemeData theme) {
    final subtitleText = subtitle;
    final iconData = icon;
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title!,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitleText != null) ...[
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            subtitleText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title + inner icon box, clustered at the reading start.
        Expanded(
          child: Row(
            children: [
              Flexible(child: titleColumn),
              if (iconData != null) ...[
                const SizedBox(width: RestoflowSpacing.md),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    iconData,
                    size: RestoflowIconSizes.lg,
                    color: Colors.white,
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
    );
  }
}
