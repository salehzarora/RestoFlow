/// The PLATFORM CONSOLE shell (ADMIN-125C.2, replacing the RF-120/128/134
/// single-page overview).
///
/// Four top-level destinations — Overview, Subscribers, Restaurants, Audit log —
/// plus a Subscriber detail that is opened FROM Subscribers rather than being a
/// destination of its own (it always belongs to a specific tenant, so it has no
/// meaning as a standalone tab, and Back returns to the list that opened it).
///
/// Navigation is lightweight local state, NOT a router. The Admin app is a
/// single gated surface with four sibling views and no deep links, so adding
/// GoRouter here would buy URL routing nobody uses and hand the auth gate a
/// second way to be bypassed.
///
/// THE AUTH GATE STAYS OUTSIDE THIS WIDGET. `AdminAuthFlow` decides whether the
/// console is reachable at all (session -> `get_my_context` -> platform admin +
/// aal2); this shell is only ever built once that has passed, and every read it
/// performs is independently re-authorized server-side by
/// `app.platform_admin_guard`. Nothing here can widen access.
///
/// READ-ONLY (DECISION D-026): the shell's only actions are refresh, language,
/// and sign out. There is no control anywhere in the console that writes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'console/audit_log_page.dart';
import 'console/overview_page.dart';
import 'console/restaurants_page.dart';
import 'console/subscriber_detail_page.dart';
import 'console/subscribers_page.dart';
import 'data/console_models.dart';
import 'state/platform_admin_providers.dart';
import 'widgets/language_selector.dart';

/// The console's top-level destinations.
enum ConsoleSection { overview, subscribers, restaurants, audit }

/// The platform console shell.
class PlatformAdminScreen extends ConsumerStatefulWidget {
  const PlatformAdminScreen({this.onSignOut, this.operatorEmail, super.key});

  /// RF-119-b: when provided (real mode), a Sign-out action clears the
  /// platform-operator session. Null in demo mode (no session to sign out of).
  final VoidCallback? onSignOut;

  /// DESIGN-002: the signed-in operator email (from `get_my_context`), shown so
  /// the operator can confirm which account is active. NON-secret; null in demo.
  final String? operatorEmail;

  @override
  ConsumerState<PlatformAdminScreen> createState() =>
      _PlatformAdminScreenState();
}

class _PlatformAdminScreenState extends ConsumerState<PlatformAdminScreen> {
  ConsoleSection _section = ConsoleSection.overview;

  /// Non-null while a Subscriber detail is open (always under
  /// [ConsoleSection.subscribers]).
  String? _openSubscriberId;

  void _select(ConsoleSection section) {
    setState(() {
      _section = section;
      // Leaving Subscribers closes any open detail, so returning to the tab
      // later lands on the list rather than a tenant the operator has moved on
      // from.
      _openSubscriberId = null;
    });
  }

  void _openSubscriber(String organizationId) =>
      setState(() => _openSubscriberId = organizationId);

  void _closeSubscriber() => setState(() => _openSubscriberId = null);

  /// Refreshes the CURRENT page only. A blanket invalidate-everything would make
  /// one tap re-read all five endpoints and write five audit rows for a refresh
  /// the operator asked of one screen.
  void _refresh() {
    switch (_section) {
      case ConsoleSection.overview:
        ref.invalidate(consoleOverviewProvider);
        // The Overview renders today's sales from a SECOND read; refreshing
        // only the counts would leave the money beside them stale.
        ref.invalidate(
          restaurantOperationsPageProvider(
            const RestaurantOperationsQuery(limit: 200),
          ),
        );
      case ConsoleSection.subscribers:
        final open = _openSubscriberId;
        if (open != null) {
          ref.invalidate(subscriberDetailProvider(open));
        } else {
          ref.invalidate(
            subscriberPageProvider(ref.read(subscriberQueryProvider)),
          );
        }
      case ConsoleSection.restaurants:
        // ADMIN-126: the page reads OPERATIONS now. Refreshing the retired
        // restaurant-list provider would leave the visible figures stale while
        // the button appeared to work.
        ref.invalidate(
          restaurantOperationsPageProvider(
            ref.read(restaurantOperationsQueryProvider),
          ),
        );
      case ConsoleSection.audit:
        ref.read(auditFeedProvider.notifier).refresh();
    }
  }

