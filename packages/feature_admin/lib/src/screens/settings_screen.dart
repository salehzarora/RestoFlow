import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/admin_failure.dart';
import '../models/role_rank.dart';
import '../models/settings_models.dart';
import '../state/admin_providers.dart';
import '../widgets/admin_common.dart';

/// The owner Settings surface (RF-113 / RF-112 §4.25): organization, restaurant,
/// and branch settings over the existing columns only. Managers and below see a
/// read-only view (the role-rank guard); validation + dirty-state + save/cancel +
/// success/error feedback are handled per section.
class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(adminSettingsProvider);
    final scope = ref.watch(adminScopeProvider);
    final canEdit = canEditSettings(scope.actingRole);
    final canEditOrg = scope.actingRole == MembershipRole.orgOwner;

    return settings.when(
      loading: AdminStateView.loading,
      error: (e, _) => AdminStateView.fromFailure(
        context,
        adminFailureOf(e),
        onRetry: () => ref.invalidate(adminSettingsProvider),
      ),
      data: (bundle) => ListView(
        padding: const EdgeInsets.only(bottom: RestoflowSpacing.xxl),
        children: [
          AdminPageHeader(
            title: l10n.adminSettingsTitle,
            subtitle: l10n.adminSettingsSubtitle,
            icon: Icons.tune_outlined,
          ),
          if (!canEdit)
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                RestoflowSpacing.lg,
                0,
                RestoflowSpacing.lg,
                RestoflowSpacing.sm,
              ),
              child: _ReadOnlyNotice(),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RestoflowSpacing.lg,
            ),
            child: Column(
              children: [
                _OrgForm(initial: bundle.organization, canEdit: canEditOrg),
                const SizedBox(height: RestoflowSpacing.lg),
                _RestaurantForm(initial: bundle.restaurant, canEdit: canEdit),
                const SizedBox(height: RestoflowSpacing.lg),
                _BranchForm(initial: bundle.branch, canEdit: canEdit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              l10n.adminSettingsReadOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A small labelled text field used by the section forms.
// ---------------------------------------------------------------------------
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.enabled,
    this.optional = false,
    this.validator,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool optional;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.md),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: optional ? '$label · ${l10n.adminOptional}' : label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: validator,
        onChanged: (_) => onChanged?.call(),
      ),
    );
  }
}

class _StatusField extends StatelessWidget {
  const _StatusField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(String s) =>
        s == 'active' ? l10n.adminStatusActive : l10n.adminStatusSuspended;
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.md),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: l10n.adminFieldStatus,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final s in kSettingsStatuses)
            DropdownMenuItem(value: s, child: Text(label(s))),
        ],
        onChanged: enabled ? (v) => onChanged(v ?? value) : null,
      ),
    );
  }
}

