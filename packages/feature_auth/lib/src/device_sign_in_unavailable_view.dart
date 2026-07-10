import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Why the real-mode device-auth bootstrap produced no pairing seams.
///
/// POS/KDS compose their real seams at startup (anonymous device sign-in ->
/// pairing repository + staff directory, D-011/RF-161). When that fails the
/// apps must show an HONEST state instead of falling back to the legacy
/// owner-account gate (which renders a misleading "Account access denied" for
/// a device that was never supposed to have an account).
enum RealDeviceAuthProblem {
  /// Real mode was selected but the Supabase connection config is missing or
  /// invalid -> [RealModeUnconfiguredView].
  unconfigured,

  /// Config is present but the anonymous device sign-in was rejected (e.g.
  /// anonymous sign-ins disabled on the project) ->
  /// [DeviceSignInUnavailableView].
  signInUnavailable,

  /// PILOT-OFFLINE-BOOT-001: config is present but the network/Supabase was
  /// UNREACHABLE at launch (the venue Wi‑Fi is down or slow) -> the retryable
  /// [OfflineBootView]. The composition root's boot gate intercepts this and
  /// shows the offline screen with a working Retry (no app restart); the app
  /// widgets map it defensively to a non-retry offline view.
  offline,
}

/// An honest, actionable "device sign-in unavailable" page for POS/KDS.
///
/// Shown when real mode is configured but `signInAnonymously()` failed, so the
/// device cannot reach the pairing backend. Explains the exact cause and the
/// local fix (the Supabase auth toggle) instead of a generic denial. The
/// config snippet is a technical identifier (not translated prose); all
/// sentences come from `restoflow_l10n` (D-014).
class DeviceSignInUnavailableView extends StatelessWidget {
  const DeviceSignInUnavailableView({super.key});

  /// The local Supabase auth setting that gates anonymous device sign-in.
  static const String configSnippet =
      'supabase/config.toml\n[auth]\nenable_anonymous_sign_ins = true';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The shared help-page pattern: a warning banner stating the honest cause
    // + a how-to card with the config snippet (RestoflowCodeBlock keeps
    // config text LTR, even under ar/he).
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
                icon: Icons.phonelink_lock_outlined,
                title: l10n.authDeviceSignInUnavailableTitle,
                body: l10n.authDeviceSignInUnavailableBody,
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              RestoflowSectionCard(
                title: l10n.authDeviceSignInUnavailableHowTo,
                children: [
                  const SizedBox(height: RestoflowSpacing.sm),
                  RestoflowCodeBlock(lines: configSnippet.split('\n')),
                  const SizedBox(height: RestoflowSpacing.md),
                  Text(l10n.authDeviceSignInUnavailableFix),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
