import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../data/recent_order.dart';
import '../data/table_move_repository.dart';
import '../state/order_setup_controller.dart' show tablesProvider;
import '../state/order_sync_controller.dart';
import '../state/pos_sync_scope_provider.dart';
import '../state/table_move_controller.dart';

/// RESTAURANT-OPERATIONS-V1-001: the "Move to another table" sheet for an
/// ACTIVE DINE-IN order.
///
/// Shows the branch's live tables (with honest derived occupancy counts), lets
/// the cashier pick a target, and pushes the SERVER-AUTHORITATIVE
/// `order.table_move` op. On success the order's authoritative snapshot is
/// re-fetched BEFORE the sheet closes, so the row behind it already names the
/// new table. The refusals follow the established conflict discipline: a
/// revision conflict or a terminal order RETIRES the sheet (Confirm becomes
/// Close — no blind retry over stale state); a vanished target table refreshes
/// the list and lets the cashier deliberately pick again.
class MoveTableSheet extends ConsumerStatefulWidget {
  const MoveTableSheet({required this.order, super.key});

  final PosRecentOrder order;

  static Future<void> show(
    BuildContext context, {
    required PosRecentOrder order,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => MoveTableSheet(order: order),
  );

  @override
  ConsumerState<MoveTableSheet> createState() => _MoveTableSheetState();
}

class _MoveTableSheetState extends ConsumerState<MoveTableSheet> {
  String? _selectedTableId;
  String? _selectedTableLabel;
  bool _submitting = false;
  String? _error;

  /// Set on the refusals no retry from THIS sheet can satisfy (conflict /
  /// order_not_movable): the sheet holds a stale picture and retires —
  /// Confirm is replaced by Close (the POS-OPERATIONS-SYNC-001 discipline).
  bool _staleAfterRefusal = false;

