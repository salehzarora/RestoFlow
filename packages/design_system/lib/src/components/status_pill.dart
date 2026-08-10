import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A small, rounded status chip with a semantic [tone] (RF-141A).
///
/// Replaces the per-app status pills (POS/KDS/dashboard/admin) with one shared
/// widget. [label] is a pre-built string (data or localized chrome — the widget
/// renders it verbatim); colours come from [tone] via the theme, so the chip is
/// themeable and RTL-agnostic (the optional leading [icon] sits at the
/// reading-start via a [Row], which mirrors automatically in RTL).
class RestoflowStatusPill extends StatelessWidget {
  const RestoflowStatusPill({
    required this.label,
    this.tone = RestoflowTone.neutral,
    this.icon,
    this.dense = true,
    super.key,
  });

  final String label;
  final RestoflowTone tone;

  /// Optional leading icon. When null, no icon is shown (the pill is text-only).
  final IconData? icon;

  /// When false the pill uses larger, bolder text (`labelLarge`) and a larger
  /// icon — for at-a-glance readability on a kitchen display (RF-141E). Defaults
  /// to true (compact `labelSmall`) for inline POS/dashboard/admin pills.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = tone.styleOf(theme);
    final textStyle =
        (dense ? theme.textTheme.labelSmall : theme.textTheme.labelLarge)
            ?.copyWith(color: style.onContainer, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 14 : 16, color: style.onContainer),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          // A PILL MAY NEVER BE WIDER THAN THE BOX IT IS GIVEN.
          //
          // A horizontal RenderFlex lays its NON-FLEX children out with an
          // unbounded main-axis constraint, so a plain `Text` here measured its
          // full single-line width however narrow the pill actually was: the
          // Container clamped itself to the parent's bound, this Row did not,
          // and the Row overflowed its own box. That is why bounding the pill
          // from OUTSIDE never helped — the bound stops at the Container and
          // never reaches the label.
          //
          // The label is the only part of a chip that may give ground, so it is
          // the only flexible child. `Flexible`, never `Expanded`: a loose fit
          // keeps the natural intrinsic width whenever there is room, so the
          // pill still hugs its label — call sites put it in Wraps, Aligns and
          // trailing slots that depend on that — and under an UNBOUNDED parent
          // a loose flex child in a MainAxisSize.min row asserts nothing, while
          // a tight one would throw at every trailing-chip Row in the repo.
          Flexible(
            child: Text(
              label,
              style: textStyle,
              softWrap: true,
              // Two lines of chrome is still a chip. Wrapping is the honest
              // refusal: the whole label survives at the text scale the user
              // asked for, which shrinking it would silently undo.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Size to the longest WRAPPED line rather than to the width on
              // offer, so a two-line pill stays a chip instead of stretching
              // into a full-width coloured bar.
              textWidthBasis: TextWidthBasis.longestLine,
            ),
          ),
        ],
      ),
    );
  }
}
