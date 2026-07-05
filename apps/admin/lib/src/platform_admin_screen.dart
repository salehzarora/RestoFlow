import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'data/platform_admin_repository.dart';
import 'data/platform_overview.dart';
import 'state/platform_admin_providers.dart';
import 'widgets/platform_widgets.dart';
import 'widgets/language_selector.dart';

/// The RF-120 / RF-128 / RF-134 platform-admin overview: a data-source notice
/// banner, the platform "as of" context, platform KPI cards, an organizations
/// summary, a branch-health list and a recent-activity feed.
///
/// The overview is loaded through the [platformOverviewProvider] seam, so the
/// screen has honest loading / error / empty states and a refresh. This is the
/// PLATFORM admin surface (org/branch SUMMARIES only — no tenant financial
/// detail); read-only (D-026). Counts are plain integers; chrome is localized
/// and RTL/LTR-correct.
///
/// UX HONESTY (RF-134): the mode is read from [runtimeConfigProvider] — the same
/// switch that selects the demo vs real repository.
///   * DEMO mode shows the demo-data banner + "Demo data" pill + the full KPI
///     set computed from the demo dataset.
///   * REAL mode shows a "live but limited" notice + "Live · limited" pill, and
///     HIDES the KPIs the RF-091/RF-125 read panel does not provide (active
///     branches, devices, open alerts, orders today) and the per-branch health
///     section, so no `0`/placeholder is ever presented as a real figure. It
///     never claims full live platform-admin capability while the aal2/grant
///     management UX is missing. Real-mode failures render categorized safe
///     states (not configured / access denied / generic) — see [_ErrorState].
class PlatformAdminScreen extends ConsumerWidget {
  const PlatformAdminScreen({this.onSignOut, this.operatorEmail, super.key});

  /// RF-119-b: when provided (real mode), an app-bar Sign-out action clears the
  /// platform-operator session. Null in demo mode (no session to sign out of).
  final VoidCallback? onSignOut;

  /// DESIGN-002: the signed-in operator email (from `get_my_context`), shown in
  /// the overview header so the operator can confirm which account is active.
  /// NON-secret; null in demo mode (no session).
  final String? operatorEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
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
          // Sprint (I): the language switcher is visible on the admin surface.
          const LanguageSelector(),
          IconButton(
            key: const Key('platform-refresh-button'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.adminRefresh,
          ),
          if (onSignOut case final signOut?)
            IconButton(
              key: const Key('platform-signout-button'),
              onPressed: signOut,
              icon: const Icon(Icons.logout),
              tooltip: l10n.authSignOut,
            ),
        ],
      ),
      body: overviewAsync.when(
        data: (overview) => _OverviewContent(
          overview: overview,
          isDemo: isDemo,
          operatorEmail: operatorEmail,
        ),
        loading: () => const _LoadingState(),
        error: (error, _) => _ErrorState(error: error, onRetry: refresh),
      ),
    );
  }
}

