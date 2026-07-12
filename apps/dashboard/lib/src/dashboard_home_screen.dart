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

/// The RF-104/RF-119 owner/manager reports dashboard, redesigned under RF-127
/// into a calm, data-forward Overview: calm page chrome (title + period + range
/// + refresh) over the RF-125 shell, the real readiness/setup content high up
/// (via the [setupPanel] slot), four prioritized primary KPIs, a compact
/// secondary operational summary, a dominant sales-by-hour area chart beside the
/// payment-mix donut, then top sellers / recent orders and the remaining
/// summaries in a clear responsive hierarchy.
///
/// The report is loaded through the [dashboardReportProvider] seam (unchanged),
/// so the screen keeps its honest loading / error / empty / range-unavailable
/// states and its refresh. Money is integer minor units (DECISION D-007); chrome
/// is localized; layout is responsive and RTL/LTR-correct. RF-127 reorganizes
/// presentation only — no data source, calculation, provider, or repository
/// changed.
class DashboardHomeScreen extends ConsumerWidget {
  const DashboardHomeScreen({this.setupPanel, super.key});

  /// RF-127 presentation-only composition slot: the shell passes the existing
  /// [DashboardSetupCenter] widget here so the readiness/setup content sits
  /// immediately after the page chrome (high priority) without moving any
  /// repository ownership, provider override, or callback. Null (demo mode /
  /// tests / no real repos) => no readiness panel, exactly as before.
  final Widget? setupPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RF-140: the same demo/real switch the repository seam reads, so the
    // banner/header are honest about the data source (never claim demo data in
    // real mode, nor vice versa). Demo is the DEFAULT.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final reportAsync = ref.watch(dashboardReportProvider);

    void refresh() => ref.invalidate(dashboardReportProvider);

    // Calm persistent chrome (RF-127): the page header + range chips stay above
    // the loading/error/data states so the title, period, refresh, and range are
    // available in every state (range switchable at any time, as before).
    final panel = setupPanel;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverviewChrome(onRefresh: refresh),
          if (panel != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                RestoflowSpacing.lg,
                RestoflowSpacing.md,
                RestoflowSpacing.lg,
                0,
              ),
              child: panel,
            ),
          Expanded(
            child: reportAsync.when(
              data: (report) => _ReportContent(report: report, isDemo: isDemo),
              loading: () => const _LoadingState(),
              error: (_, _) => _ErrorState(onRetry: refresh),
            ),
          ),
        ],
      ),
    );
  }
}

/// RF-127/RF-132 — the compact Overview page chrome: the shared
/// [RestoflowPageHeader] (localized "Overview" title + the reporting-period
/// subtitle + the refresh action, no icon badge — the reference keeps the
/// first row tight) with the cohesive reporting-range control beneath it.
/// Persistent above the report states so the range is switchable at any time.
/// The demo/live data source stays honest via the shell's mode pill + the
/// report banner, so no duplicate mode pill is shown here.
class _OverviewChrome extends ConsumerWidget {
  const _OverviewChrome({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final range = ref.watch(reportRangeProvider);
    final report = ref.watch(dashboardReportProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RestoflowPageHeader(
          key: const Key('reports-heading'),
          title: l10n.dashboardNavOverview,
          subtitle: _subtitleFor(l10n, range, report),
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            0,
          ),
          actions: [
            IconButton(
              key: const Key('reports-refresh-button'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: l10n.dashboardRefresh,
            ),
          ],
        ),
        const _RangeFilterBar(),
      ],
    );
  }
}

