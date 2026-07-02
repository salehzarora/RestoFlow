import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminPageHeader,
        AdminPill,
        AdminResult,
        AdminStateView,
        adminFailureMessage,
        adminRoleLabel;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'staff_models.dart';
import 'staff_repository.dart';

/// The dashboard Staff surface: create PIN-operated staff (cashier / kitchen
/// staff / manager) and set/reset their POS/KDS sign-in PIN.
///
/// SECURITY: the PIN is typed here once, sent over the authenticated TLS
/// transport, and bcrypt-hashed server-side. It is never displayed back,
/// never stored client-side, and the list shows only a has-PIN flag.
class StaffScreen extends StatefulWidget {
  const StaffScreen({required this.repository, super.key});

  final StaffRepository repository;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late Future<AdminResult<List<StaffMember>>> _future = widget.repository
      .load();

  void _reload() {
    // Braces, not an arrow: the setState callback must not RETURN the future.
    setState(() {
      _future = widget.repository.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.staffTitle,
          subtitle: l10n.staffSubtitle,
          icon: Icons.badge_outlined,
          actions: [
            FilledButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(
                Icons.person_add_alt,
                size: RestoflowIconSizes.sm,
              ),
              label: Text(l10n.staffAdd),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<AdminResult<List<StaffMember>>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) return AdminStateView.loading();
              return snap.data!.fold(
                (staff) => _list(context, staff),
                (failure) => AdminStateView.fromFailure(
                  context,
                  failure,
                  onRetry: _reload,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, List<StaffMember> staff) {
    final l10n = AppLocalizations.of(context);
    if (staff.isEmpty) {
      return AdminStateView(
        icon: Icons.badge_outlined,
        title: l10n.staffEmptyTitle,
        body: l10n.staffEmptyBody,
      );
    }
    final missingPins = staff.where((s) => s.isActive && !s.hasPin).isNotEmpty;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        if (missingPins) ...[
          RestoflowNoticeBanner(
            tone: RestoflowTone.warning,
            icon: Icons.pin_outlined,
            body: l10n.staffNoPinWarning,
          ),
          const SizedBox(height: RestoflowSpacing.md),
        ],
        for (final member in staff)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: _StaffCard(
              member: member,
              onSetPin: () => _showPinDialog(context, member),
            ),
          ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _CreateStaffDialog(
      onCreate: (name, role) async {
        final l10n = AppLocalizations.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final result = await widget.repository.create(
          displayName: name,
          role: role,
        );
        result.fold(
          (_) {
            messenger.showSnackBar(SnackBar(content: Text(l10n.staffCreated)));
            _reload();
          },
          (failure) => messenger.showSnackBar(
            SnackBar(content: Text(adminFailureMessage(l10n, failure))),
          ),
        );
      },
    ),
  );

  Future<void> _showPinDialog(BuildContext context, StaffMember member) =>
      showDialog<void>(
        context: context,
        builder: (_) => _SetPinDialog(
          member: member,
          onSave: (pin) async {
            final l10n = AppLocalizations.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final result = await widget.repository.setPin(
              employeeProfileId: member.employeeProfileId,
              pin: pin,
            );
            result.fold(
              (_) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.staffPinSaved)),
                );
                _reload();
              },
              (failure) => messenger.showSnackBar(
                SnackBar(content: Text(adminFailureMessage(l10n, failure))),
              ),
            );
          },
        ),
      );
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member, required this.onSetPin});

  final StaffMember member;
  final VoidCallback onSetPin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(RestoflowRadii.md),
              ),
              child: Icon(
                Icons.badge_outlined,
                size: RestoflowIconSizes.lg,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Text(
                    adminRoleLabel(l10n, member.role),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!member.isActive) ...[
              AdminPill.tone(
                label: l10n.staffInactive,
                tone: RestoflowTone.danger,
                icon: Icons.pause_circle_outline,
              ),
              const SizedBox(width: RestoflowSpacing.xs),
            ],
            AdminPill.tone(
              label: member.hasPin ? l10n.staffPinSet : l10n.staffNoPin,
              tone: member.hasPin
                  ? RestoflowTone.success
                  : RestoflowTone.danger,
              icon: member.hasPin ? Icons.pin_outlined : Icons.priority_high,
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: member.isActive ? onSetPin : null,
              icon: const Icon(Icons.password, size: RestoflowIconSizes.sm),
              label: Text(
                member.hasPin ? l10n.staffResetPin : l10n.staffSetPin,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create dialog.
// ---------------------------------------------------------------------------
class _CreateStaffDialog extends StatefulWidget {
  const _CreateStaffDialog({required this.onCreate});

  final Future<void> Function(String displayName, MembershipRole role) onCreate;

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  MembershipRole _role = MembershipRole.cashier;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    await widget.onCreate(_name.text, _role);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.staffAdd),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.staffFieldName,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            DropdownButtonFormField<MembershipRole>(
              initialValue: _role,
              decoration: InputDecoration(
                labelText: l10n.staffFieldRole,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final role in kProvisionableStaffRoles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(adminRoleLabel(l10n, role)),
                  ),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
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

// ---------------------------------------------------------------------------
// Set-PIN dialog (obscured input + confirm; never echoes the PIN back).
// ---------------------------------------------------------------------------
class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog({required this.member, required this.onSave});

  final StaffMember member;
  final Future<void> Function(String pin) onSave;

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    await widget.onSave(_pin.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.staffPinDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.member.displayName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              l10n.staffPinDialogBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextFormField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: l10n.staffFieldPin,
                border: const OutlineInputBorder(),
                isDense: true,
                counterText: '',
              ),
              validator: (v) => RegExp(r'^[0-9]{4,8}$').hasMatch(v ?? '')
                  ? null
                  : l10n.staffPinInvalid,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: l10n.staffFieldPinConfirm,
                border: const OutlineInputBorder(),
                isDense: true,
                counterText: '',
              ),
              validator: (v) => v == _pin.text ? null : l10n.staffPinMismatch,
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
          child: Text(l10n.staffSetPin),
        ),
      ],
    );
  }
}
