import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions.dart';
import '../data/order_center_view.dart';
import '../data/order_identity.dart';
import '../data/order_reconciler.dart' show unpaidOrderCount;
import '../data/order_snapshot.dart';
import '../data/order_submission.dart' show OutboxEntry, OutboxSyncState;
import '../data/recent_order.dart';
import '../format/money_format.dart';
import '../print/native_print_bridges.dart' show posActivePrintBridgeProvider;
import '../state/discount_controller.dart';
import '../state/order_sync_controller.dart';
import '../state/outbox_controller.dart';
import '../state/receipt_print_controller.dart';
import '../state/recent_orders_controller.dart';
import 'cancel_order_sheet.dart';
import 'cash_payment_sheet.dart';
import 'discount_sheet.dart';
import 'move_table_sheet.dart';
import 'order_status_pills.dart';
import 'receipt_print_preview.dart';

/// POS-ORDERS-AND-PAYMENT-001: an app-bar button that opens the operational orders
/// surface, badged with the current unpaid count.
class RecentOrdersButton extends ConsumerWidget {
  const RecentOrdersButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final orders = ref.watch(posRecentOrdersControllerProvider);
    // ONE canonical predicate, shared with the controller's count and the sections.
    final unpaid = unpaidOrderCount(orders);
    final icon = IconButton(
      key: const Key('recent-orders-button'),
      tooltip: l10n.posOrdersCenterTitle,
      icon: const Icon(Icons.receipt_long_outlined),
      onPressed: () => RecentOrdersSheet.show(context),
    );
    if (unpaid == 0) return icon;
    return Badge.count(count: unpaid, child: icon);
  }
}

/// POS-OPERATIONS-SYNC-001 (Commit 3) — THE OPERATIONAL ORDERS CENTRE.
///
/// It was a device diary: "the orders THIS till submitted", with no live status and
/// no idea what the server thought. It is now a BRANCH view — the orders that are
/// actually happening in this restaurant right now, whichever till took them —
/// grouped by what the cashier needs to DO about them.
///
/// Everything shown is authoritative: the money, the status and the settlement all
/// come from the server. Every action offered is decided by ONE eligibility policy
/// (`order_actions.dart`), so a button that cannot work is never drawn.
class RecentOrdersSheet extends ConsumerStatefulWidget {
  const RecentOrdersSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const RecentOrdersSheet(),
  );

  @override
  ConsumerState<RecentOrdersSheet> createState() => _RecentOrdersSheetState();
}