  /// The page for the current section. Subscriber detail is nested UNDER
  /// Subscribers rather than being its own destination: it always belongs to a
  /// tenant the operator picked from that list.
  Widget _buildBody() {
    switch (_section) {
      case ConsoleSection.overview:
        return const ConsoleOverviewPage();
      case ConsoleSection.subscribers:
        final open = _openSubscriberId;
        if (open != null && open.isNotEmpty) {
          return ConsoleSubscriberDetailPage(
            // Keyed by tenant, so opening a second subscriber builds a fresh
            // page instead of reusing the first one's state.
            key: ValueKey('subscriber-detail-$open'),
            organizationId: open,
            onBack: _closeSubscriber,
          );
        }
        return ConsoleSubscribersPage(onOpenSubscriber: _openSubscriber);
      case ConsoleSection.restaurants:
        return const ConsoleRestaurantsPage();
      case ConsoleSection.audit:
        return const ConsoleAuditLogPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final destinations = _destinations(l10n);

    final body = _buildBody();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final useRail = width >= _kRailBreakpoint;
        final extended = width >= _kExtendedRailBreakpoint;

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
                // Flexible, because an AppBar gives its title a BOUNDED width
                // while a Row lays a non-flex child out unbounded — that is how
                // the console's own name used to be the thing clipped at 390.
                Flexible(
                  child: Text(
                    l10n.adminAppTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              const LanguageSelector(),
              IconButton(
                key: const Key('platform-refresh-button'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: l10n.adminRefresh,
              ),
              if (widget.onSignOut case final signOut?)
                IconButton(
                  key: const Key('platform-signout-button'),
                  onPressed: signOut,
                  icon: const Icon(Icons.logout),
                  tooltip: l10n.authSignOut,
                ),
            ],
          ),
          // Below the rail breakpoint the destinations move into a drawer, so a
          // phone spends its width on the data rather than on navigation.
          drawer: useRail
              ? null
              : Drawer(
                  key: const Key('console-drawer'),
                  child: SafeArea(
                    child: ListView(
                      children: [
                        _DrawerHeader(
                          isDemo: isDemo,
                          operatorEmail: widget.operatorEmail,
                        ),
                        for (var i = 0; i < destinations.length; i++)
                          ListTile(
                            key: Key(
                              'console-drawer-${destinations[i].id.name}',
                            ),
                            leading: Icon(destinations[i].icon),
                            title: Text(destinations[i].label),
                            selected: destinations[i].id == _section,
                            onTap: () {
                              Navigator.of(context).pop();
                              _select(destinations[i].id);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (useRail)
                  NavigationRail(
                    key: const Key('console-rail'),
                    extended: extended,
                    selectedIndex: destinations.indexWhere(
                      (d) => d.id == _section,
                    ),
                    onDestinationSelected: (index) =>
                        _select(destinations[index].id),
                    labelType: extended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: extended
                        ? null
                        : const Padding(
                            padding: EdgeInsets.only(top: RestoflowSpacing.sm),
                          ),
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                if (useRail) const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ModeStrip(
                        isDemo: isDemo,
                        operatorEmail: widget.operatorEmail,
                      ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_Destination> _destinations(AppLocalizations l10n) => [
    _Destination(
      ConsoleSection.overview,
      l10n.adminNavOverview,
      Icons.insights_outlined,
      Icons.insights,
    ),
    _Destination(
      ConsoleSection.subscribers,
      l10n.adminNavSubscribers,
      Icons.domain_outlined,
      Icons.domain,
    ),
    _Destination(
      ConsoleSection.restaurants,
      l10n.adminNavRestaurants,
      Icons.restaurant_outlined,
      Icons.restaurant,
    ),
    _Destination(
      ConsoleSection.audit,
      l10n.adminNavAuditLog,
      Icons.receipt_long_outlined,
      Icons.receipt_long,
    ),
  ];
}

class _Destination {
  const _Destination(this.id, this.label, this.icon, this.selectedIcon);

  final ConsoleSection id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The persistent Demo/Live strip: which data the console is showing, which
/// operator is signed in, and that the console writes nothing.
///
/// It sits ABOVE the page content and OUTSIDE it, so no page can be read without
/// its provenance in view — a demo figure must never be mistaken for a live one.
class _ModeStrip extends StatelessWidget {
  const _ModeStrip({required this.isDemo, this.operatorEmail});

  final bool isDemo;
  final String? operatorEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final email = operatorEmail;
    return Container(
      key: isDemo
          ? const Key('platform-demo-banner')
          : const Key('platform-realmode-banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.lg,
        vertical: RestoflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: RestoflowSpacing.sm,
        runSpacing: RestoflowSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          RestoflowStatusPill(
            key: const Key('platform-data-source-pill'),
            label: isDemo ? l10n.adminDemoDataTag : l10n.adminLiveLimitedTag,
            tone: isDemo ? RestoflowTone.warning : RestoflowTone.success,
          ),
          RestoflowStatusPill(
            key: const Key('platform-readonly-pill'),
            label: l10n.adminConsoleReadOnly,
            icon: Icons.lock_outline,
          ),
          if (email != null && email.isNotEmpty)
            Text(
              l10n.adminSignedInAs(email),
              key: const Key('platform-signed-in-as'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The drawer's identity block on compact widths (the rail has no room for it).
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.isDemo, this.operatorEmail});

  final bool isDemo;
  final String? operatorEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final email = operatorEmail;
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.adminConsoleSections,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          RestoflowStatusPill(
            label: isDemo ? l10n.adminDemoDataTag : l10n.adminLiveLimitedTag,
            tone: isDemo ? RestoflowTone.warning : RestoflowTone.success,
          ),
          if (email != null && email.isNotEmpty) ...[
            const SizedBox(height: RestoflowSpacing.xs),
            Text(
              l10n.adminSignedInAs(email),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// At/above this width the destinations live in a persistent rail; below it they
/// move into a drawer.
const double _kRailBreakpoint = RestoflowBreakpoints.wide;

/// At/above this width the rail shows its labels beside the icons.
const double _kExtendedRailBreakpoint = 1200;
