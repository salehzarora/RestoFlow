/// The Dashboard "Active orders" operations centre (ACTIVE-ORDERS-001).
///
/// READ-ONLY. Every order still OPEN in the caller's scope, oldest-first (FIFO),
/// with a scope summary, scope-safe filters, and how long each order has been
/// open. Tapping a row opens the SAME read-only detail sheet the history list
/// uses (previews + copy; no action mutates an order, payment, shift or kitchen
/// job). There is deliberately NO status control, no mark-ready, no payment, no
/// void, no reassignment — those live in the POS and KDS.
///
/// HONESTY: the schema carries no promised/due/ETA timestamp anywhere, so this
/// board NEVER marks an order "late". It shows only elapsed time since the
/// order was created, and says so on the surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/active_orders_models.dart';
import '../data/audit_log_models.dart' show AuditBranchOption;
import '../data/order_history_models.dart';
import '../format/money_format.dart';
import '../state/active_orders_providers.dart';
import '../state/audit_log_providers.dart' show auditBranchOptionsProvider;
import 'order_detail_sheet.dart';
import 'order_history_screen.dart' show orderTypeLabel, statusLabel, statusTone;
import 'settlement_badge.dart';

/// Above this width the board renders as a dense operational table; below it,
/// as stacked cards. Uses the shared breakpoint so it matches the rest of the
/// dashboard.
const double _kDenseBoardWidth = RestoflowBreakpoints.wide;

/// The active-orders BODY (no page header — the Orders area owns the chrome).
class ActiveOrdersView extends ConsumerStatefulWidget {
  const ActiveOrdersView({super.key});

  @override
  ConsumerState<ActiveOrdersView> createState() => _ActiveOrdersViewState();
}

class _ActiveOrdersViewState extends ConsumerState<ActiveOrdersView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _apply(ActiveOrdersQuery Function(ActiveOrdersQuery) update) {
    final notifier = ref.read(activeOrdersQueryProvider.notifier);
    notifier.state = update(notifier.state);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final query = ref.watch(activeOrdersQueryProvider);
    final state = ref.watch(activeOrdersControllerProvider);
    final branches = ref
        .watch(auditBranchOptionsProvider)
        .maybeWhen(data: (b) => b, orElse: () => const <AuditBranchOption>[]);
    // ONE clock read per board build (the KDS rule) so every row's age is
    // measured against the same instant.
    final now = ref.watch(activeOrdersClockProvider)();

    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        if (isDemo)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.md,
            ),
            child: RestoflowNoticeBanner(
              icon: Icons.science_outlined,
              body: l10n.ordersActiveDemoNotice,
            ),
          ),
        _SummaryStrip(
          summary: state.data.summary,
          query: query,
          onApply: _apply,
          l10n: l10n,
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        _QueueSelector(query: query, onApply: _apply, l10n: l10n),
        const SizedBox(height: RestoflowSpacing.md),
        _FilterBar(
          query: query,
          branches: branches,
          searchController: _searchController,
          onApply: _apply,
          l10n: l10n,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        _FreshnessRow(state: state, l10n: l10n),
        const SizedBox(height: RestoflowSpacing.xs),
        _NoDueTimeNotice(l10n: l10n),
        // What the AWAITING-CLOSE queue actually is, and how an order leaves it.
        if (query.queue == ActiveOrderQueue.awaitingClose) ...[
          const SizedBox(height: RestoflowSpacing.md),
          RestoflowNoticeBanner(
            key: const Key('active-orders-awaiting-explainer'),
            icon: Icons.task_alt_outlined,
            body: l10n.ordersAwaitingCloseExplainer,
          ),
          // A restrained statement of fact when the backlog is meaningfully high.
          // No urgency, no blame, and deliberately NO one-click bulk close.
          if (state.data.summary.awaitingClose >=
              kAwaitingCloseBacklogNotice) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            RestoflowNoticeBanner(
              key: const Key('active-orders-awaiting-backlog'),
              icon: Icons.inventory_2_outlined,
              tone: RestoflowTone.warning,
              body: l10n.ordersAwaitingCloseBacklog(
                state.data.summary.awaitingClose,
              ),
            ),
          ],
        ],
        // The board is CAPPED, so say so — and say it in the terms of the sort
        // actually applied (newest vs oldest), never "all orders".
        if (state.data.truncated) ...[
          const SizedBox(height: RestoflowSpacing.md),
          RestoflowNoticeBanner(
            key: const Key('active-orders-truncated'),
            icon: Icons.filter_list,
            tone: RestoflowTone.warning,
            body: query.sort == ActiveOrdersSort.newest
                ? l10n.ordersActiveTruncatedNewest(
                    state.data.rows.length,
                    state.data.matching,
                  )
                : l10n.ordersActiveTruncatedOldest(
                    state.data.rows.length,
                    state.data.matching,
                  ),
          ),
        ],
        // A refresh failed but the rows are still usable — surface it BESIDE them
        // instead of blanking the operator's board.
        if (state.refreshError && !state.isEmpty) ...[
          const SizedBox(height: RestoflowSpacing.md),
          RestoflowNoticeBanner(
            key: const Key('active-orders-refresh-failed'),
            icon: Icons.cloud_off_outlined,
            tone: RestoflowTone.danger,
            body: l10n.ordersActiveRefreshFailed,
          ),
        ],
        const SizedBox(height: RestoflowSpacing.lg),
        _Board(state: state, query: query, now: now, l10n: l10n),
      ],
    );
  }
}

