import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/pos_motion.dart';
import '../design/pos_visual_tokens.dart'
    show PosThemePair, kPosMoneyFontFamily, kPosMoneyFontFallbacks;
import '../format/money_format.dart';
import '../pos_palette.dart';
import '../state/cart_controller.dart';
import '../state/pos_device_accent.dart';
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
    barrierColor: const Color(0x730B1526),
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
    // POS-PREMIUM-VISUAL-POLISH-001: interaction feedback + the count badge
    // wear THIS terminal's secondary accent (non-critical highlights by
    // contract). The bar itself stays the Midnight Navy plane.
    final accent = ref.watch(posDeviceAccentColorProvider);

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
              // UI-ORANGE-BALANCE-POLISH-001: interaction feedback only — this
              // bar deliberately does NOT become an orange CTA.
              //
              // The whole bar is one tap target that OPENS the cart sheet, and
              // Send Order — the actual next step — lives inside that sheet
              // and already holds the single orange primary. Painting this bar
              // orange would put two competing primaries one tap apart, and
              // the one that means "commit the order" would be the one further
              // away.
              //
              // What the audit did find missing is feedback: the bar had no
              // hover, no pressed tone and no visible focus at all. It now has
              // all three in brand orange, at the shared 120ms token. The navy
              // plane, the 58px height, the safe area and every content
              // position are untouched, so nothing moves.
              hoverColor: accent.withValues(alpha: 0.14),
              splashColor: accent.withValues(alpha: 0.22),
              highlightColor: accent.withValues(alpha: 0.12),
              focusColor: accent.withValues(alpha: 0.18),
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
                      accent: accent,
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
                      // Count-up tween (settles on the exact final amount;
                      // integer minor units only — D-007). 004: the running
                      // total reads in the approved ember-sand on the navy
                      // bar (tokens §8); string unchanged.
                      PosAnimatedAmount(
                        minor: cart.subtotalMinor,
                        builder: (context, minor) => Text(
                          minor == cart.subtotalMinor
                              ? totalText
                              : MoneyFormatter.formatMinor(
                                  minor,
                                  cart.currencyCode,
                                ),
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: PosThemePair.of(context).actionSoft,
                            fontWeight: FontWeight.w800,
                            fontFamily: kPosMoneyFontFamily,
                            fontFamilyFallback: kPosMoneyFontFallbacks,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
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

/// The cart glyph with the terminal-accent count badge (hidden when empty /
/// after a submitted order shows a receipt glyph instead). The count tweens
/// up/down and always settles on the exact value.
class _CartIconWithBadge extends StatelessWidget {
  const _CartIconWithBadge({
    required this.count,
    required this.submitted,
    required this.accent,
  });

  final int count;
  final bool submitted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The PHONE fly-to-cart landing point (the side cart is not mounted
        // on phone layouts, so the GlobalKey stays unique).
        KeyedSubtree(
          key: posCartFlyTargetKey,
          child: Icon(
            submitted ? Icons.receipt_long : Icons.shopping_cart,
            color: Colors.white,
            size: RestoflowIconSizes.lg,
          ),
        ),
        if (!submitted && count > 0)
          PositionedDirectional(
            top: -6,
            end: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // 004: the approved EMBER count badge with the navy ring
              // (component specs §5); interactions keep the device accent.
              decoration: BoxDecoration(
                color: PosThemePair.of(context).action,
                borderRadius: BorderRadius.circular(RestoflowRadii.pill),
                border: Border.all(color: kPosBottomBar, width: 1.5),
              ),
              child: PosAnimatedCount(
                value: count,
                builder: (context, value) => Text(
                  value.toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
