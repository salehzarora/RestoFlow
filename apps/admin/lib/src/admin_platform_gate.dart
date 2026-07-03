import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show AuthContextFetcher;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'platform_admin_screen.dart';
import 'util/external_link.dart';
import 'widgets/language_selector.dart';

/// The dashboard app's stable local origin (docs/LOCAL_RUNBOOK.md — the
/// `_run_dashboard_real.bat` fixed port). Shown as a copyable link on the
/// gate so a restaurant owner who opened the wrong app can jump to the right
/// one. Local-run helper only; a deployed build would use its real domain.
const String kLocalDashboardUrl = 'http://localhost:57026';

/// App-level platform gate for the admin surface (sprint: admin access
/// clarification).
///
/// Replaces the shared gate's dead-end "Account access denied" for this app:
/// the admin app has NO sign-in flow by design (platform access is granted
/// manually — D-026), so an unauthenticated visitor or a signed-in tenant
/// account (e.g. a restaurant owner) gets an HONEST explainer of what this
/// app is and where to go, never a scary generic denial. A real platform
/// admin (`is_platform_admin == true` from `get_my_context`) enters the
/// overview exactly as before; data reads still enforce grant + MFA + reason
/// server-side (RF-091) — this gate weakens nothing.
class AdminPlatformGate extends StatefulWidget {
  const AdminPlatformGate({required this.fetchContext, super.key});

  final AuthContextFetcher fetchContext;

  @override
  State<AdminPlatformGate> createState() => _AdminPlatformGateState();
}

class _AdminPlatformGateState extends State<AdminPlatformGate> {
  late Future<Result<MyContext, AuthFailure>> _future = widget.fetchContext();

  void _retry() {
    setState(() {
      _future = widget.fetchContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Result<MyContext, AuthFailure>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return _GateScaffold(
            child: RestoflowStateView(
              showSpinner: true,
              title: l10n.authLoadingAccount,
            ),
          );
        }
        return snap.data!.fold(
          (ctx) => ctx.isPlatformAdmin
              ? const PlatformAdminScreen()
              : AdminGateExplainer(signedIn: true, onRetry: _retry),
          (failure) => switch (failure) {
            // No session, or a session the backend rejects (unlinked/inactive):
            // the explainer, not a dead end — this app has no login by design.
            AuthUnauthenticatedFailure() || AuthDeniedFailure() =>
              AdminGateExplainer(signedIn: false, onRetry: _retry),
            // Transport/config problems stay an honest error with retry.
            _ => _GateScaffold(
              child: RestoflowStateView(
                icon: Icons.error_outline,
                tone: RestoflowTone.danger,
                title: l10n.authError,
                actions: [
                  FilledButton.tonal(
                    onPressed: _retry,
                    child: Text(l10n.authTryAgain),
                  ),
                ],
              ),
            ),
          },
        );
      },
    );
  }
}

/// The honest "this is the platform panel" explainer (Arabic-first copy).
class AdminGateExplainer extends StatelessWidget {
  const AdminGateExplainer({
    required this.signedIn,
    required this.onRetry,
    super.key,
  });

  /// True when a session exists but the account is not a platform admin
  /// (e.g. a restaurant owner) — adds the "not a platform admin" note.
  final bool signedIn;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
                  RestoflowCodeBlock(lines: const [kLocalDashboardUrl]),
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
                    onPressed: () => openExternalUrl(kLocalDashboardUrl),
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
