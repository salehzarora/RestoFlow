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

import 'floor_layout_editor.dart';
import 'table_models.dart';
import 'table_status_visuals.dart';
import 'tables_repository.dart';

/// The dashboard Tables surface (sprint `dining_tables` backend): list, add,
/// edit, set the operational status, and remove the dining tables the POS
/// table picker sells from.
///
/// TABLE-FLOOR-LAYOUT-021 adds the FLOOR layer on top: named sections, one
/// white floor-map canvas per section with tables placed at saved normalized
/// coordinates, and an Arrange mode (drag freely, save on drag END only,
/// optimistic + revert on failure). The classic card grid below stays the
/// full management surface.
class TablesScreen extends StatefulWidget {
  const TablesScreen({required this.repository, super.key});

  final TablesAdminRepository repository;

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late Future<AdminResult<TablesFloorSnapshot>> _future = widget.repository
      .load();

  /// The last successful load, shown while a reload is in flight so an
  /// arrange-mode drag save never flashes the whole screen back to a spinner.
  AdminResult<TablesFloorSnapshot>? _lastResult;

  bool _arrange = false;

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

  /// TABLE-FLOOR-LAYOUT-021: one placement write, fired on drag END only.
  /// Returns false when the write failed so the editor reverts the tile; a
  /// success silently refreshes the snapshot (no snackbar per drop).
  Future<bool> _moveTable(String tableId, int layoutX, int layoutY) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.repository.setTablePosition(
      tableId,
      layoutX,
      layoutY,
    );
    if (!mounted) return false;
    return result.fold(
      (_) {
        _reload();
        return true;
      },
      (failure) {
        messenger.showSnackBar(
          SnackBar(content: Text(adminFailureMessage(l10n, failure))),
        );
        return false;
      },
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
          child: FutureBuilder<AdminResult<TablesFloorSnapshot>>(
            future: _future,
            builder: (context, snap) {
              // Cache the last success so reloads keep the current UI up.
              if (snap.hasData) _lastResult = snap.data;
              final result = snap.data ?? _lastResult;
              if (result == null) return AdminStateView.loading();
              return result.fold(
                (snapshot) => _body(context, snapshot),
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

  Widget _body(BuildContext context, TablesFloorSnapshot snapshot) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // PILOT-OPERATIONS-CORRECTIONS-001 (A4): project the group-wide effective state +
    // active dine-in count onto every grouped member, so a free-looking peer of an
    // occupied group never appears Available. One canonical aggregation, shared with
    // the POS (packages/domain).
    final tables = withDashboardGroupAggregation(snapshot.tables);
    if (tables.isEmpty && snapshot.sections.isEmpty) {
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
    // PILOT-OPERATIONS-CORRECTIONS-001: combined member label per active link
    // group ("T4 + T5"), so each grouped tile can name the whole group (display
    // only — the POS owns link/unlink).
    final groupLabels = <String, String>{};
    final groupMembers = <String, List<String>>{};
    for (final t in tables) {
      final g = t.groupId;
      if (g != null) (groupMembers[g] ??= <String>[]).add(t.label);
    }
    groupMembers.forEach((g, labels) {
      labels.sort();
      groupLabels[g] = labels.join(' + ');
    });
    // The floor layer reads the AGGREGATED tables so a grouped tile's tint on
    // the map matches its card below.
    final floorSnapshot = TablesFloorSnapshot(
      tables: tables,
      sections: snapshot.sections,
    );
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.xxl,
      ),
      children: [
        // ------------------------------------------------------------ floor
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tablesSectionsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('tables-add-section'),
              onPressed: () => _showSectionDialog(context),
              icon: const Icon(Icons.add, size: RestoflowIconSizes.sm),
              label: Text(l10n.tablesSectionAdd),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            FilledButton.tonalIcon(
              key: const Key('tables-arrange-toggle'),
              onPressed: () => setState(() => _arrange = !_arrange),
              icon: Icon(
                _arrange ? Icons.done : Icons.open_with,
                size: RestoflowIconSizes.sm,
              ),
              label: Text(
                _arrange ? l10n.tablesArrangeDone : l10n.tablesArrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.md),
        FloorLayoutEditor(
          snapshot: floorSnapshot,
          arrange: _arrange,
          onRenameSection: (section) =>
              _showSectionDialog(context, section: section),
          onDeleteSection: (section) => _confirmDeleteSection(context, section),
          onReorderSections: (ids) =>
              _run(() => widget.repository.reorderSections(ids)),
          onMoveTable: _moveTable,
          onSetSection: (table) =>
              _chooseSection(context, table, snapshot.sections),
        ),
        const Divider(height: RestoflowSpacing.xl),
        // ------------------------------------------------------------ cards
        Wrap(
          spacing: RestoflowSpacing.md,
          runSpacing: RestoflowSpacing.md,
          children: [
            for (final table in tables)
              SizedBox(
                width: 280,
                child: _TableCard(
                  table: table,
                  groupLabel: table.groupId == null
                      ? null
                      : groupLabels[table.groupId],
                  onSetStatus: (status) =>
                      _run(() => widget.repository.setStatus(table.id, status)),
                  onSetSection: () =>
                      _chooseSection(context, table, snapshot.sections),
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

  // ------------------------------------------------------ section management

  Future<void> _showSectionDialog(
    BuildContext context, {
    DashboardTableSection? section,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _SectionDialog(
      section: section,
      onSave: ({required name, required isActive}) => _run(
        () => widget.repository.upsertSection(
          id: section?.id,
          name: name,
          isActive: isActive,
        ),
      ),
    ),
  );

  Future<void> _confirmDeleteSection(
    BuildContext context,
    DashboardTableSection section,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tablesSectionDelete),
        // Deleting a section only DETACHES its tables (they are never
        // deleted) — the confirm copy says exactly that.
        content: Text(l10n.tablesSectionDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tablesSectionDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.repository.deleteSection(section.id));
    }
  }

  /// Pick a section for [table] (or "no section"). A record wrapper
  /// distinguishes "dialog dismissed" (null) from "chose no-section" ((null,)).
  Future<void> _chooseSection(
    BuildContext context,
    DashboardTable table,
    List<DashboardTableSection> sections,
  ) async {
    final l10n = AppLocalizations.of(context);
    // Localized action word + the table's own label (data, not copy).
    final dialogTitle = '${l10n.tablesSetSection} — ${table.label}';
    final choice = await showDialog<(String?,)>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(dialogTitle),
        children: [
          for (final section in sections)
            if (section.isActive)
              SimpleDialogOption(
                key: Key('choose-section-${section.id}'),
                onPressed: () => Navigator.of(dialogContext).pop((section.id,)),
                child: Row(
                  children: [
                    Icon(
                      section.id == table.sectionId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: RestoflowIconSizes.sm,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    Expanded(child: Text(section.name)),
                  ],
                ),
              ),
          SimpleDialogOption(
            key: const Key('choose-section-none'),
            onPressed: () => Navigator.of(dialogContext).pop((null,)),
            child: Row(
              children: [
                Icon(
                  table.sectionId == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: RestoflowIconSizes.sm,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(child: Text(l10n.tablesSectionNone)),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice.$1 == table.sectionId) return; // no-op pick
    await _run(() => widget.repository.setTableSection(table.id, choice.$1));
  }
}

/// One floor tile: a status accent edge, a big table label, the seats/area
/// meta, status + inactive pills, and the per-table actions.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onSetStatus,
    required this.onSetSection,
    required this.onEdit,
    required this.onDelete,
    this.groupLabel,
  });

  final DashboardTable table;
  final ValueChanged<DiningTableStatus> onSetStatus;

  /// TABLE-FLOOR-LAYOUT-021: opens the section chooser for this table.
  final VoidCallback onSetSection;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// PILOT-OPERATIONS-CORRECTIONS-001: the combined label of this table's active
  /// link group ("T4 + T5"), or null when not grouped. Display only.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = tableStatusVisual(context, table.status);
    final statusStyle = status.tone.styleOf(theme);
    // PILOT-OPERATIONS-CORRECTIONS-001: the SERVER effective state, shown when it
    // differs from the manual status (e.g. manually Available but effectively
    // Occupied by a live order) so the floor read is honest.
    final effectiveDiffers =
        table.effectiveState != null &&
        table.effectiveState != table.status.wire;
    final detail = [
      if (table.seats != null) '${l10n.tablesFieldSeats}: ${table.seats}',
      // TABLE-FLOOR-LAYOUT-021: the section is the floor home; the legacy
      // free-text area stays visible for unsectioned tables only.
      if (table.sectionName != null)
        table.sectionName!
      else if (table.area != null)
        table.area!,
      // RESTAURANT-OPERATIONS-V1-001: DERIVED occupancy, always shown — a
      // floor manager reads "1 open order" here the moment a POS seats a
      // party, independently of the manual floor status above.
      l10n.tablesOpenOrders(table.activeOrderCount),
      if (effectiveDiffers)
        '${l10n.tablesEffective}: ${tableEffectiveLabel(context, table.effectiveState!)}',
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
                    // PILOT-OPERATIONS-CORRECTIONS-001: linked-group membership,
                    // read-only (the POS owns link/unlink for this phase).
                    if (groupLabel != null) ...[
                      const SizedBox(height: RestoflowSpacing.xxs),
                      Row(
                        key: Key('table-linked-${table.id}'),
                        children: [
                          Icon(
                            Icons.link,
                            size: RestoflowIconSizes.xs,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: RestoflowSpacing.xs),
                          Expanded(
                            child: Text(
                              '${l10n.tablesLinked}: $groupLabel',
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
                                        tableStatusVisual(context, value).icon,
                                        size: RestoflowIconSizes.sm,
                                        color: tableStatusVisual(
                                          context,
                                          value,
                                        ).tone.styleOf(theme).accent,
                                      ),
                                      const SizedBox(
                                        width: RestoflowSpacing.sm,
                                      ),
                                      Text(
                                        tableStatusVisual(context, value).label,
                                      ),
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
                          key: Key('table-set-section-${table.id}'),
                          tooltip: l10n.tablesSetSection,
                          onPressed: onSetSection,
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: RestoflowIconSizes.md,
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

// ---------------------------------------------------------------------------
// Section add / rename dialog (TABLE-FLOOR-LAYOUT-021).
// ---------------------------------------------------------------------------
class _SectionDialog extends StatefulWidget {
  const _SectionDialog({required this.onSave, this.section});

  final DashboardTableSection? section;
  final Future<void> Function({required String name, required bool isActive})
  onSave;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.section?.name ?? '',
  );
  late bool _active = widget.section?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    await widget.onSave(name: _name.text.trim(), isActive: _active);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.section == null ? l10n.tablesSectionAdd : l10n.tablesSectionEdit,
      ),
      content: SizedBox(
        width: RestoflowPanelWidths.dialog,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('section-name-field'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.tablesSectionName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.tablesErrLabel : null,
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
          key: const Key('section-save'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminSave),
        ),
      ],
    );
  }
}