/// Shared save/cancel footer + snackbar handling for a settings section.
mixin _SectionSaveMixin<T extends StatefulWidget> on State<T> {
  bool dirty = false;
  bool saving = false;

  void markDirty() {
    if (!dirty) setState(() => dirty = true);
  }

  Future<void> save({
    required GlobalKey<FormState> formKey,
    required Future<AdminResult<Object>> Function() op,
    required VoidCallback onSuccess,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    final result = await op();
    if (!mounted) return;
    setState(() => saving = false);
    result.fold(
      (_) {
        setState(() => dirty = false);
        onSuccess();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.adminSavedSnack)));
      },
      (f) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(adminFailureMessage(l10n, f)))),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: dirty && !saving ? onCancel : null,
          child: Text(l10n.adminCancel),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        FilledButton.icon(
          onPressed: dirty && !saving ? onSave : null,
          icon: saving
              ? const RestoflowInlineSpinner(size: 16)
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(l10n.adminSave),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Organization section.
// ---------------------------------------------------------------------------
class _OrgForm extends ConsumerStatefulWidget {
  const _OrgForm({required this.initial, required this.canEdit});
  final OrganizationSettings initial;
  final bool canEdit;
  @override
  ConsumerState<_OrgForm> createState() => _OrgFormState();
}

class _OrgFormState extends ConsumerState<_OrgForm> with _SectionSaveMixin {
  final _formKey = GlobalKey<FormState>();
  late final _currency = TextEditingController(
    text: widget.initial.defaultCurrency,
  );
  late final _country = TextEditingController(
    text: widget.initial.countryCode ?? '',
  );
  late String _status = widget.initial.status;

  void _reset() {
    _currency.text = widget.initial.defaultCurrency;
    _country.text = widget.initial.countryCode ?? '';
    setState(() {
      _status = widget.initial.status;
      dirty = false;
    });
  }

  @override
  void dispose() {
    _currency.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminSectionCard(
      title: l10n.adminSectionOrg,
      icon: Icons.business_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _Field(
              controller: _currency,
              label: l10n.adminFieldDefaultCurrency,
              enabled: widget.canEdit,
              textCapitalization: TextCapitalization.characters,
              onChanged: markDirty,
              validator: (v) =>
                  RegExp(r'^[A-Za-z]{3}$').hasMatch((v ?? '').trim())
                  ? null
                  : l10n.adminErrCurrency,
            ),
            _Field(
              controller: _country,
              label: l10n.adminFieldCountryCode,
              enabled: widget.canEdit,
              optional: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: markDirty,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^[A-Za-z]{2}$').hasMatch(t)
                    ? null
                    : l10n.adminErrCountry;
              },
            ),
            _StatusField(
              value: _status,
              enabled: widget.canEdit,
              onChanged: (v) => setState(() {
                _status = v;
                dirty = true;
              }),
            ),
            if (widget.canEdit)
              _SaveBar(
                dirty: dirty,
                saving: saving,
                onCancel: _reset,
                onSave: () => save(
                  formKey: _formKey,
                  op: () => ref
                      .read(adminControllerProvider)
                      .updateOrganizationSettings(
                        defaultCurrency: _currency.text,
                        countryCode: _country.text,
                        status: _status,
                      ),
                  onSuccess: () {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Restaurant section.
// ---------------------------------------------------------------------------
class _RestaurantForm extends ConsumerStatefulWidget {
  const _RestaurantForm({required this.initial, required this.canEdit});
  final RestaurantSettings initial;
  final bool canEdit;
  @override
  ConsumerState<_RestaurantForm> createState() => _RestaurantFormState();
}

class _RestaurantFormState extends ConsumerState<_RestaurantForm>
    with _SectionSaveMixin {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _currency = TextEditingController(
    text: widget.initial.currencyOverride ?? '',
  );
  late final _tz = TextEditingController(text: widget.initial.timezone ?? '');
  late String _status = widget.initial.status;

  void _reset() {
    _name.text = widget.initial.name;
    _currency.text = widget.initial.currencyOverride ?? '';
    _tz.text = widget.initial.timezone ?? '';
    setState(() {
      _status = widget.initial.status;
      dirty = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _tz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminSectionCard(
      title: l10n.adminSectionRestaurant,
      icon: Icons.storefront_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _Field(
              controller: _name,
              label: l10n.adminFieldName,
              enabled: widget.canEdit,
              onChanged: markDirty,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
            ),
            _Field(
              controller: _currency,
              label: l10n.adminFieldCurrencyOverride,
              enabled: widget.canEdit,
              optional: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: markDirty,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^[A-Za-z]{3}$').hasMatch(t)
                    ? null
                    : l10n.adminErrCurrency;
              },
            ),
            _Field(
              controller: _tz,
              label: l10n.adminFieldTimezone,
              enabled: widget.canEdit,
              optional: true,
              onChanged: markDirty,
            ),
            _StatusField(
              value: _status,
              enabled: widget.canEdit,
              onChanged: (v) => setState(() {
                _status = v;
                dirty = true;
              }),
            ),
            if (widget.canEdit)
              _SaveBar(
                dirty: dirty,
                saving: saving,
                onCancel: _reset,
                onSave: () => save(
                  formKey: _formKey,
                  op: () => ref
                      .read(adminControllerProvider)
                      .updateRestaurantSettings(
                        name: _name.text,
                        currencyOverride: _currency.text,
                        timezone: _tz.text,
                        status: _status,
                      ),
                  onSuccess: () {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Branch section.
// ---------------------------------------------------------------------------
class _BranchForm extends ConsumerStatefulWidget {
  const _BranchForm({required this.initial, required this.canEdit});
  final BranchSettings initial;
  final bool canEdit;
  @override
  ConsumerState<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<_BranchForm>
    with _SectionSaveMixin {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _address = TextEditingController(
    text: widget.initial.address ?? '',
  );
  late final _tz = TextEditingController(text: widget.initial.timezone ?? '');
  late final _prefix = TextEditingController(
    text: widget.initial.receiptPrefix ?? '',
  );
  late String _status = widget.initial.status;

  void _reset() {
    _name.text = widget.initial.name;
    _address.text = widget.initial.address ?? '';
    _tz.text = widget.initial.timezone ?? '';
    _prefix.text = widget.initial.receiptPrefix ?? '';
    setState(() {
      _status = widget.initial.status;
      dirty = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _tz.dispose();
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminSectionCard(
      title: l10n.adminSectionBranch,
      icon: Icons.store_mall_directory_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _Field(
              controller: _name,
              label: l10n.adminFieldName,
              enabled: widget.canEdit,
              onChanged: markDirty,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.adminErrName : null,
            ),
            _Field(
              controller: _address,
              label: l10n.adminFieldAddress,
              enabled: widget.canEdit,
              optional: true,
              onChanged: markDirty,
            ),
            _Field(
              controller: _tz,
              label: l10n.adminFieldTimezone,
              enabled: widget.canEdit,
              optional: true,
              onChanged: markDirty,
            ),
            _Field(
              controller: _prefix,
              label: l10n.adminFieldReceiptPrefix,
              enabled: widget.canEdit,
              optional: true,
              onChanged: markDirty,
            ),
            _StatusField(
              value: _status,
              enabled: widget.canEdit,
              onChanged: (v) => setState(() {
                _status = v;
                dirty = true;
              }),
            ),
            if (widget.canEdit)
              _SaveBar(
                dirty: dirty,
                saving: saving,
                onCancel: _reset,
                onSave: () => save(
                  formKey: _formKey,
                  op: () => ref
                      .read(adminControllerProvider)
                      .updateBranchSettings(
                        name: _name.text,
                        address: _address.text,
                        timezone: _tz.text,
                        receiptPrefix: _prefix.text,
                        status: _status,
                      ),
                  onSuccess: () {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}
