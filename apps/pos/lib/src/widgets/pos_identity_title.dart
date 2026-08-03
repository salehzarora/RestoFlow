import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

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

/// The logo box. Smaller than the 38dp brand tile: this is a companion mark,
/// not a second brand.
const double kPosIdentityLogoSize = 26;

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
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kPosIdentityMaxWidth),
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
                      color: kRestoflowInk,
                    ),
                  ),
                ),
              ],
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
