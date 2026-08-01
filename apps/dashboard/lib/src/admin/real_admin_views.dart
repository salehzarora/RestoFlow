import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminPageHeader, AdminSectionCard, AdminStateView, adminRoleLabel;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../branding/restaurant_logo_repository.dart';
import '../branding/restaurant_logo_section.dart';
import '../branding/restaurant_logo_storage.dart';
import 'branch_kitchen_workflow_repository.dart';
import 'branch_shift_close_policy_repository.dart';
import 'supabase_settings_repository.dart';
import 'timezone_catalog.dart';
import 'timezone_picker.dart';

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
    this.settingsRepository,
    this.brandingRepository,
    this.brandingStorage,
    this.kitchenWorkflowRepository,
    super.key,
  });

  final MembershipContext membership;
  final String? currencyCode;

  /// PRINT-BRANDING-LOGO-001: the receipt-branding read/write seam + blob store.
  /// Null when there is no authenticated transport or no concrete restaurant in
  /// scope — the branding section then shows an honest "unavailable" note.
  final RestaurantLogoRepository? brandingRepository;
  final RestaurantLogoStorage? brandingStorage;

  /// RF-113: the per-branch shift-close policy read/write seam. Null when there
  /// is no authenticated transport or no concrete branch in scope — the toggle
  /// section is then omitted (never a fake control).
  final BranchShiftClosePolicyRepository? policyRepository;

  /// DASHBOARD-PRINTER-ONLY-MODE-TOGGLE-010: the per-branch kitchen-workflow
  /// read/write seam. Null when there is no authenticated transport or no
  /// concrete branch in scope — the section is then omitted entirely rather than
  /// rendered as a control that cannot work.
  final BranchKitchenWorkflowRepository? kitchenWorkflowRepository;

  /// RF-116: the settings read/write seam for the owner-only editable branch/
  /// restaurant fields. Null when there is no authenticated transport or no
  /// concrete branch in scope — the editable section is then omitted (the honest
  /// read-only workspace view remains). The server enforces the owner gate.
  final SettingsRepository? settingsRepository;

  @override
  State<RealSettingsView> createState() => _RealSettingsViewState();
}

class _RealSettingsViewState extends State<RealSettingsView> {
  /// The current policy value; null while loading or after a read failure.
  bool? _shiftCloseEnabled;
  bool _loadingPolicy = false;
  bool _policyReadFailed = false;
  bool _savingPolicy = false;

  /// 010: the branch's CURRENT stored kitchen workflow, read authoritatively
  /// from the server. Null while loading or after a read failure — NEVER
  /// defaulted, because guessing would misdescribe the branch.
  KitchenWorkflowMode? _workflowMode;
  bool _loadingWorkflow = false;
  bool _workflowReadFailed = false;
  bool _savingWorkflow = false;

  /// RF-116: the editable branch/restaurant fields (owner-only).
  final _branchName = TextEditingController();
  final _receiptPrefix = TextEditingController();
  final _restaurantName = TextEditingController();
  SettingsPrefill? _prefill;
  bool _savingBranch = false;
  bool _savingRestaurant = false;

  /// TIMEZONE-GLOBAL-001: the branch timezone to APPLY on the next save, or null
  /// to leave it unchanged. The picker now SHOWS the current zone (from prefill)
  /// so an unset/UTC pilot branch is visible; the owner explicitly picks the
  /// correct IANA zone (e.g. Asia/Jerusalem) to fix branch-local timestamps.
  String? _branchTimezone;

  /// The global IANA catalog for the picker (loaded from `list_timezones`).
  List<TimezoneOption> _timezones = const [];

  /// Only a full owner (org/restaurant) may change branch settings — this
  /// mirrors the server gate (`set_branch_pos_shift_close_enabled` requires
  /// rank >= restaurant_owner). Managers/cashiers see the current value
  /// read-only.
  bool get _canEdit =>
      widget.membership.role == MembershipRole.orgOwner ||
      widget.membership.role == MembershipRole.restaurantOwner;

  /// The owner-only editable section is shown only with a settings seam AND a
  /// concrete branch in scope — exactly like the RF-113 toggle. Otherwise the
  /// honest read-only workspace view remains (never a fake form).
  bool get _showEditable =>
      widget.settingsRepository != null &&
      _canEdit &&
      widget.membership.branchId != null;