/// RF-REPORT-004 / RF-132 — the reporting range filter (Today / Yesterday /
/// Last 7 days / Last 30 days) as ONE cohesive segmented control (the four
/// options are a single mutually-exclusive group, per the approved reference).
/// Selecting a segment writes [reportRangeProvider]; the report provider
/// watches it and reloads for the new window. Rendered ABOVE the
/// loading/error/data states so the range can be changed at any time. The
/// labels are localized; each segment keeps its stable `range-chip-<wire>` key.
/// On narrow widths the segments flex to the full width; on wide layouts the
/// control sits at the reading end (reference composition).
class _RangeFilterBar extends ConsumerWidget {
  const _RangeFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(reportRangeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RestoflowSpacing.lg,
        RestoflowSpacing.md,
        RestoflowSpacing.lg,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final control = RestoflowSegmentedControl<ReportRange>(
            key: const Key('reports-range-filter'),
            expand: narrow,
            selected: selected,
            onSelected: (r) => ref.read(reportRangeProvider.notifier).state = r,
            segments: [
              for (final r in ReportRange.values)
                RestoflowSegment(
                  value: r,
                  label: _rangeLabel(l10n, r),
                  icon: Icons.calendar_today,
                  key: Key('range-chip-${r.wire}'),
                ),
            ],
          );
          if (narrow) return control;
          return Align(
            alignment: AlignmentDirectional.centerEnd,
            child: control,
          );
        },
      ),
    );
  }
}

/// The loaded report: a scrollable, responsive, data-forward layout (RF-127).
class _ReportContent extends StatelessWidget {
  const _ReportContent({required this.report, required this.isDemo});

  final DashboardReport report;

  /// Whether the report is demo data (computed locally) or real data. Drives the
  /// banner so the data source is labelled honestly (RF-140).
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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

    // RF-140: demo mode shows the demo-data notice; real mode shows a slim
    // "live · limited" caution notice — never a demo/deferred banner over real
    // data.
    final banner = isDemo
        ? RestoflowNoticeBanner(
            key: const Key('reports-demo-banner'),
            body: l10n.dashboardDemoReportsNotice,
          )
        : RestoflowNoticeBanner(
            key: const Key('reports-realmode-banner'),
            title: l10n.dashboardLiveReportsTitle,
            body: l10n.dashboardRealModeNotice,
            icon: Icons.insights_outlined,
            tone: RestoflowTone.warning,
          );

    // RF-REPORT-004: the selected range could not be served — honest note (never
    // today's data mislabelled). Chrome (title + range chips) stays above.
    if (!report.rangeSupported) {
      return ListView(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        children: [
          banner,
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
          const SizedBox(height: RestoflowSpacing.xl),
          const _EmptyState(),
        ],
      );
    }

