import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

import '../design/pos_visual_tokens.dart' show PosThemePair;
import '../state/pos_printer_assignments.dart';
import '../state/pos_receipt_logo.dart';

/// POS-TOPBAR-RESTAURANT-IDENTITY-009 — WHICH restaurant this station is
/// connected to, shown in the middle of the POS top bar.
///
/// The middle of the bar was empty while the one thing a cashier cannot verify
/// from the screen — which restaurant/branch the station is actually talking
/// to — lived three taps deep in the device-settings sheet. This surfaces it
/// permanently, with the restaurant's own receipt logo when one is configured.
///
/// It is deliberately DERIVED, never configured: both the name and the logo
/// come from the token-proven device assignments the POS already loads, so
/// there is no second source of truth to drift and nothing new to set up.

/// Below this much free space the identity is dropped entirely rather than
/// ellipsized into a meaningless "…" — the actions matter more on a phone bar.
const double kPosIdentityMinWidth = 104;

/// The identity never grows past this, so a long name cannot crowd the bar
/// even when the free space is wide.
const double kPosIdentityMaxWidth = 340;

/// The logo box. 010 grew it to 52 on the old white bar; the approved v4
/// identity CHIP carries a compact white logo box instead (component specs
/// §8), sized to ride inside the 56–68dp primary bar with the chip's 6px
/// vertical padding.
const double kPosIdentityLogoSize = 34;

/// POS-NAVBAR-TRANSPARENT-BRAND (supersedes the POS-TOPBAR-QUICK-TWEAK-010
/// RTL nudge): the block is centred on the BAR itself — the owner reads it as
/// the bar's centrepiece, not as the centre of whatever free region the brand
/// block and the action cluster happen to leave. The chip is laid out by
/// [_BarCentredLayout]: it targets the bar's midpoint (computed from the
/// region's own offset inside the bar, [PosIdentityTitle.barStartInset]) and
/// self-clamps inside the region, so it can never touch the brand block or
/// the actions and the ellipsis behaviour survives at every width. When the
/// free region cannot reach the midpoint it sits as close to it as it safely
/// can.

/// The name's scale over the base title style (010 set 1.1;
/// POS-THEME-NAVBAR-POLISH-001 raises it with the taller bar so the one
/// fact a cashier verifies reads across the counter).
const double kPosIdentityNameScale = 1.2;

class PosIdentityTitle extends ConsumerWidget {
  const PosIdentityTitle({
    this.barStartInset = 0,
    this.logoSize = kPosIdentityLogoSize,
    super.key,
  });

  /// Distance, in the reading direction, from the bar's START edge to this
  /// widget's own region (the title inset + the brand block). Lets the chip
  /// centre itself on the BAR instead of on its region.
  final double barStartInset;

  /// The logo box side. POS-NAVBAR-TRANSPARENT-BRAND: the caller passes the
  /// bar's brand-mark size so the chip stands exactly as tall as the BIZBOT
  /// lockup beside it (logo + the chip's 6 px vertical padding).
  final double logoSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(posStationIdentityLabelProvider);
    final logo = ref.watch(posReceiptLogoAssetProvider);

