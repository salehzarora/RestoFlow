import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'dashboard_home_screen.dart';
import 'widgets/demo_notice_banner.dart';

/// The owner/manager dashboard shell (RF-111): a two-destination navigation
/// (Overview + Menu) hosting the existing RF-104 overview and the RF-111 menu
/// management surface.
///
/// The menu surface is DEMO-BACKED: it runs the in-memory store + demo scope
/// (held once in state so edits persist across navigation), with a clear demo
/// banner — real persistence is deferred to the auth/org-context bridge (D1/D3).
/// The active [membership] is consumed (it gated entry and is shown as context),
/// not discarded.
class DashboardShell extends StatefulWidget {
  const DashboardShell({this.membership, super.key});

  /// The RF-108 active membership (null in demo mode).
  final MembershipContext? membership;

  static const double _wideBreakpoint = 900;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;
  late final InMemoryMenuStore _menuStore = buildDemoMenuStore();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = _index == 0
        ? const DashboardHomeScreen()
        : _menuSurface(context, l10n);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= DashboardShell._wideBreakpoint;
          if (isWide) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.dashboard_outlined),
                      selectedIcon: const Icon(Icons.dashboard),
                      label: Text(l10n.dashboardNavOverview),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.restaurant_menu_outlined),
                      selectedIcon: const Icon(Icons.restaurant_menu),
                      label: Text(l10n.dashboardNavMenu),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: content),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.dashboard_outlined),
                    selectedIcon: const Icon(Icons.dashboard),
                    label: l10n.dashboardNavOverview,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.restaurant_menu_outlined),
                    selectedIcon: const Icon(Icons.restaurant_menu),
                    label: l10n.dashboardNavMenu,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _menuSurface(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuManagementTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.membership != null)
            _MembershipContextBar(membership: widget.membership!),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RestoflowSpacing.lg,
              RestoflowSpacing.md,
              RestoflowSpacing.lg,
              0,
            ),
            child: DemoNoticeBanner(message: l10n.menuDemoBanner),
          ),
          Expanded(
            child: ProviderScope(
              overrides: menuFeatureOverrides(
                scope: demoMenuScope,
                readSource: _menuStore,
                writer: _menuStore,
              ),
              child: const MenuManagementScreen(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin context strip showing the active membership scope (organization +
/// restaurant/branch). Consumes the RF-108 membership; it is not a data source.
class _MembershipContextBar extends StatelessWidget {
  const _MembershipContextBar({required this.membership});

  final MembershipContext membership;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeName =
        membership.branchName ??
        membership.restaurantName ??
        membership.organizationName;
    final contextLabel = '${membership.organizationName} · $scopeName';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(child: Text(contextLabel, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
