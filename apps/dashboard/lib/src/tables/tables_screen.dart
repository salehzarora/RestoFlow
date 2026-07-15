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
          icon: Icons.table_restaurant_outlined,
          actions: [
            FilledButton.icon(
              onPressed: () => _showTableDialog(context),
              icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
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
          icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
          label: Text(l10n.tablesAdd),
        ),
      );
    }
    // A floor-manager grid: one status-coloured tile per table.
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        Wrap(
          spacing: RestoflowSpacing.md,
          runSpacing: RestoflowSpacing.md,
          children: [
            for (final table in tables)
              SizedBox(
                width: 280,
                child: _TableCard(
                  table: table,
                  onSetStatus: (status) =>
                      _run(() => widget.repository.setStatus(table.id, status)),
                  onEdit: () => _showTableDialog(context, table: table),
                  onDelete: () => _confirmDelete(context, table),
                ),
              ),
          ],
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

/// The localized label + semantic tone + icon for a table status. Tones ride
/// the shared TRUE semantic palette (success/warning/info/danger), so the
/// tiles stay themeable (no hardcoded palette).
({String label, RestoflowTone tone, IconData icon}) _statusVisual(
  BuildContext context,
  DiningTableStatus status,
) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    DiningTableStatus.available => (
      label: l10n.tablesStatusAvailable,
      tone: RestoflowTone.success,
      icon: Icons.check_circle_outline,
    ),
    DiningTableStatus.occupied => (
      label: l10n.tablesStatusOccupied,
      tone: RestoflowTone.warning,
      icon: Icons.people_alt_outlined,
    ),
    DiningTableStatus.reserved => (
      label: l10n.tablesStatusReserved,
      tone: RestoflowTone.info,
      icon: Icons.event_seat_outlined,
    ),
    DiningTableStatus.outOfService => (
      label: l10n.tablesStatusOutOfService,
      tone: RestoflowTone.danger,
      icon: Icons.block_outlined,
    ),
  };
}

/// One floor tile: a status accent edge, a big table label, the seats/area
/// meta, status + inactive pills, and the per-table actions.
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
    final statusStyle = status.tone.styleOf(theme);
    final detail = [
      if (table.seats != null) '${l10n.tablesFieldSeats}: ${table.seats}',
      if (table.area != null) table.area!,
      // RESTAURANT-OPERATIONS-V1-001: DERIVED occupancy, always shown — a
      // floor manager reads "1 open order" here the moment a POS seats a
      // party, independently of the manual floor status above.
      l10n.tablesOpenOrders(table.activeOrderCount),
    ].join(' · ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // IntrinsicHeight: the tile sits in a Wrap (unbounded height), so the
      // stretched accent edge needs the row's intrinsic height as its bound.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The status accent edge (start side; mirrors under RTL).
            Container(width: 6, color: statusStyle.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(RestoflowSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            table.label,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Icon(
                          Icons.table_restaurant_outlined,
                          size: RestoflowIconSizes.md,
                          color: statusStyle.accent,
                        ),
                      ],
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: RestoflowSpacing.xxs),
                      Row(
                        children: [
                          Icon(
                            Icons.event_seat_outlined,
                            size: RestoflowIconSizes.xs,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: RestoflowSpacing.xs),
                          Expanded(
                            child: Text(
                              detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: RestoflowSpacing.sm),
                    Wrap(
                      spacing: RestoflowSpacing.xs,
                      runSpacing: RestoflowSpacing.xs,
                      children: [
                        AdminPill.tone(
                          label: status.label,
                          tone: status.tone,
                          icon: status.icon,
                        ),
                        if (!table.isActive)
                          AdminPill.tone(
                            label: l10n.tablesInactive,
                            tone: RestoflowTone.danger,
                            icon: Icons.pause_circle_outline,
                          ),
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.sm),
                    Row(
                      children: [
                        // Expanded + ellipsis: the trigger label must never
                        // overflow the 280px tile (long ar/he labels).
                        Expanded(
                          child: PopupMenuButton<DiningTableStatus>(
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
                                        size: RestoflowIconSizes.sm,
                                        color: _statusVisual(
                                          context,
                                          value,
                                        ).tone.styleOf(theme).accent,
                                      ),
                                      const SizedBox(
                                        width: RestoflowSpacing.sm,
                                      ),
                                      Text(_statusVisual(context, value).label),
                                    ],
                                  ),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: RestoflowSpacing.sm,
                                vertical: RestoflowSpacing.xs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.swap_horiz_outlined,
                                    size: RestoflowIconSizes.sm,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: RestoflowSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      l10n.tablesSetStatus,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(color: scheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.tablesEdit,
                          onPressed: onEdit,
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: RestoflowIconSizes.md,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.tablesDelete,
                          style: RestoflowButtonStyles.dangerGhost(context),
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            size: RestoflowIconSizes.md,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
        width: RestoflowPanelWidths.dialog,
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