/// From this many served orders, the awaiting-close queue shows a restrained
/// "this backlog is real" notice. A presentation threshold only — it ranks
/// nothing, blames nobody, and invents no urgency.
const int kAwaitingCloseBacklogNotice = 25;

/// The operational QUEUE selector + the SORT control.
class _QueueSelector extends StatelessWidget {
  const _QueueSelector({
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final ActiveOrdersQuery query;
  final void Function(ActiveOrdersQuery Function(ActiveOrdersQuery)) onApply;
  final AppLocalizations l10n;

  void _selectQueue(ActiveOrderQueue queue) {
    if (queue == query.queue) return;
    // Changing the queue rebuilds the controller, which RESETS pagination — a
    // cursor from the old queue can never be replayed.
    onApply((q) => q.copyWith(queue: queue));
  }

  @override
  Widget build(BuildContext context) {
    final segments = <RestoflowSegment<ActiveOrderQueue>>[
      RestoflowSegment(
        key: const Key('active-queue-in-progress'),
        value: ActiveOrderQueue.inProgress,
        label: l10n.ordersQueueInProgress,
        icon: Icons.local_fire_department_outlined,
      ),
      RestoflowSegment(
        key: const Key('active-queue-awaiting-close'),
        value: ActiveOrderQueue.awaitingClose,
        label: l10n.ordersQueueAwaitingClose,
        icon: Icons.task_alt_outlined,
      ),
      RestoflowSegment(
        key: const Key('active-queue-all'),
        value: ActiveOrderQueue.allActive,
        label: l10n.ordersQueueAllActive,
        icon: Icons.list_alt_outlined,
      ),
    ];

    final sort = SizedBox(
      width: 190,
      child: DropdownButtonFormField<ActiveOrdersSort>(
        key: const Key('active-orders-sort'),
        initialValue: query.sort,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.ordersSortLabel,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: ActiveOrdersSort.newest,
            child: Text(l10n.ordersSortNewest),
          ),
          DropdownMenuItem(
            value: ActiveOrdersSort.oldest,
            child: Text(l10n.ordersSortOldest),
          ),
        ],
        onChanged: (value) {
          if (value == null || value == query.sort) return;
          // The SERVER re-sorts and pagination resets — the client never reverses
          // a capped page (the un-fetched rows are not in the payload).
          onApply((q) => q.copyWith(sort: value));
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // On a phone the queue bar and the sort control cannot share a row at
        // their natural widths, so they stack and the segments share the width.
        final narrow = constraints.maxWidth < RestoflowBreakpoints.posTwoPane;
        final control = RestoflowSegmentedControl<ActiveOrderQueue>(
          segments: segments,
          selected: query.queue,
          expand: narrow,
          onSelected: _selectQueue,
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              control,
              const SizedBox(height: RestoflowSpacing.sm),
              Align(alignment: AlignmentDirectional.centerStart, child: sort),
            ],
          );
        }
        return Row(
          children: [
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: control,
              ),
            ),
            const SizedBox(width: RestoflowSpacing.md),
            sort,
          ],
        );
      },
    );
  }
}

