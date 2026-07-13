/// The Dashboard "Order history" surface (ORDERS-HISTORY-001).
///
/// A paginated, filterable, searchable list of completed / in-progress orders in
/// the active scope. Tapping a row opens the detail sheet (with the receipt /
/// money-free kitchen-ticket previews + reprint center). Real mode reads the
/// `owner_order_history` RPC; demo mode shows the computed demo dataset with an
/// honest banner. Loading / empty / error states throughout; RTL-safe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_history_models.dart';
import '../format/money_format.dart';
import '../state/order_history_providers.dart';
import 'order_detail_sheet.dart';
import 'settlement_badge.dart';

/// The standalone Order-history surface: the page header + the [OrderHistoryView]
/// body. Kept intact so it can be mounted on its own; the tabbed Orders area
/// ([OrdersScreen]) mounts the header once and reuses [OrderHistoryView] instead,
/// so the chrome is never duplicated.
class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // RF-125: the shared calm page header as a full-width band with a warm
        // hairline boundary above the scrolling list.
        RestoflowPageHeader(
          bordered: true,
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
          ),
          icon: Icons.receipt_long_outlined,
          title: l10n.ordersHistoryTitle,
          subtitle: l10n.ordersHistorySubtitle,
          actions: [
            IconButton(
              key: const Key('orders-refresh'),
              tooltip: l10n.ordersRefresh,
              onPressed: () =>
                  ref.read(orderHistoryControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Expanded(child: OrderHistoryView()),
      ],
    );
  }
}

/// The order-history BODY (no page header): demo banner + filters + the
/// paginated list. Mounted by [OrderHistoryScreen] and by the Orders area's
/// History tab.
class OrderHistoryView extends ConsumerStatefulWidget {
  const OrderHistoryView({super.key});

  @override
  ConsumerState<OrderHistoryView> createState() => _OrderHistoryViewState();
}

class _OrderHistoryViewState extends ConsumerState<OrderHistoryView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _apply(OrderHistoryQuery Function(OrderHistoryQuery) update) {
    final notifier = ref.read(orderHistoryQueryProvider.notifier);
    notifier.state = update(notifier.state);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final query = ref.watch(orderHistoryQueryProvider);
    final state = ref.watch(orderHistoryControllerProvider);

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
              body: l10n.ordersDemoNotice,
            ),
          ),
        _FilterBar(
          query: query,
          searchController: _searchController,
          onApply: _apply,
          l10n: l10n,
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        _Body(state: state, l10n: l10n),
      ],
    );
  }
}

