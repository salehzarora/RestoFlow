import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/pos_visual_tokens.dart' show PosThemePair;
import '../pos_palette.dart';

/// A minus (white/hairline) + qty + plus (filled green) stepper (DESIGN-004).
///
/// POS-MODIFIER-SHEET-QUANTITY-003 lifted this out of `cart_panel.dart` so the
/// modifier sheet can offer the SAME control the cashier already knows from the
/// cart line, pixel for pixel. It is purely presentational: it owns no business
/// state and decides nothing. The caller supplies [quantity] and decides what a
/// tap means — the cart line removes itself at 1, the modifier sheet simply
/// disables minus at 1 — by passing a null callback to disable an edge.
///
/// Appearance and behaviour are deliberately unchanged from the private widget
/// it replaces: a >=44dp tap target (40dp when [dense]), a disabled edge that
/// LOOKS disabled rather than silently ignoring the tap, no long-press repeat,
/// no debounce, and no animation.
class PosQuantityStepper extends StatelessWidget {
  const PosQuantityStepper({
    required this.quantity,
    required this.l10n,
    required this.onIncrease,
    required this.onDecrease,
    this.dense = false,
    this.onTrack = false,
    this.decreaseKey,
    this.valueKey,
    this.increaseKey,
    super.key,
  });

  final int quantity;
  final AppLocalizations l10n;

  /// Null disables (and visibly dims) the edge.
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  /// Trims the tap target to 40dp so the narrow landscape side cart packs more
  /// lines. The modifier sheet uses the roomy 44dp default.
  final bool dense;

  /// POS-VISUAL-REDESIGN-PHASE-1-007 Step 2: wrap minus/value/plus in their own
  /// warm track so they read as ONE control on a cart line. OPT-IN and default
  /// false, so the modifier sheet (Phase 3's scope) keeps its appearance
  /// exactly as it is today.
  final bool onTrack;

  /// Optional stable keys for locale-independent testing.
  final Key? decreaseKey;
  final Key? valueKey;
  final Key? increaseKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          key: decreaseKey,
          icon: Icons.remove,
          tooltip: l10n.posDecreaseQuantity,
          filled: false,
          dense: dense,
          onPressed: onDecrease,
        ),
        SizedBox(
          width: dense ? 30 : 40,
          child: Text(
            quantity.toString(),
            key: valueKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: kRestoflowInk,
            ),
          ),
        ),
        _StepButton(
          key: increaseKey,
          icon: Icons.add,
          tooltip: l10n.posIncreaseQuantity,
          filled: true,
          dense: dense,
          onPressed: onIncrease,
        ),
      ],
    );
    if (!onTrack) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kPosStepperTrack,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm + 2),
        border: Border.all(color: kPosStepperTrackEdge),
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: row),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.filled,
    required this.onPressed,
    this.dense = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback? onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // A control inside a >=40/44dp tap target (fast, gloved cashier fingers);
    // dense trims it a touch so the landscape side cart packs more lines.
    final tap = dense ? 40.0 : 44.0;
    final inner = dense ? 34.0 : 38.0;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: dense ? 24 : 26,
        child: Opacity(
          // A disabled stepper must LOOK disabled, not just refuse the tap.
          opacity: onPressed == null ? 0.4 : 1.0,
          child: Container(
            width: tap,
            height: tap,
            alignment: Alignment.center,
            child: Container(
              width: inner,
              height: inner,
              // 004: the FILLED (plus) edge wears the approved EMBER action
              // mark (tokens §8) — the "add one more" gesture is an action
              // accent, matching the ×N marks; the minus stays quiet.
              decoration: BoxDecoration(
                color: filled
                    ? PosThemePair.of(context).actionMark
                    : Colors.white,
                borderRadius: BorderRadius.circular(RestoflowRadii.sm + 2),
                border: filled ? null : Border.all(color: kRestoflowHairline),
              ),
              child: Icon(
                icon,
                size: RestoflowIconSizes.md,
                // 010: the plus sits ON the action mark. onActionMark keeps
                // the shipped WHITE on every preset (saffron_gold's dark
                // onAction must not repaint it) and derives only for custom.
                color: filled
                    ? PosThemePair.of(context).onActionMark
                    : kRestoflowInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