class _RecentOrdersSheetState extends ConsumerState<RecentOrdersSheet> {
  PosOrderSection _section = PosOrderSection.open;
  PosSettlementFilter _settlement = PosSettlementFilter.all;
  PosOrderTypeFilter _type = PosOrderTypeFilter.all;
  PosOrderSort _sort = PosOrderSort.newestFirst;
  String? _status;
  String _query = '';

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  /// Held so [dispose] can release the consumer WITHOUT touching `ref` — Riverpod
  /// forbids a ref read after disposal, and a "stop polling" that throws on the way
  /// out would leave the timer running forever.
  PosOrderSyncController? _sync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = ref.read(posOrderSyncControllerProvider.notifier);
      _sync = sync;
      sync.addVisibleConsumer();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    // The tick STOPS with the sheet. Nothing keeps polling behind a closed screen.
    _sync?.removeVisibleConsumer();
    super.dispose();
  }

  /// DEBOUNCED. Search runs over the loaded authoritative set, so it costs nothing
  /// to run — but re-filtering and rebuilding a long list on every keystroke makes a
  /// cheap tablet feel broken, which is its own kind of lie about the software.
  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final orders = ref.watch(posRecentOrdersControllerProvider);
    final status = ref.watch(posOrderSyncControllerProvider);
    // EFFECTIVE rights, or null when UNKNOWN. Unknown is NOT denied — a failed probe
    // must not silently strip a manager of the ability to discount; the server
    // refuses correctly either way.
    final caps = ref.watch(staffCapabilitiesProvider).value;
    final entries = ref.watch(outboxControllerProvider);

    // The local queue, joined by ORDER IDENTITY. It reports what THIS DEVICE is doing —
    // never what the ORDER is doing. Conflating the two is what made a queued
    // payment look like a lifecycle state.
    //
    // Joined on the code, this map put one order's "syncing" badge on a DIFFERENT order
    // that happened to share it — and, through `resolveOrderActions`, withdrew that
    // innocent order's controls as though it had work in flight.
    final pendingByIdentity = <String, PosPendingKind>{
      for (final e in entries)
        if (e.syncState.isPending) _entryIdentity(e).key: PosPendingKind.submit,
    };

    final counts = sectionCounts(orders);
    final visible = viewOrders(
      orders,
      section: _section,
      settlement: _settlement,
      type: _type,
      status: _status,
      query: _query,
      sort: _sort,
    );

    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= RestoflowBreakpoints.posTwoPane;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const Key('recent-orders-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(l10n: l10n, status: status, theme: theme),
          const SizedBox(height: RestoflowSpacing.sm),
          _SectionTabs(
            l10n: l10n,
            selected: _section,
            counts: counts,
            // The counts describe what is LOADED. While more history remains we do
            // not pretend otherwise — see the '+' in the chip.
            partial: status.hasMoreHistory,
            onSelect: (s) => setState(() => _section = s),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          _SearchField(
            l10n: l10n,
            controller: _search,
            onChanged: _onQuery,
            onClear: _clearSearch,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          _Filters(
            l10n: l10n,
            settlement: _settlement,
            type: _type,
            status: _status,
            sort: _sort,
            onSettlement: (s) => setState(() => _settlement = s),
            onType: (t) => setState(() => _type = t),
            onStatus: (s) => setState(() => _status = s),
            onSort: (s) => setState(() => _sort = s),
          ),
          if (status.error == PosSyncError.offline) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            _OfflineBanner(l10n: l10n, theme: theme),
          ],
          const SizedBox(height: RestoflowSpacing.md),
          Flexible(
            child: visible.isEmpty
                ? _EmptyState(
                    l10n: l10n,
                    section: _section,
                    searching: _query.trim().isNotEmpty,
                    offlineNoData:
                        status.error == PosSyncError.offline && orders.isEmpty,
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: visible.length + (status.hasMoreHistory ? 1 : 0),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: RestoflowSpacing.sm),
                    itemBuilder: (context, i) {
                      if (i == visible.length) {
                        return _LoadMoreButton(l10n: l10n, status: status);
                      }
                      final o = visible[i];
                      return _OrderCard(
                        order: o,
                        l10n: l10n,
                        isWide: isWide,
                        actions: resolveOrderActions(
                          o,
                          capabilities: caps,
                          pending: pendingByIdentity[o.identity.key],
                        ),
                        outboxState: _outboxStateFor(entries, o.identity),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  OutboxSyncState? _outboxStateFor(
    List<OutboxEntry> entries,
    PosOrderIdentity identity,
  ) {
    for (final e in entries) {
      if (_entryIdentity(e) == identity) return e.syncState;
    }
    return null;
  }
}

/// The IDENTITY of the order an outbox entry submitted.
///
/// `targetId` is the client-generated order id the server adopts, so a queued submit
/// resolves to the SAME identity as the recent-order row it created — and never to a
/// different order that merely shares its printed code.
PosOrderIdentity _entryIdentity(OutboxEntry e) => PosOrderIdentity.of(
  orderId: e.targetId,
  localOperationId: e.localOperationId,
  orderNumber: e.summary.orderNumber,
);

// ---------------------------------------------------------------------------
// Header — title + honest sync status. Never the words "live" or "real-time":
// we poll on a timer, and claiming otherwise would be a promise we do not keep.
// ---------------------------------------------------------------------------
class _Header extends ConsumerWidget {
  const _Header({
    required this.l10n,
    required this.status,
    required this.theme,
  });

  final AppLocalizations l10n;
  final PosSyncStatus status;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String subtitle;
    if (status.isSyncing) {
      subtitle = l10n.posOrdersSyncing;
    } else if (status.error == PosSyncError.offline) {
      subtitle = l10n.posOrdersOffline;
    } else if (status.lastSyncedAt != null) {
      subtitle = l10n.posOrdersLastUpdated(_hhmm(status.lastSyncedAt!));
    } else {
      subtitle = l10n.posRecentOrdersWindow;
    }

    return Row(
      children: [
        Icon(Icons.receipt_long_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.posOrdersCenterTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                key: const Key('orders-sync-status'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (status.isSyncing)
          const Padding(
            padding: EdgeInsetsDirectional.only(end: RestoflowSpacing.sm),
            child: SizedBox(
              key: Key('orders-syncing-indicator'),
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          key: const Key('orders-refresh-button'),
          tooltip: l10n.posOrdersRefresh,
          icon: const Icon(Icons.refresh),
          // MANUAL refresh goes through the coordinator like everything else, so it
          // cannot race the periodic tick — a second caller joins the one in flight.
          onPressed: () =>
              ref.read(posOrderSyncControllerProvider.notifier).refreshWindow(),
        ),
      ],
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.l10n,
    required this.selected,
    required this.counts,
    required this.partial,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final PosOrderSection selected;
  final Map<PosOrderSection, int> counts;
  final bool partial;
  final ValueChanged<PosOrderSection> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final s in PosOrderSection.values) ...[
          ChoiceChip(
            key: Key('orders-section-${s.name}'),
            // The count is of what is LOADED. While older pages remain we mark it
            // with '+' rather than presenting a page total as a branch total.
            label: Text(
              '${_sectionLabel(l10n, s)} (${counts[s] ?? 0}${partial ? '+' : ''})',
            ),
            selected: selected == s,
            onSelected: (_) => onSelect(s),
          ),
          const SizedBox(width: RestoflowSpacing.xs),
        ],
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.l10n,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final AppLocalizations l10n;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('orders-search-field'),
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      isDense: true,
      hintText: l10n.posOrdersSearchHint,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              key: const Key('orders-search-clear'),
              tooltip: l10n.posOrdersSearchClear,
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
      border: const OutlineInputBorder(),
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.l10n,
    required this.settlement,
    required this.type,
    required this.status,
    required this.sort,
    required this.onSettlement,
    required this.onType,
    required this.onStatus,
    required this.onSort,
  });

  final AppLocalizations l10n;
  final PosSettlementFilter settlement;
  final PosOrderTypeFilter type;
  final String? status;
  final PosOrderSort sort;
  final ValueChanged<PosSettlementFilter> onSettlement;
  final ValueChanged<PosOrderTypeFilter> onType;
  final ValueChanged<String?> onStatus;
  final ValueChanged<PosOrderSort> onSort;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: RestoflowSpacing.xs,
    runSpacing: RestoflowSpacing.xs,
    children: [
      // SETTLEMENT — EXACT. "Paid" means paid; it does NOT quietly include a comp.
      // Nobody handed over money for a comped order, and a cashier reconciling a
      // drawer must not be sent hunting for cash that was never taken.
      for (final f in PosSettlementFilter.values)
        FilterChip(
          key: Key('orders-settlement-${f.name}'),
          label: Text(_settlementLabel(l10n, f)),
          selected: settlement == f,
          onSelected: (_) => onSettlement(f),
        ),
      const SizedBox(width: RestoflowSpacing.sm),
      // ORDER TYPE - EXACT, like settlement (RESTAURANT-OPERATIONS-V1-001).
      for (final t in PosOrderTypeFilter.values)
        FilterChip(
          key: Key('orders-type-' + t.name),
          label: Text(_typeLabel(l10n, t)),
          selected: type == t,
          onSelected: (_) => onType(t),
        ),
      const SizedBox(width: RestoflowSpacing.sm),
      for (final s in <String?>[
        null,
        ...kPosOpenStatuses,
        ...kPosTerminalStatuses,
      ])
        if (s != null)
          FilterChip(
            key: Key('orders-status-$s'),
            label: Text(orderStatusLabel(l10n, s)),
            selected: status == s,
            onSelected: (sel) => onStatus(sel ? s : null),
          ),
      const SizedBox(width: RestoflowSpacing.sm),
      FilterChip(
        key: const Key('orders-sort-toggle'),
        label: Text(
          sort == PosOrderSort.newestFirst
              ? l10n.posOrdersSortNewest
              : l10n.posOrdersSortOldest,
        ),
        selected: sort == PosOrderSort.oldestFirst,
        onSelected: (_) => onSort(
          sort == PosOrderSort.newestFirst
              ? PosOrderSort.oldestFirst
              : PosOrderSort.newestFirst,
        ),
      ),
    ],
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.l10n, required this.theme});

  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tone = RestoflowTone.warning.styleOf(theme);
    return Container(
      key: const Key('orders-offline-banner'),
      padding: const EdgeInsets.all(RestoflowSpacing.sm),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: tone.accent),
          const SizedBox(width: RestoflowSpacing.sm),
          // The rows STAY. Stale-but-labelled beats a blank screen that looks like
          // the orders were lost.
          Expanded(
            child: Text(
              l10n.posOrdersOffline,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends ConsumerWidget {
  const _LoadMoreButton({required this.l10n, required this.status});

  final AppLocalizations l10n;
  final PosSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
    child: OutlinedButton.icon(
      key: const Key('orders-load-more'),
      onPressed: status.isLoadingMore
          ? null
          : () => ref.read(posOrderSyncControllerProvider.notifier).loadMore(),
      icon: status.isLoadingMore
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.history, size: 18),
      label: Text(l10n.posOrdersLoadMore),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.l10n,
    required this.section,
    required this.searching,
    required this.offlineNoData,
  });

  final AppLocalizations l10n;
  final PosOrderSection section;
  final bool searching;
  final bool offlineNoData;

  @override
  Widget build(BuildContext context) {
    final String title;
    if (offlineNoData) {
      title = l10n.posOrdersEmptyOffline;
    } else if (searching) {
      title = l10n.posOrdersSearchEmpty;
    } else {
      title = switch (section) {
        PosOrderSection.open => l10n.posOrdersEmptyOpen,
        PosOrderSection.needsPayment => l10n.posOrdersEmptyNeedsPayment,
        PosOrderSection.completedRecently => l10n.posOrdersEmptyCompleted,
        PosOrderSection.all => l10n.posRecentEmpty,
      };
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xl),
      child: RestoflowStateView(
        key: const Key('recent-orders-empty'),
        icon: Icons.receipt_long_outlined,
        title: title,
        message: l10n.posRecentEmptyHint,
      ),
    );
  }
}

/// One order. It says what the order IS (status, settlement, total) and — separately
/// — what THIS DEVICE is doing about it (a queued payment is not a lifecycle state).
class _OrderCard extends ConsumerWidget {
  const _OrderCard({
    required this.order,
    required this.l10n,
    required this.actions,
    required this.isWide,
    required this.outboxState,
  });

  final PosRecentOrder order;
  final AppLocalizations l10n;
  final PosOrderActions actions;
  final bool isWide;
  final OutboxSyncState? outboxState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverStatus = order.serverStatus;

    final meta = <String>[
      // The order TYPE, always visible (RESTAURANT-OPERATIONS-V1-001): a floor
      // under rush must tell a table order from a counter pickup at a glance.
      if (order.orderType case final t?)
        t == OrderType.dineIn
            ? l10n.posOrderTypeDineIn
            : l10n.posOrderTypeTakeaway,
      if (order.tableLabel case final t? when t.trim().isNotEmpty)
        '${l10n.posTableLabel} $t',
      if (order.order?.customerName case final c? when c.trim().isNotEmpty) c,
      if (order.origin == PosOrderOrigin.branchDiscovered)
        l10n.posOrdersOtherTill,
    ].join(' · ');

    return Container(
      key: Key('recent-order-${order.orderNumber}'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.orderNumber,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Text(
                          _hhmm(order.sortAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(
                // AUTHORITATIVE money. This is the "stale 40" fix, at the pixel.
                MoneyFormatter.formatMinor(
                  order.grandTotalMinor,
                  order.currencyCode,
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.xs,
            runSpacing: RestoflowSpacing.xs,
            children: [
              // A3: a PERMANENTLY-REJECTED submit created no server order. It shows ONE
              // honest "Not created" marker instead of a lifecycle/settlement that would
              // imply a real order — and it carries no actions (the policy fails closed).
              if (order.isNeverCreated)
                RestoflowStatusPill(
                  key: Key('recent-not-created-${order.orderNumber}'),
                  label: l10n.posRecentOrderNotCreated,
                  tone: RestoflowTone.danger,
                  icon: Icons.error_outline,
                )
              else
                // LIFECYCLE + SETTLEMENT, from the ONE shared vocabulary both order
                // surfaces speak (see order_status_pills.dart). The confirmation screen
                // renders exactly these.
                OrderStatusPills(
                  serverStatus: serverStatus,
                  settlement: order.settlement,
                  keySuffix: order.orderNumber,
                  // A takeaway's `served` reads "Picked up" - same state machine,
                  // honest operational words (RESTAURANT-OPERATIONS-V1-001).
                  orderType: order.orderType,
                ),
              // THIS DEVICE's queued work — reported SEPARATELY from the lifecycle.
              // "My payment is syncing" is a fact about this till, not the order.
              if (actions.pendingKind case final p?)
                RestoflowStatusPill(
                  key: Key('order-pending-${order.orderNumber}'),
                  label: _pendingLabel(l10n, p),
                  tone: RestoflowTone.info,
                  icon: Icons.sync,
                ),
              if (outboxState != null && outboxState!.isFailed)
                RestoflowStatusPill(
                  label: l10n.posRecentSyncFailed,
                  tone: RestoflowTone.danger,
                  icon: Icons.sync_problem,
                ),
            ],
          ),
          // A DEAD CONTROL WITH NO REASON IS WORSE THAN NO CONTROL. When an order is
          // still active but owes nothing, the missing Take-payment button needs an
          // explanation — otherwise the cashier just sees a button that "should be
          // there" and does not know why it is not.
          if (!order.isTerminal &&
              order.settlement == PosSettlement.notChargeable &&
              order.payment == null) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              key: Key('recent-nocharge-note-${order.orderNumber}'),
              l10n.posNoChargeNoPayment,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!actions.isEmpty) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            _ActionRow(order: order, l10n: l10n, actions: actions),
          ],
        ],
      ),
    );
  }
}

/// The trailing actions — EVERY one of them decided by the central policy. A control
/// that the server would refuse is not drawn at all: a button that always fails is a
/// lie, and under a lunch rush it is an expensive one.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({
    required this.order,
    required this.l10n,
    required this.actions,
  });

  final PosRecentOrder order;
  final AppLocalizations l10n;
  final PosOrderActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (actions.canPay) {
      children.add(
        _ActionButton(
          child: FilledButton.icon(
            key: Key('recent-pay-${order.orderNumber}'),
            onPressed: () => CashPaymentSheet.show(
              context,
              identity: order.identity,
              orderId: order.orderId,
              orderNumber: order.orderNumber,
              // AUTHORITATIVE total + revision. The sheet no longer receives the
              // submit-time figure it used to be handed.
              amountMinor: order.grandTotalMinor,
              currencyCode: order.currencyCode,
              expectedRevision: order.revision,
            ),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(l10n.posTakePayment),
          ),
        ),
      );
    }

    if (actions.canDiscount) {
      children.add(
        _ActionButton(
          child: OutlinedButton.icon(
            key: Key('recent-discount-${order.orderNumber}'),
            onPressed: () => DiscountSheet.show(
              context,
              orderId: order.orderId ?? '',
              subtotalMinor: order.subtotalMinor,
              taxTotalMinor: order.taxTotalMinor,
              currencyCode: order.currencyCode,
              expectedRevision: order.revision,
            ),
            icon: const Icon(Icons.percent, size: 18),
            label: Text(l10n.posApplyDiscount),
          ),
        ),
      );
    }

    if (actions.canVoid) {
      children.add(
        _ActionButton(
          child: OutlinedButton.icon(
            key: Key('recent-cancel-${order.orderNumber}'),
            onPressed: () => CancelOrderSheet.show(context, order: order),
            icon: const Icon(Icons.block, size: 18),
            label: Text(l10n.posCancelOrderAction),
            style: OutlinedButton.styleFrom(
              foregroundColor: RestoflowTone.danger.styleOf(theme).accent,
              side: BorderSide(
                color: RestoflowTone.danger.styleOf(theme).accent,
              ),
            ),
          ),
        ),
      );
    }

    if (actions.canMoveTable) {
      children.add(
        _ActionButton(
          child: OutlinedButton.icon(
            key: Key('recent-move-table-${order.orderNumber}'),
            onPressed: () => MoveTableSheet.show(context, order: order),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(l10n.posMoveTableAction),
          ),
        ),
      );
    }

    if (actions.canOpenReceipt) {
      children.add(
        _ActionButton(
          child: OutlinedButton.icon(
            key: Key('recent-reprint-${order.orderNumber}'),
            onPressed: () => _reprint(context, ref),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.posRecentReprintAction),
          ),
        ),
      );
      children.add(
        _ActionButton(
          child: TextButton.icon(
            key: Key('recent-view-${order.orderNumber}'),
            onPressed: () => ReceiptPrintPreview.show(
              context,
              order: order.order!,
              payment: order.payment!,
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(l10n.receiptPreviewTitle),
          ),
        ),
      );
    }

    // A WRAP, not a Row: on a phone the actions stack instead of being squeezed
    // below a usable touch target, and on a tablet they sit on one line.
    return Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.sm,
      children: children,
    );
  }

  /// Reprints the STORED receipt. It needs the ORDER-TIME lines, which only a
  /// device-owned order has — the eligibility policy already refuses it otherwise.
  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final payment = order.payment;
    final view = order.order;
    if (payment == null || view == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final bridge = ref.read(posActivePrintBridgeProvider);
    if (bridge == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.printStatusNotConfigured)),
      );
      return;
    }
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    final document = buildReceiptDocument(l10n, view, payment, isDemo: isDemo);
    await ref
        .read(receiptPrintControllerProvider.notifier)
        .reprint(
          // The receipt belongs to THIS order, keyed by its identity — not to whichever
          // order shares its printed code.
          orderKey: order.identity.key,
          document: document,
          submitToBridge: bridge.submit,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posRecentReprintStarted)),
    );
  }
}

