import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../data/table_operations_repository.dart';
import '../state/discount_controller.dart' show staffCapabilitiesProvider;
import '../state/order_setup_controller.dart';
import '../state/table_operations_controller.dart'
    show tableOperationsRepositoryProvider;
import 'table_operations_sheet.dart';
import 'table_picker_sheet.dart'
    show TableGroupCardData, compareTablesByLabelThenId, localizedTableArea;

/// PSC-001B — the linked-group detail sheet, opened from a combined group card
/// in the table picker.
///
/// Shows the group's members SEPARATELY — each physical table with its OWN
/// area, its OWN effective state and its OWN active-order count (the member
/// truth, not the group projection), so it stays clear which physical table
/// owns which activity. Starting a NEW order requires an EXPLICIT member
/// choice here: selection is offered only for members the existing canonical
/// assignment rules allow ([DemoTable.isAssignable] — the group-projected A4
/// rule, unchanged), there is no anchor table and no automatic pick, and the
/// value handed back is always ONE physical table. Unlink reuses the existing
/// server-authoritative write path (`table.unlink` via sync_push), gated by
/// `manage_table_operations`, with honest pending/error states — orders are
/// never merged or mutated by anything in this sheet.
class TableGroupDetailSheet extends ConsumerStatefulWidget {
  const TableGroupDetailSheet({
    required this.group,
    required this.allTables,
    required this.onSelectMember,
    super.key,
  });

  final TableGroupCardData group;

  /// The full (projected) branch table list at open time — handed to the
  /// per-member [TableOperationsSheet] so its link-candidate filtering stays
  /// honest, exactly as the long-press path always did.
  final List<DemoTable> allTables;

  /// Invoked AFTER this sheet pops, with the explicitly chosen physical member.
  final void Function(DemoTable member) onSelectMember;

  static Future<void> show(
    BuildContext context, {
    required TableGroupCardData group,
    required List<DemoTable> allTables,
    required void Function(DemoTable member) onSelectMember,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TableGroupDetailSheet(
      group: group,
      allTables: allTables,
      onSelectMember: onSelectMember,
    ),
  );

  @override
  ConsumerState<TableGroupDetailSheet> createState() =>
      _TableGroupDetailSheetState();
}

class _TableGroupDetailSheetState extends ConsumerState<TableGroupDetailSheet> {
  bool _submitting = false;
  String? _errorCode;

  TableGroupCardData get _group => widget.group;

  /// PSC-001B correction 1: the freshest projected member list. Re-derived from
  /// the live [tablesProvider] data whenever available — so a status change made
  /// in the per-member management sheet is reflected here on return (the ops
  /// sheet already invalidates the provider on success). Falls back to the
  /// open-time snapshot while loading or when the group can no longer be
  /// resolved to >= 2 members (the documented snapshot limitation, unchanged).
  List<DemoTable> _resolveMembers(List<DemoTable>? live) {
    if (live == null) return _group.members;
    final members = [
      for (final t in live)
        if (t.groupId == _group.groupId) t,
    ]..sort(compareTablesByLabelThenId);
    return members.length >= 2 ? members : _group.members;
  }

  /// PSC-001B correction 1: opens the EXISTING shipped management surface for
  /// ONE physical member — the same TableOperationsSheet the long-press path
  /// uses, with the same repository, capability enforcement, typed errors,
  /// offline honesty, and audit behavior. Nothing here assigns a table, and no
  /// status logic is duplicated. On return this sheet rebuilds from the
  /// provider the ops sheet invalidated.
  Future<void> _manage(DemoTable member) => TableOperationsSheet.show(
    context,
    table: member,
    allTables: widget.allTables,
  );

