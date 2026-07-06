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

/// A page header: an optional icon badge, a title, an optional subtitle, and
/// trailing actions. Dashboard "1c": delegates to the full-bleed brand-gradient
/// [RestoflowGradientHeader] so every admin/dashboard page opens with the same
/// warm hero band. The trailing [actions] are re-themed to read on the gradient
/// (white primary buttons, white-foreground outlined/text/icon buttons) via a
/// scoped [Theme], so existing call sites keep passing their ordinary buttons.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Optional leading icon rendered in a soft rounded badge.
  final IconData? icon;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onGradient = theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: RestoflowGradientHeader.whiteActionStyle(context),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Colors.white),
      ),
    );
    return RestoflowGradientHeader(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: [
        for (final action in actions) Theme(data: onGradient, child: action),
      ],
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

/// A compact status pill. Prefer the tone-based constructor ([AdminPill.tone])
/// so statuses resolve to the TRUE semantic palette (success green / warning
/// amber / danger red); the colour-based constructor remains for identity
/// chips (roles, scopes) that are not statuses.
class AdminPill extends StatelessWidget {
  const AdminPill({
    required this.label,
    required Color this.color,
    this.icon,
    super.key,
  }) : tone = null;

  /// A pill filled with the tone's semantic container colours.
  const AdminPill.tone({
    required this.label,
    required RestoflowTone this.tone,
    this.icon,
    super.key,
  }) : color = null;

  final String label;
  final Color? color;
  final RestoflowTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = tone?.styleOf(theme);
    final background = style?.container ?? color!.withValues(alpha: 0.14);
    final foreground = style?.onContainer ?? color!;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: RestoflowIconSizes.xs, color: foreground),
            const SizedBox(width: RestoflowSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
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

/// The semantic tone + localized label for a device lifecycle status:
/// active = TRUE success green, code-issued/pending = warning amber,
/// paired = info (mid-provisioning), revoked/suspended/expired = danger red.
({String label, RestoflowTone tone, IconData icon}) deviceStatusVisual(
  BuildContext context,
  DeviceLifecycleStatus status,
) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    DeviceLifecycleStatus.none => (
      label: l10n.adminDevStatusNone,
      tone: RestoflowTone.neutral,
      icon: Icons.smartphone_outlined,
    ),
    DeviceLifecycleStatus.codeIssued => (
      label: l10n.adminDevStatusCodeIssued,
      tone: RestoflowTone.warning,
      icon: Icons.qr_code_2,
    ),
    DeviceLifecycleStatus.pending => (
      label: l10n.adminDevStatusPending,
      tone: RestoflowTone.warning,
      icon: Icons.hourglass_top,
    ),
    DeviceLifecycleStatus.paired => (
      label: l10n.adminDevStatusPaired,
      tone: RestoflowTone.info,
      icon: Icons.link,
    ),
    DeviceLifecycleStatus.active => (
      label: l10n.adminDevStatusActive,
      tone: RestoflowTone.success,
      icon: Icons.check_circle,
    ),
    DeviceLifecycleStatus.suspended => (
      label: l10n.adminDevStatusSuspended,
      tone: RestoflowTone.danger,
      icon: Icons.pause_circle_outline,
    ),
    DeviceLifecycleStatus.revoked => (
      label: l10n.adminDevStatusRevoked,
      tone: RestoflowTone.danger,
      icon: Icons.block,
    ),
    DeviceLifecycleStatus.codeExpired => (
      label: l10n.adminDevStatusCodeExpired,
      tone: RestoflowTone.danger,
      icon: Icons.timer_off_outlined,
    ),
    DeviceLifecycleStatus.rejected => (
      label: l10n.adminDevStatusRejected,
      tone: RestoflowTone.danger,
      icon: Icons.cancel_outlined,
    ),
  };
}

/// A centred state panel (loading / empty / error / permission-denied).
/// Delegates to the shared [RestoflowStateView] (deliberately not Card-based —
/// some empty-state tests assert `find.byType(Card)` findsNothing).
class AdminStateView extends StatelessWidget {
  const AdminStateView({
    required this.icon,
    required this.title,
    required this.body,
    this.tone,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Semantic accent for the icon circle (danger for failures, warning for
  /// permission-denied). Null keeps the quiet neutral empty-state look.
  final RestoflowTone? tone;

  final Widget? action;

  /// The loading variant (exactly ONE CircularProgressIndicator).
  static Widget loading() => const RestoflowStateView(showSpinner: true);

  @override
  Widget build(BuildContext context) {
    return RestoflowStateView(
      icon: icon,
      title: title,
      message: body,
      tone: tone,
      actions: [if (action case final action?) action],
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
        tone: RestoflowTone.warning,
      );
    }
    return AdminStateView(
      icon: Icons.error_outline,
      title: l10n.adminStateErrorTitle,
      body: l10n.adminStateErrorBody,
      tone: RestoflowTone.danger,
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
/// Rides the shared info-tone notice banner (demo = informational).
class AdminDemoBanner extends StatelessWidget {
  const AdminDemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return RestoflowNoticeBanner(
      icon: Icons.science_outlined,
      body: AppLocalizations.of(context).adminDemoBanner,
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
