import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import 'cart_panel.dart';

/// Opens the phone slide-up cart sheet (DESIGN-004 §6.8): a rounded-top white
/// sheet hosting the SHARED [CartPanelContent] (the same cart the side panel
/// shows), with a drag handle + close button and a dark scrim.
Future<void> showPosCartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x7310201A),
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.89;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(RestoflowRadii.xl),
              topEnd: Radius.circular(RestoflowRadii.xl),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(RestoflowRadii.xl),
              topEnd: Radius.circular(RestoflowRadii.xl),
            ),
            child: CartPanelContent(
              key: const Key('pos-cart-sheet-content'),
              isSheet: true,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      );
    },
  );
}

/// The fixed dark bottom cart bar for phone portrait (DESIGN-004 §6.8): shows
/// the cart count + total (or the "order sent" state) and opens the cart sheet.
/// Presentation only — reads [cartControllerProvider]; the sheet it opens hosts
/// the shared cart content so no cart logic is duplicated.
class PosBottomBar extends ConsumerWidget {
  const PosBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cart = ref.watch(cartControllerProvider);
    final submitted = cart.submittedOrder != null;
    final totalText = MoneyFormatter.formatMinor(
      cart.subtotalMinor,
      cart.currencyCode,
    );
    final label = submitted ? l10n.posCartBarSent : l10n.posCartTitle;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.md,
          RestoflowSpacing.xs,
          RestoflowSpacing.md,
          RestoflowSpacing.md,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kPosBottomBar,
            borderRadius: BorderRadius.circular(RestoflowRadii.lg),
            boxShadow: RestoflowShadows.lg,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('pos-bottom-cart-bar'),
              borderRadius: BorderRadius.circular(RestoflowRadii.lg),
              onTap: () => showPosCartSheet(context),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(
                  horizontal: RestoflowSpacing.lg,
                ),
                child: Row(
                  children: [
                    _CartIconWithBadge(
                      count: cart.itemCount,
                      submitted: submitted,
                    ),
                    const SizedBox(width: RestoflowSpacing.md),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!submitted)
                      Text(
                        totalText,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cart glyph with a terracotta count badge (hidden when empty / after a
/// submitted order shows a receipt glyph instead).
class _CartIconWithBadge extends StatelessWidget {
  const _CartIconWithBadge({required this.count, required this.submitted});

  final int count;
  final bool submitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          submitted ? Icons.receipt_long : Icons.shopping_cart,
          color: Colors.white,
          size: RestoflowIconSizes.lg,
        ),
        if (!submitted && count > 0)
          PositionedDirectional(
            top: -6,
            end: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: kPosTerracotta,
                borderRadius: BorderRadius.circular(RestoflowRadii.pill),
                border: Border.all(color: kPosBottomBar, width: 1.5),
              ),
              child: Text(
                count.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