/// The loaded overview: a scrollable, responsive layout of all sections.
class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.overview,
    required this.isDemo,
    this.operatorEmail,
  });

  final PlatformOverview overview;

  /// The signed-in operator email (real mode), or null (demo).
  final String? operatorEmail;

  /// Whether the data is demo (computed locally) or real (the limited RF-091
  /// read panel). Drives the banner, the header pill, and which KPIs / sections
  /// are shown — see [PlatformAdminScreen] (RF-134).
  final bool isDemo;

  static const double _twoColBreakpoint = RestoflowBreakpoints.wide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final banner = isDemo
        ? RestoflowNoticeBanner(
            key: const Key('platform-demo-banner'),
            body: l10n.adminDemoDataNotice,
          )
        : RestoflowNoticeBanner(
            key: const Key('platform-realmode-banner'),
            body: l10n.adminRealModeNotice,
            tone: RestoflowTone.warning,
          );
    final header = _OverviewHeader(
      overview: overview,
      isDemo: isDemo,
      operatorEmail: operatorEmail,
    );

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
    // Organizations, restaurants and branches are provided in BOTH modes (the
    // RF-091 read panel returns org status + restaurant/branch counts). The
    // remaining KPIs (active branches, devices, open alerts, orders today) are
    // NOT provided by that panel, so they are shown ONLY in demo mode — never as
    // a fabricated `0` in real mode (RF-134).
    final kpis = <Widget>[
      RestoflowMetricCard(
        key: const Key('kpi-organizations'),
        label: l10n.adminKpiOrganizations,
        value: overview.organizationCount.toString(),
        caption: activeOrgCaption,
        icon: Icons.domain_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-restaurants'),
        label: l10n.adminKpiRestaurants,
        value: overview.restaurantCount.toString(),
        icon: Icons.restaurant_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-branches'),
        label: l10n.adminKpiBranches,
        value: overview.branchCount.toString(),
        icon: Icons.store_mall_directory_outlined,
      ),
      if (isDemo) ...[
        RestoflowMetricCard(
          key: const Key('kpi-active-branches'),
          label: l10n.adminKpiActiveBranches,
          value: overview.activeBranchCount.toString(),
          icon: Icons.check_circle_outline,
        ),
        RestoflowMetricCard(
          key: const Key('kpi-devices'),
          label: l10n.adminKpiDevices,
          value: overview.deviceCount.toString(),
          icon: Icons.devices_outlined,
        ),
        RestoflowMetricCard(
          key: const Key('kpi-alerts'),
          label: l10n.adminKpiAlerts,
          value: overview.warningCount.toString(),
          icon: Icons.warning_amber_outlined,
        ),
        RestoflowMetricCard(
          key: const Key('kpi-orders-today'),
          label: l10n.adminKpiOrdersToday,
          value: overview.todayOrderCount.toString(),
          icon: Icons.receipt_long_outlined,
        ),
      ],
    ];

    final organizations = RestoflowSectionCard(
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
            // Tone only — the label stays the raw wire status string.
            trailing: RestoflowStatusPill(
              label: org.status,
              tone: org.status == 'active'
                  ? RestoflowTone.success
                  : RestoflowTone.danger,
            ),
          ),
      ],
    );

    final branchHealth = RestoflowSectionCard(
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
                ? RestoflowStatusPill(
                    label: l10n.adminWarningChip,
                    tone: RestoflowTone.danger,
                  )
                : null,
          ),
      ],
    );

    final activity = RestoflowSectionCard(
      key: const Key('recent-activity-card'),
      title: l10n.adminRecentActivityHeading,
      children: [
        for (final event in overview.activity)
          PlatformActivityTile(event: event),
      ],
    );

    // Branch health is per-branch data the RF-091 read panel does not provide,
    // so it is shown only in demo mode. Activity is shown whenever there are
    // events (the real audit feed may be empty). Organizations are shown when
    // present (RF-134).
    final hasOrgs = overview.organizations.isNotEmpty;
    final secondarySections = <Widget>[
      if (isDemo) branchHealth,
      if (overview.activity.isNotEmpty) activity,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn =
            constraints.maxWidth >= _twoColBreakpoint &&
            hasOrgs &&
            secondarySections.isNotEmpty;
        final sections = twoColumn
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: organizations),
                  const SizedBox(width: RestoflowSpacing.lg),
                  Expanded(
                    child: Column(children: _withColumnGaps(secondarySections)),
                  ),
                ],
              )
            : Column(
                children: _withColumnGaps([
                  if (hasOrgs) organizations,
                  ...secondarySections,
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
            const SizedBox(height: RestoflowSpacing.lg),
            sections,
          ],
        );
      },
    );
  }
}

