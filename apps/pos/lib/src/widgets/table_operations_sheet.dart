import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../data/table_operations_repository.dart';
import '../state/order_setup_controller.dart';
import '../state/table_operations_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — the POS operational table-control sheet.
///
/// Opened by a DELIBERATE long-press on a table (ONLY for an operator with
/// `manage_table_operations`). Shows the table's manual status, EFFECTIVE state
/// (honestly distinct — a manually-Available table can be effectively Occupied by
/// a live order) and active-order count, and the deliberate actions: mark
/// Available / Reserved / Occupied / Out of service, Link another table, Unlink.
/// Invalid actions are disabled with a reason. Every mutation is
/// server-authoritative (online-required — no fake offline success); the table
/// read model refreshes on success.
class TableOperationsSheet extends ConsumerStatefulWidget {
  const TableOperationsSheet({
    required this.table,
    required this.allTables,
    super.key,
  });

  final DemoTable table;
  final List<DemoTable> allTables;

  static Future<void> show(
    BuildContext context, {
    required DemoTable table,
    required List<DemoTable> allTables,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TableOperationsSheet(table: table, allTables: allTables),
  );

  @override
  ConsumerState<TableOperationsSheet> createState() =>
      _TableOperationsSheetState();
}

class _TableOperationsSheetState extends ConsumerState<TableOperationsSheet> {
  bool _submitting = false;
  String? _errorCode;
  bool _linkMode = false;

  DemoTable get _table => widget.table;

