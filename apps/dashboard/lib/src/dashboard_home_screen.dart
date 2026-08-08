import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'analytics/analytics_labels.dart';
import 'analytics/comparison_delta.dart';
import 'analytics/dashboard_analytics_scope.dart';
import 'analytics/dashboard_destination.dart';
import 'analytics/dashboard_drilldown.dart';
import 'analytics/order_type_analytics.dart';
import 'analytics/owner_sales_series_query_key.dart';
import 'analytics/payment_method_analytics.dart';
import 'data/audit_log_models.dart' show AuditBranchOption;
import 'data/demo_report.dart';
import 'data/owner_sales_series.dart';
import 'format/money_format.dart';
import 'state/audit_log_providers.dart' show auditBranchOptionsProvider;
import 'state/dashboard_providers.dart';
// CLIENT-D: the ONE localized order-type mapper, already shared by the order
// history list, the active board and the detail sheet. Imported rather than
// re-declared so this surface cannot drift from what those call a dine-in.
import 'orders/order_history_screen.dart' show orderTypeLabel;
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
  const DashboardHomeScreen({
    this.setupPanel,
    this.deviceSummary,
    this.onNavigate,
    super.key,
  });

  /// RF-127 presentation-only composition slot: the shell passes the existing
  /// [DashboardSetupCenter] widget here so the readiness/setup content sits
  /// immediately after the page chrome (high priority) without moving any
  /// repository ownership, provider override, or callback. Null (demo mode /
  /// tests / no real repos) => no readiness panel, exactly as before.
  final Widget? setupPanel;

  /// Dashboard V2 presentation-only slot: the shell passes an honest device
  /// readiness card (active-of-configured counts from the SAME real devices
  /// repository the tabs use) that joins the lower operational card row. Null
  /// (demo mode / tests / no real repos) => the row keeps its three report
  /// cards, exactly as before. Never fabricated: no repository, no card.
  final Widget? deviceSummary;

  /// F0.4: the shell's NAMED navigation seam. Null (tests / demo harnesses
  /// that mount this screen directly) leaves every KPI display-only, exactly
  /// as before — a drill-down is offered only when there is somewhere to go.
  final void Function(DashboardDestination destination)? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RF-140: the same demo/real switch the repository seam reads, so the
    // banner/header are honest about the data source (never claim demo data in
    // real mode, nor vice versa). Demo is the DEFAULT.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final reportAsync = ref.watch(dashboardReportProvider);

    // F0.6: refresh the CURRENT report key only. Invalidating
    // dashboardReportProvider itself would just rebuild the projection
    // without re-running the request, and a global invalidate would throw
    // away every other range/scope the owner had already loaded.
    void refresh() => refreshOwnerReport(ref);

    // Calm persistent chrome (RF-127): the page header + range chips stay above
    // the loading/error/data states so the title, period, refresh, and range are
    // available in every state (range switchable at any time, as before).
    // CLIENT-A: the daily sales trend, for the multi-day ranges only. A null key
    // means the selected range keeps its sales-by-HOUR curve, and — because the
    // family entry is then never watched — no `owner_sales_series` request is
    // issued at all. Built HERE so the card is a composition slot like
    // [setupPanel]/[deviceSummary] and `_ReportContent` stays Riverpod-free.
    final seriesKey = ref.watch(currentOwnerSalesSeriesKeyProvider);

    final panel = setupPanel;
    final nav = onNavigate;
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
              data: (report) => _ReportContent(
                report: report,
                isDemo: isDemo,
                deviceSummary: deviceSummary,
                salesByDay: seriesKey == null
                    ? null
                    : _SalesByDayCard(queryKey: seriesKey),
                salesSeriesKey: seriesKey,
                // F0.4: bound HERE, where a WidgetRef exists. The child
                // stays a plain StatelessWidget and never learns about
                // Riverpod or the shell's tab indices.
                onDrillDown: nav == null
                    ? null
                    : (drillDown) => runDashboardDrillDown(
                        ref: ref,
                        drillDown: drillDown,
                        navigate: nav,
                      ),
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
        const _ScopeSelector(),
        const _RangeFilterBar(),
      ],
    );
  }
}

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-E1) — the analytics scope control.
///
/// Sits ABOVE the range chips and the KPIs, because the scope changes what
/// every figure below it means and an owner has to see it before they read a
/// number, not after.
///
/// It is a FILTER over already-authorized coverage. It writes one provider —
/// the selected branch — and touches no membership, role or token. The options
/// come from the SAME scope-safe source the Activity branch filter uses
/// (`list_org_structure`, then filtered to the caller's role coverage), so a
/// branch this owner cannot read is never even offered.
///
/// Three shapes, decided by what the membership actually covers:
///
///  * a scope-LIMITED membership (manager, cashier, …) covers exactly one
///    branch, so it gets a read-only label. No dropdown, and above all no "All
///    permitted branches" option — offering a choice that does not exist would
///    imply the data might be broader than it is;
///  * a broad membership gets "All permitted branches" plus its authorized
///    branches, and STARTS on the broad option. That default is the fix: the
///    resolved membership had already been pinned to the first branch, so the
///    old Overview silently reported one branch of an organization;
///  * no membership at all (demo mode) renders nothing, exactly as before.
///
/// A failed option load leaves the broad default in place and simply offers no
/// individual branches. It never falls back to a branch, and never widens.
class _ScopeSelector extends ConsumerWidget {
  const _ScopeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covered = ref.watch(dashboardCoveredScopeProvider);
    if (covered == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final padding = const EdgeInsetsDirectional.fromSTEB(
      RestoflowSpacing.lg,
      RestoflowSpacing.md,
      RestoflowSpacing.lg,
      0,
    );

    // A membership that covers ONE branch has nothing to choose. Show what is
    // being reported on and stop there.
    if (covered.kind == DashboardAnalyticsScopeKind.singleBranch) {
      final name = covered.branchLabel;
      if (name == null || name.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: padding,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            key: const Key('overview-scope-fixed'),
            '${l10n.activityLogFilterBranch}: $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    // Fail-soft: a failed or still-loading option list yields no individual
    // branches, so the control offers only the broad scope — which is exactly
    // what is being displayed. Never a fabricated option, never a fallback to
    // some branch the owner did not pick.
    final options =
        ref.watch(auditBranchOptionsProvider).asData?.value ??
        const <AuditBranchOption>[];
    final selectable = [
      for (final o in options)
        if (covered.covers(o)) o,
    ];
    final selected = ref.watch(dashboardAnalyticsScopeProvider);
    final selectedId = selected?.branchId;

    return Padding(
      padding: padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DropdownButtonFormField<String?>(
            key: const Key('overview-scope-selector'),
            initialValue: selectedId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.activityLogFilterBranch,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  l10n.activityLogBranchAll,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final b in selectable)
                DropdownMenuItem<String?>(
                  value: b.branchId,
                  child: Text(b.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              ref
                  .read(selectedAnalyticsBranchProvider.notifier)
                  .state = id == null
                  ? null
                  : selectable.firstWhere((b) => b.branchId == id);
            },
          ),
        ),
      ),
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
  const _ReportContent({
    required this.report,
    required this.isDemo,
    this.deviceSummary,
    this.salesByDay,
    this.salesSeriesKey,
    this.onDrillDown,
  });

  final DashboardReport report;

  /// Whether the report is demo data (computed locally) or real data. Drives the
  /// banner so the data source is labelled honestly (RF-140).
  final bool isDemo;

  /// The shell-provided device readiness card for the operational row
  /// (Dashboard V2); null hides it (demo mode / no real repositories).
  final Widget? deviceSummary;

  /// CLIENT-A: the daily sales-trend card, for the multi-day ranges. Null for
  /// `today`/`yesterday`, which keep the sales-by-hour curve — so this slot and
  /// the hourly chart are never both present, and the analytics row always has
  /// exactly one dominant time series in it.
  final Widget? salesByDay;

  /// CLIENT-C: the identity of the sales series ALREADY being loaded for
  /// [salesByDay], or null when this range has none.
  ///
  /// A plain value, not a provider read — this widget stays Riverpod-free. It
  /// is handed to the per-method trend strip, which watches the SAME family
  /// entry, so the payment trend costs no additional request.
  final OwnerSalesSeriesQueryKey? salesSeriesKey;

  /// F0.4: executes a typed drill-down (filters first, then navigate).
  /// Null keeps every KPI display-only, exactly as before.
  final void Function(DashboardDrillDown drillDown)? onDrillDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final drill = onDrillDown;
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
    // CLIENT-B: the KPI deltas now go through the SHARED [ComparisonDelta]
    // instead of the loose `deltaPercent`, so the zero-baseline rule lives in
    // one place for every surface. Behaviour is unchanged by construction —
    // ComparisonDelta's percent is the same truncating integer math, and
    // `noBasis` covers exactly the null/zero prior that returned null before.
    RestoflowMetricDelta? deltaOf(int current, int? prior) {
      final delta = ComparisonDelta.of(current, prior);
      if (!delta.hasBasis) return null;
      return RestoflowMetricDelta(
        label: deltaLabel(delta.percent!.abs()),
        // RestoflowMetricDelta is binary (success/danger); it has no neutral
        // tone, and widening a shared design-system component is not this
        // slice's business. A measured `flat` therefore keeps its existing
        // rendering here, and the comparison strip below — which is app-local —
        // is where flat and the ambiguous-direction metrics are shown neutrally.
        positive: !delta.isDecrease,
      );
    }

    // CLIENT-B: average order value compared against the prior window, computed
    // from INTEGER primitives only — `net ~/ orders` on both sides, never a
    // double. A prior window with no orders has no average to compare against,
    // so the getter returns null and ComparisonDelta renders no basis.
    final priorAvgOrderValueMinor = comparison?.avgOrderValueMinor;

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
        // CLIENT-B: the card had a value but no comparison. Both sides are
        // integer minor units derived the same way (net ~/ orders), so the
        // delta is a like-for-like figure rather than a ratio of ratios.
        delta: report.orderCount == 0
            ? null
            : deltaOf(report.avgOrderValueMinor, priorAvgOrderValueMinor),
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
        // F0.4: cash is the ONLY tender the history filter can express
        // today. card / bit / external stay display-only until the Phase-A
        // server widening exists - offering a filter the RPC would reject
        // is worse than offering none.
        onTap: drill == null
            ? null
            : () => drill(const OrdersHistoryDrillDown.cash()),
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
        // F0.4: the outstanding-money question opens the list that
        // answers it. RestoflowMetricCard.onTap already exists
        // (RF-141D), so this is wiring only - no component change.
        onTap: drill == null
            ? null
            : () => drill(const OrdersHistoryDrillDown.unpaid()),
      ),
      // Dashboard V2: the honest device readiness card (real repositories
      // only) completes the reference's four-card operational row.
      if (deviceSummary case final device?) device,
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
        // dedicated "Shift & cash" card when it is present.
        //
        // F0.5 — these rows are now omitted when there is NO shift state at all,
        // rather than rendering a fabricated zero beside a raw wire token.
        // `shiftCash == null` was being read as "the richer card is absent, so
        // show the simple rows here", but it actually means "no shift/drawer
        // data was returned". The rows then claimed a variance of ₪0.00 —
        // absence of data presented as a measured zero — next to a status pill
        // reading the literal string `none`.
        //
        // This was not a fallback-only defect: owner_report_range,
        // owner_daily_report AND the sales_summary fallback all hardcode
        // shiftStatus to 'none', so it showed on every real deployment.
        if (report.shiftCash == null && reportHasShiftState(report)) ...[
          SummaryRow(
            label: l10n.dashboardCashVariance,
            value: money(report.varianceMinor),
          ),
          SummaryRow(
            label: l10n.dashboardShiftStatus,
            trailing: RestoflowStatusPill(
              label: shiftStatusLabel(l10n, report.shiftStatus),
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
            // Dashboard V2: monotone smoothing (never overshoots the real
            // points) + point selection with a tooltip built from the REAL
            // datum — hour label + the MoneyFormatter-formatted value.
            smooth: true,
            tooltipBuilder: (d) => '${d.label}:00\n${money(d.value)}',
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
    //
    // CLIENT-C: the rows now carry share and average alongside the amount. The
    // share DENOMINATOR is the window's COLLECTED total, which is the only
    // divisor under which the methods describe one whole — billed sales would
    // shrink every share whenever an order went unpaid, for a reason that has
    // nothing to do with tenders.
    final Widget? paymentMix = report.paymentMethods.isEmpty
        ? null
        : _PaymentMixCard(
            analytics: PaymentMethodAnalytics.forLines(
              report.paymentMethods,
              totalCollectedMinor: report.collectedMinor,
            ),
            currencyCode: report.currencyCode,
            supportsMethodFilters: report.supportsPaymentMethodHistoryFilters,
            // F0.4 / CLIENT-C: a legend row answers "which orders make up this
            // total?" through the SAME typed drill-down the KPI cards use, so
            // the two surfaces can never disagree. Cash has always been
            // expressible; the other three go through the capability gate
            // inside the card, and an unknown method has no token at all.
            onTapMethod: drill == null
                ? null
                : (method) => switch (method) {
                    'cash' => drill(const OrdersHistoryDrillDown.cash()),
                    'card' => drill(const OrdersHistoryDrillDown.card()),
                    'bit' => drill(const OrdersHistoryDrillDown.bit()),
                    'external' => drill(
                      const OrdersHistoryDrillDown.external(),
                    ),
                    // Unreachable: the card only offers a tap for the four
                    // tokens above. Doing nothing is the safe floor if that
                    // ever changes.
                    _ => null,
                  },
            trend: salesSeriesKey == null
                ? null
                : _MethodTrendStrip(
                    queryKey: salesSeriesKey!,
                    method: _trendMethodFor(report.paymentMethods),
                    currencyCode: report.currencyCode,
                  ),
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
    // CLIENT-D: the dine-in / takeaway split joins the secondary grid beside
    // "Sales by branch", its closest sibling — a compact breakdown of the same
    // window, not a second analytics page. Present only for the multi-day
    // ranges: `owner_report_range` has no order-type breakdown, and today /
    // yesterday deliberately issue no series request to go and find one.
    final Widget? orderTypeCard = salesSeriesKey == null
        ? null
        : _OrderTypeCard(
            queryKey: salesSeriesKey!,
            currencyCode: report.currencyCode,
            onTapOrderType: drill == null
                ? null
                : (orderType) => switch (orderType) {
                    'dine_in' => drill(const OrdersHistoryDrillDown.dineIn()),
                    'takeaway' => drill(
                      const OrdersHistoryDrillDown.takeaway(),
                    ),
                    // Unreachable: the card offers a tap only for the two
                    // persisted tokens. Doing nothing is the safe floor.
                    _ => null,
                  },
          );

    final remaining = <Widget>[
      summary,
      payment,
      if (report.branches.isNotEmpty) branches,
      if (orderTypeCard != null) orderTypeCard,
      if (shiftCashCard != null) shiftCashCard,
    ];

    // CLIENT-B: the period-comparison strip. It carries ONLY the metrics whose
    // comparison has nowhere else to live — completed orders and discounts —
    // because net, gross, orders, cash and average ticket already show their
    // delta on their own KPI card, and repeating them here would be clutter
    // rather than clarity.
    //
    // It renders only when the server actually sent at least one of SERVER-B's
    // additive comparison keys. Against a database where that migration is not
    // applied yet, both are absent and the whole strip is simply not there —
    // which is the honest outcome, and the reason those fields are nullable.
    final comparisonStrip =
        (comparison != null &&
            (comparison.completedOrderCount != null ||
                comparison.discountTotalMinor != null))
        ? _ComparisonStrip(
            title: switch (report.range) {
              ReportRange.today => l10n.dashboardComparedVsYesterdayAll,
              ReportRange.yesterday => l10n.dashboardComparedVsDayBefore,
              ReportRange.last7 => l10n.dashboardComparedVsPrev7,
              ReportRange.last30 => l10n.dashboardComparedVsPrev30,
            },
            rows: [
              if (comparison.completedOrderCount != null)
                _ComparisonRowData(
                  key: 'comparison-completed',
                  label: l10n.dashboardCompletedOrders,
                  delta: ComparisonDelta.of(
                    report.completedOrderCount,
                    comparison.completedOrderCount,
                  ),
                  format: (v) => v.toString(),
                ),
              if (comparison.discountTotalMinor != null)
                _ComparisonRowData(
                  key: 'comparison-discounts',
                  label: l10n.dashboardDiscounts,
                  delta: ComparisonDelta.of(
                    report.discountTotalMinor,
                    comparison.discountTotalMinor,
                  ),
                  format: money,
                ),
            ],
          )
        : null;

    // RF-132 (Codex review): the reference order is primary KPIs → the
    // dominant analytics row → the compact secondary operational cards →
    // top sellers / recent orders → the detailed summaries. The secondary
    // grid therefore renders AFTER the analytics row (or the honest limited
    // panel holding its slot), never between the KPIs and the chart.
    // CLIENT-A: the multi-day ranges fill the analytics slot with the daily
    // trend. It takes precedence over the limited-analytics placeholder for the
    // obvious reason — the placeholder exists to say "there is no chart yet",
    // and now there is one.
    final analyticsStart =
        salesByHour ?? salesByDay ?? (showLimitedNote ? limitedNote : null);
    final blocks = <Widget>[
      banner,
      _KpiGrid(cards: primaryKpis),
      if (comparisonStrip != null) comparisonStrip,
      if (analyticsStart != null || paymentMix != null)
        _AnalyticsRow(hourly: analyticsStart, mix: paymentMix),
      _KpiGrid(cards: secondaryKpis, wideColumns: secondaryKpis.length),
      if (strongPair.isNotEmpty) _PairRow(sections: strongPair),
      if (remaining.isNotEmpty) _TwoColumn(sections: remaining),
    ];

    return ListView(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      children: _verticallySpaced(blocks),
    );
  }

  /// F0.5: was `method == 'cash' ? … : method`, which leaked the raw `card` /
  /// `bit` / `external` wire tokens into the owner's payment summary. Delegates
  /// to the ONE shared mapper so this surface and the order sheet can never
  /// disagree about what a tender is called.
  static String _methodLabel(AppLocalizations l10n, String method) =>
      paymentMethodLabel(l10n, method);

  /// CLIENT-C: which method the compact daily tender trend shows.
  ///
  /// Deterministic, and deliberately not a control: cash when the window has
  /// any, otherwise the method that carried the most money. A selector would
  /// add interactive state to a secondary strip, and — more importantly — a
  /// chart whose subject can change silently is a chart whose numbers get
  /// attributed to the wrong tender. The heading always names what is drawn.
  static String _trendMethodFor(List<PaymentMethodLine> methods) {
    for (final m in methods) {
      if (m.method == 'cash') return 'cash';
    }
    return methods
        .reduce((a, b) => a.totalMinor >= b.totalMinor ? a : b)
        .method;
  }
}

/// One row of the CLIENT-B comparison strip: a label, a comparison, and the
/// formatter that turns its integer values into display text.
///
/// [format] receives integer minor units for money and a plain count otherwise,
/// so the row itself never decides what a number means — and never divides.
class _ComparisonRowData {
  const _ComparisonRowData({
    required this.key,
    required this.label,
    required this.delta,
    required this.format,
  });

  final String key;
  final String label;
  final ComparisonDelta delta;
  final String Function(int value) format;
}

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-B) — the period-comparison strip.
///
/// A compact card that answers one question — "compared with what, and by how
/// much" — for the metrics that have no delta anywhere else. Its title states
/// the comparison window in words, which is where the `today` honesty lives:
/// the server compares a PARTIAL today against a COMPLETE yesterday, so the
/// heading says "all of yesterday" rather than implying an elapsed-time match
/// the backend does not compute.
///
/// DIRECTION IS NOT DESIRABILITY here, and the rendering says so. The KPI cards
/// tone their deltas success/danger because more sales is unambiguously better;
/// these two are not like that. More discount may be a successful promotion or
/// a leak, and fewer completed orders may mean a quiet day or an unpaid
/// backlog. So the arrow shows the direction and the colour stays neutral —
/// the owner is told what moved, not what to feel about it.
///
/// A metric with no honest basis (a prior of zero, or one the server did not
/// send) renders an em dash. A measured no-change renders a real zero, because
/// "did not move" and "cannot be compared" are different answers.
class _ComparisonStrip extends StatelessWidget {
  const _ComparisonStrip({required this.title, required this.rows});

  final String title;
  final List<_ComparisonRowData> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return RestoflowSectionCard(
      key: const Key('period-comparison-card'),
      title: title,
      children: [for (final row in rows) _ComparisonRow(data: row)],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.data});

  final _ComparisonRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final delta = data.delta;

    // Deliberately NOT Icons.arrow_upward/arrow_downward: those are the KPI
    // cards' TONED trend arrows, and reusing them here would make a neutral
    // directional mark indistinguishable from a success/danger judgement — on
    // screen and in every `find.byIcon` assertion in the suite.
    final (IconData? icon, String text) = switch (delta.state) {
      // An em dash, never a percentage against nothing.
      ComparisonState.noBasis => (null, '—'),
      ComparisonState.flat => (Icons.remove, _text(delta)),
      ComparisonState.increase => (Icons.north, _text(delta)),
      ComparisonState.decrease => (Icons.south, _text(delta)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: Row(
        children: [
          // Both sides flex, and both can ellipsize: at a 2x text scale on a
          // phone a fixed trailing group would push the row past the card.
          Expanded(
            flex: 3,
            child: Text(
              data.label,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: RestoflowIconSizes.xs, color: muted),
                  const SizedBox(width: RestoflowSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    key: Key('${data.key}-delta'),
                    text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      // Neutral on purpose — see the class doc. No
                      // success/danger tone.
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The signed change and the signed percentage, e.g. `+₪4.00 · +5%`.
  ///
  /// Both come straight from [ComparisonDelta] — integer minor units and
  /// truncating integer percentage — so no money is ever divided into a double
  /// on the way to the screen. A negative amount already carries its sign from
  /// [MoneyFormatter]; only a positive one needs the `+` added.
  String _text(ComparisonDelta delta) {
    final absolute = delta.absolute!;
    final percent = delta.percent!;
    final amount = absolute > 0
        ? '+${data.format(absolute)}'
        : data.format(absolute);
    final pct = percent > 0 ? '+$percent%' : '$percent%';
    return '$amount · $pct';
  }
}

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-A) — the daily sales trend.
///
/// The multi-day counterpart of the sales-by-hour card, and deliberately the
/// SAME component: [RestoflowAreaChart], not the unused [RestoflowBarChart]. The
/// bar chart was considered and rejected on two concrete grounds — it has no
/// selection/tooltip API at all, so the per-day figures this card exists to
/// expose would have nowhere to go, and it labels every bar with no
/// subsampling, which a 30-day window cannot fit. Matching the hourly chart also
/// means an owner reads one visual language for "sales over time" regardless of
/// which range they picked.
///
/// The metric is BILLED NET (`net_minor`) — the same figure as the "Net sales"
/// KPI above it and the same figure the hourly curve plots, so the bars sum to
/// the headline. Collected cash is deliberately NOT overlaid: billed and
/// collected are different facts, and drawing them as one unlabelled series is
/// exactly the confusion the server split them to prevent.
///
/// Every state is honest and LOCAL to this card — a failed series never removes
/// the KPIs, the payment mix, or the rest of the Overview:
///
///  * loading  -> a spinner, never a zeroed chart;
///  * missing  -> "range unavailable" (the RPC is not deployed on this database
///                yet), which is not the same claim as "no sales";
///  * empty    -> "no report data", the server's real answer;
///  * error    -> the shared error state.
class _SalesByDayCard extends ConsumerWidget {
  const _SalesByDayCard({required this.queryKey});

  final OwnerSalesSeriesQueryKey queryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(ownerSalesSeriesForKeyProvider(queryKey));
    return RestoflowSectionCard(
      key: const Key('sales-by-day-card'),
      title: l10n.dashboardSalesByDay,
      children: [
        const SizedBox(height: RestoflowSpacing.sm),
        async.when(
          loading: () => const Padding(
            key: Key('sales-by-day-loading'),
            padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => RestoflowStateView(
            key: const Key('sales-by-day-error'),
            icon: Icons.error_outline,
            tone: RestoflowTone.danger,
            message: l10n.dashboardReportsError,
          ),
          data: (series) => _seriesBody(context, l10n, series),
        ),
      ],
    );
  }

  Widget _seriesBody(
    BuildContext context,
    AppLocalizations l10n,
    OwnerSalesSeries series,
  ) {
    if (!series.supported) {
      return RestoflowStateView(
        key: const Key('sales-by-day-unavailable'),
        icon: Icons.event_busy_outlined,
        message: l10n.dashboardRangeUnavailable,
      );
    }
    final peak = series.peakByNet;
    if (peak == null) {
      return RestoflowStateView(
        key: const Key('sales-by-day-empty'),
        icon: Icons.inbox_outlined,
        message: l10n.dashboardNoReportData,
      );
    }

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, series.currencyCode);

    // The chart datum carries only a short label and an int, so the tooltip
    // needs a way back to the full bucket. Keyed by IDENTITY, not by the axis
    // label: a 30-day window can span a short month and repeat a day-of-month,
    // and a label lookup would then tooltip the wrong day's money.
    final byDatum = Map<RestoflowAreaDatum, OwnerSalesSeriesBucket>.identity();
    final points = <RestoflowAreaDatum>[];
    for (final bucket in series.buckets) {
      final datum = RestoflowAreaDatum(
        label: bucket.day.dayOfMonthLabel,
        value: bucket.netMinor,
      );
      byDatum[datum] = bucket;
      points.add(datum);
    }
    final peakLabel = money(peak.netMinor);

    return RestoflowAreaChart(
      key: const Key('sales-by-day-chart'),
      height: 260,
      points: points,
      peakValueLabel: peakLabel,
      yAxisTicks: _axisTicksFor(peak.netMinor),
      yAxisLabelBuilder: money,
      smooth: true,
      // The full branch-local date, the day's net, and its order count — the
      // three things an owner asks of a bar. The date is the server's exact
      // calendar label, never a device-timezone re-render.
      tooltipBuilder: (datum) {
        final bucket = byDatum[datum];
        if (bucket == null) return money(datum.value);
        return '${bucket.day.label}\n${money(bucket.netMinor)}\n'
            '${bucket.orderCount} · ${l10n.dashboardOrders}';
      },
      semanticsLabel: l10n.dashboardSalesByDaySemantics(
        peak.day.label,
        peakLabel,
      ),
    );
  }
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

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-C) — the payment mix, enriched.
///
/// The donut and its legend stay; each legend row now answers what an owner
/// actually asks of a tender line — how much, how many, what share of the money
/// that came in, and how big a typical payment is. Every figure is integer
/// minor units or an integer count, computed by [PaymentMethodAnalytics] from
/// what the report already returned. No extra request, no estimate.
///
/// RECORDED TENDER ONLY. These are the completed payments staff recorded at the
/// till. RestoFlow has no acquirer integration, so the card carries a caption
/// saying exactly that: nothing here is a processor approval, a reconciliation
/// or a settlement, and the wording must never imply one.
///
/// CLICKABILITY IS A DEPLOYMENT QUESTION. Cash has always been expressible by
/// the history RPC. card / bit / external became expressible only with the
/// SERVER-B migration, and BEFORE it an unknown `p_payment` returned an empty
/// list rather than an error — so a row that navigated on an older database
/// would answer "no orders" for money the owner can see. Those rows are
/// therefore display-only until [supportsMethodFilters] proves otherwise, and
/// an unrecognised future method is never clickable at all, because there is no
/// filter token to send for it.
class _PaymentMixCard extends StatelessWidget {
  const _PaymentMixCard({
    required this.analytics,
    required this.currencyCode,
    required this.supportsMethodFilters,
    this.onTapMethod,
    this.trend,
  });

  final List<PaymentMethodAnalytics> analytics;
  final String currencyCode;

  /// Whether the deployed server can answer a card / bit / external history
  /// filter. False leaves those rows display-only; cash is unaffected.
  final bool supportsMethodFilters;

  /// Opens the order list for one tender method. Null keeps EVERY row
  /// display-only, exactly as before.
  final void Function(String method)? onTapMethod;

  /// The compact per-method daily trend, for the multi-day ranges. Null on
  /// today / yesterday, which keep the current-window mix only.
  final Widget? trend;

  /// Whether a row may be tapped: a destination must exist, the token must be
  /// one the history filter knows, and for the three new ones the server must
  /// have proven it can answer them.
  bool _isTappable(String method) {
    if (onTapMethod == null) return false;
    return switch (method) {
      'cash' => true,
      'card' || 'bit' || 'external' => supportsMethodFilters,
      _ => false,
    };
  }

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
    // F0.5: the donut legend had its own cash-only mapper, so a card / bit /
    // external slice was labelled with its raw wire token right next to a
    // correctly-labelled cash slice. One shared mapper now serves the legend,
    // the payment summary and the order sheet alike.
    String label(String m) => paymentMethodLabel(l10n, m);
    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, currencyCode);

    final top = analytics.reduce(
      (a, b) => a.amountMinor >= b.amountMinor ? a : b,
    );
    // Integer basis points, then a half-up whole percent — the same number the
    // previous `(amount * 100 / total).round()` produced, without ever creating
    // a double to round.
    final topBps = top.shareBps;

    final donut = RestoflowDonutChart(
      size: 120,
      ringWidth: 15,
      segments: [
        for (final m in analytics)
          RestoflowDonutSegment(
            value: m.amountMinor,
            color: colorFor(m.method),
            label: label(m.method),
          ),
      ],
      centerLabel: '${topBps == null ? 0 : roundedPercentFromBps(topBps)}%',
      centerSub: label(top.method),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in analytics)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: _MaybeTappableRow(
              key: Key('payment-mix-row-${m.method}'),
              onTap: _isTappable(m.method)
                  ? () => onTapMethod!(m.method)
                  : null,
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: RestoflowSpacing.md,
                  vertical: RestoflowSpacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: kRestoflowHairline),
                  borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
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
                        Expanded(
                          child: Text(
                            label(m.method),
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Flexible(
                          child: Text(
                            key: Key('payment-amount-${m.method}'),
                            money(m.amountMinor),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    // Count, share and average. Each is OMITTED rather than
                    // faked when its basis is missing: a window that collected
                    // nothing has no share to take, and a method with no
                    // payments has nothing to average.
                    Text(
                      key: Key('payment-meta-${m.method}'),
                      [
                        l10n.dashboardRecordedPaymentsCount(m.count),
                        if (m.shareBps case final bps?)
                          l10n.dashboardShareOfCollected(formatShareBps(bps)),
                        if (m.averageMinor case final avg?)
                          l10n.dashboardAvgRecordedPayment(money(avg)),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final t = trend;
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
        if (t != null) ...[const SizedBox(height: RestoflowSpacing.md), t],
        const SizedBox(height: RestoflowSpacing.xs),
        Text(
          key: const Key('payment-recorded-tenders-note'),
          l10n.dashboardRecordedTendersNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-D) — the dine-in / takeaway split.
///
/// Reads the SAME `owner_sales_series` entry the daily sales trend and the
/// per-method tender strip already watch — same query key, same family — so the
/// whole Overview still makes exactly ONE series request per multi-day range.
///
/// SINGLE-DAY RANGES DO NOT GET THIS CARD. `owner_report_range` carries no
/// order-type breakdown, and today/yesterday deliberately never ask for a
/// series (CLIENT-A). Adding a request here to fill one card would quietly
/// double the page's cost on its default range, so the card is simply absent
/// instead — the caller passes no key for those ranges.
///
/// Two figures per type, and they answer different questions: the SHARE is a
/// share of ORDERS, said in words, and the money beside it is that type's billed
/// net. One unlabelled "share" next to an amount would be read as whichever the
/// reader assumed.
///
/// Rows are tappable. Unlike the tender methods, `p_order_type` has been part of
/// `owner_order_history` since its first migration, so every deployed database
/// can answer it — no capability gate is needed or wanted here. An UNRECOGNISED
/// future type is still display-only, because the client filter enum has no
/// value for it and inventing a token is how an owner lands on an empty list.
class _OrderTypeCard extends ConsumerWidget {
  const _OrderTypeCard({
    required this.queryKey,
    required this.currencyCode,
    this.onTapOrderType,
  });

  final OwnerSalesSeriesQueryKey queryKey;
  final String currencyCode;

  /// Opens the order list for one type. Null keeps every row display-only.
  final void Function(String orderType)? onTapOrderType;

  /// Whether a row may be tapped: a destination must exist and the token must
  /// be one the history filter can actually express.
  bool _isTappable(String orderType) =>
      onTapOrderType != null && kOrderTypeWireTokens.contains(orderType);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(ownerSalesSeriesForKeyProvider(queryKey));
    final series = async.valueOrNull;
    // Loading, failed, unavailable, or an empty window: no card. Nothing here
    // is worth a placeholder of its own — the daily trend above already reports
    // the state of this exact series, and repeating it would be noise. What
    // matters is that ZERO rows are drawn rather than zero-valued ones.
    if (series == null || !series.supported || series.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = aggregateOrderTypeAnalytics(series.buckets);
    if (rows.isEmpty) return const SizedBox.shrink();

    String money(int amountMinor) =>
        MoneyFormatter.formatMinor(amountMinor, currencyCode);

    return RestoflowSectionCard(
      key: const Key('order-type-card'),
      title: l10n.dashboardSalesByOrderType,
      children: [
        for (final row in rows)
          _MaybeTappableRow(
            key: Key('order-type-row-${row.orderType}'),
            onTap: _isTappable(row.orderType)
                ? () => onTapOrderType!(row.orderType)
                : null,
            child: SectionRow(
              label: orderTypeLabel(l10n, row.orderType),
              // Count first (the existing "N · Orders" idiom), then the share
              // with its denominator spelled out.
              secondary: [
                '${row.orderCount} · ${l10n.dashboardOrders}',
                if (row.shareBps case final bps?)
                  l10n.dashboardShareOfOrders(formatShareBps(bps)),
              ].join(' · '),
              trailingValue: money(row.netMinor),
            ),
          ),
      ],
    );
  }
}

/// DASHBOARD-OWNER-ANALYTICS-PHASE-A (CLIENT-C) — the compact per-method daily
/// tender trend, for the multi-day ranges.
///
/// Reads the SAME `owner_sales_series` entry the daily sales trend already
/// loaded — same query key, same family — so this adds NO request. On today and
/// yesterday it is never built, because those ranges deliberately never ask for
/// a series at all.
///
/// ONE method, named in the heading. Four overlapping lines in a card this size
/// would be decoration rather than information, and an unlabelled multi-series
/// chart is exactly how a reader ends up attributing one method's money to
/// another. The method is chosen deterministically — cash when the window has
/// any, otherwise the method that carried the most — so the chart never changes
/// what it is showing without the heading changing with it.
///
/// [RestoflowBarChart] rather than the area chart used for the headline trend:
/// this is a secondary strip inside another card, it needs no tooltip, and the
/// bar chart's compact single-hue rendering is what it was built for. Its axis
/// labels every bar with no subsampling, so a 30-day window would draw thirty
/// overlapping numbers — the labels are therefore thinned here, which the
/// component supports natively by passing an empty label.
class _MethodTrendStrip extends ConsumerWidget {
  const _MethodTrendStrip({
    required this.queryKey,
    required this.method,
    required this.currencyCode,
  });

  final OwnerSalesSeriesQueryKey queryKey;
  final String method;
  final String currencyCode;

  /// At most this many x-axis labels; the rest render blank so 30 days stay
  /// readable in a narrow card.
  static const int _maxLabels = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final series = ref
        .watch(ownerSalesSeriesForKeyProvider(queryKey))
        .valueOrNull;
    // Loading, failed, or a server without the series RPC: the strip simply is
    // not there. The payment analytics above it come from a different call and
    // must keep rendering — one missing capability may not take another
    // surface's data down with it.
    if (series == null || !series.supported || series.isEmpty) {
      return const SizedBox.shrink();
    }

    final amounts = <int>[
      for (final bucket in series.buckets) _amountFor(bucket),
    ];
    if (amounts.every((a) => a == 0)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final step = (series.buckets.length / _maxLabels).ceil().clamp(
      1,
      series.buckets.length,
    );
    final peak = amounts.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          key: const Key('payment-method-trend-title'),
          l10n.dashboardMethodTrendTitle(paymentMethodLabel(l10n, method)),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        RestoflowBarChart(
          key: const Key('payment-method-trend-chart'),
          height: 120,
          bars: [
            for (var i = 0; i < series.buckets.length; i++)
              RestoflowBarDatum(
                // The day-of-month, thinned. Never a re-rendered date: the
                // label comes from the server's own calendar token.
                label: i % step == 0 || i == series.buckets.length - 1
                    ? series.buckets[i].day.dayOfMonthLabel
                    : '',
                value: amounts[i],
              ),
          ],
          peakValueLabel: MoneyFormatter.formatMinor(peak, currencyCode),
        ),
      ],
    );
  }

  /// This method's recorded completed tender for one day.
  ///
  /// A day the method does not appear in collected NOTHING by it — the server
  /// omits a method with no completed payment — so 0 is the truthful value, not
  /// a gap to be interpolated.
  int _amountFor(OwnerSalesSeriesBucket bucket) {
    for (final line in bucket.byMethod) {
      if (line.method == method) return line.totalMinor;
    }
    return 0;
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

/// F0.4 — wraps a legend row so it is tappable ONLY when a destination exists.
///
/// App-local on purpose: RestoflowDonutChart has no tap API, and adding
/// painter hit-testing to a shared component to make one row clickable would be
/// a large change for a small gain. The legend is built here, so the
/// interaction belongs here too - packages/design_system is untouched.
///
/// With a null [onTap] it renders the child EXACTLY as before: no ripple, no
/// button semantics, no hover target. A row that cannot go anywhere must not
/// look like it can.
class _MaybeTappableRow extends StatelessWidget {
  const _MaybeTappableRow({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    if (tap == null) return child;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        child: child,
      ),
    );
  }
}
