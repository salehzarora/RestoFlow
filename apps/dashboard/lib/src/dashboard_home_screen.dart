import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'data/demo_report.dart';
import 'format/money_format.dart';
import 'state/dashboard_providers.dart';
import 'widgets/daily_summary_card.dart';
import 'widgets/dashboard_status_pill.dart';
import 'widgets/demo_notice_banner.dart';
import 'widgets/metric_card.dart';
import 'widgets/recent_order_tile.dart';
import 'widgets/section_card.dart';

/// The RF-104/RF-119 owner/manager reports dashboard: a demo-data banner, the
/// report day context, daily KPI cards (gross/net sales, orders, average ticket,
/// cash sales, completed, unpaid), a daily summary, a payment & cash summary,
/// sales-by-branch, ranked top items and recent orders.
///
/// The report is loaded through the [dashboardReportProvider] seam (computed
/// from a structured demo dataset — no Supabase, no report views, no backend),
/// so the screen has honest loading / error / empty states and a refresh. Money
/// is integer minor units (DECISION D-007); chrome is localized; layout is
/// responsive and RTL/LTR-correct.
class DashboardHomeScreen extends ConsumerWidget {
  const DashboardHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // RF-140: the same demo/real switch the repository seam reads, so the
    // banner/header are honest about the data source (never claim demo data in
    // real mode, nor vice versa). Demo is the DEFAULT.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final reportAsync = ref.watch(dashboardReportProvider);

    void refresh() => ref.invalidate(dashboardReportProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(l10n.dashboardAppTitle),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('reports-refresh-button'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.dashboardRefresh,
          ),
        ],
      ),
      body: reportAsync.when(
        data: (report) => _ReportContent(report: report, isDemo: isDemo),
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(onRetry: refresh),
      ),
    );
  }
}