  Future<void> _submit(AppLocalizations l10n) async {
    if (_submitting || _staleAfterRefusal) return;
    final tableId = _selectedTableId;
    final tableLabel = _selectedTableLabel;
    if (tableId == null || tableLabel == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // CAPTURED BEFORE THE AWAIT — the sheet is dismissible while the move is in
    // flight; the data work must complete on notifiers that outlive it.
    // `mounted` gates ONLY setState / pop / snackbars.
    final moves = ref.read(posMoveTableRepositoryProvider);
    final sync = ref.read(posOrderSyncControllerProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    // The scope this move is submitted IN. A result landing after a pairing
    // change belongs to the ORIGINAL scope — nothing is merged into the new one
    // (it reconciles from its own authoritative feed).
    final scopeKey = container.read(posSyncScopeProvider)?.key;
    bool scopeMoved() => container.read(posSyncScopeProvider)?.key != scopeKey;
    try {
      final result = await moves.moveTable(
        orderId: widget.order.orderId ?? '',
        tableId: tableId,
        tableLabel: tableLabel,
        // The AUTHORITATIVE revision this move is made against — another
        // device's payment/void/bump in the window is a typed conflict, never
        // a silent overwrite.
        expectedRevision: widget.order.revision,
      );
      if (scopeMoved()) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      // The server confirmed the move. Take the authoritative snapshot BEFORE
      // closing, so the row behind the sheet already names the new table.
      await _reconcile(sync);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posMoveTableMoved(result.tableLabel))),
      );
    } on MoveTableException catch (e) {
      // A conflict or a terminal order means OUR picture of the order is wrong:
      // reconcile so the truth is on screen behind the sheet, then retire it.
      // A vanished TARGET table is different — the ORDER is exactly as we
      // thought; refresh the table list and let the cashier pick again.
      if ((e.conflict || e.notMovable || e.notAllowed) && !scopeMoved()) {
        await _reconcile(sync);
      }
      if (e.tableUnavailable) container.invalidate(tablesProvider);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _staleAfterRefusal = e.conflict || e.notMovable || e.notAllowed;
        if (e.tableUnavailable) {
          _selectedTableId = null;
          _selectedTableLabel = null;
        }
        _error = switch (e) {
          MoveTableException(conflict: true) => l10n.posMoveTableConflict,
          MoveTableException(notMovable: true) ||
          MoveTableException(notAllowed: true) => l10n.posMoveTableNotMovable,
          MoveTableException(tableUnavailable: true) =>
            l10n.posMoveTableTableUnavailable,
          MoveTableException(permissionDenied: true) =>
            l10n.posMoveTablePermissionDenied,
          _ => l10n.posMoveTableFailed,
        };
      });
    }
  }

  /// Pulls the authoritative snapshot for THIS order through the CAPTURED
  /// coordinator. Never throws — a failed refresh must not turn a successful
  /// move into an error the cashier sees.
  Future<void> _reconcile(PosOrderSyncController sync) async {
    final orderId = widget.order.orderId;
    if (orderId == null || orderId.isEmpty) return;
    await sync.refreshOrders(<String>[orderId]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tables = ref.watch(tablesProvider);
    final currentLabel = widget.order.tableLabel?.trim();
    final danger = RestoflowTone.danger.styleOf(theme).accent;

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('move-table-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.posMoveTableTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        // The order being moved + where it sits NOW. A legacy
                        // dine-in row may honestly have no table yet — the move
                        // doubles as the assign/recovery path.
                        currentLabel == null || currentLabel.isEmpty
                            ? '${widget.order.orderNumber} · ${l10n.posMoveTableNoTable}'
                            : '${widget.order.orderNumber} · ${l10n.posMoveTableCurrent(currentLabel)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Flexible(
              child: tables.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(RestoflowSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => RestoflowStateView(
                  icon: Icons.table_restaurant_outlined,
                  title: l10n.posTablesError,
                ),
                data: (list) => _TableGrid(
                  l10n: l10n,
                  tables: list,
                  currentLabel: currentLabel,
                  selectedId: _selectedTableId,
                  enabled: !_submitting && !_staleAfterRefusal,
                  onSelect: (t) => setState(() {
                    _selectedTableId = t.tableId;
                    _selectedTableLabel = t.label;
                    _error = null;
                  }),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                key: const Key('move-table-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: RestoflowIconSizes.sm,
                    color: danger,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _staleAfterRefusal
                  // RETIRED — the picture this sheet holds is the one the
                  // server just refused. Acknowledge and act again from the
                  // refreshed order.
                  ? FilledButton.icon(
                      key: const Key('move-table-close-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.posOrdersConflictClose),
                      style: RestoflowButtonStyles.big(context),
                    )
                  : FilledButton.icon(
                      key: const Key('move-table-confirm-button'),
                      onPressed: _submitting || _selectedTableId == null
                          ? null
                          : () => _submit(l10n),
                      icon: _submitting
                          ? const RestoflowInlineSpinner()
                          : const Icon(Icons.swap_horiz),
                      label: Text(l10n.posMoveTableConfirm),
                      style: RestoflowButtonStyles.big(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The target grid: every live table of the branch. Manual floor blocks
/// (out-of-service) are not offered; an OCCUPIED table IS — parties merge onto
/// one table in real restaurants, and the server allows it — with its honest
/// open-order count shown. The order's CURRENT table is marked and disabled
/// (a same-table move is a no-op the cashier does not need).
class _TableGrid extends StatelessWidget {
  const _TableGrid({
    required this.l10n,
    required this.tables,
    required this.currentLabel,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final List<DemoTable> tables;
  final String? currentLabel;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<DemoTable> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = [
      for (final t in tables)
        if (t.status != TableStatusKind.blocked) t,
    ];
    if (candidates.isEmpty) {
      return RestoflowStateView(
        icon: Icons.table_restaurant_outlined,
        title: l10n.posTablesEmpty,
      );
    }
    return SingleChildScrollView(
      child: Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.sm,
        children: [
          for (final t in candidates)
            _TableTile(
              l10n: l10n,
              table: t,
              isCurrent: currentLabel != null && t.label == currentLabel,
              selected: t.tableId == selectedId,
              enabled: enabled,
              theme: theme,
              onSelect: onSelect,
            ),
        ],
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.l10n,
    required this.table,
    required this.isCurrent,
    required this.selected,
    required this.enabled,
    required this.theme,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final DemoTable table;
  final bool isCurrent;
  final bool selected;
  final bool enabled;
  final ThemeData theme;
  final ValueChanged<DemoTable> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final canPick = enabled && !isCurrent;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, minHeight: 64),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : isCurrent
            ? scheme.surfaceContainerHighest
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('move-table-tile-${table.tableId}'),
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          onTap: canPick ? () => onSelect(table) : null,
          child: Padding(
            padding: const EdgeInsets.all(RestoflowSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.table_restaurant_outlined,
                      size: RestoflowIconSizes.sm,
                      color: canPick
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: RestoflowSpacing.xs),
                    Text(
                      table.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: canPick
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (isCurrent)
                  Text(
                    l10n.posTableStatusSelected,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else if (table.activeOrderCount > 0)
                  // HONEST derived occupancy: the table already hosts live
                  // orders; picking it merges parties, and the cashier should
                  // know that before tapping.
                  Text(
                    l10n.posTableOpenOrders(table.activeOrderCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: RestoflowTone.warning.styleOf(theme).accent,
                    ),
                  )
                else if (table.status == TableStatusKind.occupied)
                  // STABILIZATION: a manual occupied/RESERVED floor state with
                  // no live order still deserves a cue — the server accepts
                  // the move, but the cashier must not pick a reserved table
                  // blind.
                  Text(
                    l10n.posTableStatusOccupied,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: RestoflowTone.warning.styleOf(theme).accent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
