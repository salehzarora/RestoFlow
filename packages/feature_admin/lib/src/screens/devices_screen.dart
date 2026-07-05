import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/admin_failure.dart';
import '../models/device_models.dart';
import '../models/role_rank.dart';
import '../state/admin_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/one_time_secret_dialog.dart';

/// The owner Devices surface (RF-113 / RF-112 §4.27–§4.29). Lists devices with a
/// lifecycle status chip and the single next provisioning action; issue + start-
/// session reveal a server one-time secret exactly once. approve = pending→paired,
/// activate = paired→active, start-session requires active; pending→active is
/// impossible (the lifecycle note + the per-status action make this explicit).
class AdminDevicesScreen extends ConsumerWidget {
  const AdminDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(adminDevicesProvider);
    final scope = ref.watch(adminScopeProvider);
    final manage = canManage(scope.actingRole);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.adminDevicesTitle,
          subtitle: l10n.adminDevicesSubtitle,
          icon: Icons.devices_outlined,
          actions: [
            FilledButton.icon(
              onPressed: manage
                  ? () => _showCreateDeviceDialog(context, ref)
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.adminCreateDevice),
            ),
          ],
        ),
        Expanded(
          child: devices.when(
            loading: AdminStateView.loading,
            error: (e, _) => AdminStateView.fromFailure(
              context,
              adminFailureOf(e),
              onRetry: () => ref.invalidate(adminDevicesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return AdminStateView(
                  icon: Icons.devices_other_outlined,
                  title: l10n.adminDevicesEmptyTitle,
                  body: l10n.adminDevicesEmptyBody,
                );
              }
              // LIVE-UX-001: keep the ACTIVE list clean — a revoked device is
              // terminal (is_active=false: it cannot pair or re-issue a code), so
              // it does not belong in the main list. Active/pending/paired stay
              // up top; revoked history moves to a collapsed, read-only section.
              final active = [
                for (final d in list)
                  if (d.status != DeviceLifecycleStatus.revoked) d,
              ];
              final revoked = [
                for (final d in list)
                  if (d.status == DeviceLifecycleStatus.revoked) d,
              ];
              return ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  RestoflowSpacing.lg,
                  0,
                  RestoflowSpacing.lg,
                  RestoflowSpacing.xxl,
                ),
                children: [
                  const _LifecycleNote(),
                  const SizedBox(height: RestoflowSpacing.sm),
                  _DeviceCounts(
                    activeCount: active.length,
                    revokedCount: revoked.length,
                  ),
                  const SizedBox(height: RestoflowSpacing.md),
                  for (final d in active)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: RestoflowSpacing.sm,
                      ),
                      child: _DeviceTile(device: d, canManage: manage),
                    ),
                  if (revoked.isNotEmpty) ...[
                    const SizedBox(height: RestoflowSpacing.sm),
                    _RevokedDevicesSection(devices: revoked),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LifecycleNote extends StatelessWidget {
  const _LifecycleNote();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.route_outlined,
            size: RestoflowIconSizes.sm,
            color: scheme.primary,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              l10n.adminLifecycleNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small, honest count line above the device list (LIVE-UX-001): how many
/// devices are live vs how many have been revoked (the revoked total only shows
/// when there are any).
class _DeviceCounts extends StatelessWidget {
  const _DeviceCounts({required this.activeCount, required this.revokedCount});

  final int activeCount;
  final int revokedCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      key: const Key('device-counts'),
      children: [
        Icon(
          Icons.devices_outlined,
          size: RestoflowIconSizes.xs,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Text(l10n.adminDevicesShownCount(activeCount), style: style),
        if (revokedCount > 0) ...[
          Text('  ·  ', style: style),
          Text(l10n.adminDevicesRevokedCount(revokedCount), style: style),
        ],
      ],
    );
  }
}

/// The collapsed, read-only "Revoked devices" history (LIVE-UX-001). Collapsed by
/// default so revoked devices never clutter the active list; expanding is the
/// "show revoked devices" affordance. Tiles are read-only (`canManage: false`):
/// a revoked device is terminal — it offers neither Revoke nor Issue code.
class _RevokedDevicesSection extends StatelessWidget {
  const _RevokedDevicesSection({required this.devices});

  final List<AdminDevice> devices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: const Key('revoked-devices-section'),
        leading: Icon(Icons.block, color: theme.colorScheme.onSurfaceVariant),
        title: Text(l10n.adminDevicesRevokedSection),
        subtitle: Text(l10n.adminDevicesRevokedCount(devices.length)),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.md,
          0,
          RestoflowSpacing.md,
          RestoflowSpacing.md,
        ),
        children: [
          for (final d in devices)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                bottom: RestoflowSpacing.sm,
              ),
              child: _DeviceTile(device: d, canManage: false),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerStatefulWidget {
  const _DeviceTile({required this.device, required this.canManage});
  final AdminDevice device;
  final bool canManage;
  @override
  ConsumerState<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends ConsumerState<_DeviceTile> {
  bool _busy = false;

  AdminController get _ctrl => ref.read(adminControllerProvider);

  void _onFailure(AdminFailure f) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(adminFailureMessage(l10n, f))));
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _issueCode() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await _ctrl.issueEnrollmentCode(widget.device.id);
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (issued) => OneTimeSecretDialog.show(
        context,
        title: l10n.adminCodeIssuedTitle,
        subtitle: l10n.adminCodeIssuedSubtitle,
        secret: issued.code,
        icon: Icons.qr_code_2,
        footnote: l10n.adminCodeExpiresNote,
      ),
      _onFailure,
    );
  }

  Future<void> _startSession() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await _ctrl.startDeviceSession(widget.device.id);
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold(
      (started) => OneTimeSecretDialog.show(
        context,
        title: l10n.adminTokenStartedTitle,
        subtitle: l10n.adminTokenStartedSubtitle,
        secret: started.token,
        icon: Icons.vpn_key_outlined,
      ),
      _onFailure,
    );
  }

  Future<void> _transition(
    Future<AdminResult<AdminDevice>> Function() op,
  ) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await op();
    if (!mounted) return;
    setState(() => _busy = false);
    r.fold((_) => _snack(l10n.adminDeviceUpdated), _onFailure);
  }

  Future<void> _revoke() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminRevoke),
        content: Text(l10n.adminRevokeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _transition(() => _ctrl.revokeDevice(widget.device.id));
  }

  /// Whether the device currently has a revocable pairing/session.
  bool get _revocable => switch (widget.device.status) {
    DeviceLifecycleStatus.codeIssued ||
    DeviceLifecycleStatus.pending ||
    DeviceLifecycleStatus.paired ||
    DeviceLifecycleStatus.active ||
    DeviceLifecycleStatus.suspended => true,
    _ => false,
  };

  /// The single next provisioning action for the current lifecycle status.
  ///
  /// With a REAL backend ([AdminController.supportsManualLifecycle] false) the
  /// device pairs ITSELF by redeeming the code on its own pairing screen
  /// (RF-161), so the manual redeem/approve/activate/start-session simulation is
  /// hidden — only issue-code (and revoke, rendered separately) remain.
  Widget? _action() {
    final l10n = AppLocalizations.of(context);
    if (!widget.canManage) return null;
    final manual = _ctrl.supportsManualLifecycle;
    final id = widget.device.id;
    ({String label, IconData icon, Future<void> Function() run})? spec =
        switch (widget.device.status) {
          // LIVE-UX-001: a REVOKED device is is_active=false, so
          // issue_device_enrollment_code fails closed with 42501 ("device not
          // found, inactive") which the client can only surface as a misleading
          // "you don't have permission" toast. So it is NOT offered here (a
          // revoked device is terminal). none/codeExpired/rejected are still
          // active devices where re-issuing a fresh code is valid.
          DeviceLifecycleStatus.none ||
          DeviceLifecycleStatus.codeExpired ||
          DeviceLifecycleStatus.rejected => (
            label: l10n.adminIssueCode,
            icon: Icons.qr_code_2,
            run: _issueCode,
          ),
          DeviceLifecycleStatus.codeIssued when manual => (
            label: l10n.adminRedeem,
            icon: Icons.smartphone,
            run: () => _transition(() => _ctrl.redeemEnrollmentCode(id)),
          ),
          DeviceLifecycleStatus.pending when manual => (
            label: l10n.adminApprove,
            icon: Icons.verified_user_outlined,
            run: () => _transition(() => _ctrl.approveDevice(id)),
          ),
          DeviceLifecycleStatus.paired when manual => (
            label: l10n.adminActivate,
            icon: Icons.power_settings_new,
            run: () => _transition(() => _ctrl.activateDevice(id)),
          ),
          DeviceLifecycleStatus.active when manual => (
            label: l10n.adminStartSession,
            icon: Icons.vpn_key_outlined,
            run: _startSession,
          ),
          _ => null,
        };
    if (spec == null) return null;
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : spec.run,
      icon: _busy
          ? const RestoflowInlineSpinner(size: 16)
          : Icon(spec.icon, size: RestoflowIconSizes.sm),
      label: Text(spec.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    final visual = deviceStatusVisual(context, widget.device.status);
    final isKds = widget.device.deviceType == 'kds';
    final warningStyle = RestoflowTone.warning.styleOf(theme);
    // POS vs KDS at a glance: distinct icon + a distinctly tinted badge.
    final typeIcon = isKds ? Icons.countertops_outlined : Icons.point_of_sale;
    final typeBackground = isKds
        ? semantic.infoContainer
        : semantic.accentContainer;
    final typeForeground = isKds
        ? semantic.onInfoContainer
        : semantic.onAccentContainer;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: typeBackground,
                    borderRadius: BorderRadius.circular(RestoflowRadii.md),
                  ),
                  child: Icon(
                    typeIcon,
                    size: RestoflowIconSizes.lg,
                    color: typeForeground,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.label,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: RestoflowSpacing.xxs),
                      Wrap(
                        spacing: RestoflowSpacing.sm,
                        runSpacing: RestoflowSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AdminPill(
                            label: isKds
                                ? l10n.adminDeviceTypeKds
                                : l10n.adminDeviceTypePos,
                            color: typeForeground,
                            icon: typeIcon,
                          ),
                          Text(
                            widget.device.branchLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                AdminPill.tone(
                  label: visual.label,
                  tone: visual.tone,
                  icon: visual.icon,
                ),
              ],
            ),
            if (widget.device.hasOpenSession) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.bolt,
                    size: RestoflowIconSizes.xs,
                    color: semantic.success,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Text(
                    l10n.adminSessionOpen,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: semantic.success,
                    ),
                  ),
                ],
              ),
            ],
            // Real backend: the device redeems its code itself (RF-161) — say so
            // instead of showing a manual redeem button.
            if (!_ctrl.supportsManualLifecycle &&
                widget.device.status == DeviceLifecycleStatus.codeIssued) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.smartphone,
                    size: RestoflowIconSizes.xs,
                    color: warningStyle.accent,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.adminPairOnDevice,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: warningStyle.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.canManage && (_revocable || _action() != null)) ...[
              const SizedBox(height: RestoflowSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_revocable)
                    TextButton.icon(
                      style: RestoflowButtonStyles.dangerGhost(context),
                      onPressed: _busy ? null : _revoke,
                      icon: const Icon(
                        Icons.block,
                        size: RestoflowIconSizes.sm,
                      ),
                      label: Text(l10n.adminRevoke),
                    ),
                  if (_action() case final action?) ...[
                    const SizedBox(width: RestoflowSpacing.sm),
                    action,
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create-device dialog.
// ---------------------------------------------------------------------------
Future<void> _showCreateDeviceDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CreateDeviceDialog(ref: ref),
    );

class _CreateDeviceDialog extends StatefulWidget {
  const _CreateDeviceDialog({required this.ref});
  final WidgetRef ref;
  @override
  State<_CreateDeviceDialog> createState() => _CreateDeviceDialogState();
}

class _CreateDeviceDialogState extends State<_CreateDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  String _type = 'pos';
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final r = await widget.ref
        .read(adminControllerProvider)
        .createDevice(label: _label.text, deviceType: _type);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    r.fold(
      (_) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.adminDeviceCreated)),
        );
      },
      (f) => messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, f))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminCreateDeviceTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _label,
              decoration: InputDecoration(
                labelText: l10n.adminFieldDeviceLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: l10n.adminFieldDeviceType,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: 'pos',
                  child: Text(l10n.adminDeviceTypePos),
                ),
                DropdownMenuItem(
                  value: 'kds',
                  child: Text(l10n.adminDeviceTypeKds),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminCreate),
        ),
      ],
    );
  }
}
