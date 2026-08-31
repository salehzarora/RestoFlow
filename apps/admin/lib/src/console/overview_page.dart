/// The Platform Console OVERVIEW page (ADMIN-125C.2).
///
/// Consumes `public.platform_admin_console_overview` and shows ONLY metrics the
/// platform can actually measure: tenants, their statuses, restaurants,
/// branches, active memberships, and the four subscription states.
///
/// What is deliberately ABSENT is the point of this page. The pre-125C.2 console
/// carried device, orders-today, active-branch and "open alerts" cards. The read
/// panel never provided any of them, so in real mode they were either hidden or
/// shown as a fabricated `0` — and the "Open alerts" card was the SUSPENDED
/// ORGANIZATION count wearing an alarm label, which invites an operator to go
/// hunting for an incident that does not exist. Those cards are gone; the
/// suspended count is now named for what it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/console_models.dart';
import '../state/platform_admin_providers.dart';
import 'console_widgets.dart';
import 'restaurants_page.dart' show CurrencyTotalsStrip;

class ConsoleOverviewPage extends ConsumerWidget {
  const ConsoleOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(consoleOverviewProvider);
    void refresh() => ref.invalidate(consoleOverviewProvider);

    return async.when(
      loading: ConsoleLoading.new,
      error: (error, _) => ConsoleErrorView(error: error, onRetry: refresh),
      data: (overview) => _Content(overview: overview, l10n: l10n),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.overview, required this.l10n});

  final ConsoleOverview overview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // The server's own "as of" day, so the operator sees the BACKEND's clock
    // rather than this device's.
    final asOf = '${l10n.adminOverviewAsOf} ${overview.serverDateLabel}';

    if (overview.isEmpty) {
      return ConsolePage(
        title: l10n.adminOverviewTitle,
        subtitle: asOf,
        icon: Icons.insights_outlined,
        headerKey: const Key('platform-overview-title'),
        children: [ConsoleEmpty(message: l10n.adminEmpty)],
      );
    }

    final platformCards = <Widget>[
      RestoflowMetricCard(
        key: const Key('kpi-organizations'),
        label: l10n.adminKpiSubscribers,
        value: overview.organizationsTotal.toString(),
        caption: '${l10n.adminActiveLabel}: ${overview.organizationsActive}',
        icon: Icons.domain_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-suspended-organizations'),
        label: l10n.adminKpiSuspendedOrganizations,
        value: overview.organizationsSuspended.toString(),
        icon: Icons.pause_circle_outline,
        // Toned only when there is actually something suspended: a permanently
        // red zero trains the operator to ignore the card.
        tone: overview.organizationsSuspended > 0
            ? RestoflowTone.danger
            : RestoflowTone.neutral,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-restaurants'),
        label: l10n.adminKpiRestaurants,
        value: overview.restaurantsTotal.toString(),
        icon: Icons.restaurant_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-branches'),
        label: l10n.adminKpiBranches,
        value: overview.branchesTotal.toString(),
        icon: Icons.store_mall_directory_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-active-memberships'),
        label: l10n.adminKpiActiveMemberships,
        value: overview.activeMembershipsTotal.toString(),
        icon: Icons.badge_outlined,
      ),
    ];

    final subscriptionCards = <Widget>[
      RestoflowMetricCard(
        key: const Key('kpi-subscriptions-trialing'),
        label: l10n.adminSubStatusTrialing,
        value: overview.subscriptionsTrialing.toString(),
        icon: Icons.hourglass_bottom_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-subscriptions-active'),
        label: l10n.adminSubStatusActive,
        value: overview.subscriptionsActive.toString(),
        icon: Icons.verified_outlined,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-subscriptions-past-due'),
        label: l10n.adminSubStatusPastDue,
        value: overview.subscriptionsPastDue.toString(),
        icon: Icons.schedule_outlined,
        tone: overview.subscriptionsPastDue > 0
            ? RestoflowTone.warning
            : RestoflowTone.neutral,
      ),
      RestoflowMetricCard(
        key: const Key('kpi-subscriptions-canceled'),
        label: l10n.adminSubStatusCanceled,
        value: overview.subscriptionsCanceled.toString(),
        icon: Icons.cancel_outlined,
      ),
    ];

    return ConsolePage(
      title: l10n.adminOverviewTitle,
      subtitle: asOf,
      icon: Icons.insights_outlined,
      headerKey: const Key('platform-overview-title'),
      children: [
        ConsoleMetricGrid(cards: platformCards),
        const SizedBox(height: RestoflowSpacing.xl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l10n.adminSubscriptionsHeading,
            key: const Key('subscriptions-heading'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        // Four zeros with no explanation read like a billing outage. Production
        // has simply never had a plan assigned, so say that instead.
        if (overview.hasNoSubscriptions) ...[
          RestoflowNoticeBanner(
            key: const Key('no-subscriptions-notice'),
            title: l10n.adminNoSubscriptionsConfiguredTitle,
            body: l10n.adminNoSubscriptionsConfiguredBody,
          ),
          const SizedBox(height: RestoflowSpacing.md),
        ],
        ConsoleMetricGrid(cards: subscriptionCards),
        const SizedBox(height: RestoflowSpacing.xl),
        const _SalesTodayByCurrency(),
      ],
    );
  }
}

/// Today's trading across the platform, grouped BY CURRENCY.
///
/// A SEPARATE read from the counts above, rendered independently: if it fails
/// or is slow it must not take the Overview's tenant counts down with it, and a
/// missing sales figure is far less serious than a missing tenant count.
///
/// There is deliberately no combined total. The platform trades in several
/// currencies and this system holds no exchange rate, so one number spanning
/// them would be wrong in every one of them.
class _SalesTodayByCurrency extends ConsumerWidget {
  const _SalesTodayByCurrency();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A page-size of 200 is the server's own cap; the totals it returns cover
    // the whole filtered set regardless of the page, so this is one read.
    const query = RestaurantOperationsQuery(limit: 200);
    final async = ref.watch(restaurantOperationsPageProvider(query));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (page) => CurrencyTotalsStrip(
        totals: page.totalsByCurrency,
        keyPrefix: 'overview',
      ),
    );
  }
}
