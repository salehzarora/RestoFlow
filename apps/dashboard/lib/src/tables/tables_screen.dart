import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show
        AdminPageHeader,
        AdminPill,
        AdminResult,
        AdminStateView,
        adminFailureMessage;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'table_models.dart';
import 'tables_repository.dart';

/// The dashboard Tables surface (sprint `dining_tables` backend): list, add,
/// edit, set the operational status, and remove the dining tables the POS
/// table picker sells from.
class TablesScreen extends StatefulWidget {
  const TablesScreen({required this.repository, super.key});

  final TablesAdminRepository repository;

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late Future<AdminResult<List<DashboardTable>>> _future = widget.repository
      .load();

  void _reload() {
    // Braces, not an arrow: the setState callback must not RETURN the future.
    setState(() {
      _future = widget.repository.load();
    });
  }

  Future<void> _run(Future<AdminResult<void>> Function() op) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await op();
    if (!mounted) return;
    result.fold(
      (_) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.tablesSaved)));
        _reload();
      },
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l10n, failure))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          title: l10n.tablesTitle,
          subtitle: l10n.tablesSubtitle,
          actions: [
            FilledButton.icon(
              onPressed: () => _showTableDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.tablesAdd),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<AdminResult<List<DashboardTable>>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) return AdminStateView.loading();
              return snap.data!.fold(
                (tables) => _list(context, tables),
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

  Widget _list(BuildContext context, List<DashboardTable> tables) {
    final l10n = AppLocalizations.of(context);
    if (tables.isEmpty) {
      return AdminStateView(
        icon: Icons.table_restaurant_outlined,
        title: l10n.tablesEmptyTitle,
        body: l10n.tablesEmptyBody,
        action: FilledButton.icon(
          onPressed: () => _showTableDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.tablesAdd),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        for (final table in tables)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
            child: _TableCard(
              table: table,
              onSetStatus: (status) =>
                  _run(() => widget.repository.setStatus(table.id, status)),
              onEdit: () => _showTableDialog(context, table: table),
              onDelete: () => _confirmDelete(context, table),
            ),
          ),
      ],
    );
  }

  Future<void> _showTableDialog(
    BuildContext context, {
    DashboardTable? table,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _TableDialog(
      table: table,
      onSave:
          ({
            required label,
            required seats,
            required area,
            required isActive,
          }) => _run(
            () => widget.repository.upsertTable(
              id: table?.id,
              label: label,
              seats: seats,
              area: area,
              isActive: isActive,
            ),
          ),
    ),
  );

  Future<void> _confirmDelete(
    BuildContext context,
    DashboardTable table,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tablesDelete),
        content: Text(l10n.tablesDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tablesDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.repository.deleteTable(table.id));
    }
  }
}

/// The localized label + tone colour + icon for a table status. Colours ride
/// the shared semantic tones (success/warning/info/danger), so the pills stay
/// themeable (no hardcoded palette).
({String label, Color color, IconData icon}) _statusVisual(
  BuildContext context,
  DiningTableStatus status,
) {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    DiningTableStatus.available => (
      label: l10n.tablesStatusAvailable,
      color: RestoflowTone.success.style(scheme).accent,
      icon: Icons.check_circle_outline,
    ),
    DiningTableStatus.occupied => (
      label: l10n.tablesStatusOccupied,
      color: RestoflowTone.warning.style(scheme).accent,
      icon: Icons.people_alt_outlined,
    ),
    DiningTableStatus.reserved => (
      label: l10n.tablesStatusReserved,
      color: RestoflowTone.info.style(scheme).accent,
      icon: Icons.event_seat_outlined,
    ),
    DiningTableStatus.outOfService => (
      label: l10n.tablesStatusOutOfService,
      color: RestoflowTone.danger.style(scheme).accent,
      icon: Icons.block_outlined,
    ),
  };
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onSetStatus,
    required this.onEdit,
    required this.onDelete,
  });

  final DashboardTable table;
  final ValueChanged<DiningTableStatus> onSetStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _statusVisual(context, table.status);
    final detail = [
      if (table.seats != null) '${l10n.tablesFieldSeats}: ${table.seats}',
      if (table.area != null) table.area!,
    ].join(' · ');

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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.table_restaurant_outlined,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        table.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!table.isActive) ...[
                  AdminPill(
                    label: l10n.tablesInactive,
                    color: scheme.error,
                    icon: Icons.pause_circle_outline,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                ],
                AdminPill(
                  label: status.label,
                  color: status.color,
                  icon: status.icon,
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Row(
              children: [
                PopupMenuButton<DiningTableStatus>(
                  tooltip: l10n.tablesSetStatus,
                  onSelected: onSetStatus,
                  itemBuilder: (context) => [
                    for (final value in DiningTableStatus.values)
                      PopupMenuItem(
                        value: value,
                        child: Row(
                          children: [
                            Icon(
                              _statusVisual(context, value).icon,
                              size: 18,
                              color: _statusVisual(context, value).color,
                            ),
                            const SizedBox(width: RestoflowSpacing.sm),
                            Text(_statusVisual(context, value).label),
                          ],
                        ),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RestoflowSpacing.sm,
                      vertical: RestoflowSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.swap_horiz_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: RestoflowSpacing.xs),
                        Text(
                          l10n.tablesSetStatus,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.tablesEdit),
                ),
                IconButton(
                  tooltip: l10n.tablesDelete,
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit dialog.
// ---------------------------------------------------------------------------
class _TableDialog extends StatefulWidget {
  const _TableDialog({required this.onSave, this.table});

  final DashboardTable? table;
  final Future<void> Function({
    required String label,
    required int? seats,
    required String? area,
    required bool isActive,
  })
  onSave;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label = TextEditingController(
    text: widget.table?.label ?? '',
  );
  late final TextEditingController _seats = TextEditingController(
    text: widget.table?.seats?.toString() ?? '',
  );
  late final TextEditingController _area = TextEditingController(
    text: widget.table?.area ?? '',
  );
  late bool _active = widget.table?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _seats.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final seatsText = _seats.text.trim();
    final areaText = _area.text.trim();
    await widget.onSave(
      label: _label.text,
      seats: seatsText.isEmpty ? null : int.parse(seatsText),
      area: areaText.isEmpty ? null : areaText,
      isActive: _active,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    return AlertDialog(
      title: Text(widget.table == null ? l10n.tablesAdd : l10n.tablesEdit),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _label,
                decoration: deco(l10n.tablesFieldLabel),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.tablesErrLabel : null,
              ),
              const SizedBox(height: RestoflowSpacing.md),
              TextFormField(
                controller: _seats,
                decoration: deco(l10n.tablesFieldSeats),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null; // seats are optional
                  final seats = int.tryParse(text);
                  return (seats == null || seats < 1)
                      ? l10n.tablesErrSeats
                      : null;
                },
              ),
              const SizedBox(height: RestoflowSpacing.md),
              TextFormField(
                controller: _area,
                decoration: deco(l10n.tablesFieldArea),
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.tablesActive),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminSave),
        ),
      ],
    );
  }
}
