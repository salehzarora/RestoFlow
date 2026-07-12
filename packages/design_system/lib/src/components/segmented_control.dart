import 'package:flutter/material.dart';

import '../tokens.dart';

/// One option of a [RestoflowSegmentedControl] (RF-132): a caller-localized
/// [label], the [value] it selects, an optional stable [key] for testing, and
/// an optional [icon] shown only while the segment is selected (a visual
/// accent, never information on its own — the label always renders).
class RestoflowSegment<T> {
  const RestoflowSegment({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;

  /// Decorative leading icon rendered ONLY on the selected segment (e.g. the
  /// calendar glyph on the active date range). Optional.
  final IconData? icon;

  /// A stable widget key for the segment's tappable surface
  /// (locale-independent testing).
  final Key? key;
}

/// A cohesive single-choice segmented control (RF-132): one bordered white bar
/// holding every option, thin hairline dividers between unselected neighbours,
/// and a solid brand-green fill (white foreground, soft green shadow) on the
/// selected segment.
///
/// Replaces detached chip rows where the options form ONE mutually-exclusive
/// group (e.g. the Overview reporting range). Pure presentation: the caller
/// owns the selected [value] and receives taps through [onSelected]; labels are
/// caller-localized strings.
///
/// Accessibility: each segment is one merged semantic node — a button carrying
/// its label and a selected state (selection is never conveyed by colour alone;
/// the selected segment also gains its icon and a weight change). Keyboard
/// focus is visible via [InkWell]'s focus highlight. RTL-safe: a plain [Row]
/// mirrors with the ambient [Directionality]. Static (no animation beyond the
/// ink feedback) so it stays `pumpAndSettle`-safe.
class RestoflowSegmentedControl<T> extends StatelessWidget {
  const RestoflowSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.expand = false,
    super.key,
  });

  /// The options, in reading order.
  final List<RestoflowSegment<T>> segments;

  /// The currently selected value.
  final T selected;

  /// Called with the tapped segment's value (also when re-tapping the current
  /// selection — the caller decides whether that is a no-op).
  final ValueChanged<T> onSelected;

  /// When true each segment takes an equal share of the available width
  /// (narrow layouts); when false the bar hugs its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final isSelected = segments[i].value == selected;
      final prevSelected = i > 0 && segments[i - 1].value == selected;
      if (i > 0) {
        // A hairline divider between neighbours, hidden next to the selected
        // segment so its filled pill reads as one uninterrupted shape.
        children.add(_SegmentDivider(visible: !isSelected && !prevSelected));
      }
      final segment = _SegmentButton<T>(
        segment: segments[i],
        selected: isSelected,
        dense: expand,
        onTap: () => onSelected(segments[i].value),
      );
      children.add(expand ? Expanded(child: segment) : segment);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: kRestoflowHairline),
      ),
      padding: const EdgeInsets.all(3),
      // IntrinsicHeight bounds the stretch axis so every segment (and divider)
      // shares the tallest segment's height in any parent, including
      // unbounded-height columns.
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The 1px hairline between two unselected neighbours; an equally-sized
/// transparent spacer otherwise, so segment geometry never shifts on
/// selection change.
class _SegmentDivider extends StatelessWidget {
  const _SegmentDivider({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      color: visible ? kRestoflowHairline : Colors.transparent,
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final RestoflowSegment<T> segment;
  final bool selected;

  /// True in expand mode: tighter horizontal padding so flexed segments give
  /// their labels the most room on narrow layouts (word-boundary wrapping
  /// instead of mid-word breaks).
  final bool dense;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(RestoflowRadii.sm + 1);
    final foreground = selected ? Colors.white : kRestoflowInk2;
    final icon = segment.icon;

    final content = Container(
      constraints: const BoxConstraints(minHeight: 38),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: dense ? RestoflowSpacing.sm : RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: selected ? kRestoflowSeedColor : Colors.transparent,
        borderRadius: radius,
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x3D1B7A52),
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected && icon != null) ...[
            Icon(icon, size: RestoflowIconSizes.sm, color: foreground),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          Flexible(
            child: Text(
              segment.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    // One merged, selectable button node per segment so screen readers get the
    // label + selection, and the visual subtree adds no duplicate node.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: segment.label,
        child: Material(
          key: segment.key,
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: kRestoflowCanvas,
            focusColor: kRestoflowSeedColor.withValues(alpha: 0.12),
            child: ExcludeSemantics(child: content),
          ),
        ),
      ),
    );
  }
}
