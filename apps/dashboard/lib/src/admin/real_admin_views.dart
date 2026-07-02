import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPageHeader, AdminSectionCard, AdminStateView, adminRoleLabel;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Honest REAL-mode replacements for the demo-backed Users/Settings tabs
/// (sprint). The demo store must never render fabricated people or values as
/// if they were the signed-in tenant's data — real mode shows what actually
/// exists (the resolved workspace) and says plainly what is not connected yet.

/// Users tab, real mode: there is NO member read API yet (grant/update-role
/// write RPCs exist, but nothing a JWT can list members with), so instead of
/// sample people this states exactly that.
class RealUsersUnavailableView extends StatelessWidget {
  const RealUsersUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            0,
          ),
          child: AdminPageHeader(
            title: l10n.adminUsersTitle,
            subtitle: l10n.adminUsersSubtitle,
          ),
        ),
        Expanded(
          child: AdminStateView(
            icon: Icons.group_off_outlined,
            title: l10n.dashboardUsersNotConnectedTitle,
            body: l10n.dashboardUsersNotConnectedBody,
          ),
        ),
      ],
    );
  }
}

/// Settings tab, real mode: the REAL workspace values the dashboard actually
/// knows (resolved org/restaurant/branch + currency + role), read-only, with
/// an honest "saving is not connected" notice. No Save button exists — there
/// is no settings READ API to round-trip against yet, so a form would lie.
class RealSettingsView extends StatelessWidget {
  const RealSettingsView({
    required this.membership,
    this.currencyCode,
    super.key,
  });

  final MembershipContext membership;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        AdminPageHeader(
          title: l10n.adminSettingsTitle,
          subtitle: l10n.adminSettingsSubtitle,
        ),
        const SizedBox(height: RestoflowSpacing.md),
        RestoflowNoticeBanner(
          tone: RestoflowTone.info,
          icon: Icons.lock_outline,
          body: l10n.dashboardSettingsRealNotice,
        ),
        const SizedBox(height: RestoflowSpacing.md),
        AdminSectionCard(
          title: l10n.dashboardSettingsWorkspace,
          icon: Icons.storefront_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ValueRow(
                label: l10n.authOrganization,
                value: membership.organizationName,
              ),
              _ValueRow(
                label: l10n.authRestaurant,
                value: membership.restaurantName,
              ),
              _ValueRow(label: l10n.authBranch, value: membership.branchName),
              _ValueRow(label: l10n.menuCurrencyLabel, value: currencyCode),
              _ValueRow(
                label: l10n.authRole,
                value: adminRoleLabel(l10n, membership.role),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An unresolved value renders as an em dash — never a fabricated default.
    final display = (value == null || value!.isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              display,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