  void _select(DemoTable member) {
    // Defence in depth: the button/tap is only offered for assignable members,
    // and OrderSetupController.assignTable re-checks assignability anyway.
    if (_submitting || !member.isAssignable) return;
    Navigator.of(context).pop();
    widget.onSelectMember(member);
  }

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
    if (ok != true || !mounted) return;
    setState(() {
      _submitting = true;
      _errorCode = null;
    });
    try {
      // The existing server-authoritative unlink: dissolving the group from any
      // member dissolves it for all (orders untouched). No new write path. The
      // member id is resolved from the freshest available list.
      await ref
          .read(tableOperationsRepositoryProvider)
          .unlink(
            tableId: _resolveMembers(
              ref.read(tablesProvider).valueOrNull,
            ).first.tableId,
          );
      ref.invalidate(tablesProvider); // reconcile from the authoritative read
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

  String _errorMessage(AppLocalizations l10n, String code) => switch (code) {
    'offline' => l10n.posTableStatusOffline,
    'permission_denied' => l10n.posTableRequiresPermission,
    'table_in_use' => l10n.posTableOccupiedByOrder,
    _ => l10n.posTableUnlinkFailed,
  };

  String _stateLabel(AppLocalizations l10n, String state) => switch (state) {
    'available' => l10n.posTableStateAvailable,
    'reserved' => l10n.posTableStateReserved,
    'occupied' => l10n.posTableStateOccupied,
    'out_of_service' => l10n.posTableStateOutOfService,
    // Fail-closed honesty: an unknown state is surfaced as blocked, never as
    // free capacity and never as raw backend text.
    _ => l10n.posTableStatusBlocked,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Live members (correction 1): watching the provider makes this sheet
    // reconcile through the SAME invalidation seam the operations sheet and
    // the picker already use.
    final members = _resolveMembers(ref.watch(tablesProvider).valueOrNull);
    final anyAssignable = members.any((m) => m.isAssignable);
    final canManage =
        ref
            .watch(staffCapabilitiesProvider)
            .valueOrNull
            ?.manageTableOperations ??
        false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    '${l10n.posTableGroupDetailTitle} · ${members.map((m) => m.label).join(l10n.posTableGroupJoiner)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            // Group-wide truth: the fused (most restrictive) state + the total
            // active-order count across the members.
            _kv(
              theme,
              l10n.posTableEffectiveStatus,
              _stateLabel(l10n, members.first.effectiveState),
              key: const Key('group-detail-effective'),
            ),
            _kv(
              theme,
              l10n.posTableActiveOrders,
              l10n.posTableOpenOrders(members.first.activeOrderCount),
              key: const Key('group-detail-active-orders'),
            ),
            const Divider(),
            Text(
              l10n.posTableGroupMembers,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            if (anyAssignable)
              Text(
                l10n.posTableGroupChoosePrompt,
                key: const Key('group-choose-prompt'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              RestoflowNoticeBanner(
                key: const Key('group-no-assignable'),
                tone: RestoflowTone.info,
                icon: Icons.info_outline,
                body: l10n.posTableGroupNoAssignable,
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in members)
                    ListTile(
                      key: Key('group-member-${m.tableId}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_seat),
                      title: Text(m.label),
                      // The member's OWN truth (area · own state · own orders),
                      // so which physical table owns which activity stays clear.
                      subtitle: Text(
                        _memberSubtitle(l10n, m),
                        key: Key('group-member-state-${m.tableId}'),
                      ),
                      // PSC-001B correction 1: per-member management for an
                      // operator the server says holds manage_table_operations
                      // — INDEPENDENT of assignability (an occupied member is
                      // not selectable for a new order but stays manageable).
                      // Without the capability the control is not built at all
                      // (no hidden semantics/tap action). Selection remains
                      // governed solely by assignability.
                      trailing: (canManage || m.isAssignable)
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canManage)
                                  IconButton(
                                    key: Key(
                                      'group-member-manage-${m.tableId}',
                                    ),
                                    tooltip: l10n.posTableOperations,
                                    icon: const Icon(Icons.tune),
                                    onPressed: _submitting
                                        ? null
                                        : () => _manage(m),
                                  ),
                                if (m.isAssignable)
                                  FilledButton.tonal(
                                    key: Key(
                                      'group-member-select-${m.tableId}',
                                    ),
                                    onPressed: _submitting
                                        ? null
                                        : () => _select(m),
                                    child: Text(l10n.posTableGroupSelectAction),
                                  ),
                              ],
                            )
                          : null,
                      enabled: !_submitting,
                      onTap: m.isAssignable && !_submitting
                          ? () => _select(m)
                          : null,
                    ),
                ],
              ),
            ),
            if (canManage) ...[
              const Divider(),
              ListTile(
                key: const Key('group-unlink'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  Icons.link_off,
                  color: RestoflowTone.neutral.styleOf(theme).accent,
                ),
                title: Text(l10n.posTableUnlink),
                enabled: !_submitting,
                onTap: _submitting ? null : _unlink,
              ),
            ],
            if (_submitting)
              const Padding(
                key: Key('group-detail-submitting'),
                padding: EdgeInsets.only(top: RestoflowSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
                child: RestoflowNoticeBanner(
                  key: const Key('group-detail-error'),
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

  /// "Main · Available · 2 open orders" — area, the member's OWN state, and the
  /// member's OWN order count (omitted at zero). The separator matches the
  /// existing table-operations title convention.
  String _memberSubtitle(AppLocalizations l10n, DemoTable m) {
    final parts = <String>[
      localizedTableArea(_normalizedArea(m), l10n),
      _stateLabel(l10n, m.memberEffectiveState),
      if (m.memberActiveOrderCount > 0)
        l10n.posTableOpenOrders(m.memberActiveOrderCount),
    ];
    return parts.join(' · ');
  }

  /// The SAME null/empty fallback the picker layout uses.
  String _normalizedArea(DemoTable t) {
    final area = t.area;
    return (area == null || area.trim().isEmpty) ? 'Main' : area;
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
}
