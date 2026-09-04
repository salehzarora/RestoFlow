import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../data/order_actions.dart';
import '../data/order_actions_assembly.dart';
import '../data/order_snapshot.dart' show PosSettlement;
import '../data/recent_order.dart';
import '../state/order_sync_controller.dart'
    show orderSnapshotRepositoryProvider, posSyncClockProvider;
import '../state/order_setup_controller.dart' show tablesSnapshotProvider;
import 'order_action_row.dart';

/// STALE-TABLE-ORDER-RECOVERY-001 — the recovery path for ONE live order that
/// occupies a table.
///
/// The POS's recent-orders surface is a today+yesterday window (server
/// `pos_order_snapshots` window + local prune), so an unsettled order that
/// aged past yesterday used to be unreachable: the floor said "1 open order"
/// while nothing let the cashier identify, open, pay or cancel it. This sheet
/// closes that gap WITHOUT any new mutation:
///
///   1. the order is fetched BY ID (`fetchOrders` → `pos_order_snapshots`
///      with `p_order_ids`, which bypasses the window) and adopted exactly like
///      any other branch-discovered row ([PosRecentOrder.discovered]);
///   2. the shared [OrderActionRow] renders the CANONICAL operations the
///      session is allowed — pay (settles under the current open shift and
///      auto-completes) or cancel (void, unpaid + authorized) — through the
///      same policy every other order uses ([PosOrderActionsAssembly]);
///   3. when neither is allowed, the EXACT refusal is shown instead of a dead
///      end; a failed fetch is shown as a failed fetch, never as a fake order.
///
/// Occupancy is never edited here: the table frees as a CONSEQUENCE of the
/// order's own transition (derived occupancy), or not at all.
class TableOrderRecoverySheet extends ConsumerStatefulWidget {
  const TableOrderRecoverySheet({
    required this.table,
    required this.entry,
    super.key,
  });

  final DemoTable table;
  final PosTableActiveOrder entry;