/// The filter bar: range chips + search + status/type/payment dropdowns.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.searchController,
    required this.onApply,
    required this.l10n,
  });

  final OrderHistoryQuery query;
  final TextEditingController searchController;
  final void Function(OrderHistoryQuery Function(OrderHistoryQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ranges = <OrderHistoryRange, String>{
      OrderHistoryRange.today: l10n.ordersRangeToday,
      OrderHistoryRange.yesterday: l10n.ordersRangeYesterday,
      OrderHistoryRange.last7: l10n.ordersRangeLast7,
      OrderHistoryRange.last30: l10n.ordersRangeLast30,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          children: [
            for (final entry in ranges.entries)
              ChoiceChip(
                key: Key('orders-range-${entry.key.wire}'),
                label: Text(entry.value),
                selected: query.range == entry.key,
                onSelected: (_) => onApply((q) => q.copyWith(range: entry.key)),
              ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.md),
        TextField(
          key: const Key('orders-search-field'),
          controller: searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.ordersSearchHint,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: const Key('orders-search-apply'),
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
            _StatusDropdown(query: query, onApply: onApply, l10n: l10n),
            _TypeDropdown(query: query, onApply: onApply, l10n: l10n),
            _PaymentDropdown(query: query, onApply: onApply, l10n: l10n),
          ],
        ),
      ],
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final OrderHistoryQuery query;
  final void Function(OrderHistoryQuery Function(OrderHistoryQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _FilterDropdown<OrderStatusFilter>(
      keyValue: 'orders-status-filter',
      label: l10n.ordersFilterStatus,
      value: query.status,
      items: {
        for (final s in OrderStatusFilter.values) s: statusFilterLabel(l10n, s),
      },
      onChanged: (v) => onApply((q) => q.copyWith(status: v)),
    );
  }
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final OrderHistoryQuery query;
  final void Function(OrderHistoryQuery Function(OrderHistoryQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _FilterDropdown<OrderTypeFilter>(
      keyValue: 'orders-type-filter',
      label: l10n.ordersFilterType,
      value: query.orderType,
      items: {
        OrderTypeFilter.all: l10n.ordersTypeAll,
        OrderTypeFilter.dineIn: l10n.posOrderTypeDineIn,
        OrderTypeFilter.takeaway: l10n.posOrderTypeTakeaway,
      },
      onChanged: (v) => onApply((q) => q.copyWith(orderType: v)),
    );
  }
}

class _PaymentDropdown extends StatelessWidget {
  const _PaymentDropdown({
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final OrderHistoryQuery query;
  final void Function(OrderHistoryQuery Function(OrderHistoryQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _FilterDropdown<PaymentFilter>(
      keyValue: 'orders-payment-filter',
      label: l10n.ordersFilterPayment,
      value: query.payment,
      items: {
        PaymentFilter.all: l10n.ordersPaymentAll,
        PaymentFilter.paid: l10n.dashboardPaid,
        PaymentFilter.unpaid: l10n.dashboardUnpaid,
        PaymentFilter.cash: l10n.posPaymentMethodCash,
      },
      onChanged: (v) => onApply((q) => q.copyWith(payment: v)),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
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

/// The list body: loading skeletons / error / empty / rows + load-more.
class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.l10n});

  final OrderHistoryState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return Column(
        key: const Key('orders-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          RestoflowSkeleton(height: 76),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 76),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 76),
        ],
      );
    }
    if (state.error != null) {
      return RestoflowStateView(
        key: const Key('orders-error'),
        icon: Icons.error_outline,
        title: l10n.ordersError,
        message: l10n.ordersErrorHint,
        tone: RestoflowTone.danger,
        actions: [
          FilledButton.tonal(
            onPressed: () =>
                ref.read(orderHistoryControllerProvider.notifier).refresh(),
            child: Text(l10n.ordersRefresh),
          ),
        ],
      );
    }
    if (state.isEmpty) {
      return RestoflowStateView(
        key: const Key('orders-empty'),
        icon: Icons.receipt_long_outlined,
        title: l10n.ordersEmpty,
        message: l10n.ordersEmptyHint,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in state.rows)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: OrderHistoryCard(row: row, l10n: l10n),
          ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
            child: Center(
              child: state.loadingMore
                  ? const RestoflowSkeleton(width: 160, height: 40)
                  : OutlinedButton.icon(
                      key: const Key('orders-load-more'),
                      onPressed: () => ref
                          .read(orderHistoryControllerProvider.notifier)
                          .loadMore(),
                      icon: const Icon(Icons.expand_more),
                      label: Text(l10n.ordersLoadMore),
                    ),
            ),
          ),
      ],
    );
  }
}

/// One order row card: code + time, customer/type/table, total, status/payment.
class OrderHistoryCard extends ConsumerWidget {
  const OrderHistoryCard({required this.row, required this.l10n, super.key});

  final OrderHistoryRow row;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusStyle = statusTone(row.status).styleOf(theme);
    final money = MoneyFormatter.formatMinor(
      row.grandTotalMinor,
      row.currencyCode,
    );
    final subtitleParts = <String>[
      orderTypeLabel(l10n, row.orderType),
      if (row.tableLabel != null && row.tableLabel!.isNotEmpty)
        '${l10n.posTableLabel} ${row.tableLabel}',
      if (row.customerName != null && row.customerName!.isNotEmpty)
        row.customerName!,
      l10n.ordersItemsCount(row.itemCount),
    ];
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      child: InkWell(
        key: Key('order-card-${row.orderId}'),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        onTap: () => showOrderDetailSheet(context, ref, row),
        child: Container(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: kRestoflowHairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(row.orderCode, style: theme.textTheme.titleMedium),
                        const SizedBox(width: RestoflowSpacing.sm),
                        if (row.createdAtLabel.isNotEmpty)
                          Text(
                            row.createdAtLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: kRestoflowInk3,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    Text(
                      subtitleParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kRestoflowInk2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RestoflowSpacing.sm),
                    Wrap(
                      spacing: RestoflowSpacing.xs,
                      runSpacing: RestoflowSpacing.xs,
                      children: [
                        RestoflowStatusPill(
                          label: statusLabel(l10n, row.status),
                          tone: statusTone(row.status),
                        ),
                        settlementPill(l10n, row.settlement),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: statusStyle.accent,
                    ),
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  Icon(Icons.chevron_right, color: kRestoflowInk3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tone for an order status pill.
RestoflowTone statusTone(String status) => switch (status) {
  'completed' || 'served' => RestoflowTone.success,
  'voided' || 'cancelled' => RestoflowTone.danger,
  'ready' => RestoflowTone.info,
  'preparing' || 'accepted' || 'submitted' => RestoflowTone.warning,
  _ => RestoflowTone.neutral,
};

/// The localized label for an order status value (display, all statuses).
String statusLabel(AppLocalizations l10n, String status) => switch (status) {
  'draft' => l10n.ordersStatusDraft,
  'submitted' => l10n.ordersStatusSubmitted,
  'accepted' => l10n.ordersStatusAccepted,
  'preparing' => l10n.ordersStatusPreparing,
  'ready' => l10n.ordersStatusReady,
  'served' => l10n.ordersStatusServed,
  'completed' => l10n.ordersStatusCompleted,
  'cancelled' => l10n.ordersStatusCancelled,
  'voided' => l10n.ordersStatusVoided,
  _ => status,
};

/// The localized label for a status FILTER option (adds "All").
String statusFilterLabel(AppLocalizations l10n, OrderStatusFilter f) =>
    switch (f) {
      OrderStatusFilter.all => l10n.ordersStatusAll,
      OrderStatusFilter.submitted => l10n.ordersStatusSubmitted,
      OrderStatusFilter.preparing => l10n.ordersStatusPreparing,
      OrderStatusFilter.ready => l10n.ordersStatusReady,
      OrderStatusFilter.completed => l10n.ordersStatusCompleted,
      OrderStatusFilter.voided => l10n.ordersStatusVoided,
      OrderStatusFilter.cancelled => l10n.ordersStatusCancelled,
    };

/// The localized label for an order type value.
String orderTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'dine_in' => l10n.posOrderTypeDineIn,
  'takeaway' => l10n.posOrderTypeTakeaway,
  _ => type,
};