/// The loaded report: a scrollable, responsive layout of all report sections.
class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.report, required this.isDemo});

  final DashboardReport report;

  /// Whether the report is demo data (computed locally) or real data. Drives the
  /// banner + header pill so the data source is labelled honestly (RF-140).
  final bool isDemo;

  static const double _twoColBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, report.currencyCode);

    final header = _ReportHeader(report: report, isDemo: isDemo);
    // RF-140: demo mode shows the demo-data notice; real mode shows a slim
    // "live · limited" caution notice — never a demo/deferred banner over real
    // data. (Real mode currently fails closed before reaching this content; the
    // mode-aware banner keeps the screen honest for when real data lands.)
    final banner = isDemo
        ? DemoNoticeBanner(
            key: const Key('reports-demo-banner'),
            message: l10n.dashboardDemoReportsNotice,
          )
        : DemoNoticeBanner(
            key: const Key('reports-realmode-banner'),
            message: l10n.dashboardRealModeNotice,
            tone: DemoNoticeTone.caution,
          );

    if (report.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        children: [
          banner,
          const SizedBox(height: RestoflowSpacing.lg),
          header,
          const SizedBox(height: RestoflowSpacing.xl),
          const _EmptyState(),
        ],
      );
    }

    final openCaption = '${l10n.dashboardOpenOrders}: ${report.openOrderCount}';
    final kpis = <Widget>[
      MetricCard(
        key: const Key('kpi-gross-sales'),
        label: l10n.dashboardGrossSales,
        value: money(report.grossSalesMinor),
        icon: Icons.point_of_sale_outlined,
      ),
      MetricCard(
        key: const Key('kpi-net-sales'),
        label: l10n.dashboardTodaySales,
        value: money(report.netSalesMinor),
        icon: Icons.payments_outlined,
      ),
      MetricCard(
        key: const Key('kpi-orders'),
        label: l10n.dashboardOrders,
        value: report.orderCount.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      MetricCard(
        key: const Key('kpi-avg-ticket'),
        label: l10n.dashboardAvgOrderValue,
        value: money(report.avgOrderValueMinor),
        icon: Icons.trending_up,
      ),
      MetricCard(
        key: const Key('kpi-cash-sales'),
        label: l10n.dashboardCashSales,
        value: money(report.cashSalesMinor),
        icon: Icons.account_balance_wallet_outlined,
      ),
      MetricCard(
        key: const Key('kpi-completed'),
        label: l10n.dashboardCompletedOrders,
        value: report.completedOrderCount.toString(),
        caption: openCaption,
        icon: Icons.task_alt,
      ),
      MetricCard(
        key: const Key('kpi-unpaid'),
        label: l10n.dashboardUnpaidOrders,
        value: report.unpaidOrderCount.toString(),
        icon: Icons.pending_actions_outlined,
      ),
    ];

    final summary = DailySummaryCard(
      title: l10n.dashboardDailySummary,
      rows: [
        SummaryRow(
          label: l10n.dashboardNetSales,
          value: money(report.netSalesMinor),
        ),
        SummaryRow(
          label: l10n.dashboardDiscounts,
          value: money(report.discountTotalMinor),
        ),
        SummaryRow(
          label: l10n.dashboardVoids,
          value: '${report.voidCount} · ${money(report.voidTotalMinor)}',
        ),
        SummaryRow(
          label: l10n.dashboardCashCollected,
          value: money(report.collectedMinor),
        ),
        SummaryRow(
          label: l10n.dashboardCashVariance,
          value: money(report.varianceMinor),
        ),
        SummaryRow(
          label: l10n.dashboardShiftStatus,
          trailing: DashboardStatusPill(label: report.shiftStatus),
        ),
      ],
    );

    final payment = DailySummaryCard(
      key: const Key('payment-summary-card'),
      title: l10n.dashboardPaymentSummary,
      rows: [
        SummaryRow(
          label: l10n.dashboardOpeningFloat,
          value: money(report.openingFloatMinor),
        ),
        SummaryRow(
          label: l10n.dashboardCashSales,
          value: money(report.cashSalesMinor),
        ),
        SummaryRow(
          label: l10n.dashboardExpectedDrawer,
          value: money(report.expectedCashMinor),
        ),
        SummaryRow(
          label: l10n.dashboardCountedCash,
          value: money(report.countedCashMinor),
        ),
        SummaryRow(
          label: l10n.dashboardCashVariance,
          value: money(report.varianceMinor),
        ),
        SummaryRow(
          label: l10n.dashboardLastCashPayment,
          value: money(report.lastCashPaymentMinor),
        ),
        for (final method in report.paymentMethods)
          SummaryRow(
            label: _methodLabel(l10n, method.method),
            value: '${method.count} · ${money(method.totalMinor)}',
          ),
      ],
    );

    final branches = SectionCard(
      key: const Key('sales-by-branch-card'),
      title: l10n.dashboardSalesByBranch,
      children: [
        for (final branch in report.branches)
          SectionRow(
            label: branch.branchName,
            secondary: '${branch.orderCount} · ${l10n.dashboardOrders}',
            trailingValue: MoneyFormatter.formatMinor(
              branch.netSalesMinor,
              branch.currencyCode,
            ),
          ),
      ],
    );

    final topItems = SectionCard(
      key: const Key('top-items-card'),
      title: l10n.dashboardTopItems,
      children: [
        for (var i = 0; i < report.topItems.length; i++)
          SectionRow(
            label: report.topItems[i].name,
            secondary: '#${i + 1} · ×${report.topItems[i].quantity}',
            trailingValue: MoneyFormatter.formatMinor(
              report.topItems[i].lineRevenueMinor,
              report.topItems[i].currencyCode,
            ),
          ),
      ],
    );

    final recentOrders = SectionCard(
      key: const Key('recent-orders-card'),
      title: l10n.dashboardRecentOrders,
      children: [
        for (final row in report.recentOrders) RecentOrderTile(row: row),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= _twoColBreakpoint;
        final sections = twoColumn
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        summary,
                        const SizedBox(height: RestoflowSpacing.lg),
                        payment,
                      ],
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.lg),
                  Expanded(
                    child: Column(
                      children: [
                        branches,
                        const SizedBox(height: RestoflowSpacing.lg),
                        topItems,
                        const SizedBox(height: RestoflowSpacing.lg),
                        recentOrders,
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  summary,
                  const SizedBox(height: RestoflowSpacing.lg),
                  payment,
                  const SizedBox(height: RestoflowSpacing.lg),
                  branches,
                  const SizedBox(height: RestoflowSpacing.lg),
                  topItems,
                  const SizedBox(height: RestoflowSpacing.lg),
                  recentOrders,
                ],
              );

        return ListView(
          padding: const EdgeInsets.all(RestoflowSpacing.lg),
          children: [
            banner,
            const SizedBox(height: RestoflowSpacing.lg),
            header,
            const SizedBox(height: RestoflowSpacing.lg),
            _KpiGrid(cards: kpis),
            const SizedBox(height: RestoflowSpacing.lg),
            sections,
          ],
        );
      },
    );
  }

  static String _methodLabel(AppLocalizations l10n, String method) =>
      method == 'cash' ? l10n.dashboardPaymentMethodCash : method;
}

/// The reports title + the report day context (day + a demo/live pill).
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.report, required this.isDemo});

  final DashboardReport report;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dayText =
        '${l10n.dashboardReportDayLabel}: ${report.businessDateLabel}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboardReportsHeading,
          key: const Key('reports-heading'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              dayText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            DashboardStatusPill(
              label: isDemo ? l10n.dashboardDemoDay : l10n.dashboardLiveDataTag,
            ),
          ],
        ),
      ],
    );
  }
}

/// Lays the KPI metric cards out in a responsive grid (4 / 2 / 1 columns).
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : (constraints.maxWidth >= 560 ? 2 : 1);
        const gap = RestoflowSpacing.md;
        final gutters = gap * (columns - 1);
        final cardWidth = (constraints.maxWidth - gutters) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

/// The loading state while the report is fetched through the repository.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('reports-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: RestoflowSpacing.lg),
          Text(
            l10n.dashboardLoadingReports,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The error state when the report fails to load, with a retry action.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('reports-error'),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              l10n.dashboardReportsError,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: RestoflowSpacing.lg),
            FilledButton.icon(
              key: const Key('reports-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.dashboardRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state when there is no report data for the day.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('reports-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Text(
            l10n.dashboardNoReportData,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