/// The overview title + the platform "as of" context (day + a data-source pill:
/// "Demo data" in demo mode, "Live · limited" in real mode).
class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({
    required this.overview,
    required this.isDemo,
    this.operatorEmail,
  });

  final PlatformOverview overview;
  final bool isDemo;

  /// The signed-in operator email (real mode), or null (demo).
  final String? operatorEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final asOf = '${l10n.adminOverviewAsOf} ${overview.generatedDateLabel}';
    final email = operatorEmail;
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
            RestoflowStatusPill(
              key: const Key('platform-data-source-pill'),
              label: isDemo ? l10n.adminDemoDataTag : l10n.adminLiveLimitedTag,
            ),
          ],
        ),
        // DESIGN-002: confirm which operator account is signed in (real mode).
        if (email != null && email.isNotEmpty) ...[
          const SizedBox(height: RestoflowSpacing.xxs),
          Text(
            l10n.adminSignedInAs(email),
            key: const Key('platform-signed-in-as'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

/// The loading state while the overview is fetched through the repository.
/// Exactly ONE CircularProgressIndicator (loading-state test contract).
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      key: const Key('platform-loading'),
      showSpinner: true,
      message: l10n.adminLoading,
    );
  }
}

/// The failure state when the overview can't load. It dispatches on the
/// [PlatformAdminException.kind] to render an honest, specific safe state
/// (RF-134):
///   * [PlatformAdminErrorKind.notConfigured] — real mode is selected but the
///     Supabase connection is missing/invalid; no retry (config is needed).
///   * [PlatformAdminErrorKind.accessDenied] — the backend refused the read
///     (missing platform-admin grant / aal2 MFA step-up, D-026); no retry (the
///     step-up/grant UX is not in this build).
///   * [PlatformAdminErrorKind.unexpected] (and any non-categorized error) — the
///     generic, retryable error with a retry action.
/// The developer-facing exception message is never shown to the user.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = error is PlatformAdminException
        ? (error as PlatformAdminException).kind
        : PlatformAdminErrorKind.unexpected;

    switch (kind) {
      case PlatformAdminErrorKind.notConfigured:
        return _SafeState(
          stateKey: const Key('platform-not-configured'),
          icon: Icons.cloud_off_outlined,
          tone: RestoflowTone.neutral,
          title: l10n.adminNotConfiguredTitle,
          body: l10n.adminNotConfiguredBody,
        );
      case PlatformAdminErrorKind.accessDenied:
        return _SafeState(
          stateKey: const Key('platform-access-denied'),
          icon: Icons.lock_outline,
          tone: RestoflowTone.danger,
          title: l10n.adminAccessDeniedTitle,
          body: l10n.adminAccessDeniedBody,
        );
      case PlatformAdminErrorKind.unexpected:
        return _SafeState(
          stateKey: const Key('platform-error'),
          icon: Icons.error_outline,
          tone: RestoflowTone.danger,
          title: l10n.adminError,
          action: FilledButton.icon(
            key: const Key('platform-retry-button'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.adminRetry),
          ),
        );
    }
  }
}

/// A tone-aware safe state shared by the failure states (RF-134), rendered
/// through the shared [RestoflowStateView] so failures look like failures.
/// [stateKey] keys the state view so each state is individually findable in
/// tests.
class _SafeState extends StatelessWidget {
  const _SafeState({
    required this.stateKey,
    required this.icon,
    required this.title,
    this.tone,
    this.body,
    this.action,
  });

  final Key stateKey;
  final IconData icon;
  final String title;
  final RestoflowTone? tone;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final actionWidget = action;
    return RestoflowStateView(
      key: stateKey,
      icon: icon,
      tone: tone,
      title: title,
      message: body,
      actions: [if (actionWidget != null) actionWidget],
    );
  }
}

/// The empty state when there is no platform data.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestoflowStateView(
      key: const Key('platform-empty'),
      icon: Icons.inbox_outlined,
      title: l10n.adminEmpty,
    );
  }
}

/// Interleaves a vertical gap between [widgets] for stacking section cards in a
/// [Column], so a conditionally-empty section list lays out without dangling
/// gaps (RF-134).
List<Widget> _withColumnGaps(List<Widget> widgets) {
  final out = <Widget>[];
  for (var i = 0; i < widgets.length; i++) {
    if (i > 0) out.add(const SizedBox(height: RestoflowSpacing.lg));
    out.add(widgets[i]);
  }
  return out;
}
