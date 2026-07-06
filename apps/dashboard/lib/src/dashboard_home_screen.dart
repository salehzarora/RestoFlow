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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RangeFilterBar(),
          Expanded(
            child: reportAsync.when(
              data: (report) => _ReportContent(
                report: report,
                isDemo: isDemo,
                onRefresh: refresh,
              ),
              loading: () => const _LoadingState(),
              error: (_, _) => _ErrorState(onRetry: refresh),
            ),
          ),
        ],
      ),
    );
  }
}

/// RF-REPORT-004 — the reporting range filter (Today / Yesterday / Last 7 days /
/// Last 30 days). Selecting a chip writes [reportRangeProvider]; the report
/// provider watches it and reloads for the new window. Rendered ABOVE the
/// loading/error/data states so the range can be changed at any time. The chip
/// labels are localized; the Wrap keeps it responsive + RTL-correct.
class _RangeFilterBar extends ConsumerWidget {
  const _RangeFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(reportRangeProvider);
    String labelFor(ReportRange r) => switch (r) {
      ReportRange.today => l10n.dashboardRangeToday,
      ReportRange.yesterday => l10n.dashboardRangeYesterday,
      ReportRange.last7 => l10n.dashboardRangeLast7,
      ReportRange.last30 => l10n.dashboardRangeLast30,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.lg,
        0,
      ),
      child: Wrap(
        key: const Key('reports-range-filter'),
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        children: [
          for (final r in ReportRange.values)
            ChoiceChip(
              key: Key('range-chip-${r.wire}'),
              label: Text(labelFor(r)),
              selected: selected == r,
              onSelected: (_) =>
                  ref.read(reportRangeProvider.notifier).state = r,
            ),
        ],
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
    final theme = Theme.of(context);
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    // The terracotta "accent" tile is a semantic colour, not one of the five
    // RestoflowTones, so it is passed to the filled metric card as a fillStyle.
    final accentFill = RestoflowToneStyle(
      container: semantic.accentContainer,
      onContainer: semantic.onAccentContainer,
      accent: semantic.accent,
      icon: Icons.account_balance_wallet_outlined,
    );

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, report.currencyCode);