    // Nothing proven about this station yet (demo / unconfigured / loading /
    // failed): keep the region stable and empty. Inventing a placeholder name
    // here would be a lie the cashier cannot check.
    if (label == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The free middle space, measured AFTER the left block and the actions
        // have taken theirs — so this one rule covers every layout mode and
        // both text directions without guessing at breakpoints.
        if (constraints.maxWidth < kPosIdentityMinWidth) {
          return const SizedBox.shrink();
        }
        // POS-NAVBAR-TRANSPARENT-BRAND: centred on the BAR in both text
        // directions (the region's offset inside the bar is barStartInset).
        final direction = Directionality.of(context);
        // POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the identity rides the navy
        // bar as the approved translucent chip (white-9% bed) with light
        // text. Still DERIVED-only — the chip adds no tap, no configuration.
        return CustomSingleChildLayout(
          delegate: _BarCentredLayout(
            barWidth: MediaQuery.sizeOf(context).width,
            barStartInset: barStartInset,
            direction: direction,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kPosIdentityMaxWidth),
            // POS-THEME-NAVBAR-POLISH-001: a stronger, easier-to-read chip —
            // a firmer translucent bed with a hairline edge and roomier
            // padding, sized for the taller bar.
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(9, 6, 14, 6),
              // POS-CUSTOM-DEVICE-THEME-010: bed/edge/ink ride the pair —
              // identical white-wash bytes on every preset bar, a dark wash
              // when a custom pair paints the bar light.
              decoration: BoxDecoration(
                color: PosThemePair.of(context).identityBed,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: PosThemePair.of(context).identityEdge,
                ),
              ),
              child: Row(
                key: const Key('pos-topbar-identity'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (logo != null) ...[
                    _IdentityLogo(bytes: logo.sourceBytes, size: logoSize),
                    const SizedBox(width: RestoflowSpacing.sm),
                  ],
                  // Flexible + ellipsis: a long Arabic/Hebrew/English name stays
                  // on ONE line and truncates instead of pushing the bar.
                  Flexible(
                    child: Text(
                      label,
                      key: const Key('pos-topbar-identity-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: PosThemePair.of(context).onPrimary,
                        // 010: +10% on whatever the theme resolves to, so the
                        // tweak rides the theme instead of pinning a literal.
                        // POS-NAVBAR-TRANSPARENT-BRAND: and it grows gently
                        // with the logo box (44 → ×1.07, 40 → ×1.04, 34 → ×1)
                        // so the name keeps pace with the taller chip.
                        fontSize:
                            (theme.textTheme.titleSmall?.fontSize ?? 14) *
                            kPosIdentityNameScale *
                            posIdentityNameGrowth(logoSize),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The restaurant's receipt logo, contained in a rounded square.
///
/// `BoxFit.contain` — a logo mark must never be cropped to fill a box, so the
/// aspect ratio wins and the padding absorbs the difference.
class _IdentityLogo extends StatelessWidget {
  const _IdentityLogo({required this.bytes, required this.size});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pos-topbar-identity-logo'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        border: Border.all(color: kRestoflowHairline),
      ),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Undecodable/corrupt bytes must degrade to TEXT ONLY, never a broken
        // image icon and never an exception on the cashier's top bar.
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

/// The name's growth over the 34 px logo baseline: a quarter of the logo's
/// relative growth, so a 44 px chip reads ~7 % larger — never a shout.
double posIdentityNameGrowth(double logoSize) =>
    0.75 + 0.25 * (logoSize / kPosIdentityLogoSize);

/// Positions the identity chip at the BAR's midpoint (not the region's),
/// clamped inside the region so it can never overlap the brand block or the
/// action cluster. The child keeps its natural (capped) size.
class _BarCentredLayout extends SingleChildLayoutDelegate {
  const _BarCentredLayout({
    required this.barWidth,
    required this.barStartInset,
    required this.direction,
  });

  final double barWidth;
  final double barStartInset;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Leading edge (in the reading direction) that puts the chip's centre on
    // the bar's centre, clamped to the region.
    final free = (size.width - childSize.width).clamp(0.0, double.infinity);
    final wanted = barWidth / 2 - barStartInset - childSize.width / 2;
    final leading = wanted.clamp(0.0, free).toDouble();
    final dx = direction == TextDirection.rtl
        ? size.width - leading - childSize.width
        : leading;
    return Offset(dx, (size.height - childSize.height) / 2);
  }

  @override
  bool shouldRelayout(_BarCentredLayout oldDelegate) =>
      barWidth != oldDelegate.barWidth ||
      barStartInset != oldDelegate.barStartInset ||
      direction != oldDelegate.direction;
}
