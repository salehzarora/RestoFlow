import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminSectionCard;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'branch_kitchen_workflow_repository.dart' show KitchenWorkflowMode;
import 'branch_order_edit_settings_repository.dart';

/// ORDER-EDIT-001G — the Settings card for the branch's two order-editing
/// switches (API_CONTRACT §4.45.8; ORDER_EDIT_DESIGN §10, §11).
///
///  * **Owner-only.** Writes go through `set_branch_order_edit_settings`, which
///    the server gates at restaurant_owner; [canEdit] mirrors that gate so a
///    manager or cashier sees the real values locked, with the owner-only note.
///  * **Never optimistic.** A write sends the toggled switch plus the OTHER
///    switch's current server value, adopts the server's echo, then re-reads.
///    A denial or a failure leaves the stored values on screen.
///  * **One write at a time.** [_saving] blocks a second press, so a double tap
///    cannot send two requests with two different request keys.
///  * **Printer-only note.** On a branch without a kitchen screen the
///    finished-food switch has no effect (the system cannot tell when food is
///    ready). The stored value is kept and stays editable (Q-046); the note
///    says so.
class OrderEditSettingsSection extends StatefulWidget {
  const OrderEditSettingsSection({
    required this.repository,
    required this.canEdit,
    this.kitchenMode,
    super.key,
  });

  final BranchOrderEditSettingsRepository repository;

  /// The caller is an owner (org or restaurant) — the server's write gate.
  final bool canEdit;

  /// The branch's kitchen workflow as the Settings screen currently shows it.
  /// Null while that card is loading or failed; the reader's own
  /// `kitchen_workflow_mode` is then the fallback.
  final KitchenWorkflowMode? kitchenMode;

  @override
  State<OrderEditSettingsSection> createState() =>
      _OrderEditSettingsSectionState();
}

class _OrderEditSettingsSectionState extends State<OrderEditSettingsSection> {
  OrderEditSettings? _settings;
  OrderEditSettingsStatus _readStatus = OrderEditSettingsStatus.ok;
  bool _loading = true;
  bool _saving = false;

  /// Bumped when the seam changes, so a late answer for the previous branch
  /// can never land on this one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OrderEditSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different seam is a different branch: never show the old one's values.
    if (!identical(oldWidget.repository, widget.repository)) {
      _generation++;
      setState(() {
        _settings = null;
        _loading = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    final result = await widget.repository.read();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _readStatus = result.status;
      if (result.status == OrderEditSettingsStatus.ok) {
        _settings = result.settings;
      }
    });
  }

  Future<void> _write({required bool enabled, required bool finished}) async {
    if (_saving || !widget.canEdit || _settings == null) return;
    final l10n = AppLocalizations.of(context);
    final generation = _generation;
    setState(() => _saving = true);
    final result = await widget.repository.write(
      enabled: enabled,
      finishedFoodManagerOnly: finished,
    );
    if (!mounted) return;
    final sameSeam = generation == _generation;
    setState(() {
      _saving = false;
      // Adopt the SERVER's echo, never the requested values. The kitchen mode
      // is not in a write echo, so the last read value is kept. An echo for a
      // previous seam is never shown on this one.
      final echoed = result.settings;
      if (sameSeam &&
          result.status == OrderEditSettingsStatus.ok &&
          echoed != null) {
        _settings = OrderEditSettings(
          enabled: echoed.enabled,
          finishedFoodManagerOnly: echoed.finishedFoodManagerOnly,
          kitchenMode: _settings?.kitchenMode,
        );
      }
    });
    final message = switch (result.status) {
      OrderEditSettingsStatus.ok => l10n.dashboardOrderEditSaved,
      OrderEditSettingsStatus.denied => l10n.dashboardKitchenWorkflowDenied,
      OrderEditSettingsStatus.notFound => l10n.dashboardKitchenWorkflowNotFound,
      OrderEditSettingsStatus.unavailable => l10n.dashboardOrderEditSaveFailed,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    // Re-read authoritatively so the screen matches the branch, not the reply.
    if (sameSeam && result.status == OrderEditSettingsStatus.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdminSectionCard(
      key: const Key('order-edit-settings-section'),
      title: l10n.dashboardOrderEditSectionTitle,
      icon: Icons.edit_note_outlined,
      child: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        key: Key('order-edit-settings-loading'),
        padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
        child: RestoflowSkeleton(height: 48),
      );
    }
    final settings = _settings;
    if (settings == null) {
      return RestoflowNoticeBanner(
        key: const Key('order-edit-settings-unavailable'),
        tone: RestoflowTone.warning,
        icon: Icons.cloud_off_outlined,
        body: _readStatus == OrderEditSettingsStatus.notFound
            ? l10n.dashboardKitchenWorkflowNotFound
            : l10n.dashboardKitchenWorkflowUnavailable,
      );
    }
    final mode = widget.kitchenMode ?? settings.kitchenMode;
    final printerOnly = mode == KitchenWorkflowMode.printerOnly;
    final enabledToggle = widget.canEdit && !_saving;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('order-edit-enabled-toggle'),
          contentPadding: EdgeInsets.zero,
          value: settings.enabled,
          onChanged: enabledToggle
              ? (v) => _write(
                  enabled: v,
                  finished: settings.finishedFoodManagerOnly,
                )
              : null,
          title: Text(l10n.dashboardOrderEditEnabledLabel),
          subtitle: Text(l10n.dashboardOrderEditEnabledHelp),
        ),
        SwitchListTile(
          key: const Key('order-edit-finished-food-toggle'),
          contentPadding: EdgeInsets.zero,
          value: settings.finishedFoodManagerOnly,
          onChanged: enabledToggle
              ? (v) => _write(enabled: settings.enabled, finished: v)
              : null,
          title: Text(l10n.dashboardOrderEditFinishedFoodLabel),
          subtitle: Text(l10n.dashboardOrderEditFinishedFoodHelp),
        ),
        if (printerOnly)
          Padding(
            key: const Key('order-edit-printer-only-note'),
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: RestoflowNoticeBanner(
              tone: RestoflowTone.info,
              icon: Icons.print_outlined,
              body: l10n.dashboardOrderEditFinishedFoodPrinterOnlyNote,
            ),
          ),
        if (!widget.canEdit)
          Padding(
            key: const Key('order-edit-settings-owner-only'),
            padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
            child: Text(l10n.dashboardKitchenWorkflowOwnerOnly, style: muted),
          ),
      ],
    );
  }
}
