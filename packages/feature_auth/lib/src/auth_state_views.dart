import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A tone-aware auth-state scaffold: a hero icon in a semantic tone circle, a
/// localized message, and optional action buttons — so a denied/error state
/// LOOKS like a failure instead of a brand moment. Delegates its presentation
/// to [RestoflowStateView] (which falls back to plain [ColorScheme] roles when
/// the RestoFlow theme extension is absent, e.g. bare test harnesses). Shared
/// by the auth-gate state views below. All text is supplied localized
/// (RF-020 / D-014) - no hardcoded strings.
class AuthMessageView extends StatelessWidget {
  const AuthMessageView({
    required this.icon,
    required this.message,
    this.tone,
    this.actions = const <Widget>[],
    super.key,
  });

  final IconData icon;
  final String message;

  /// Semantic accent for the icon circle (danger/warning/info). Null keeps
  /// the quiet neutral treatment.
  final RestoflowTone? tone;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return RestoflowStateView(
      icon: icon,
      title: message,
      tone: tone,
      actions: actions,
    );
  }
}

/// The auth context is loading.
class AuthLoadingView extends StatelessWidget {
  const AuthLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: RestoflowSpacing.lg),
          Text(l10n.authLoadingAccount),
        ],
      ),
    );
  }
}

/// No authenticated session - a sign-in placeholder (Stage 3 has no live form).
class AuthSignInRequiredView extends StatelessWidget {
  const AuthSignInRequiredView({this.onContinue, super.key});

  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.lock_outline,
      message: l10n.authSignInRequired,
      actions: [
        FilledButton(onPressed: onContinue, child: Text(l10n.authContinue)),
      ],
    );
  }
}

/// Access denied (42501: unauthenticated/unlinked/inactive).
class AuthDeniedView extends StatelessWidget {
  const AuthDeniedView({this.onRetry, this.onSignOut, super.key});

  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.account_circle_outlined,
      message: l10n.authAccessDenied,
      tone: RestoflowTone.danger,
      actions: [
        if (onRetry != null)
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(l10n.authTryAgain),
          ),
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: Text(l10n.authSignOut)),
      ],
    );
  }
}

/// A generic backend/auth error (malformed response, etc.).
class AuthErrorView extends StatelessWidget {
  const AuthErrorView({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.error_outline,
      message: l10n.authError,
      tone: RestoflowTone.danger,
      actions: [
        if (onRetry != null)
          FilledButton(onPressed: onRetry, child: Text(l10n.authTryAgain)),
      ],
    );
  }
}

/// The user has no active membership for this app.
class AuthNoAccessView extends StatelessWidget {
  const AuthNoAccessView({this.onSignOut, super.key});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.do_not_disturb_alt,
      message: l10n.authNoAccess,
      tone: RestoflowTone.warning,
      actions: [
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: Text(l10n.authSignOut)),
      ],
    );
  }
}

/// The active role cannot use this app surface.
class AuthWrongRoleView extends StatelessWidget {
  const AuthWrongRoleView({this.onSignOut, super.key});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.block,
      message: l10n.authWrongRole,
      tone: RestoflowTone.warning,
      actions: [
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: Text(l10n.authSignOut)),
      ],
    );
  }
}

/// A deferred role for RF-108 (accountant, Q-017) - a "coming soon" state.
class AuthDeferredRoleView extends StatelessWidget {
  const AuthDeferredRoleView({this.onSignOut, super.key});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.schedule,
      message: l10n.authComingSoon,
      tone: RestoflowTone.info,
      actions: [
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: Text(l10n.authSignOut)),
      ],
    );
  }
}

/// Platform-admin entry/hint (separate from tenant roles, D-026).
class AuthPlatformAdminView extends StatelessWidget {
  const AuthPlatformAdminView({this.onSignOut, super.key});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthMessageView(
      icon: Icons.admin_panel_settings_outlined,
      message: l10n.authPlatformAdmin,
      tone: RestoflowTone.info,
      actions: [
        if (onSignOut != null)
          TextButton(onPressed: onSignOut, child: Text(l10n.authSignOut)),
      ],
    );
  }
}