    // --- Primary KPIs (RF-127, restyled to the approved reference under
    // RF-132): the four headline figures as white KPI tiles with tinted icon
    // tiles, prominent dark values, and one consistent card height. ---
    final primaryKpis = <Widget>[
      RestoflowMetricCard(
        key: const Key('kpi-gross-sales'),
        style: RestoflowMetricCardStyle.kpi,
        label: l10n.dashboardGrossSales,
        value: money(report.grossSalesMinor),
        icon: Icons.point_of_sale_outlined,
        delta: deltaOf(report.grossSalesMinor, comparison?.grossSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-net-sales'),
        style: RestoflowMetricCardStyle.kpi,
        tone: RestoflowTone.success,
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
        style: RestoflowMetricCardStyle.kpi,
        tone: RestoflowTone.info,
        label: l10n.dashboardOrders,
        value: report.orderCount.toString(),
        icon: Icons.receipt_long_outlined,
        delta: deltaOf(report.orderCount, comparison?.orderCount),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-avg-ticket'),
        style: RestoflowMetricCardStyle.kpi,
        tone: RestoflowTone.success,
        label: l10n.dashboardAvgOrderValue,
        value: money(report.avgOrderValueMinor),
        icon: Icons.trending_up,
      ),
    ];

    // --- Secondary operational summary (RF-127): compact, not a wall of equal
    // cards. Every previously-shown figure is preserved (none removed). ---
    final openCaption = '${l10n.dashboardOpenOrders}: ${report.openOrderCount}';
    final secondaryKpis = <Widget>[
      RestoflowMetricCard(
        key: const Key('kpi-cash-sales'),
        style: RestoflowMetricCardStyle.kpi,
        label: l10n.dashboardCashSales,
        value: money(report.cashSalesMinor),
        icon: Icons.account_balance_wallet_outlined,
        delta: deltaOf(report.cashSalesMinor, comparison?.cashSalesMinor),
      ),
      RestoflowMetricCard(
        key: const Key('kpi-completed'),
        style: RestoflowMetricCardStyle.kpi,
        tone: RestoflowTone.success,
        label: l10n.dashboardCompletedOrders,
        value: report.completedOrderCount.toString(),
        caption: openCaption,
        icon: Icons.task_alt,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-unpaid'),
        style: RestoflowMetricCardStyle.kpi,
        tone: RestoflowTone.warning,
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

    // RF-127: the sales-by-hour curve is the DOMINANT visualization. It renders
    // only when the report carries hourly data (demo mode / RF-REPORT-002); real
    // mode without it leaves it out, so nothing is fabricated. Money stays
    // integer-minor: the chart takes raw ints and the peak label is formatted
    // here, plus an accessible textual summary. RF-132 adds the reference's
    // y-axis money gridlines (tick VALUES computed with integer math from the
    // real peak; labels formatted by MoneyFormatter — never floating point).
    final hourly = report.hourlyNetSales;
    final Widget? salesByHour;
    if (hourly.isEmpty) {
      salesByHour = null;
    } else {
      // The peak hour drives both the chart's peak marker label and the
      // accessible summary — real hourly data only, never fabricated.
      var peakEntry = hourly.first;
      for (final h in hourly) {
        if (h.netSalesMinor > peakEntry.netSalesMinor) peakEntry = h;
      }
      final peakLabel = money(peakEntry.netSalesMinor);
      salesByHour = RestoflowSectionCard(
        key: const Key('sales-by-hour-card'),
        title: l10n.dashboardSalesByHour,
        children: [
          const SizedBox(height: RestoflowSpacing.sm),
          RestoflowAreaChart(
            key: const Key('sales-by-hour-chart'),
            height: 260,
            points: [
              for (final h in hourly)
                RestoflowAreaDatum(
                  label: h.hourLabel.split(':').first,
                  value: h.netSalesMinor,
                ),
            ],
            peakValueLabel: peakLabel,
            yAxisTicks: _axisTicksFor(peakEntry.netSalesMinor),
            yAxisLabelBuilder: money,
            // A meaningful, localized screen-reader summary naming the peak hour
            // and its formatted value (not conveyed by colour/shape alone).
            semanticsLabel: l10n.dashboardSalesByHourSemantics(
              peakEntry.hourLabel,
              peakLabel,
            ),
          ),
        ],
      );
    }

    // "1c" payment-mix donut (real data only — from report.paymentMethods).
    final Widget? paymentMix = report.paymentMethods.isEmpty
        ? null
        : _PaymentMixCard(
            methods: report.paymentMethods,
            currencyCode: report.currencyCode,
          );

    // LIVE-UX-001 / RF-132: when the report is live-but-limited (real mode with
    // none of the richer analytics sourced yet), an honest "more analytics
    // coming" panel HOLDS the analytics slot (instead of the legacy tables
    // collapsing into the first viewport). No fake chart, no fake values — a
    // muted icon + the existing explanation. Never shown in demo (full data).
    final showLimitedNote =
        !isDemo &&
        report.hourlyNetSales.isEmpty &&
        report.branches.isEmpty &&
        report.topItems.isEmpty &&
        report.recentOrders.isEmpty;
    final theme = Theme.of(context);
    final limitedNote = RestoflowSectionCard(
      key: const Key('reports-limited-analytics'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xl),
          child: Column(
            children: [
              Icon(
                Icons.query_stats_outlined,
                size: RestoflowIconSizes.xl,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: RestoflowSpacing.md),
              Text(
                l10n.dashboardLiveReportsPending,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    // RF-REPORT-003: the real (or demo) shift/cash reconciliation card — present
    // whenever shiftCash is populated; null in the fallback so it hides (never
    // fabricated).
    final shiftCash = report.shiftCash;
    final Widget? shiftCashCard = shiftCash == null
        ? null
        : _ShiftCashCard(
            shiftCash: shiftCash,
            currencyCode: report.currencyCode,
            range: report.range,
          );

    // RF-127 hierarchy: top sellers + recent orders form the strong secondary
    // row; daily/payment/branch/shift summaries remain accessible below in a
    // balanced two-column grid rather than a wall of equal cards. RF-132: in
    // the live-limited state the honest limited-analytics panel HOLDS the
    // chart's slot in the analytics row (beside the real payment mix when that
    // exists), so the legacy tables never climb into the first viewport.
    final strongPair = <Widget>[
      if (report.topItems.isNotEmpty) topItems,
      if (report.recentOrders.isNotEmpty) recentOrders,
    ];
    final remaining = <Widget>[
      summary,
      payment,
      if (report.branches.isNotEmpty) branches,
      if (shiftCashCard != null) shiftCashCard,
    ];

    // RF-132 (Codex review): the reference order is primary KPIs → the
    // dominant analytics row → the compact secondary operational cards →
    // top sellers / recent orders → the detailed summaries. The secondary
    // grid therefore renders AFTER the analytics row (or the honest limited
    // panel holding its slot), never between the KPIs and the chart.
    final analyticsStart =
        salesByHour ?? (showLimitedNote ? limitedNote : null);
    final blocks = <Widget>[
      banner,
      _KpiGrid(cards: primaryKpis),
      if (analyticsStart != null || paymentMix != null)
        _AnalyticsRow(hourly: analyticsStart, mix: paymentMix),
      _KpiGrid(cards: secondaryKpis, wideColumns: 3),
      if (strongPair.isNotEmpty) _PairRow(sections: strongPair),
      if (remaining.isNotEmpty) _TwoColumn(sections: remaining),
    ];

    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: _verticallySpaced(blocks),
    );
  }

  static String _methodLabel(AppLocalizations l10n, String method) =>
      method == 'cash' ? l10n.dashboardPaymentMethodCash : method;
}

/// RF-127 — the primary analytics row: the dominant sales-by-hour chart beside
/// the payment-mix donut at wide widths (the chart gets the larger share), or
/// stacked (chart first) on narrow widths. Renders whichever pieces exist.
class _AnalyticsRow extends StatelessWidget {
  const _AnalyticsRow({this.hourly, this.mix});

  final Widget? hourly;
  final Widget? mix;

  @override
  Widget build(BuildContext context) {
    final h = hourly;
    final m = mix;
    if (h == null && m == null) return const SizedBox.shrink();
    if (h == null) return m!;
    if (m == null) return h;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= RestoflowBreakpoints.wide) {
          // RF-132: the reference gives the hourly chart roughly 7:3 of the
          // row (clearly dominant) rather than the previous 3:2.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: h),
              const SizedBox(width: RestoflowSpacing.lg),
              Expanded(flex: 3, child: m),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            h,
            const SizedBox(height: RestoflowSpacing.lg),
            m,
          ],
        );
      },
    );
  }
}

/// RF-127 — a two-up row for the strong secondary pair (top sellers + recent
/// orders): side by side at wide widths, stacked on narrow. With a single
/// section it renders that section full width.
class _PairRow extends StatelessWidget {
  const _PairRow({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.length == 1) return sections.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= RestoflowBreakpoints.wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: sections[0]),
              const SizedBox(width: RestoflowSpacing.lg),
              Expanded(child: sections[1]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _verticallySpaced(sections),
        );
      },
    );
  }
}