// ---------------------------------------------------------------------------
// Labels. Every user-facing string is localized; no raw wire token ever reaches
// the screen (`not_chargeable` is a protocol detail, not English).
// ---------------------------------------------------------------------------

String _sectionLabel(AppLocalizations l10n, PosOrderSection s) => switch (s) {
  PosOrderSection.open => l10n.posOrdersSectionOpen,
  PosOrderSection.needsPayment => l10n.posOrdersSectionNeedsPayment,
  PosOrderSection.completedRecently => l10n.posOrdersSectionCompleted,
  PosOrderSection.all => l10n.posOrdersSectionAll,
};

String _settlementLabel(AppLocalizations l10n, PosSettlementFilter f) =>
    switch (f) {
      PosSettlementFilter.all => l10n.posOrdersSettlementAll,
      PosSettlementFilter.needsPayment => l10n.posOrdersSettlementUnpaid,
      PosSettlementFilter.paid => l10n.posOrdersSettlementPaid,
      PosSettlementFilter.noCharge => l10n.posOrdersSettlementNoCharge,
    };

String _typeLabel(AppLocalizations l10n, PosOrderTypeFilter t) => switch (t) {
  PosOrderTypeFilter.all => l10n.posOrdersFilterTypeAll,
  PosOrderTypeFilter.dineIn => l10n.posOrderTypeDineIn,
  PosOrderTypeFilter.takeaway => l10n.posOrderTypeTakeaway,
};

String _pendingLabel(AppLocalizations l10n, PosPendingKind k) => switch (k) {
  PosPendingKind.submit ||
  PosPendingKind.payment => l10n.posOrdersPendingPayment,
  PosPendingKind.discount => l10n.posOrdersPendingDiscount,
  PosPendingKind.cancellation => l10n.posOrdersPendingCancellation,
};

String _hhmm(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}

/// One action control, sized so it stays a real touch target on a phone and does
/// not stretch absurdly wide on a tablet. (It is deliberately NOT `Expanded`: these
/// live in a `Wrap`, which is not a Flex, and `Expanded` there is a crash.)
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 148, minHeight: 44),
    child: child,
  );
}