  Future<void> _run(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    try {
      await action();
      ref.invalidate(
        tablesProvider,
      ); // reconcile from the authoritative read model
      if (mounted) Navigator.of(context).maybePop();
    } on TableOperationException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = e.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = 'rejected';
      });
    }
  }

  void _setStatus(String status) => _run(
    () => ref
        .read(tableOperationsRepositoryProvider)
        .setStatus(tableId: _table.tableId, status: status),
  );

  void _link(DemoTable other) => _run(
    () => ref
        .read(tableOperationsRepositoryProvider)
        .link(tableIdA: _table.tableId, tableIdB: other.tableId),
  );

  Future<void> _unlink() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.posTableUnlinkConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l10n.posShiftCancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.posTableUnlink),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref
          .read(tableOperationsRepositoryProvider)
          .unlink(tableId: _table.tableId),
    );
  }

  String _errorMessage(AppLocalizations l10n, String code) => switch (code) {
    'offline' => l10n.posTableStatusOffline,
    'permission_denied' => l10n.posTableRequiresPermission,
    'table_in_use' => l10n.posTableOccupiedByOrder,
    'invalid_link' => l10n.posTableAlreadyGrouped,
    'table_not_available' => l10n.posTableLinkFailed,
    _ => l10n.posTableStatusFailed,
  };

  String _stateLabel(AppLocalizations l10n, String state) => switch (state) {
    'available' => l10n.posTableStateAvailable,
    'reserved' => l10n.posTableStateReserved,
    'occupied' => l10n.posTableStateOccupied,
    'out_of_service' => l10n.posTableStateOutOfService,
    _ => state,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = _table;

    if (_linkMode) return _buildLinkCandidates(l10n, theme);

    // Out-of-service is REFUSED server-side while a live order sits on the table;
    // disable it with a clear reason rather than let the cashier hit the refusal.
    final occupiedByOrder = t.activeOrderCount > 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${l10n.posTableOperations} · ${t.label}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            // Manual vs EFFECTIVE state (honestly distinct) + active-order count.
            _kv(
              theme,
              l10n.posTableManualStatus,
              _stateLabel(l10n, t.manualStatus),
            ),
            _kv(
              theme,
              l10n.posTableEffectiveStatus,
              _stateLabel(l10n, t.effectiveState),
              key: const Key('table-ops-effective'),
            ),
            _kv(
              theme,
              l10n.posTableActiveOrders,
              l10n.posTableOpenOrders(t.activeOrderCount),
            ),
            if (t.isGrouped)
              _kv(theme, l10n.posTableGroup, l10n.posTableLinked),
            const Divider(),
            _action(
              key: 'table-ops-available',
              icon: Icons.check_circle_outline,
              tone: RestoflowTone.success,
              label: l10n.posTableMarkAvailable,
              selected: t.manualStatus == 'available',
              onTap: () => _setStatus('available'),
            ),
            _action(
              key: 'table-ops-reserved',
              icon: Icons.event_seat_outlined,
              tone: RestoflowTone.info,
              label: l10n.posTableMarkReserved,
              selected: t.manualStatus == 'reserved',
              onTap: () => _setStatus('reserved'),
            ),
            _action(
              key: 'table-ops-occupied',
              icon: Icons.people_outline,
              tone: RestoflowTone.warning,
              label: l10n.posTableMarkOccupied,
              selected: t.manualStatus == 'occupied',
              onTap: () => _setStatus('occupied'),
            ),
            _action(
              key: 'table-ops-out-of-service',
              icon: Icons.block,
              tone: RestoflowTone.danger,
              label: l10n.posTableMarkOutOfService,
              selected: t.manualStatus == 'out_of_service',
              // Disabled while a live order occupies the table (server refuses it).
              disabledReason: occupiedByOrder
                  ? l10n.posTableOccupiedByOrder
                  : null,
              onTap: () => _setStatus('out_of_service'),
            ),
            const Divider(),
            _action(
              key: 'table-ops-link',
              icon: Icons.link,
              tone: RestoflowTone.info,
              label: l10n.posTableLinkAnother,
              onTap: () => setState(() => _linkMode = true),
            ),
            if (t.isGrouped)
              _action(
                key: 'table-ops-unlink',
                icon: Icons.link_off,
                tone: RestoflowTone.neutral,
                label: l10n.posTableUnlink,
                onTap: _unlink,
              ),
            if (_submitting)
              const Padding(
                key: Key('table-ops-submitting'),
                padding: EdgeInsets.only(top: RestoflowSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
                child: RestoflowNoticeBanner(
                  key: const Key('table-ops-error'),
                  tone: RestoflowTone.danger,
                  icon: Icons.error_outline,
                  body: _errorMessage(l10n, _errorCode!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkCandidates(AppLocalizations l10n, ThemeData theme) {
    // Valid candidates: same branch (all rows are session-branch), NOT this table,
    // NOT out of service, and NOT already in a DIFFERENT group.
    final candidates = widget.allTables.where((c) {
      if (c.tableId == _table.tableId) return false;
      if (c.isOutOfService) return false;
      if (c.isGrouped && _table.isGrouped && c.groupId != _table.groupId) {
        return false;
      }
      if (c.isGrouped && c.groupId == _table.groupId)
        return false; // already ours
      return true;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.posTableSelectToLink,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in candidates)
                    ListTile(
                      key: Key('table-link-candidate-${c.tableId}'),
                      leading: const Icon(Icons.table_restaurant),
                      title: Text(c.label),
                      subtitle: Text(_stateLabel(l10n, c.effectiveState)),
                      onTap: _submitting ? null : () => _link(c),
                    ),
                ],
              ),
            ),
            if (_submitting) const LinearProgressIndicator(),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
                child: RestoflowNoticeBanner(
                  key: const Key('table-ops-error'),
                  tone: RestoflowTone.danger,
                  icon: Icons.error_outline,
                  body: _errorMessage(l10n, _errorCode!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(
          k,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(v, style: theme.textTheme.bodyMedium),
      ],
    ),
  );

  Widget _action({
    required String key,
    required IconData icon,
    required RestoflowTone tone,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    String? disabledReason,
  }) {
    final enabled = disabledReason == null && !_submitting;
    return ListTile(
      key: Key(key),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: tone.styleOf(Theme.of(context)).accent),
      title: Text(label),
      subtitle: disabledReason == null ? null : Text(disabledReason),
      trailing: selected ? const Icon(Icons.check) : null,
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
