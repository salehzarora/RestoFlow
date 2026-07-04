import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPageHeader, AdminSectionCard, AdminStateView, adminRoleLabel;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'branch_shift_close_policy_repository.dart';

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
        AdminPageHeader(
          title: l10n.adminUsersTitle,
          subtitle: l10n.adminUsersSubtitle,
          icon: Icons.group_outlined,
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
class RealSettingsView extends StatefulWidget {
  const RealSettingsView({
    required this.membership,
    this.currencyCode,
    this.policyRepository,
    super.key,
  });

  final MembershipContext membership;
  final String? currencyCode;

  /// RF-113: the per-branch shift-close policy read/write seam. Null when there
  /// is no authenticated transport or no concrete branch in scope — the toggle
  /// section is then omitted (never a fake control).
  final BranchShiftClosePolicyRepository? policyRepository;

  @override
  State<RealSettingsView> createState() => _RealSettingsViewState();
}

class _RealSettingsViewState extends State<RealSettingsView> {
  /// The current policy value; null while loading or after a read failure.
  bool? _shiftCloseEnabled;
  bool _loadingPolicy = false;
  bool _policyReadFailed = false;
  bool _savingPolicy = false;

  /// Only a full owner (org/restaurant) may change branch settings — this
  /// mirrors the server gate (`set_branch_pos_shift_close_enabled` requires
  /// rank >= restaurant_owner). Managers/cashiers see the current value
  /// read-only.
  bool get _canEdit =>
      widget.membership.role == MembershipRole.orgOwner ||
      widget.membership.role == MembershipRole.restaurantOwner;

  @override
  void initState() {
    super.initState();
    final repo = widget.policyRepository;
    if (repo != null) {
      _loadingPolicy = true;
      _loadPolicy(repo);
    }
  }

  Future<void> _loadPolicy(BranchShiftClosePolicyRepository repo) async {
    final value = await repo.read();
    if (!mounted) return;
    setState(() {
      _shiftCloseEnabled = value;
      _policyReadFailed = value == null;
      _loadingPolicy = false;
    });
  }

  Future<void> _onToggle(bool next) async {
    final repo = widget.policyRepository;
    if (repo == null || _savingPolicy) return;
    final previous = _shiftCloseEnabled;
    setState(() {
      _shiftCloseEnabled = next;
      _savingPolicy = true;
    });
    final result = await repo.setEnabled(next);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _savingPolicy = false;
      if (result != BranchPolicyWrite.ok) _shiftCloseEnabled = previous;
    });
    final message = switch (result) {
      BranchPolicyWrite.ok => l10n.dashboardShiftCloseSaved,
      BranchPolicyWrite.denied => l10n.dashboardShiftCloseDenied,
      BranchPolicyWrite.unavailable => l10n.dashboardShiftCloseSaveFailed,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final membership = widget.membership;
    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        AdminPageHeader(
          title: l10n.adminSettingsTitle,
          subtitle: l10n.adminSettingsSubtitle,
          icon: Icons.tune_outlined,
        ),
        const SizedBox(height: RestoflowSpacing.md),
        // The blanket "nothing to save" notice is honest ONLY when there is no
        // editable control — with the RF-113 toggle present, the workspace
        // fields below are self-evidently read-only.
        if (widget.policyRepository == null) ...[
          RestoflowNoticeBanner(
            tone: RestoflowTone.info,
            icon: Icons.lock_outline,
            body: l10n.dashboardSettingsRealNotice,
          ),
          const SizedBox(height: RestoflowSpacing.md),
        ],
        AdminSectionCard(
          title: l10n.dashboardSettingsWorkspace,
          icon: Icons.storefront_outlined,
          // A responsive field grid (stacked label-over-value tiles that wrap)
          // instead of the old rigid fixed-width label column.
          child: Wrap(
            spacing: RestoflowSpacing.xl,
            runSpacing: RestoflowSpacing.md,
            children: [
              _ValueField(
                label: l10n.authOrganization,
                value: membership.organizationName,
              ),
              _ValueField(
                label: l10n.authRestaurant,
                value: membership.restaurantName,
              ),
              _ValueField(label: l10n.authBranch, value: membership.branchName),
              _ValueField(
                label: l10n.menuCurrencyLabel,
                value: widget.currencyCode,
              ),
              _ValueField(
                label: l10n.authRole,
                value: adminRoleLabel(l10n, membership.role),
              ),
            ],
          ),
        ),
        if (widget.policyRepository != null) ...[
          const SizedBox(height: RestoflowSpacing.md),
          AdminSectionCard(
            title: l10n.dashboardShiftCloseSectionTitle,
            icon: Icons.point_of_sale_outlined,
            child: _shiftClosePolicy(context, l10n),
          ),
        ],
      ],
    );
  }

  Widget _shiftClosePolicy(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_loadingPolicy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_policyReadFailed || _shiftCloseEnabled == null) {
      return RestoflowNoticeBanner(
        tone: RestoflowTone.warning,
        icon: Icons.cloud_off_outlined,
        body: l10n.dashboardShiftCloseUnavailable,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('shift-close-policy-toggle'),
          contentPadding: EdgeInsets.zero,
          value: _shiftCloseEnabled!,
          // Owner-only + not mid-save. A non-owner sees the real value, locked.
          onChanged: (_canEdit && !_savingPolicy) ? _onToggle : null,
          title: Text(l10n.dashboardShiftCloseToggleLabel),
          subtitle: Text(l10n.dashboardShiftCloseToggleHelp),
        ),
        if (!_canEdit)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: Text(
              l10n.dashboardShiftCloseOwnerOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One read-only workspace field: a muted label stacked over its value.
class _ValueField extends StatelessWidget {
  const _ValueField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An unresolved value renders as an em dash — never a fabricated default.
    final display = (value == null || value!.isEmpty) ? '—' : value!;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            display,
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