/// RF-127 — the remaining summaries in a balanced two-column grid at wide widths
/// (alternating so both columns fill), or a single column when narrow. Keeps all
/// summaries accessible without a wall of equal-weight cards.
class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn =
            constraints.maxWidth >= RestoflowBreakpoints.wide &&
            sections.length > 1;
        if (!twoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _verticallySpaced(sections),
          );
        }
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < sections.length; i++) {
          (i.isEven ? left : right).add(sections[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: _verticallySpaced(left))),
            const SizedBox(width: RestoflowSpacing.lg),
            Expanded(child: Column(children: _verticallySpaced(right))),
          ],
        );
      },
    );
  }
}

/// RF-132 — the sales-by-hour y-axis tick values, derived from the REAL peak
/// with integer math only (DECISION D-007: no floating point anywhere near
/// money). Four evenly-spaced ticks at a "nice" whole-currency step (1/2/5 ×
/// 10^k major units) whose top tick covers the peak. Returns minor units; the
/// chart labels them through the caller's MoneyFormatter closure.
List<int> _axisTicksFor(int peakMinor) {
  if (peakMinor <= 0) return const [];
  // Ceiling of the peak in whole major units (100 minor = 1 major).
  final maxMajor = (peakMinor + 99) ~/ 100;
  var magnitude = 1;
  while (true) {
    for (final s in const [1, 2, 5]) {
      final stepMajor = s * magnitude;
      if (stepMajor * 4 >= maxMajor) {
        return [for (var i = 1; i <= 4; i++) i * stepMajor * 100];
      }
    }
    magnitude *= 10;
  }
}