    // DESIGN-002 / RF-REPORT-004: a trend delta vs the prior EQUIVALENT period,
    // when one exists — demo, the live-limited "vs yesterday" (LIVE-UX-001), or
    // the range's prior window (owner_report_range). The label matches the
    // selected range; a null comparison shows no delta (never invented). Integer
    // percentage math only (never floating-point).
    String deltaLabel(int pct) => switch (report.range) {
      ReportRange.today => l10n.dashboardDeltaVsYesterday(pct),
      ReportRange.yesterday => l10n.dashboardDeltaVsDayBefore(pct),
      ReportRange.last7 => l10n.dashboardDeltaVsPrev7(pct),
      ReportRange.last30 => l10n.dashboardDeltaVsPrev30(pct),
    };
    final comparison = report.comparison;
    RestoflowMetricDelta? deltaOf(int current, int? prior) {
      final pct = deltaPercent(current, prior);
      if (pct == null) return null;
      return RestoflowMetricDelta(
        label: deltaLabel(pct.abs()),
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

    // RF-REPORT-004: the selected range could not be served (owner_report_range
    // not deployed yet and the range isn't today). Show an honest note — never
    // today's data mislabelled, never fabricated figures.
    if (!report.rangeSupported) {
      return ListView(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        children: [
          banner,
          const SizedBox(height: RestoflowSpacing.lg),
          header,
          const SizedBox(height: RestoflowSpacing.xl),
          const _RangeUnavailable(),
        ],
      );
    }

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
        // "Today's sales" only reads right for today; other ranges use the
        // range-neutral "Net sales".
        label: report.range == ReportRange.today
            ? l10n.dashboardTodaySales
            : l10n.dashboardNetSales,
        value: money(report.netSalesMinor),
        icon: Icons.payments_outlined,
        delta: deltaOf(report.netSalesMinor, comparison?.netSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-orders'),
        label: l10n.dashboardOrders,
        value: report.orderCount.toString(),
        icon: Icons.receipt_long_outlined,
        filled: true,
        tone: RestoflowTone.info,
        delta: deltaOf(report.orderCount, comparison?.orderCount),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-avg-ticket'),
        label: l10n.dashboardAvgOrderValue,
        value: money(report.avgOrderValueMinor),
        icon: Icons.trending_up,
        filled: true,
        tone: RestoflowTone.success,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-cash-sales'),
        label: l10n.dashboardCashSales,
        value: money(report.cashSalesMinor),
        icon: Icons.account_balance_wallet_outlined,
        filled: true,
        fillStyle: accentFill,
        delta: deltaOf(report.cashSalesMinor, comparison?.cashSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-completed'),
        label: l10n.dashboardCompletedOrders,
        value: report.completedOrderCount.toString(),
        caption: openCaption,
        icon: Icons.task_alt,
        filled: true,
        tone: RestoflowTone.neutral,
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
        // RF-REPORT-003: cash reconciliation (variance) + shift status live in the
        // dedicated "Shift & cash" card when it is present — showing them here too
        // would duplicate (and, in real mode, contradict with ₪0.00) that card.
        if (report.shiftCash == null) ...[
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
      ],
    );

    final payment = DailySummaryCard(
      key: const Key('payment-summary-card'),
      title: l10n.dashboardPaymentSummary,
      rows: [
        // RF-REPORT-003: the DRAWER-reconciliation rows (opening float / expected /
        // counted / variance) are owned by the "Shift & cash" card when present —
        // here they would duplicate it (and read ₪0.00 in real mode). The payment
        // card keeps the collection figures (cash sales, last cash, tenders).
        if (report.shiftCash == null)
          SummaryRow(
            label: l10n.dashboardOpeningFloat,
            value: money(report.openingFloatMinor),
          ),
        SummaryRow(
          label: l10n.dashboardCashSales,
          value: money(report.cashSalesMinor),
        ),
        if (report.shiftCash == null) ...[
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
        ],
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

    // "1c" top sellers: a numbered rank badge + name + `×qty · amount` + a mini
    // share bar (revenue / top revenue). Money stays formatted via MoneyFormatter.
    final topRevenue = report.topItems.isEmpty
        ? 0
        : report.topItems.first.lineRevenueMinor;
    final topItems = RestoflowSectionCard(
      key: const Key('top-items-card'),
      title: l10n.dashboardTopItems,
      children: [
        for (var i = 0; i < report.topItems.length; i++)
          RestoflowRankRow(
            rank: i + 1,
            name: report.topItems[i].name,
            meta:
                '×${report.topItems[i].quantity} · '
                '${MoneyFormatter.formatMinor(report.topItems[i].lineRevenueMinor, report.topItems[i].currencyCode)}',
            fraction: topRevenue == 0
                ? 0
                : report.topItems[i].lineRevenueMinor / topRevenue,
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
    // RF-REPORT-003: the real (or demo) shift/cash reconciliation card. Present
    // whenever shiftCash is populated (demo + real owner_daily_report); in the
    // sales_summary fallback it is null, so the card hides (never fabricated) —
    // the live-limited note already explains the gap.
    final shiftCash = report.shiftCash;
    final leftSections = <Widget>[
      summary,
      payment,
      // "1c" payment-mix donut (real data only — from report.paymentMethods).
      if (report.paymentMethods.isNotEmpty)
        _PaymentMixCard(
          methods: report.paymentMethods,
          currencyCode: report.currencyCode,
        ),
      if (shiftCash != null)
        _ShiftCashCard(
          shiftCash: shiftCash,
          currencyCode: report.currencyCode,
          range: report.range,
        ),
    ];
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

/// RF-REPORT-003 — the Overview's "Shift & cash" card: TODAY's closed-shift cash
/// reconciliation (counts + expected/counted/variance aggregate) and the last
/// closed shift. Money is integer-minor formatted here; variance is tinted calmly
/// (never a dramatic red). A day with no closed shifts shows a calm empty state.
class _ShiftCashCard extends StatelessWidget {
  const _ShiftCashCard({
    required this.shiftCash,
    required this.currencyCode,
    required this.range,
  });

  final ShiftCash shiftCash;
  final String currencyCode;

  /// RF-REPORT-004 — the selected range, so the "closed" count reads "closed
  /// today" for today and range-neutral "closed" otherwise.
  final ReportRange range;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String money(int m) => MoneyFormatter.formatMinor(m, currencyCode);
    final last = shiftCash.lastClosedShift;
    // RF-REPORT-004: the additional closed shifts beyond the one shown in detail.
    // Exclude the last-closed by SHIFT ID (not positionally) so a payload whose
    // last_closed_shift is null/absent while recent_closed_shifts is non-empty
    // still shows ALL recent shifts rather than silently dropping the first one.
    final more = last == null
        ? shiftCash.recentClosedShifts
        : shiftCash.recentClosedShifts
              .where((s) => s.shiftId != last.shiftId)
              .toList(growable: false);
    final closedLabel = range == ReportRange.today
        ? l10n.dashboardShiftClosedToday(shiftCash.closedShiftCount)
        : l10n.dashboardShiftClosedInRange(shiftCash.closedShiftCount);

    return RestoflowSectionCard(
      key: const Key('shift-cash-card'),
      title: l10n.dashboardShiftCashTitle,
      children: [
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          children: [
            RestoflowStatusPill(label: closedLabel, tone: RestoflowTone.info),
            RestoflowStatusPill(
              label: l10n.dashboardShiftOpenNow(shiftCash.openShiftCount),
              tone: RestoflowTone.neutral,
            ),
          ],
        ),
        if (!shiftCash.hasClosedShifts) ...[
          const SizedBox(height: RestoflowSpacing.md),
          Text(
            range == ReportRange.today
                ? l10n.dashboardShiftNoneToday
                : l10n.dashboardShiftNoneRange,
            key: const Key('shift-cash-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          SectionRow(
            label: l10n.dashboardShiftExpectedCash,
            trailingValue: money(shiftCash.expectedCashMinor),
          ),
          SectionRow(
            label: l10n.dashboardCountedCash,
            trailingValue: money(shiftCash.countedCashMinor),
          ),
          _VarianceRow(
            label: l10n.dashboardCashVariance,
            varianceMinor: shiftCash.varianceMinor,
            currencyCode: currencyCode,
          ),
          if (last != null) ...[
            const Divider(height: RestoflowSpacing.xl),
            _LastClosedShift(shift: last, currencyCode: currencyCode),
          ],
          if (more.isNotEmpty) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            _RecentShiftsList(shifts: more, currencyCode: currencyCode),
          ],
        ],
      ],
    );
  }
}

/// A cash-variance row whose value is CALMLY tinted (never dramatic): exact = the
/// default text colour, overage = success, shortage = warning. Integer minor.
class _VarianceRow extends StatelessWidget {
  const _VarianceRow({
    required this.label,
    required this.varianceMinor,
    required this.currencyCode,
  });

  final String label;
  final int varianceMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = varianceMinor == 0
        ? RestoflowTone.neutral
        : (varianceMinor > 0 ? RestoflowTone.success : RestoflowTone.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            MoneyFormatter.formatMinor(varianceMinor, currencyCode),
            key: const Key('shift-cash-variance'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: varianceMinor == 0
                  ? theme.colorScheme.onSurface
                  : tone.styleOf(theme).accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact summary of the most recent closed shift: which branch + when, who
/// opened/closed it, the RF-REPORT-004 per-shift detail (opening float, duration,
/// orders / collected / cash) when available, and its own cash variance (tinted
/// calmly). The detail rows only render when sourced (owner_report_range), so the
/// today-only fallback shows just branch/time/closed-by/variance.
class _LastClosedShift extends StatelessWidget {
  const _LastClosedShift({required this.shift, required this.currencyCode});

  final ClosedShiftSummary shift;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = [
      if (shift.branchName.isNotEmpty) shift.branchName,
      if (shift.closedAtLabel.isNotEmpty) shift.closedAtLabel,
    ].join(' · ');
    return Column(
      key: const Key('shift-cash-last'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboardShiftLastClosed,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(subtitle, style: theme.textTheme.bodyMedium),
        ],
        if (shift.openedByName != null && shift.openedByName!.isNotEmpty)
          Text(
            l10n.dashboardShiftOpenedBy(shift.openedByName!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (shift.closedByName.isNotEmpty)
          Text(
            l10n.dashboardShiftClosedBy(shift.closedByName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (shift.hasDetail) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          _ShiftDetailChips(shift: shift, currencyCode: currencyCode),
        ],
        const SizedBox(height: RestoflowSpacing.xs),
        _VarianceRow(
          label: l10n.dashboardCashVariance,
          varianceMinor: shift.varianceMinor,
          currencyCode: currencyCode,
        ),
      ],
    );
  }
}

/// RF-REPORT-004 — a compact Wrap of the per-shift detail (opening float,
/// duration, order count, collected, cash sales), each rendered only when its
/// value is present. Muted "Label value" pieces so the card stays readable and
/// RTL-correct without a heavy table.
class _ShiftDetailChips extends StatelessWidget {
  const _ShiftDetailChips({required this.shift, required this.currencyCode});

  final ClosedShiftSummary shift;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String money(int m) => MoneyFormatter.formatMinor(m, currencyCode);
    final pieces = <String>[
      if (shift.orderCount != null)
        '${l10n.dashboardOrders}: ${shift.orderCount}',
      if (shift.collectedMinor != null)
        '${l10n.dashboardShiftCollected}: ${money(shift.collectedMinor!)}',
      if (shift.cashSalesMinor != null)
        '${l10n.dashboardCashSales}: ${money(shift.cashSalesMinor!)}',
      if (shift.openingFloatMinor != null)
        '${l10n.dashboardOpeningFloat}: ${money(shift.openingFloatMinor!)}',
      if (shift.durationMinutes != null)
        '${l10n.dashboardShiftDurationLabel}: '
            '${_shiftDurationText(l10n, shift.durationMinutes!)}',
    ];
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: RestoflowSpacing.md,
      runSpacing: RestoflowSpacing.xxs,
      children: [
        for (final p in pieces)
          Text(
            p,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// RF-REPORT-004 — the remaining closed shifts in the range (beyond the one shown
/// in detail), inside a collapsible section so the card is not overloaded. Each
/// row is a compact branch · time · variance line with the per-shift detail
/// beneath it (when available).
class _RecentShiftsList extends StatelessWidget {
  const _RecentShiftsList({required this.shifts, required this.currencyCode});

  final List<ClosedShiftSummary> shifts;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Theme(
      // Drop the default ExpansionTile dividers so it reads as part of the card.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('shift-cash-recent'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          l10n.dashboardShiftRecentTitle(shifts.length),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final s in shifts)
            Padding(
              padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
              child: _RecentShiftTile(shift: s, currencyCode: currencyCode),
            ),
        ],
      ),
    );
  }
}

/// One row in the recent-shifts list: branch · closed time on the leading side,
/// a calmly-tinted variance on the trailing side, and the per-shift detail
/// beneath (when sourced).
class _RecentShiftTile extends StatelessWidget {
  const _RecentShiftTile({required this.shift, required this.currencyCode});

  final ClosedShiftSummary shift;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = shift.varianceMinor == 0
        ? RestoflowTone.neutral
        : (shift.varianceMinor > 0
              ? RestoflowTone.success
              : RestoflowTone.warning);
    final title = [
      if (shift.branchName.isNotEmpty) shift.branchName,
      if (shift.closedAtLabel.isNotEmpty) shift.closedAtLabel,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
            Text(
              MoneyFormatter.formatMinor(shift.varianceMinor, currencyCode),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: shift.varianceMinor == 0
                    ? theme.colorScheme.onSurface
                    : tone.styleOf(theme).accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (shift.hasDetail) ...[
          const SizedBox(height: RestoflowSpacing.xxs),
          _ShiftDetailChips(shift: shift, currencyCode: currencyCode),
        ],
      ],
    );
  }
}

/// RF-REPORT-004 — the honest "this range isn't available yet" panel shown in
/// live mode when owner_report_range isn't deployed and the range isn't today
/// (the range chips stay visible above so the owner can switch back).
class _RangeUnavailable extends StatelessWidget {
  const _RangeUnavailable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      key: const Key('reports-range-unavailable'),
      icon: Icons.event_busy_outlined,
      message: l10n.dashboardRangeUnavailable,
    );
  }
}

/// The header subtitle for a non-today range: the range label plus its
/// branch-local start→end window when known (single-day windows collapse to one
/// date). Plain data strings — the range label is localized chrome.
String _rangeSubtitle(AppLocalizations l10n, DashboardReport report) {
  final label = switch (report.range) {
    ReportRange.today => l10n.dashboardRangeToday,
    ReportRange.yesterday => l10n.dashboardRangeYesterday,
    ReportRange.last7 => l10n.dashboardRangeLast7,
    ReportRange.last30 => l10n.dashboardRangeLast30,
  };
  final start = report.rangeStartLabel;
  final end = report.rangeEndLabel;
  if (start != null && end != null && start.isNotEmpty && end.isNotEmpty) {
    return start == end ? '$label · $end' : '$label · $start → $end';
  }
  return label;
}

/// Formats a whole-minute shift duration as a localized "Xh Ym" data string.
String _shiftDurationText(AppLocalizations l10n, int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  return l10n.dashboardShiftDurationValue(safe ~/ 60, safe % 60);
}

/// The Overview HERO header (Dashboard "1c"): the brand-gradient panel with the
/// period's big net-sales value + a delta line + a sparkline, plus the pinned
/// "Owner reports" heading, the "Report day: …" (or range) context, the
/// demo/live pill, and the refresh action. Money is formatted via
/// [MoneyFormatter]; the key/heading/day strings are preserved so the surface
/// stays honest and testable. RTL-safe (Rows + directional layout).
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
    final theme = Theme.of(context);
    String money(int m) => MoneyFormatter.formatMinor(m, report.currencyCode);
    final white70 = Colors.white.withValues(alpha: 0.82);
    final dayText = report.range == ReportRange.today
        ? '${l10n.dashboardReportDayLabel}: ${report.businessDateLabel}'
        : _rangeSubtitle(l10n, report);
    final valueLabel = report.range == ReportRange.today
        ? l10n.dashboardTodaySales
        : l10n.dashboardNetSales;
    final pct = deltaPercent(
      report.netSalesMinor,
      report.comparison?.netSalesMinor,
    );
    final spark = [for (final h in report.hourlyNetSales) h.netSalesMinor];

    final hero = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.insights_outlined,
              size: RestoflowIconSizes.md,
              color: white70,
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: Text(
                l10n.dashboardReportsHeading,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            RestoflowStatusPill(
              label: isDemo ? l10n.dashboardDemoDay : l10n.dashboardLiveDataTag,
              tone: RestoflowTone.info,
            ),
            IconButton(
              key: const Key('reports-refresh-button'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: l10n.dashboardRefresh,
            ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueLabel,
                    style: theme.textTheme.labelLarge?.copyWith(color: white70),
                  ),
                  const SizedBox(height: RestoflowSpacing.xxs),
                  Text(
                    money(report.netSalesMinor),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  Text(
                    dayText,
                    style: theme.textTheme.bodyMedium?.copyWith(color: white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pct != null) ...[
                    const SizedBox(height: RestoflowSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          size: RestoflowIconSizes.xs,
                          color: Colors.white,
                        ),
                        const SizedBox(width: RestoflowSpacing.xxs),
                        Flexible(
                          child: Text(
                            _heroDeltaLabel(l10n, report.range, pct.abs()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (spark.length > 1) ...[
              const SizedBox(width: RestoflowSpacing.md),
              _Sparkline(values: spark),
            ],
          ],
        ),
      ],
    );

    return ClipRRect(
      key: const Key('reports-heading'),
      borderRadius: BorderRadius.circular(RestoflowRadii.lg),
      child: RestoflowGradientHeader(hero: hero),
    );
  }
}

/// The hero's range-aware "vs prior period" delta label.
String _heroDeltaLabel(AppLocalizations l10n, ReportRange range, int pct) =>
    switch (range) {
      ReportRange.today => l10n.dashboardDeltaVsYesterday(pct),
      ReportRange.yesterday => l10n.dashboardDeltaVsDayBefore(pct),
      ReportRange.last7 => l10n.dashboardDeltaVsPrev7(pct),
      ReportRange.last30 => l10n.dashboardDeltaVsPrev30(pct),
    };

/// A tiny white polyline sparkline of the period's hourly net sales, drawn in
/// list (chronological) order — decorative, static, money-free.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    height: 44,
    child: CustomPaint(painter: _SparkPainter(values: values)),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values});

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - ((values[i] - minV) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

/// The "1c" payment-mix donut card: a ring of the period's tenders (real data
/// from `report.paymentMethods`, never invented) with a legend of dot + method +
/// share% + amount. Money via [MoneyFormatter]; RTL-safe.
class _PaymentMixCard extends StatelessWidget {
  const _PaymentMixCard({required this.methods, required this.currencyCode});

  final List<PaymentMethodLine> methods;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic =
        theme.extension<RestoflowSemanticColors>() ??
        RestoflowSemanticColors.of(theme.brightness);
    Color colorFor(String m) => switch (m) {
      'cash' => kRestoflowSeedColor,
      'card' => semantic.accent,
      'bit' => semantic.info,
      _ => semantic.warning,
    };
    String label(String m) => m == 'cash' ? l10n.dashboardPaymentMethodCash : m;
    final total = methods.fold<int>(0, (s, x) => s + x.totalMinor);
    final top = methods.reduce((a, b) => a.totalMinor >= b.totalMinor ? a : b);
    final topPct = total == 0 ? 0 : (top.totalMinor * 100 / total).round();

    return RestoflowSectionCard(
      key: const Key('payment-mix-card'),
      title: l10n.dashboardPaymentMix,
      children: [
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.xl,
          runSpacing: RestoflowSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RestoflowDonutChart(
              size: 140,
              segments: [
                for (final m in methods)
                  RestoflowDonutSegment(
                    value: m.totalMinor,
                    color: colorFor(m.method),
                    label: label(m.method),
                  ),
              ],
              centerLabel: '$topPct%',
              centerSub: label(top.method),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in methods)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: RestoflowSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorFor(m.method),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Text(
                          label(m.method),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Text(
                          '${total == 0 ? 0 : (m.totalMinor * 100 / total).round()}% · '
                          '${MoneyFormatter.formatMinor(m.totalMinor, currencyCode)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
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
