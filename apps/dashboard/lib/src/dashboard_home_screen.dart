import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'format/money_format.dart';
import 'state/dashboard_providers.dart';
import 'widgets/daily_summary_card.dart';
import 'widgets/dashboard_status_pill.dart';
import 'widgets/demo_notice_banner.dart';
import 'widgets/metric_card.dart';
import 'widgets/section_card.dart';

/// The RF-104 owner/manager dashboard demo screen: a demo-data banner, daily
/// KPI cards, a daily summary card, sales-by-branch, and top items.
///
/// In-memory only (Riverpod over a demo report) — no Supabase, no report views,
/// no backend. Money is integer minor units (DECISION D-007); chrome is
/// localized; layout is responsive and RTL/LTR-correct.
class DashboardHomeScreen extends ConsumerWidget {
  const DashboardHomeScreen({super.key});

  static const double _twoColBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = ref.watch(dashboardReportProvider);

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, report.currencyCode);

    final kpis = <Widget>[
      MetricCard(
        label: l10n.dashboardTodaySales,
        value: money(report.netSalesMinor),
        icon: Icons.payments_outlined,
      ),
      MetricCard(
        label: l10n.dashboardOrders,
        value: report.orderCount.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      MetricCard(
        label: l10n.dashboardAvgOrderValue,
        value: money(report.avgOrderValueMinor),
        icon: Icons.trending_up,
      ),
      MetricCard(
        label: l10n.dashboardCompletedOrders,
        value: report.completedOrderCount.toString(),
        caption: '${l10n.dashboardOpenOrders}: ${report.openOrderCount}',
        icon: Icons.task_alt,
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

    final branches = SectionCard(
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
      title: l10n.dashboardTopItems,
      children: [
        for (final item in report.topItems)
          SectionRow(
            label: item.name,
            secondary: '×${item.quantity}',
            trailingValue: MoneyFormatter.formatMinor(
              item.lineRevenueMinor,
              item.currencyCode,
            ),
          ),
      ],
    );

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
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumn = constraints.maxWidth >= _twoColBreakpoint;
          final sections = twoColumn
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: RestoflowSpacing.lg),
                    Expanded(
                      child: Column(
                        children: [
                          branches,
                          const SizedBox(height: RestoflowSpacing.lg),
                          topItems,
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    summary,
                    const SizedBox(height: RestoflowSpacing.lg),
                    branches,
                    const SizedBox(height: RestoflowSpacing.lg),
                    topItems,
                  ],
                );

          return ListView(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            children: [
              DemoNoticeBanner(message: l10n.dashboardDemoNotice),
              const SizedBox(height: RestoflowSpacing.lg),
              Text(
                l10n.dashboardOverviewHeading,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              _KpiGrid(cards: kpis),
              const SizedBox(height: RestoflowSpacing.lg),
              sections,
            ],
          );
        },
      ),
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