  static Future<void> show(
    BuildContext context, {
    required DemoTable table,
    required PosTableActiveOrder entry,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TableOrderRecoverySheet(table: table, entry: entry),
  );

  @override
  ConsumerState<TableOrderRecoverySheet> createState() =>
      _TableOrderRecoverySheetState();
}

class _TableOrderRecoverySheetState
    extends ConsumerState<TableOrderRecoverySheet> {
  PosRecentOrder? _order;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref.read(orderSnapshotRepositoryProvider).fetchOrders(
        <String>[widget.entry.orderId],
      );
      PosRecentOrder? adopted;
      for (final snap in page.orders) {
        if (snap.orderId == widget.entry.orderId) {
          adopted = PosRecentOrder.discovered(snap);
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _order = adopted;
        _loading = false;
        // The floor counted it but the by-id read did not return it: say so.
        // Never synthesize an order from the floor summary.
        _failed = adopted == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _order = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  void _refreshFloor() {
    if (!mounted) return;
    // The snapshot provider is the fetcher; tablesProvider derives from it
    // (the same idiom the move-table and table-operations sheets use).
    ref.invalidate(tablesSnapshotProvider);
  }

  /// The EXACT reason nothing can be done here, by the state the server
  /// reported - never a generic shrug when the cause is known.
  ///   * terminal            -> already closed (the floor frees on refresh)
  ///   * served + settled    -> completion is the exit (Dashboard / Complete)
  ///   * paid, not served    -> the kitchen must bring it to served first
  ///   * zero-total (nothing to pay), nothing offered -> cancel if wrong,
  ///     otherwise it completes once served
  ///   * else                -> role / shift limits
  static String _refusal(AppLocalizations l10n, PosRecentOrder order) {
    if (order.isTerminal) return l10n.posTableRecoveryAlreadyClosed;
    // The SERVER's status for a discovered row (the local field is only what
    // this device was told, which for a by-id read is nothing).
    final served = order.serverStatus == 'served';
    switch (order.settlement) {
      case PosSettlement.paid:
        return served
            ? l10n.posTableRecoveryPaidNeedsCompletion
            : l10n.posTableRecoveryPaidAwaitingKitchen;
      case PosSettlement.notChargeable:
        return served
            ? l10n.posTableRecoveryPaidNeedsCompletion
            : l10n.posTableRecoveryNothingToPay;
      case PosSettlement.unpaid:
        return l10n.posTableRecoveryNoActions;
    }
  }

  /// A KNOWN-PAID snapshot is never offered Cancel: the server refuses it
  /// with order_has_completed_payment. A zero-total (not_chargeable) order
  /// has NO payment row, so the server accepts its void - the shared policy's
  /// verdict stands for it.
  static PosOrderActions _withoutVoidWhenSettled(
    PosOrderActions a,
    PosRecentOrder order,
  ) {
    if (order.settlement != PosSettlement.paid || !a.canVoid) return a;
    return PosOrderActions(
      canPay: a.canPay,
      canDiscount: a.canDiscount,
      canFullComp: a.canFullComp,
      canVoid: false,
      canMoveTable: a.canMoveTable,
      canOpenReceipt: a.canOpenReceipt,
      pendingKind: a.pendingKind,
      canAddItems: a.canAddItems,
      canComplete: a.canComplete,
      canPrintBill: a.canPrintBill,
      submitUnacknowledged: a.submitUnacknowledged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entry = widget.entry;
    final now = ref.watch(posSyncClockProvider)();
    final order = _order;
    final resolved = order == null
        ? null
        : PosOrderActionsAssembly.watch(ref, <PosRecentOrder>[
            order,
          ]).resolveFor(order);
    // The shared policy never denies on unknowns; here the by-id snapshot is
    // KNOWN, so a settled order must not be offered a Cancel the server would
    // refuse (order_has_completed_payment). The server stays authoritative.
    final actions = (resolved == null || order == null)
        ? null
        : _withoutVoidWhenSettled(resolved, order);
    final anyAction =
        actions != null &&
        (actions.canPay || actions.canVoid || actions.canComplete);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          RestoflowSpacing.md,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${l10n.posTableRecoveryTitle} · ${entry.orderCode}',
              key: const Key('table-recovery-title'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              tableActiveOrderSummary(
                l10n,
                entry,
                now,
                tableLabel: widget.table.label,
              ),
              key: const Key('table-recovery-summary'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(l10n.posTableRecoveryHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: RestoflowSpacing.md),
            if (_loading) ...[
              const LinearProgressIndicator(key: Key('table-recovery-loading')),
              const SizedBox(height: RestoflowSpacing.xs),
              Text(
                l10n.posTableRecoveryLoading,
                style: theme.textTheme.bodySmall,
              ),
            ] else if (_failed || order == null || actions == null) ...[
              RestoflowNoticeBanner(
                key: const Key('table-recovery-unavailable'),
                tone: RestoflowTone.warning,
                icon: Icons.cloud_off_outlined,
                body: l10n.posTableRecoveryUnavailable,
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton.icon(
                  key: const Key('table-recovery-retry'),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.posTableRecoveryRetry),
                ),
              ),
            ] else ...[
              // The CANONICAL operations, through the shared policy + row.
              OrderActionRow(
                order: order,
                l10n: l10n,
                actions: actions,
                keyPrefix: 'table-recovery',
                // A settlement frees the table as a CONSEQUENCE: refresh the
                // floor read model and leave; the operations sheet beneath
                // re-resolves its row from that model.
                onPaymentSuccess: () {
                  _refreshFloor();
                  if (mounted) Navigator.of(context).maybePop();
                },
                // Whatever the cancel sheet did, re-read the truth by id (a
                // voided order comes back terminal) and refresh the floor.
                onCancelClosed: () {
                  _refreshFloor();
                  _load();
                },
                // The printer-only Complete safety net is the third canonical
                // exit: re-read by id (a completed order comes back terminal)
                // and refresh the floor, exactly like the other two.
                onCompleteFinished: () {
                  _refreshFloor();
                  _load();
                },
              ),
              if (!anyAction) ...[
                const SizedBox(height: RestoflowSpacing.sm),
                RestoflowNoticeBanner(
                  key: const Key('table-recovery-no-actions'),
                  tone: RestoflowTone.info,
                  icon: Icons.lock_outline,
                  body: _refusal(l10n, order),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The elapsed age of an occupying order, in the coarse units a cashier
/// scans a floor with (minutes → whole hours → days + hours).
String tableOrderAgeLabel(AppLocalizations l10n, Duration age) {
  final clamped = age.isNegative ? Duration.zero : age;
  if (clamped.inHours < 1)
    return l10n.posTableOrderAgeMinutes(clamped.inMinutes);
  if (clamped.inDays < 1) return l10n.posTableOrderAgeHours(clamped.inHours);
  return l10n.posTableOrderAgeDays(clamped.inDays, clamped.inHours % 24);
}

/// The localized status of an occupying order (the shared order-status keys;
/// a takeaway served row reads "picked up", as everywhere else).
String tableOrderStatusLabel(AppLocalizations l10n, PosTableActiveOrder e) =>
    switch (e.status) {
      'submitted' => l10n.ordersStatusSubmitted,
      'accepted' => l10n.ordersStatusAccepted,
      'preparing' => l10n.ordersStatusPreparing,
      'ready' => l10n.ordersStatusReady,
      'served' =>
        e.orderType == 'takeaway'
            ? l10n.ordersStatusPickedUp
            : l10n.ordersStatusServed,
      _ => e.status,
    };

/// The settlement word for an occupying order — the server's three honest
/// states, never a client guess.
String tableOrderPaymentLabel(AppLocalizations l10n, PosTableActiveOrder e) =>
    e.isNotChargeable
    ? l10n.posTableOrderNotChargeable
    : (e.isPaid ? l10n.posTableOrderPaid : l10n.posTableOrderUnpaid);

/// One-line summary: status · age · payment (· shift closed) for a floor row
/// or the recovery sheet header.
String tableActiveOrderSummary(
  AppLocalizations l10n,
  PosTableActiveOrder e,
  DateTime now, {
  String? tableLabel,
}) {
  final parts = <String>[
    if (tableLabel != null && tableLabel.isNotEmpty)
      '${l10n.posTableLabel} $tableLabel',
    tableOrderStatusLabel(l10n, e),
    tableOrderAgeLabel(l10n, now.toUtc().difference(e.createdAt)),
    tableOrderPaymentLabel(l10n, e),
    if (e.originatingShiftClosed) l10n.posTableOrderShiftClosed,
  ];
  return parts.join(' · ');
}
