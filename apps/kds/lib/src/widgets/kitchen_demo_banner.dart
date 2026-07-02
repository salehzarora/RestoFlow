import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A slim, honest banner (RF-117) stating the KDS board is a local demo feed,
/// not synced to a backend. Keeps the kitchen-screen honest about persistence.
///
/// Design-polish sprint: rendered through the shared [RestoflowNoticeBanner]
/// (info tone) so the banner stays readable on the dark kitchen theme instead
/// of hardcoding a light-scheme container role.
class KitchenDemoBanner extends StatelessWidget {
  const KitchenDemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.md,
        RestoflowSpacing.md,
        RestoflowSpacing.md,
        0,
      ),
      child: RestoflowNoticeBanner(
        tone: RestoflowTone.info,
        icon: Icons.cloud_off_outlined,
        body: l10n.kdsDemoFeedBanner,
      ),
    );
  }
}