  /// A concrete restaurant is in scope, so its name is editable too.
  bool get _hasRestaurant => widget.membership.restaurantId != null;

  @override
  void initState() {
    super.initState();
    final repo = widget.policyRepository;
    if (repo != null) {
      _loadingPolicy = true;
      _loadPolicy(repo);
    }
    final workflow = widget.kitchenWorkflowRepository;
    if (workflow != null) {
      _loadingWorkflow = true;
      _loadWorkflow(workflow);
    }
    // Seed the editable fields with the resolved membership names, then refine
    // them from list_org_structure (the source of truth for the current name).
    _branchName.text = widget.membership.branchName ?? '';
    _restaurantName.text = widget.membership.restaurantName ?? '';
    final settings = widget.settingsRepository;
    if (_showEditable && settings != null) {
      _loadPrefill(settings);
      _loadTimezones(settings);
    }
  }

  @override
  void dispose() {
    _branchName.dispose();
    _receiptPrefix.dispose();
    _restaurantName.dispose();
    super.dispose();
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

  Future<void> _loadWorkflow(BranchKitchenWorkflowRepository repo) async {
    final value = await repo.read();
    if (!mounted) return;
    setState(() {
      _workflowMode = value;
      _workflowReadFailed = value == null;
      _loadingWorkflow = false;
    });
  }

  /// 010: the owner picked the OTHER workflow. Confirm first (naming the branch,
  /// the old mode and the new one), then write through the guarded RPC.
  ///
  /// Deliberately NOT optimistic: the displayed value is only ever the server's
  /// answer. A denial, a refusal or a transport failure leaves the previously
  /// stored mode on screen, so the control can never imply a change that did not
  /// happen. Re-entrancy is blocked by [_savingWorkflow], so a double press
  /// cannot produce a second write.
  Future<void> _onWorkflowSelected(KitchenWorkflowMode next) async {
    final repo = widget.kitchenWorkflowRepository;
    final current = _workflowMode;
    if (repo == null || _savingWorkflow || !_canEdit) return;
    if (current == null || current == next) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dashboardKitchenWorkflowConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardKitchenWorkflowConfirmBranch(
                widget.membership.branchName ?? '',
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              l10n.dashboardKitchenWorkflowConfirmChange(
                _workflowLabel(l10n, current),
                _workflowLabel(l10n, next),
              ),
            ),
            if (next == KitchenWorkflowMode.printerOnly) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              RestoflowNoticeBanner(
                tone: RestoflowTone.warning,
                icon: Icons.print_outlined,
                body: l10n.dashboardKitchenWorkflowPrinterWarning,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const Key('kitchen-workflow-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dashboardKitchenWorkflowConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingWorkflow = true);
    final result = await repo.setMode(next);
    if (!mounted) return;
    setState(() {
      _savingWorkflow = false;
      // Adopt the SERVER's stored value, never the requested one.
      if (result.status == KitchenWorkflowWrite.ok && result.mode != null) {
        _workflowMode = result.mode;
      }
    });
    final message = switch (result.status) {
      KitchenWorkflowWrite.ok => l10n.dashboardKitchenWorkflowSaved,
      KitchenWorkflowWrite.denied => l10n.dashboardKitchenWorkflowDenied,
      KitchenWorkflowWrite.notFound => l10n.dashboardKitchenWorkflowNotFound,
      KitchenWorkflowWrite.invalidMode || KitchenWorkflowWrite.unavailable =>
        l10n.dashboardKitchenWorkflowSaveFailed,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    // Re-read authoritatively so the screen matches the branch, not the reply.
    if (result.status == KitchenWorkflowWrite.ok) await _loadWorkflow(repo);
  }

  String _workflowLabel(AppLocalizations l10n, KitchenWorkflowMode mode) =>
      switch (mode) {
        KitchenWorkflowMode.kds => l10n.dashboardKitchenWorkflowKdsLabel,
        KitchenWorkflowMode.printerOnly =>
          l10n.dashboardKitchenWorkflowPrinterLabel,
      };

  Future<void> _loadPrefill(SettingsRepository repo) async {
    final prefill = await repo.readPrefill();
    if (!mounted || prefill == null) return;
    setState(() {
      _prefill = prefill;
      // Overwrite the seeded fallback with the readable current value.
      if (prefill.branchName != null) _branchName.text = prefill.branchName!;
      if (prefill.restaurantName != null) {
        _restaurantName.text = prefill.restaurantName!;
      }
    });
  }

  Future<void> _loadTimezones(SettingsRepository repo) async {
    final zones = await repo.loadTimezones();
    if (!mounted || zones.isEmpty) return;
    setState(() => _timezones = zones);
  }

  String _writeMessage(
    AppLocalizations l10n,
    SettingsWrite result,
  ) => switch (result) {
    // Reuses the RF-113 save-result strings (applied / role-denied / failed).
    SettingsWrite.ok => l10n.dashboardShiftCloseSaved,
    SettingsWrite.denied => l10n.dashboardShiftCloseDenied,
    SettingsWrite.unavailable => l10n.dashboardShiftCloseSaveFailed,
  };

  Future<void> _saveBranch() async {
    final repo = widget.settingsRepository;
    if (repo == null || _savingBranch) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _branchName.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.adminErrName)));
      return;
    }
    setState(() => _savingBranch = true);
    final prefix = _receiptPrefix.text.trim();
    final result = await repo.saveBranch(
      name: name,
      // A blank receipt prefix leaves the current value unchanged (null param).
      receiptPrefix: prefix.isEmpty ? null : prefix,
      status: _prefill?.branchStatus ?? 'active',
      // Null leaves the timezone unchanged; a picked zone corrects reporting's
      // branch-local bucketing (RF-REPORT-004).
      timezone: _branchTimezone,
    );
    if (!mounted) return;
    setState(() => _savingBranch = false);
    messenger.showSnackBar(
      SnackBar(content: Text(_writeMessage(l10n, result))),
    );
  }

