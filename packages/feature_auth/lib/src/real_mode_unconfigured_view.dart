import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A helpful, honest "real mode is not configured" page.
///
/// Shown when an app is started in REAL mode (`RESTOFLOW_DEMO_MODE=false`) but
/// the Supabase connection config is missing/invalid — or when the backend
/// bootstrap failed at startup. RestoFlow never fakes a backend, so instead of
/// crashing (or silently showing demo data as if it were real) the app explains
/// exactly which `--dart-define` values real mode needs and how to run the demo
/// instead. The env names are technical identifiers (not translated prose); all
/// sentences come from `restoflow_l10n` (D-014).
class RealModeUnconfiguredView extends StatelessWidget {
  const RealModeUnconfiguredView({super.key});

  /// The demo/real flag read by `authDemoModeEnabled` (default true = demo).
  static const String demoModeEnvName = 'RESTOFLOW_DEMO_MODE';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final defines = [
      '--dart-define=$demoModeEnvName=false',
      '--dart-define=${SupabaseBootstrapConfig.urlEnvName}=<supabase-url>',
      '--dart-define=${SupabaseBootstrapConfig.anonKeyEnvName}=<anon-key>',
    ];
    // The shared help-page pattern: a warning banner stating the honest cause
    // + a how-to card with the config snippet (RestoflowCodeBlock keeps
    // command-line text LTR, even under ar/he).
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: RestoflowPanelWidths.helpPanel,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(RestoflowSpacing.xl),
            children: [
              RestoflowNoticeBanner(
                tone: RestoflowTone.warning,
                icon: Icons.settings_outlined,
                title: l10n.authRealModeUnconfiguredTitle,
                body: l10n.authRealModeUnconfiguredBody,
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              RestoflowSectionCard(
                title: l10n.authRealModeUnconfiguredHowTo,
                children: [
                  const SizedBox(height: RestoflowSpacing.sm),
                  RestoflowCodeBlock(lines: defines),
                  const SizedBox(height: RestoflowSpacing.md),
                  Text(l10n.authRealModeUnconfiguredDemoHint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