/// The localized label for a reporting range (shared by the chrome subtitle and
/// the range chips).
String _rangeLabel(AppLocalizations l10n, ReportRange r) => switch (r) {
  ReportRange.today => l10n.dashboardRangeToday,
  ReportRange.yesterday => l10n.dashboardRangeYesterday,
  ReportRange.last7 => l10n.dashboardRangeLast7,
  ReportRange.last30 => l10n.dashboardRangeLast30,
};

/// The chrome subtitle: for today, the business-date "Report day: …" context
/// once the report is loaded; for other ranges, the range + branch-local window;
/// while the report is still loading, just the range label. Never fabricated —
/// only the loaded report's own labels are used.
String _subtitleFor(
  AppLocalizations l10n,
  ReportRange range,
  DashboardReport? report,
) {
  if (report == null) return _rangeLabel(l10n, range);
  if (report.range == ReportRange.today) {
    return '${l10n.dashboardReportDayLabel}: ${report.businessDateLabel}';
  }
  return _rangeSubtitle(l10n, report);
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
  final label = _rangeLabel(l10n, report.range);
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

    final donut = RestoflowDonutChart(
      size: 120,
      ringWidth: 15,
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
    );

    // RF-132 reference legend: one quiet row per tender — dot + name at the
    // reading start, the share + amount in a soft boxed value at the end.
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in methods)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: Row(
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
                // Both sides flex (the value box gets the larger share) so a
                // narrow card ellipsizes gracefully instead of overflowing.
                Flexible(
                  flex: 2,
                  child: Text(
                    label(m.method),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: RestoflowSpacing.sm),
                Flexible(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: RestoflowSpacing.sm,
                      vertical: RestoflowSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                    ),
                    child: Text(
                      '${total == 0 ? 0 : (m.totalMinor * 100 / total).round()}% · '
                      '${MoneyFormatter.formatMinor(m.totalMinor, currencyCode)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return RestoflowSectionCard(
      key: const Key('payment-mix-card'),
      title: l10n.dashboardPaymentMix,
      children: [
        const SizedBox(height: RestoflowSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // Donut beside the legend when the card is wide enough (the
            // reference's side-by-side card); stacked and centred when narrow.
            if (constraints.maxWidth >= 300) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  donut,
                  const SizedBox(width: RestoflowSpacing.lg),
                  Expanded(child: legend),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: donut),
                const SizedBox(height: RestoflowSpacing.md),
                legend,
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Lays the KPI metric cards out in a responsive grid. [wideColumns] columns at
/// the wide breakpoint (4 for the primary row, 3 for the compact secondary
/// summary), 2 on mid widths, 1 when compact.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cards, this.wideColumns = 4});

  final List<Widget> cards;
  final int wideColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= RestoflowBreakpoints.wide
            ? wideColumns
            : (constraints.maxWidth >= RestoflowBreakpoints.compact ? 2 : 1);
        // RF-132: the reference breathes a little more between KPI tiles.
        const gap = RestoflowSpacing.lg;
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
/// of the Overview (KPI grid + chart) instead of a lone spinner — deliberately
/// spinner-free and non-animated (the shared [RestoflowSkeleton] is static, so it
/// stays `pumpAndSettle`-safe). The localized caption remains for screen readers.
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
            child: RestoflowSkeleton(height: 220, radius: RestoflowRadii.md),
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
