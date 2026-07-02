import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A full-width notice banner with a semantic [tone] (RF-141A).
///
/// Replaces the per-app demo/real notice banners with one shared widget. Use it
/// to keep a surface honest about its data source (info = demo data; warning =
/// "live · limited"; danger = a failure). [body] is the main message; [title]
/// is an optional bold lead line. Colours come from [tone] via the theme.
/// RTL-friendly: an icon + an [Expanded] text column in a [Row] mirror
/// automatically, and padding is direction-agnostic.
class RestoflowNoticeBanner extends StatelessWidget {
  const RestoflowNoticeBanner({
    required this.body,
    this.title,
    this.tone = RestoflowTone.info,
    this.icon,
    this.action,
    super.key,
  });

  /// Optional bold lead line above [body].
  final String? title;

  /// The main message.
  final String body;

  final RestoflowTone tone;

  /// Overrides the tone's default leading icon when set.
  final IconData? icon;

  /// Optional trailing action (e.g. a compact button that resolves the
  /// notice). Rendered after the text column; mirrors under RTL.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = tone.styleOf(theme);
    final titleText = title;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? style.icon, size: 20, color: style.onContainer),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titleText != null) ...[
                  Text(
                    titleText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: style.onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                ],
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: style.onContainer,
                  ),
                ),
              ],
            ),
          ),
          if (action case final action?) ...[
            const SizedBox(width: RestoflowSpacing.sm),
            action,
          ],
        ],
      ),
    );
  }
}
