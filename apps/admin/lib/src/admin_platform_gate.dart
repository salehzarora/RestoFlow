import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'util/external_link.dart';
import 'widgets/language_selector.dart';

/// The dashboard app's stable LOCAL origin (docs/LOCAL_RUNBOOK.md — the
/// `_run_dashboard_real.bat` fixed port). Used ONLY as the local/dev fallback.
const String kLocalDashboardUrl = 'http://localhost:57026';

/// The optional build-time override pointing the Admin app at the HOSTED
/// Dashboard (e.g. `--dart-define=RESTOFLOW_DASHBOARD_URL=https://...`). Absent by
/// default so local/dev builds keep using [kLocalDashboardUrl]. Public URL only —
/// never a secret.
const String kDashboardUrlEnvName = 'RESTOFLOW_DASHBOARD_URL';
const String _configuredDashboardUrl = String.fromEnvironment(
  kDashboardUrlEnvName,
);

/// RF-LIVE-002 — resolves the Dashboard URL shown on the explainer: the
/// configured [RESTOFLOW_DASHBOARD_URL] wins (so a hosted Admin points at the
/// hosted Dashboard), otherwise the local/dev [kLocalDashboardUrl] fallback. An
/// empty/whitespace value falls back too, so a blank define never yields a dead
/// link. [configured] is injectable for tests; production reads the dart-define.
String resolveDashboardUrl([String? configured]) {
  final value = (configured ?? _configuredDashboardUrl).trim();
  return value.isEmpty ? kLocalDashboardUrl : value;
}

/// The honest "this is the platform panel" explainer (Arabic-first copy) — shown
/// by [AdminAuthFlow] when a signed-in account is NOT a platform admin (e.g. a
/// restaurant owner). Explains what this app is, points to the Dashboard, and
/// (RF-119-b) lets the operator sign out to try a different account. This gate
/// weakens nothing — platform reads stay grant + aal2 + reason gated server-side.
class AdminGateExplainer extends StatelessWidget {
  const AdminGateExplainer({
    required this.signedIn,
    required this.onRetry,
    this.onSignOut,
    this.dashboardUrl,
    super.key,
  });

  /// True when a session exists but the account is not a platform admin
  /// (e.g. a restaurant owner) — adds the "not a platform admin" note.
  final bool signedIn;

  final VoidCallback onRetry;

  /// RF-119-b: when provided (a real session exists), a Sign-out action lets the
  /// operator switch accounts. Null when there is no session.
  final VoidCallback? onSignOut;

  /// RF-LIVE-002: the Dashboard URL to show/open. Null => resolved from
  /// `RESTOFLOW_DASHBOARD_URL` (hosted) or the local fallback. Injectable for
  /// tests.
  final String? dashboardUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final resolvedDashboardUrl = resolveDashboardUrl(dashboardUrl);
    return _GateScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: RestoflowPanelWidths.helpPanel,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(RestoflowSpacing.xl),
            children: [
              Center(child: RestoflowBrandMark(title: l10n.adminAppTitle)),
              const SizedBox(height: RestoflowSpacing.xl),
              RestoflowNoticeBanner(
                tone: RestoflowTone.info,
                icon: Icons.admin_panel_settings_outlined,
                title: l10n.adminGateTitle,
                body: l10n.adminGateNotOwner,
              ),
              if (signedIn) ...[
                const SizedBox(height: RestoflowSpacing.sm),
                Text(
                  l10n.adminGateNotAdminAccount,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: RestoflowSpacing.lg),
              RestoflowSectionCard(
                title: l10n.adminGateUseDashboard,
                children: [
                  const SizedBox(height: RestoflowSpacing.md),
                  RestoflowCodeBlock(lines: [resolvedDashboardUrl]),
                  const SizedBox(height: RestoflowSpacing.md),
                  Text(
                    l10n.adminGateProvisionHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              Wrap(
                spacing: RestoflowSpacing.sm,
                runSpacing: RestoflowSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('admin-gate-open-dashboard'),
                    onPressed: () => openExternalUrl(resolvedDashboardUrl),
                    icon: const Icon(
                      Icons.open_in_new,
                      size: RestoflowIconSizes.sm,
                    ),
                    label: Text(l10n.adminGateOpenDashboard),
                  ),
                  OutlinedButton.icon(
                    key: const Key('admin-gate-retry'),
                    onPressed: onRetry,
                    icon: const Icon(
                      Icons.refresh,
                      size: RestoflowIconSizes.sm,
                    ),
                    label: Text(l10n.authTryAgain),
                  ),
                  if (signedIn && onSignOut != null)
                    TextButton.icon(
                      key: const Key('admin-gate-signout'),
                      onPressed: onSignOut,
                      icon: const Icon(
                        Icons.logout,
                        size: RestoflowIconSizes.sm,
                      ),
                      label: Text(l10n.authSignOut),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared scaffold for the gate states: app title + language switcher, so the
/// explainer is readable in the visitor's language before any sign-in.
class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).adminAppTitle),
        actions: const [LanguageSelector()],
      ),
      body: SafeArea(child: child),
    );
  }
}
