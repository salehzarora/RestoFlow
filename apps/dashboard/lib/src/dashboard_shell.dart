import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'dashboard_home_screen.dart';

/// The owner/manager dashboard shell (RF-111): a branded side navigation
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

  void _select(int value) => setState(() => _index = value);

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
                _SideNav(selectedIndex: _index, onSelected: _select),
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
                onDestinationSelected: _select,
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
      appBar: AppBar(
        titleSpacing: RestoflowSpacing.lg,
        title: Text(l10n.menuManagementTitle),
      ),
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
            child: _MenuDemoBanner(message: l10n.menuDemoBanner),
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

/// The branded wide-screen side navigation.
class _SideNav extends StatelessWidget {
  const _SideNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      backgroundColor: scheme.surfaceContainer,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.9,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.lg),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primary,
          child: Icon(Icons.restaurant, color: scheme.onPrimary),
        ),
      ),
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
    );
  }
}

/// A professional demo banner: an accent bar, an icon, and the message.
class _MenuDemoBanner extends StatelessWidget {
  const _MenuDemoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: BorderDirectional(
          start: BorderSide(color: scheme.tertiary, width: 4),
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
        RestoflowSpacing.md,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.science_outlined,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
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
      color: theme.colorScheme.surfaceContainerHigh,
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