/// The scope's operational picture. Each tile is a shortcut into the matching
/// filter — the counters themselves always describe the whole scope, so they do
/// not move as the operator narrows the list.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.summary,
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final ActiveOrdersSummary summary;
  final ActiveOrdersQuery query;
  final void Function(ActiveOrdersQuery Function(ActiveOrdersQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // The counters are SERVER-computed over the whole SCOPE (never the queue and
    // never the loaded page), so they stay put while the operator moves between
    // queues — and they can never disagree with what the board is showing.
    final tiles = <Widget>[
      RestoflowMetricCard(
        key: const Key('active-summary-total'),
        label: l10n.ordersActiveSummaryTotal,
        value: '${summary.total}',
        icon: Icons.pending_actions_outlined,
        tone: RestoflowTone.info,
        onTap: () => onApply(
          (q) => q.copyWith(
            queue: ActiveOrderQueue.allActive,
            stage: ActiveOrderStageFilter.all,
            payment: PaymentFilter.all,
          ),
        ),
      ),
      RestoflowMetricCard(
        key: const Key('active-summary-in-progress'),
        label: l10n.ordersQueueInProgress,
        value: '${summary.inProgress}',
        icon: Icons.local_fire_department_outlined,
        tone: RestoflowTone.success,
        // The card IS the queue selector — tapping it opens the In-progress queue.
        onTap: () =>
            onApply((q) => q.copyWith(queue: ActiveOrderQueue.inProgress)),
      ),
      RestoflowMetricCard(
        key: const Key('active-summary-awaiting-close'),
        label: l10n.ordersQueueAwaitingClose,
        value: '${summary.awaitingClose}',
        icon: Icons.task_alt_outlined,
        tone: RestoflowTone.neutral,
        onTap: () =>
            onApply((q) => q.copyWith(queue: ActiveOrderQueue.awaitingClose)),
      ),
      RestoflowMetricCard(
        key: const Key('active-summary-unpaid'),
        label: l10n.dashboardUnpaid,
        value: '${summary.unpaid}',
        icon: Icons.schedule,
        tone: RestoflowTone.warning,
        // Unpaid is a PAYMENT attribute, never an operational stage (D-025): this
        // applies the payment filter and leaves the lifecycle queue alone.
        onTap: () => onApply(
          (q) => q.copyWith(
            queue: ActiveOrderQueue.allActive,
            payment: PaymentFilter.unpaid,
          ),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= _kDenseBoardWidth
            ? 4
            : width >= RestoflowBreakpoints.compact
            ? 2
            : 1;
        const gap = RestoflowSpacing.md;
        final tileWidth =
            (width - gap * (columns - 1)) / columns - 0.01; // avoid FP overflow
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

/// Branch + stage + type + payment + search. The branch options come from the
/// scope-safe option source (a branch the caller does not cover is never even
/// offered); the server intersects the choice with its own scope regardless.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.branches,
    required this.searchController,
    required this.onApply,
    required this.l10n,
  });

  final ActiveOrdersQuery query;
  final List<AuditBranchOption> branches;
  final TextEditingController searchController;
  final void Function(ActiveOrdersQuery Function(ActiveOrdersQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final branchIds = branches.map((b) => b.branchId).toSet();
    final selectedBranchId = branchIds.contains(query.branch?.branchId)
        ? query.branch?.branchId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('active-orders-search-field'),
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.ordersSearchHint,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: const Key('active-orders-search-apply'),
              tooltip: l10n.ordersSearchHint,
              icon: const Icon(Icons.arrow_forward),
              onPressed: () =>
                  onApply((q) => q.copyWith(search: searchController.text)),
            ),
          ),
          onSubmitted: (value) => onApply((q) => q.copyWith(search: value)),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Wrap(
          spacing: RestoflowSpacing.md,
          runSpacing: RestoflowSpacing.sm,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                key: const Key('active-orders-branch-filter'),
                initialValue: selectedBranchId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.ordersBranchLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.ordersBranchAll),
                  ),
                  for (final b in branches)
                    DropdownMenuItem<String?>(
                      value: b.branchId,
                      child: Text(b.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) {
                    onApply((q) => q.copyWith(clearBranch: true));
                    return;
                  }
                  final picked = branches.firstWhere((b) => b.branchId == id);
                  onApply((q) => q.copyWith(branch: picked));
                },
              ),
            ),
            _Dropdown<ActiveOrderStageFilter>(
              keyValue: 'active-orders-stage-filter',
              label: l10n.ordersFilterStatus,
              value: query.stage,
              items: {
                for (final s in ActiveOrderStageFilter.values)
                  s: activeStageLabel(l10n, s),
              },
              onChanged: (v) => onApply((q) => q.copyWith(stage: v)),
            ),
            _Dropdown<OrderTypeFilter>(
              keyValue: 'active-orders-type-filter',
              label: l10n.ordersFilterType,
              value: query.orderType,
              items: {
                OrderTypeFilter.all: l10n.ordersTypeAll,
                OrderTypeFilter.dineIn: l10n.posOrderTypeDineIn,
                OrderTypeFilter.takeaway: l10n.posOrderTypeTakeaway,
              },
              onChanged: (v) => onApply((q) => q.copyWith(orderType: v)),
            ),
            _Dropdown<PaymentFilter>(
              keyValue: 'active-orders-payment-filter',
              label: l10n.ordersFilterPayment,
              value: query.payment,
              items: {
                PaymentFilter.all: l10n.ordersPaymentAll,
                PaymentFilter.paid: l10n.dashboardPaid,
                PaymentFilter.unpaid: l10n.dashboardUnpaid,
                PaymentFilter.cash: l10n.posPaymentMethodCash,
              },
              onChanged: (v) => onApply((q) => q.copyWith(payment: v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.keyValue,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String keyValue;
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<T>(
        key: Key(keyValue),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// The freshness controls: when the board was last read, and the OPT-IN
/// auto-refresh. Nothing claims to be live unless the toggle is actually on.
class _FreshnessRow extends ConsumerWidget {
  const _FreshnessRow({required this.state, required this.l10n});

  final ActiveOrdersState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final updated = state.lastUpdated;

    // ACTIVE-ORDERS-002: the auto-refresh SWITCH is gone. The board refreshes
    // itself while it is on screen, so all the operator needs is an honest stamp
    // of when it was last read. It is never described as "live" or "real-time".
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: RestoflowSpacing.sm,
      children: [
        if (state.refreshing)
          const SizedBox(
            width: RestoflowIconSizes.sm,
            height: RestoflowIconSizes.sm,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (updated != null)
          Semantics(
            // Screen readers get the same sentence sighted users read.
            label: l10n.ordersActiveLastUpdated(_hhmm(updated)),
            child: ExcludeSemantics(
              child: Text(
                key: const Key('active-orders-last-updated'),
                // The viewer's own device clock: this stamps when THEY last read
                // the board, not when anything happened in a branch.
                l10n.ordersActiveLastUpdated(_hhmm(updated)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kRestoflowInk3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _hhmm(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// The standing, honest statement that lateness cannot be reported: no
/// promised/due/ETA field exists anywhere in the schema, so an "overdue" badge
/// would be fabricated. Elapsed time is shown instead.
class _NoDueTimeNotice extends StatelessWidget {
  const _NoDueTimeNotice({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('active-orders-no-due-notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: RestoflowIconSizes.xs,
          color: kRestoflowInk3,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            l10n.ordersActiveNoDueTimeNotice,
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk3),
          ),
        ),
      ],
    );
  }
}

/// Loading skeletons / error + retry / the QUEUE-specific empty state / the rows
/// (in the SERVER's order) + the load-more continuation.
class _Board extends ConsumerWidget {
  const _Board({
    required this.state,
    required this.query,
    required this.now,
    required this.l10n,
  });

  final ActiveOrdersState state;
  final ActiveOrdersQuery query;
  final DateTime now;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return Column(
        key: const Key('active-orders-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          RestoflowSkeleton(height: 72),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 72),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 72),
        ],
      );
    }
    if (state.error != null) {
      return RestoflowStateView(
        key: const Key('active-orders-error'),
        icon: Icons.error_outline,
        title: l10n.ordersError,
        message: l10n.ordersErrorHint,
        tone: RestoflowTone.danger,
        actions: [
          FilledButton.tonal(
            key: const Key('active-orders-retry'),
            onPressed: () =>
                ref.read(activeOrdersControllerProvider.notifier).refresh(),
            child: Text(l10n.ordersRefresh),
          ),
        ],
      );
    }
    if (state.isEmpty) {
      // The empty state must say what THIS queue means — "no orders" is useless
      // when the awaiting-close backlog is 127.
      return RestoflowStateView(
        key: const Key('active-orders-empty'),
        icon: Icons.inbox_outlined,
        title: l10n.ordersActiveEmpty,
        message: switch (query.queue) {
          ActiveOrderQueue.inProgress => l10n.ordersActiveEmptyInProgress,
          ActiveOrderQueue.awaitingClose => l10n.ordersActiveEmptyAwaitingClose,
          ActiveOrderQueue.allActive => l10n.ordersActiveEmptyHint,
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxWidth >= _kDenseBoardWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in state.data.rows)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: RestoflowSpacing.sm,
                ),
                child: ActiveOrderTile(
                  row: row,
                  now: now,
                  dense: dense,
                  l10n: l10n,
                ),
              ),
            // Page BEYOND the cap instead of silently ending at the limit. Pages
            // are appended in the SERVER's order — never re-sorted here.
            if (state.data.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RestoflowSpacing.sm,
                ),
                child: Center(
                  child: state.loadingMore
                      ? const RestoflowSkeleton(width: 160, height: 40)
                      : OutlinedButton.icon(
                          key: const Key('active-orders-load-more'),
                          onPressed: () => ref
                              .read(activeOrdersControllerProvider.notifier)
                              .loadMore(),
                          icon: const Icon(Icons.expand_more),
                          label: Text(l10n.ordersLoadMore),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One active order. READ-ONLY: tapping opens the detail sheet (previews + copy).
/// Status is carried by a LABELLED pill, never by colour alone.
class ActiveOrderTile extends ConsumerWidget {
  const ActiveOrderTile({
    required this.row,
    required this.now,
    required this.l10n,
    this.dense = false,
    super.key,
  });

  final OrderHistoryRow row;
  final DateTime now;
  final AppLocalizations l10n;

  /// True on wide layouts: one dense operational line. False: a stacked card.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = MoneyFormatter.formatMinor(
      row.grandTotalMinor,
      row.currencyCode,
    );
    final age = activeAgeText(l10n, openMinutes(row, now));
    final meta = <String>[
      orderTypeLabel(l10n, row.orderType),
      if (row.tableLabel != null && row.tableLabel!.isNotEmpty)
        '${l10n.posTableLabel} ${row.tableLabel}',
      if (row.branchName != null && row.branchName!.isNotEmpty) row.branchName!,
      if (row.customerName != null && row.customerName!.isNotEmpty)
        row.customerName!,
      l10n.ordersItemsCount(row.itemCount),
    ].join(' · ');

    final pills = Wrap(
      spacing: RestoflowSpacing.xs,
      runSpacing: RestoflowSpacing.xs,
      children: [
        RestoflowStatusPill(
          label: statusLabel(l10n, row.status),
          tone: statusTone(row.status),
        ),
        settlementPill(l10n, row.settlement),
      ],
    );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      child: InkWell(
        key: Key('active-order-card-${row.orderId}'),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        onTap: () => showOrderDetailSheet(context, ref, row),
        child: Container(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: kRestoflowHairline),
          ),
          child: dense
              ? _denseLine(theme, pills, meta, age, money)
              : _card(theme, pills, meta, age, money),
        ),
      ),
    );
  }

  Widget _denseLine(
    ThemeData theme,
    Widget pills,
    String meta,
    String? age,
    String money,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.orderCode,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              if (row.createdAtLabel.isNotEmpty)
                Text(
                  row.createdAtLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kRestoflowInk3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(flex: 3, child: pills),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          flex: 4,
          child: Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(color: kRestoflowInk2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          flex: 2,
          child: _AgeBlock(label: l10n.ordersActiveAgeLabel, age: age),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          flex: 2,
          child: Text(
            money,
            textAlign: TextAlign.end,
            style: theme.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.chevron_right, color: kRestoflowInk3),
      ],
    );
  }

  Widget _card(
    ThemeData theme,
    Widget pills,
    String meta,
    String? age,
    String money,
  ) {
    return Row(
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
                      row.orderCode,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (row.createdAtLabel.isNotEmpty) ...[
                    const SizedBox(width: RestoflowSpacing.sm),
                    Flexible(
                      child: Text(
                        row.createdAtLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kRestoflowInk3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: RestoflowSpacing.xs),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kRestoflowInk2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              pills,
            ],
          ),
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money, style: theme.textTheme.titleMedium),
            const SizedBox(height: RestoflowSpacing.xs),
            _AgeBlock(
              label: l10n.ordersActiveAgeLabel,
              age: age,
              alignEnd: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Open for / 23 min". Renders NOTHING when the age is unknown — a missing
/// timestamp is never shown as "0 min".
class _AgeBlock extends StatelessWidget {
  const _AgeBlock({
    required this.label,
    required this.age,
    this.alignEnd = false,
  });

  final String label;
  final String? age;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final value = age;
    if (value == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: kRestoflowInk3),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(color: kRestoflowInk),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The localized elapsed-age text, or null when the age is unknown.
String? activeAgeText(AppLocalizations l10n, int? minutes) {
  if (minutes == null) return null;
  if (minutes < 60) return l10n.ordersActiveAgeMinutes(minutes);
  return l10n.ordersActiveAgeHours(minutes ~/ 60, minutes % 60);
}

/// The localized label for an active-stage FILTER option (adds "All stages").
String activeStageLabel(AppLocalizations l10n, ActiveOrderStageFilter f) =>
    switch (f) {
      ActiveOrderStageFilter.all => l10n.ordersActiveStageAll,
      ActiveOrderStageFilter.submitted => l10n.ordersStatusSubmitted,
      ActiveOrderStageFilter.accepted => l10n.ordersStatusAccepted,
      ActiveOrderStageFilter.preparing => l10n.ordersStatusPreparing,
      ActiveOrderStageFilter.ready => l10n.ordersStatusReady,
      ActiveOrderStageFilter.served => l10n.ordersStatusServed,
    };
