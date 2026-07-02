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
    final theme = Theme.of(context);
    final defines = [
      '--dart-define=$demoModeEnvName=false',
      '--dart-define=${SupabaseBootstrapConfig.urlEnvName}=<supabase-url>',
      '--dart-define=${SupabaseBootstrapConfig.anonKeyEnvName}=<anon-key>',
    ].join('\n');
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                    ),
                    // Command-line text is always LTR, even under ar/he.
                    child: Text(
                      defines,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
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
