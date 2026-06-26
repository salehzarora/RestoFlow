import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/admin_failure.dart';
import '../models/device_models.dart';

/// The localized label for a tenant role (reuses the RF-108 auth role strings).
String adminRoleLabel(AppLocalizations l10n, MembershipRole role) =>
    switch (role) {
      MembershipRole.orgOwner => l10n.authRoleOwner,
      MembershipRole.restaurantOwner => l10n.authRoleRestaurantOwner,
      MembershipRole.manager => l10n.authRoleManager,
      MembershipRole.cashier => l10n.authRoleCashier,
      MembershipRole.kitchenStaff => l10n.authRoleKitchenStaff,
      MembershipRole.accountant => l10n.authRoleAccountant,
    };

/// A page header: a title, an optional subtitle, and trailing actions.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.lg,
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: RestoflowSpacing.xs / 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A titled, elevated section card (the building block of every admin screen).
class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    super.key,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: RestoflowSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// A compact status pill with a tonal colour.
class AdminPill extends StatelessWidget {
  const AdminPill({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs / 1.5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A role chip (tonal, role-coloured).
class AdminRoleChip extends StatelessWidget {
  const AdminRoleChip({required this.role, super.key});
  final MembershipRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (role) {
      MembershipRole.orgOwner => scheme.primary,
      MembershipRole.restaurantOwner => scheme.tertiary,
      MembershipRole.manager => scheme.secondary,
      _ => scheme.onSurfaceVariant,
    };
    return AdminPill(
      label: adminRoleLabel(AppLocalizations.of(context), role),
      color: color,
      icon: Icons.shield_outlined,
    );
  }
}

/// The colour + localized label for a device lifecycle status.
({String label, Color color, IconData icon}) deviceStatusVisual(
  BuildContext context,
  DeviceLifecycleStatus status,
) {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    DeviceLifecycleStatus.none => (
      label: l10n.adminDevStatusNone,
      color: scheme.onSurfaceVariant,
      icon: Icons.smartphone_outlined,
    ),
    DeviceLifecycleStatus.codeIssued => (
      label: l10n.adminDevStatusCodeIssued,
      color: scheme.tertiary,
      icon: Icons.qr_code_2,
    ),
    DeviceLifecycleStatus.pending => (
      label: l10n.adminDevStatusPending,
      color: scheme.secondary,
      icon: Icons.hourglass_top,
    ),
    DeviceLifecycleStatus.paired => (
      label: l10n.adminDevStatusPaired,
      color: scheme.tertiary,
      icon: Icons.link,
    ),
    DeviceLifecycleStatus.active => (
      label: l10n.adminDevStatusActive,
      color: scheme.primary,
      icon: Icons.check_circle,
    ),
    DeviceLifecycleStatus.suspended => (
      label: l10n.adminDevStatusSuspended,
      color: scheme.error,
      icon: Icons.pause_circle_outline,
    ),
    DeviceLifecycleStatus.revoked => (
      label: l10n.adminDevStatusRevoked,
      color: scheme.error,
      icon: Icons.block,
    ),
    DeviceLifecycleStatus.codeExpired => (
      label: l10n.adminDevStatusCodeExpired,
      color: scheme.error,
      icon: Icons.timer_off_outlined,
    ),
    DeviceLifecycleStatus.rejected => (
      label: l10n.adminDevStatusRejected,
      color: scheme.error,
      icon: Icons.cancel_outlined,
    ),
  };
}

/// A centred state panel (loading / empty / error / permission-denied).
class AdminStateView extends StatelessWidget {
  const AdminStateView({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  /// The loading variant.
  static Widget loading() => const Center(
    child: Padding(
      padding: EdgeInsets.all(RestoflowSpacing.xl),
      child: CircularProgressIndicator(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: RestoflowSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: RestoflowSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }

  /// Maps an [AdminFailure] to a permission-denied / error panel.
  factory AdminStateView.fromFailure(
    BuildContext context,
    AdminFailure failure, {
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    if (failure is AdminPermissionDenied) {
      return AdminStateView(
        icon: Icons.lock_outline,
        title: l10n.adminPermissionDeniedTitle,
        body: l10n.adminPermissionDeniedBody,
      );
    }
    return AdminStateView(
      icon: Icons.error_outline,
      title: l10n.adminStateErrorTitle,
      body: l10n.adminStateErrorBody,
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.adminRetry),
            ),
    );
  }
}

/// The "demo data / backend-ready" banner shown atop every admin surface.
class AdminDemoBanner extends StatelessWidget {
  const AdminDemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: BorderDirectional(
          start: BorderSide(color: scheme.tertiary, width: 4),
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.science_outlined,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.of(context).adminDemoBanner,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps an [AdminFailure] to a short, localized snackbar message.
String adminFailureMessage(AppLocalizations l10n, AdminFailure failure) =>
    switch (failure) {
      AdminPermissionDenied() => l10n.adminPermissionDeniedTitle,
      AdminValidation(:final message) => _validationMessage(l10n, message),
      AdminConflict() => l10n.adminConflictMessage,
      AdminNotFound() => l10n.adminStateErrorTitle,
      AdminTransient() => l10n.adminActionProblem,
    };

String _validationMessage(AppLocalizations l10n, String key) => switch (key) {
  'currency' => l10n.adminErrCurrency,
  'country' => l10n.adminErrCountry,
  'name' => l10n.adminErrName,
  'email' => l10n.adminErrEmail,
  'status' => l10n.adminErrStatus,
  _ => l10n.adminErrRequired,
};