  Future<void> _saveRestaurant() async {
    final repo = widget.settingsRepository;
    if (repo == null || _savingRestaurant) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _restaurantName.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.adminErrName)));
      return;
    }
    setState(() => _savingRestaurant = true);
    final result = await repo.saveRestaurant(
      name: name,
      status: _prefill?.restaurantStatus ?? 'active',
    );
    if (!mounted) return;
    setState(() => _savingRestaurant = false);
    messenger.showSnackBar(
      SnackBar(content: Text(_writeMessage(l10n, result))),
    );
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
        // editable control — with the RF-113 toggle or the RF-116 editable
        // section present, the workspace fields below are self-evidently
        // read-only.
        if (widget.policyRepository == null && !_showEditable) ...[
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
        if (_showEditable) ...[
          const SizedBox(height: RestoflowSpacing.md),
          AdminSectionCard(
            title: l10n.dashboardSettingsEditableTitle,
            icon: Icons.edit_outlined,
            child: _editableFields(context, l10n),
          ),
        ],
        // PRINT-BRANDING-LOGO-001: the receipt-branding card, shown whenever a
        // concrete restaurant is in scope. Editability is derived from the
        // BACKEND capability (get_restaurant_receipt_logo.can_manage) inside the
        // section — a covering non-manager sees a read-only preview — never the
        // literal role name. An unbuilt repo/storage renders an honest note.
        if (_hasRestaurant && membership.restaurantId != null) ...[
          const SizedBox(height: RestoflowSpacing.md),
          RestaurantLogoSection(
            repository: widget.brandingRepository,
            storage: widget.brandingStorage,
            organizationId: membership.organizationId,
            restaurantId: membership.restaurantId!,
          ),
        ],
        if (widget.kitchenWorkflowRepository != null) ...[
          const SizedBox(height: RestoflowSpacing.md),
          AdminSectionCard(
            title: l10n.dashboardKitchenWorkflowSectionTitle,
            icon: Icons.soup_kitchen_outlined,
            child: _kitchenWorkflow(context, l10n),
          ),
        ],
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

  /// The owner-only editable fields (RF-116): branch display name + receipt
  /// prefix (one Save), and — when a concrete restaurant is in scope — the
  /// restaurant name (its own Save). Currency stays locked (ILS-only pilot).
  /// Every Save calls the real backend RPC and reflects the true result.
  Widget _editableFields(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Currency is fixed to ILS — a read-only note, NEVER an editable selector.
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: RestoflowIconSizes.sm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: RestoflowSpacing.xs),
            Expanded(
              child: Text(
                l10n.dashboardSettingsCurrencyLocked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.md),
        TextField(
          key: const Key('settings-branch-name'),
          controller: _branchName,
          decoration: InputDecoration(
            labelText: l10n.dashboardSettingsBranchNameLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        TextField(
          key: const Key('settings-receipt-prefix'),
          controller: _receiptPrefix,
          decoration: InputDecoration(
            labelText: l10n.adminFieldReceiptPrefix,
            helperText: l10n.dashboardSettingsReceiptPrefixHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        // TIMEZONE-GLOBAL-001: searchable GLOBAL IANA timezone picker. Shows the
        // branch's CURRENT zone (so an unset/UTC pilot branch is visible), lets
        // the owner search the full catalog by country/city/IANA id, and stores
        // the canonical IANA id. Null pick = leave unchanged. Correcting it fixes
        // branch-local timestamps (Activity log + reporting).
        TimezonePickerField(
          l10n: l10n,
          options: _timezones,
          currentTimezone: _prefill?.branchTimezone,
          selected: _branchTimezone,
          onChanged: (value) => setState(() => _branchTimezone = value),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('settings-save-branch'),
            onPressed: _savingBranch ? null : _saveBranch,
            child: _savingBranch
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.adminSave),
          ),
        ),
        if (_hasRestaurant) ...[
          const Divider(height: RestoflowSpacing.xl),
          TextField(
            key: const Key('settings-restaurant-name'),
            controller: _restaurantName,
            decoration: InputDecoration(
              labelText: l10n.dashboardSettingsRestaurantNameLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('settings-save-restaurant'),
              onPressed: _savingRestaurant ? null : _saveRestaurant,
              child: _savingRestaurant
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.adminSave),
            ),
          ),
        ],
      ],
    );
  }

  /// 010: the branch's kitchen workflow. Two mutually exclusive options, the
  /// current one selected from the SERVER's answer. Owner-only: every other role
  /// sees the real value, locked, and cannot reach the RPC from here (the server
  /// re-checks regardless).
  Widget _kitchenWorkflow(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_loadingWorkflow) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_workflowReadFailed || _workflowMode == null) {
      return RestoflowNoticeBanner(
        key: const Key('kitchen-workflow-unavailable'),
        tone: RestoflowTone.warning,
        icon: Icons.cloud_off_outlined,
        body: l10n.dashboardKitchenWorkflowUnavailable,
      );
    }
    final editable = _canEdit && !_savingWorkflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The handler itself refuses a non-owner and a mid-save press, so the
        // RPC is unreachable from here regardless of the widget state; the
        // tiles are ALSO disabled so a non-owner sees the real value, locked.
        RadioGroup<KitchenWorkflowMode>(
          groupValue: _workflowMode,
          onChanged: (v) {
            if (v != null) _onWorkflowSelected(v);
          },
          child: Column(
            children: [
              _WorkflowOption(
                optionKey: const Key('kitchen-workflow-kds'),
                mode: KitchenWorkflowMode.kds,
                enabled: editable,
              ),
              _WorkflowOption(
                optionKey: const Key('kitchen-workflow-printer-only'),
                mode: KitchenWorkflowMode.printerOnly,
                enabled: editable,
              ),
            ],
          ),
        ),
        if (!_canEdit)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: Text(
              l10n.dashboardKitchenWorkflowOwnerOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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

/// 010: one kitchen-workflow choice. Split out so the tiles sit under a
/// [RadioGroup] ancestor (the non-deprecated selection API) while keeping their
/// stable keys and localized copy.
class _WorkflowOption extends StatelessWidget {
  const _WorkflowOption({
    required this.optionKey,
    required this.mode,
    required this.enabled,
  });

  final Key optionKey;
  final KitchenWorkflowMode mode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, help) = switch (mode) {
      KitchenWorkflowMode.kds => (
        l10n.dashboardKitchenWorkflowKdsLabel,
        l10n.dashboardKitchenWorkflowKdsHelp,
      ),
      KitchenWorkflowMode.printerOnly => (
        l10n.dashboardKitchenWorkflowPrinterLabel,
        l10n.dashboardKitchenWorkflowPrinterHelp,
      ),
    };
    return RadioListTile<KitchenWorkflowMode>(
      key: optionKey,
      contentPadding: EdgeInsets.zero,
      value: mode,
      enabled: enabled,
      title: Text(title),
      subtitle: Text(help),
    );
  }
}
