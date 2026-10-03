import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// POS-QUICK-NOTE-CHIPS-001 — one quick note the cashier added to an item, as
/// a box with its own remove button, so a phrase tapped by mistake goes away
/// in one tap instead of being deleted character by character.
///
/// The owner's label is shown verbatim and wraps inside the box rather than
/// being cut to an ellipsis: it is a kitchen instruction. The remove button is
/// a full 48dp target (a chip's built-in delete icon is only about 27dp wide),
/// sits at the END edge so it follows the reading direction (left in Arabic
/// and Hebrew, right in English), and uses Flutter's own localized "Delete"
/// tooltip, so no new copy is needed. The label and the button are announced
/// together ("No onions, Delete"), so a screen reader never meets several
/// identical "Delete" buttons without knowing which phrase each removes.
class QuickNoteChip extends StatelessWidget {
  const QuickNoteChip({
    required this.label,
    required this.onRemove,
    required this.removeKey,
    super.key,
  });

  /// The preset's phrase, exactly as the owner wrote it.
  final String label;

  /// Removes this one phrase. Never confirms or closes the sheet.
  final VoidCallback onRemove;

  /// The remove button's key, so tests and tooling can target it directly.
  final Key removeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Material(
        color: scheme.secondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.pill),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: RestoflowSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    softWrap: true,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                IconButton(
                  key: removeKey,
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  onPressed: onRemove,
                  color: scheme.onSecondaryContainer,
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
