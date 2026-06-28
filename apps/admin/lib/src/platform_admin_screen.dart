import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'data/platform_overview.dart';
import 'state/platform_admin_providers.dart';
import 'widgets/platform_widgets.dart';

/// The RF-120 platform-admin overview: a demo-data banner, the platform "as of"
/// context, platform KPI cards (organizations, restaurants, branches, active
/// branches, devices, open alerts, orders today), an organizations summary, a
/// branch-health list and a recent-activity feed.
///
/// The overview is loaded through the [platformOverviewProvider] seam (computed
/// from a structured demo dataset — no Supabase, no RPC, no backend), so the
/// screen has honest loading / error / empty states and a refresh. This is the
/// PLATFORM admin surface (org/branch SUMMARIES only — no tenant financial
/// detail); read-only. Counts are plain integers; chrome is localized and
/// RTL/LTR-correct.
class PlatformAdminScreen extends ConsumerWidget {
  const PlatformAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final overviewAsync = ref.watch(platformOverviewProvider);

    void refresh() => ref.invalidate(platformOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.admin_panel_settings_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Text(l10n.adminAppTitle),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('platform-refresh-button'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.adminRefresh,
          ),
        ],
      ),
      body: overviewAsync.when(
        data: (overview) => _OverviewContent(overview: overview),
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(onRetry: refresh),
      ),
    );
  }
}

/// The loaded overview: a scrollable, responsive layout of all sections.
class _OverviewContent extends StatelessWidget {
  const _OverviewContent({required this.overview});

  final PlatformOverview overview;

  static const double _twoColBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final banner = PlatformDemoBanner(
      key: const Key('platform-demo-banner'),
      message: l10n.adminDemoDataNotice,
    );
    final header = _OverviewHeader(overview: overview);

    if (overview.isEmpty) {
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

    final activeOrgCaption =
        '${l10n.adminActiveLabel}: ${overview.activeOrganizationCount}';
    final kpis = <Widget>[
      PlatformMetricCard(
        key: const Key('kpi-organizations'),
        label: l10n.adminKpiOrganizations,
        value: overview.organizationCount.toString(),
        caption: activeOrgCaption,
        icon: Icons.domain_outlined,
      ),
      PlatformMetricCard(
        key: const Key('kpi-restaurants'),
        label: l10n.adminKpiRestaurants,
        value: overview.restaurantCount.toString(),
        icon: Icons.restaurant_outlined,
      ),
      PlatformMetricCard(
        key: const Key('kpi-branches'),
        label: l10n.adminKpiBranches,
        value: overview.branchCount.toString(),
        icon: Icons.store_mall_directory_outlined,
      ),
      PlatformMetricCard(
        key: const Key('kpi-active-branches'),
        label: l10n.adminKpiActiveBranches,
        value: overview.activeBranchCount.toString(),
        icon: Icons.check_circle_outline,
      ),
      PlatformMetricCard(
        key: const Key('kpi-devices'),
        label: l10n.adminKpiDevices,
        value: overview.deviceCount.toString(),
        icon: Icons.devices_outlined,
      ),
      PlatformMetricCard(
        key: const Key('kpi-alerts'),
        label: l10n.adminKpiAlerts,
        value: overview.warningCount.toString(),
        icon: Icons.warning_amber_outlined,
      ),
      PlatformMetricCard(
        key: const Key('kpi-orders-today'),
        label: l10n.adminKpiOrdersToday,
        value: overview.todayOrderCount.toString(),
        icon: Icons.receipt_long_outlined,
      ),
    ];

    final organizations = PlatformSectionCard(
      key: const Key('organizations-card'),
      title: l10n.adminOrganizationsHeading,
      children: [
        for (final org in overview.organizations)
          PlatformSectionRow(
            label: org.organizationName,
            secondary:
                '${org.restaurantCount} ${l10n.adminKpiRestaurants} · '
                '${org.branchCount} ${l10n.adminKpiBranches} · '
                '${l10n.adminCreatedLabel} ${org.createdAtLabel}',
            trailingValue: org.plan,
            trailing: PlatformStatusPill(
              label: org.status,
              tone: org.status == 'active'
                  ? PillTone.neutral
                  : PillTone.warning,
            ),
          ),
      ],
    );

    final branchHealth = PlatformSectionCard(
      key: const Key('branch-health-card'),
      title: l10n.adminBranchHealthHeading,
      children: [
        for (final branch in overview.branchHealth)
          PlatformSectionRow(
            label: branch.branchName,
            secondary:
                '${branch.organizationName} · '
                '${branch.deviceCount} ${l10n.adminKpiDevices} · '
                '${l10n.adminLastActivityLabel} ${branch.lastActivityLabel} · '
                '${branch.todayOrderCount} ${l10n.adminOrdersTodayShort}',
            trailingValue: branch.status,
            trailing: branch.hasWarning
                ? PlatformStatusPill(
                    label: l10n.adminWarningChip,
                    tone: PillTone.warning,
                  )
                : null,
          ),
      ],
    );

    final activity = PlatformSectionCard(
      key: const Key('recent-activity-card'),
      title: l10n.adminRecentActivityHeading,
      children: [
        for (final event in overview.activity)
          PlatformActivityTile(event: event),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= _twoColBreakpoint;
        final sections = twoColumn
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: organizations),
                  const SizedBox(width: RestoflowSpacing.lg),
                  Expanded(
                    child: Column(
                      children: [
                        branchHealth,
                        const SizedBox(height: RestoflowSpacing.lg),
                        activity,
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  organizations,
                  const SizedBox(height: RestoflowSpacing.lg),
                  branchHealth,
                  const SizedBox(height: RestoflowSpacing.lg),
                  activity,
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
}

/// The overview title + the platform "as of" context (day + a "Demo data" pill).
class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.overview});

  final PlatformOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final asOf = '${l10n.adminOverviewAsOf} ${overview.generatedDateLabel}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.adminOverviewTitle,
          key: const Key('platform-overview-title'),
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
              asOf,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            PlatformStatusPill(label: l10n.adminDemoDataTag),
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

/// The loading state while the overview is fetched through the repository.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('platform-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: RestoflowSpacing.lg),
          Text(
            l10n.adminLoading,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The error state when the overview fails to load, with a retry action.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('platform-error'),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: RestoflowSpacing.md),
            Text(l10n.adminError, style: theme.textTheme.titleMedium),
            const SizedBox(height: RestoflowSpacing.lg),
            FilledButton.icon(
              key: const Key('platform-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.adminRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state when there is no platform data.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      key: const Key('platform-empty'),
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
            l10n.adminEmpty,
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
