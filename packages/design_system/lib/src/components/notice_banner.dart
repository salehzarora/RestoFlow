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
              mainAxisSize: MainAxisSize.min,
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
                // THE ACTION SITS UNDER THE MESSAGE, NOT BESIDE IT.
                //
                // It used to be a NON-FLEX child of the outer Row, so it
                // measured its full intrinsic width however little the banner
                // had left. Measured with a realistic "Create kitchen display"
                // action, the first failing text scale per width was:
                //
                //     1280 never · 834 never · 700 at 2.0 · 540 at 1.5
                //     430 at 1.15 · 390 at 1.0
                //
                // 390 at 1.0 is the part that matters — a shipping defect at
                // ordinary text on any phone-width surface, and a banner is
                // exactly where the product tells someone what to do next.
                //
                // A button cannot ellipsise (its label belongs to the caller),
                // so the layout has to become vertical. It does so
                // UNCONDITIONALLY rather than by measuring, because the natural
                // way to measure — LayoutBuilder — cannot be used here: dialogs
                // size their content by asking for intrinsic dimensions and
                // LayoutBuilder refuses to answer that, and this banner is
                // rendered inside dialogs. Unconditional also matches
                // MaterialBanner's own convention of putting actions below the
                // content, and it keeps one layout to reason about instead of
                // two that differ by a threshold.
                if (action case final action?) ...[
                  const SizedBox(height: RestoflowSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
