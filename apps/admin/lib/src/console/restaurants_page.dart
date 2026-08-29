/// The Platform Console RESTAURANTS page (ADMIN-125C.2).
///
/// Consumes `public.platform_admin_list_restaurants` — the platform's FIRST
/// cross-tenant restaurant read. Before ADMIN-125C.1, restaurants were reachable
/// one organization at a time only, so "which restaurants exist on this
/// platform" had no answer short of a DBA query.
///
/// The currency column shows the EFFECTIVE currency
/// (`coalesce(currency_override, organization default)`) — the same rule the POS
/// and menu reads apply — with an explicit marker when a restaurant overrides
/// its organization. Quoting the organization default alone would let the
/// console disagree with the till that actually prints the receipt.
///
/// No financial or order metrics: this is a structural inventory, not a report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/console_models.dart';
import '../state/platform_admin_providers.dart';
import 'console_widgets.dart';

class ConsoleRestaurantsPage extends ConsumerWidget {
  const ConsoleRestaurantsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(restaurantQueryProvider);
    final async = ref.watch(restaurantPageProvider(query));

    void setQuery(RestaurantQuery next) =>
        ref.read(restaurantQueryProvider.notifier).state = next;

    final filters = ConsoleFilterBar(
      isFiltered:
          query.search != null ||
          query.organizationStatus != null ||
          query.sort != RestaurantSort.nameAsc,
      onClear: () => setQuery(const RestaurantQuery()),
      children: [
        ConsoleSearchField(
          fieldKey: const Key('restaurants-search'),
          value: query.search,
          onSubmitted: (value) =>
              setQuery(query.copyWith(search: value).resetToFirstPage()),
        ),
        ConsoleFilterDropdown<String>(
          key: const Key('restaurants-org-status-filter'),
          label: l10n.adminFilterOrganizationStatus,
          value: query.organizationStatus,
          options: kOrganizationStatuses,
          labelOf: (status) => localizedStatus(l10n, status),
          onChanged: (value) => setQuery(
            query.copyWith(organizationStatus: value).resetToFirstPage(),
          ),
        ),
        ConsoleFilterDropdown<RestaurantSort>(
          key: const Key('restaurants-sort'),
          label: l10n.adminSortLabel,
          value: query.sort,
          options: RestaurantSort.values,
          allLabel: l10n.adminSortNameAsc,
          labelOf: (sort) => _sortLabel(l10n, sort),
          onChanged: (value) => setQuery(
            query
                .copyWith(sort: value ?? RestaurantSort.nameAsc)
                .resetToFirstPage(),
          ),
        ),
      ],
    );

    return ConsolePage(
      title: l10n.adminNavRestaurants,
      subtitle: l10n.adminConsoleReadOnly,
      icon: Icons.restaurant_outlined,
      children: [
        filters,
        const SizedBox(height: RestoflowSpacing.lg),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: RestoflowSpacing.xl),
            child: ConsoleLoading(),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.xl),
            child: ConsoleErrorView(
              error: error,
              onRetry: () => ref.invalidate(restaurantPageProvider(query)),
            ),
          ),
          data: (page) => page.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: RestoflowSpacing.xl),
                  child: ConsoleEmpty(
                    stateKey: const Key('restaurants-empty'),
                    message: l10n.adminNoRestaurants,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RestoflowSectionCard(
                      key: const Key('restaurants-card'),
                      children: [
                        for (final row in page.rows)
                          _RestaurantTile(row: row, l10n: l10n),
                      ],
                    ),
                    ConsolePaginationBar(
                      firstRowNumber: page.firstRowNumber,
                      lastRowNumber: page.lastRowNumber,
                      totalCount: page.totalCount,
                      onPrevious: page.hasPrevious
                          ? () => setQuery(
                              query.copyWith(
                                offset: (query.offset - query.limit).clamp(
                                  0,
                                  1 << 30,
                                ),
                              ),
                            )
                          : null,
                      onNext: page.hasNext
                          ? () => setQuery(
                              query.copyWith(
                                offset: query.offset + query.limit,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RestaurantTile extends StatelessWidget {
  const _RestaurantTile({required this.row, required this.l10n});

  final RestaurantRow row;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ConsoleListRow(
      key: Key('restaurant-row-${row.restaurantId}'),
      title: row.restaurantName,
      meta: [
        '${l10n.adminOrganizationHeading}: ${row.organizationName}',
        '${l10n.adminBranchesLabel}: ${row.branchesCount}',
        '${l10n.adminCreatedLabel} ${row.createdAtLabel}',
        '${l10n.adminEffectiveCurrency}: ${row.effectiveCurrency}',
      ],
      trailing: [
        // Only shown when it is actually true — an override is unusual, and
        // marking every row would make the marker meaningless.
        if (row.hasCurrencyOverride)
          RestoflowStatusPill(
            key: Key('restaurant-currency-override-${row.restaurantId}'),
            label: l10n.adminCurrencyOverride,
            tone: RestoflowTone.info,
          ),
        ConsoleStatusPill(status: row.restaurantStatus),
        // The ORGANIZATION status matters here too: an active restaurant under
        // a suspended tenant is a real and confusing state, and hiding the
        // second half would make the row look healthy.
        if (row.organizationStatus != 'active')
          ConsoleStatusPill(
            key: Key('restaurant-org-status-${row.restaurantId}'),
            status: row.organizationStatus,
            icon: Icons.domain_outlined,
          ),
      ],
    );
  }
}

String _sortLabel(AppLocalizations l10n, RestaurantSort sort) => switch (sort) {
  RestaurantSort.nameAsc => l10n.adminSortNameAsc,
  RestaurantSort.nameDesc => l10n.adminSortNameDesc,
  RestaurantSort.createdAsc => l10n.adminSortOldestFirst,
  RestaurantSort.createdDesc => l10n.adminSortNewestFirst,
  RestaurantSort.organizationAsc => l10n.adminSortOrganizationAsc,
  RestaurantSort.organizationDesc => l10n.adminSortOrganizationDesc,
};
