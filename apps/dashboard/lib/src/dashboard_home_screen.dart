import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'data/demo_report.dart';
import 'format/money_format.dart';
import 'state/dashboard_providers.dart';
import 'widgets/daily_summary_card.dart';
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
    // RF-140: the same demo/real switch the repository seam reads, so the
    // banner/header are honest about the data source (never claim demo data in
    // real mode, nor vice versa). Demo is the DEFAULT.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final reportAsync = ref.watch(dashboardReportProvider);

    void refresh() => ref.invalidate(dashboardReportProvider);

    // The former nested AppBar is flattened into the page header (the shell
    // already provides the persistent chrome); the refresh action rides the
    // report header so it stays on the page.
    return Scaffold(
      body: reportAsync.when(
        data: (report) =>
            _ReportContent(report: report, isDemo: isDemo, onRefresh: refresh),
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(onRetry: refresh),
      ),
    );
  }
}

/// The loaded report: a scrollable, responsive layout of all report sections.
class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.report,
    required this.isDemo,
    required this.onRefresh,
  });

  final DashboardReport report;

  /// Whether the report is demo data (computed locally) or real data. Drives the
  /// banner + header pill so the data source is labelled honestly (RF-140).
  final bool isDemo;

  final VoidCallback onRefresh;

  static const double _twoColBreakpoint = RestoflowBreakpoints.wide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, report.currencyCode);

    // DESIGN-002: a trend delta vs the prior period, when one exists — demo, or
    // the live-limited "vs yesterday" derived from sales_summary (LIVE-UX-001).
    // A null comparison shows no delta (never invented). Integer percentage math
    // only (never floating-point).
    final comparison = report.comparison;
    RestoflowMetricDelta? deltaOf(int current, int? prior) {
      final pct = deltaPercent(current, prior);
      if (pct == null) return null;
      return RestoflowMetricDelta(
        label: l10n.dashboardDeltaVsYesterday(pct.abs()),
        positive: pct >= 0,
      );
    }

    final header = _ReportHeader(
      report: report,
      isDemo: isDemo,
      onRefresh: onRefresh,
    );
    // RF-140: demo mode shows the demo-data notice; real mode shows a slim
    // "live · limited" caution notice — never a demo/deferred banner over real
    // data. (Real mode currently fails closed before reaching this content; the
    // mode-aware banner keeps the screen honest for when real data lands.)
    final banner = isDemo
        ? RestoflowNoticeBanner(
            key: const Key('reports-demo-banner'),
            body: l10n.dashboardDemoReportsNotice,
          )
        : RestoflowNoticeBanner(
            key: const Key('reports-realmode-banner'),
            // LIVE-UX-001: a titled, iconed banner reads as an intentional
            // "live but limited" state rather than a bare caution strip.
            title: l10n.dashboardLiveReportsTitle,
            body: l10n.dashboardRealModeNotice,
            icon: Icons.insights_outlined,
            tone: RestoflowTone.warning,
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
      RestoflowMetricCard(
        key: const Key('kpi-gross-sales'),
        label: l10n.dashboardGrossSales,
        value: money(report.grossSalesMinor),
        icon: Icons.point_of_sale_outlined,
        delta: deltaOf(report.grossSalesMinor, comparison?.grossSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-net-sales'),
        label: l10n.dashboardTodaySales,
        value: money(report.netSalesMinor),
        icon: Icons.payments_outlined,
        delta: deltaOf(report.netSalesMinor, comparison?.netSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-orders'),
        label: l10n.dashboardOrders,
        value: report.orderCount.toString(),
        icon: Icons.receipt_long_outlined,
        delta: deltaOf(report.orderCount, comparison?.orderCount),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-avg-ticket'),
        label: l10n.dashboardAvgOrderValue,
        value: money(report.avgOrderValueMinor),
        icon: Icons.trending_up,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-cash-sales'),
        label: l10n.dashboardCashSales,
        value: money(report.cashSalesMinor),
        icon: Icons.account_balance_wallet_outlined,
        delta: deltaOf(report.cashSalesMinor, comparison?.cashSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-completed'),
        label: l10n.dashboardCompletedOrders,
        value: report.completedOrderCount.toString(),
        caption: openCaption,
        icon: Icons.task_alt,
      ),
      RestoflowMetricCard(
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
          trailing: RestoflowStatusPill(
            label: report.shiftStatus,
            tone: RestoflowTone.info,
          ),
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

    final branches = RestoflowSectionCard(
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

    final topItems = RestoflowSectionCard(
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

    final recentOrders = RestoflowSectionCard(
      key: const Key('recent-orders-card'),
      title: l10n.dashboardRecentOrders,
      children: [
        for (final row in report.recentOrders) RecentOrderTile(row: row),
      ],
    );

    // DESIGN-002: the sales-by-hour chart. Renders only when the report carries
    // hourly data (demo mode); real mode leaves it out, so nothing is
    // fabricated. Money stays integer-minor: the chart takes raw ints and the
    // peak label is formatted here.
    final hourly = report.hourlyNetSales;
    final Widget? salesByHour = hourly.isEmpty
        ? null
        : RestoflowSectionCard(
            key: const Key('sales-by-hour-card'),
            title: l10n.dashboardSalesByHour,
            children: [
              const SizedBox(height: RestoflowSpacing.sm),
              RestoflowBarChart(
                bars: [
                  for (final h in hourly)
                    RestoflowBarDatum(
                      label: h.hourLabel.split(':').first,
                      value: h.netSalesMinor,
                    ),
                ],
                peakValueLabel: money(
                  hourly
                      .map((h) => h.netSalesMinor)
                      .reduce((a, b) => a > b ? a : b),
                ),
              ),
            ],
          );

    // LIVE-UX-001: hide sections that carry NO rows (an empty card reads as
    // broken/old) and, when the report is live-but-limited (real mode with none
    // of the richer analytics sourced yet), show a calm "more analytics coming"
    // note so the gap is clearly INTENTIONAL. Never shown in demo (full data).
    final showLimitedNote =
        !isDemo &&
        report.hourlyNetSales.isEmpty &&
        report.branches.isEmpty &&
        report.topItems.isEmpty &&
        report.recentOrders.isEmpty;
    final limitedNote = RestoflowNoticeBanner(
      key: const Key('reports-limited-analytics'),
      body: l10n.dashboardLiveReportsPending,
      icon: Icons.query_stats_outlined,
    );
    final leftSections = <Widget>[summary, payment];
    final rightSections = <Widget>[
      if (report.branches.isNotEmpty) branches,
      if (report.topItems.isNotEmpty) topItems,
      if (report.recentOrders.isNotEmpty) recentOrders,
      if (showLimitedNote) limitedNote,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn =
            constraints.maxWidth >= _twoColBreakpoint &&
            rightSections.isNotEmpty;
        final sections = twoColumn
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(children: _verticallySpaced(leftSections)),
                  ),
                  const SizedBox(width: RestoflowSpacing.lg),
                  Expanded(
                    child: Column(children: _verticallySpaced(rightSections)),
                  ),
                ],
              )
            : Column(
                children: _verticallySpaced([
                  ...leftSections,
                  ...rightSections,
                ]),
              );

        return ListView(
          padding: const EdgeInsets.all(RestoflowSpacing.lg),
          children: [
            banner,
            const SizedBox(height: RestoflowSpacing.lg),
            header,
            const SizedBox(height: RestoflowSpacing.lg),
            _KpiGrid(cards: kpis),
            if (salesByHour != null) ...[
              const SizedBox(height: RestoflowSpacing.lg),
              salesByHour,
            ],
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

/// Joins [items] into a vertical run with a large gap between them. Gaps are only
/// placed BETWEEN present items (LIVE-UX-001), so a hidden/empty section leaves no
/// dangling double-space.
List<Widget> _verticallySpaced(List<Widget> items) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) const SizedBox(height: RestoflowSpacing.lg),
    items[i],
  ],
];

/// The reports page header. DESIGN-002: consolidated onto the shared
/// [RestoflowPageHeader] (was a hand-rolled Row) so every dashboard tab's
/// header reads identically. The data-source pill + refresh ride the header's
/// trailing actions; the day context is the subtitle.
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.report,
    required this.isDemo,
    required this.onRefresh,
  });

  final DashboardReport report;
  final bool isDemo;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dayText =
        '${l10n.dashboardReportDayLabel}: ${report.businessDateLabel}';
    // The Key stays on the header so find.byKey('reports-heading') matches, and
    // the title/subtitle keep the pinned 'Owner reports' / 'Report day: …'
    // strings.
    return RestoflowPageHeader(
      key: const Key('reports-heading'),
      icon: Icons.insights_outlined,
      title: l10n.dashboardReportsHeading,
      subtitle: dayText,
      actions: [
        RestoflowStatusPill(
          label: isDemo ? l10n.dashboardDemoDay : l10n.dashboardLiveDataTag,
          tone: RestoflowTone.info,
        ),
        IconButton(
          key: const Key('reports-refresh-button'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          tooltip: l10n.dashboardRefresh,
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
        final columns = constraints.maxWidth >= RestoflowBreakpoints.wide
            ? 4
            : (constraints.maxWidth >= RestoflowBreakpoints.compact ? 2 : 1);
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

/// The loading state while the report is fetched. DESIGN-002: a static skeleton
/// of the Overview (header + KPI grid + chart) instead of a lone spinner —
/// deliberately spinner-free and non-animated (the shared [RestoflowSkeleton] is
/// static, so it stays `pumpAndSettle`-safe). The localized caption remains for
/// screen readers.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      key: const Key('reports-loading'),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: [
        Row(
          children: [
            const RestoflowSkeleton(
              width: 44,
              height: 44,
              radius: RestoflowRadii.md,
            ),
            const SizedBox(width: RestoflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  RestoflowSkeleton(width: 180, height: 22),
                  SizedBox(height: RestoflowSpacing.sm),
                  RestoflowSkeleton(width: 130, height: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        _KpiGrid(
          cards: const [
            _MetricSkeleton(),
            _MetricSkeleton(),
            _MetricSkeleton(),
            _MetricSkeleton(),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(RestoflowSpacing.lg),
            child: RestoflowSkeleton(height: 168, radius: RestoflowRadii.md),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Center(
          child: Text(
            l10n.dashboardLoadingReports,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single KPI card skeleton (a label bar + a value bar).
class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RestoflowSkeleton(width: 90, height: 14),
          SizedBox(height: RestoflowSpacing.md),
          RestoflowSkeleton(width: 120, height: 24),
        ],
      ),
    ),
  );
}

/// The error state when the report fails to load, with a retry action.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      key: const Key('reports-error'),
      icon: Icons.error_outline,
      tone: RestoflowTone.danger,
      title: l10n.dashboardReportsError,
      actions: [
        FilledButton.icon(
          key: const Key('reports-retry-button'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.dashboardRetry),
        ),
      ],
    );
  }
}

/// The empty state when there is no report data for the day.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      key: const Key('reports-empty'),
      icon: Icons.inbox_outlined,
      message: l10n.dashboardNoReportData,
    );
  }
}
