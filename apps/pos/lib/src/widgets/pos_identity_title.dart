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

/// POS-TOPBAR-QUICK-TWEAK-010: in RTL the block sits left of centre.
///
/// [Alignment] is used rather than a translation or end-padding on purpose. It
/// shifts by `|x|/2` of the FREE width, which means it can never push the block
/// outside its own box and never steals width from the name — so both the
/// no-overlap guarantee and the ellipsis behaviour survive the tweak at every
/// width. On a typical 1280 landscape bar this lands the block ~15% of the
/// middle region to the left (~74dp); for a long name, where there is little
/// free width, it self-clamps to whatever is safely available.
const double kPosIdentityRtlAlignX = -0.6;

/// The name's scale over the base title style (010 set 1.1;
/// POS-THEME-NAVBAR-POLISH-001 raises it with the taller bar so the one
/// fact a cashier verifies reads across the counter).
const double kPosIdentityNameScale = 1.2;

class PosIdentityTitle extends ConsumerWidget {
  const PosIdentityTitle({super.key});

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
        // POS-TOPBAR-QUICK-TWEAK-010: centred in LTR, nudged left in RTL.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        // POS-DESIGN-HANDOFF-IMPLEMENTATION-004: the identity rides the navy
        // bar as the approved translucent chip (white-9% bed) with light
        // text. Still DERIVED-only — the chip adds no tap, no configuration.
        return Align(
          alignment: rtl
              ? const Alignment(kPosIdentityRtlAlignX, 0)
              : Alignment.center,
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
                    _IdentityLogo(bytes: logo.sourceBytes),
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
                        fontSize:
                            (theme.textTheme.titleSmall?.fontSize ?? 14) *
                            kPosIdentityNameScale,
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
  const _IdentityLogo({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pos-topbar-identity-logo'),
      width: kPosIdentityLogoSize,
      height: kPosIdentityLogoSize,
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
