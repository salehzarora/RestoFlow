/// The Platform Console RESTAURANTS page (ADMIN-125C.2, extended by ADMIN-126
/// into an OPERATIONS view).
///
/// Consumes `public.platform_admin_restaurant_operations`, which returns each
/// restaurant's own trading figures for its own business day PLUS the active
/// organization-owner contact(s).
///
/// THE MONEY ON THIS PAGE IS THE TENANT'S OWN NUMBER. The server reads it from
/// `app.owner_report_range` — the identical function the restaurant owner's
/// Dashboard reads — so a figure here and the figure the owner is looking at
/// cannot drift apart. This page therefore performs NO arithmetic on money: it
/// formats integer minor units and nothing else (DECISION D-007).
///
/// CURRENCIES ARE NEVER ADDED. Each row is shown in its own effective currency
/// and the page-level totals are grouped BY currency. A single number spanning
/// ILS and USD would be wrong in both, so it is not offered at all — not even
/// as a convenience.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_currency/restoflow_currency.dart';
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
    final query = ref.watch(restaurantOperationsQueryProvider);
    final async = ref.watch(restaurantOperationsPageProvider(query));

    void setQuery(RestaurantOperationsQuery next) =>
        ref.read(restaurantOperationsQueryProvider.notifier).state = next;

    final filters = ConsoleFilterBar(
      isFiltered:
          query.search != null ||
          query.organizationStatus != null ||
          query.withSales != null ||
          query.sort != RestaurantOperationsSort.salesDesc,
      onClear: () => setQuery(const RestaurantOperationsQuery()),
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
        ConsoleFilterDropdown<bool>(
          key: const Key('restaurants-sales-filter'),
          label: l10n.adminFilterSalesToday,
          value: query.withSales,
          options: const [true, false],
          labelOf: (v) =>
              v ? l10n.adminFilterWithSales : l10n.adminFilterNoSales,
          onChanged: (value) =>
              setQuery(query.copyWith(withSales: value).resetToFirstPage()),
        ),
        ConsoleFilterDropdown<RestaurantOperationsSort>(
          key: const Key('restaurants-sort'),
          label: l10n.adminSortLabel,
          value: query.sort,
          options: RestaurantOperationsSort.values,
          allLabel: l10n.adminSortSalesDesc,
          labelOf: (sort) => _sortLabel(l10n, sort),
          onChanged: (value) => setQuery(
            query
                .copyWith(sort: value ?? RestaurantOperationsSort.salesDesc)
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
              onRetry: () =>
                  ref.invalidate(restaurantOperationsPageProvider(query)),
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
                    CurrencyTotalsStrip(
                      totals: page.totalsByCurrency,
                      keyPrefix: 'restaurants',
                    ),
                    const SizedBox(height: RestoflowSpacing.md),
                    RestoflowSectionCard(
                      key: const Key('restaurants-card'),
                      children: [
                        for (final row in page.rows)
                          _OperationsTile(row: row, l10n: l10n),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
                      child: Text(
                        l10n.adminOperationsNote,
                        key: const Key('restaurants-provenance-note'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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

class _OperationsTile extends StatelessWidget {
  const _OperationsTile({required this.row, required this.l10n});

  final RestaurantOperationsRow row;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConsoleListRow(
      key: Key('restaurant-row-${row.restaurantId}'),
      title: row.restaurantName,
      meta: [
        '${l10n.adminOrganizationHeading}: ${row.organizationName}',
        '${l10n.adminBranchesLabel}: ${row.branchesCount}',
        '${l10n.adminKpiOrdersToday}: ${row.todayOrdersCount}',
        // The restaurant's OWN business day, which for a tenant in another
        // timezone is not necessarily the operator's today.
        '${l10n.adminBusinessDay} ${row.reportingDate}',
        OwnerContactLabel.of(l10n, row.ownerContacts),
      ],
      trailing: [
        // Money is formatted through the ONE shared formatter, in the row's own
        // currency. No conversion, no rounding, no arithmetic.
        Text(
          formatCurrencyMinor(row.todayRevenueMinor, row.currencyCode),
          key: Key('restaurant-sales-${row.restaurantId}'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: row.todayRevenueMinor > 0
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ConsoleStatusPill(status: row.restaurantStatus),
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

/// Renders the owner contact for a row: the first email, plus a count of any
/// others. A tenant with no active owner says so — an empty cell would read as
/// a failed load rather than as the real answer.
abstract final class OwnerContactLabel {
  static String of(AppLocalizations l10n, List<String> contacts) {
    if (contacts.isEmpty) return l10n.adminNoOwnerContact;
    if (contacts.length == 1) {
      return '${l10n.adminOwnerContact}: ${contacts.first}';
    }
    return '${l10n.adminOwnerContact}: ${contacts.first} '
        '${l10n.adminMoreContacts(contacts.length - 1)}';
  }
}

/// Today's totals, one chip per currency.
///
/// There is deliberately no combined figure. Two currencies produce two chips;
/// they are never reduced to one number, because that number would be wrong in
/// both currencies and there is no exchange rate in this system to make it right.
class CurrencyTotalsStrip extends StatelessWidget {
  const CurrencyTotalsStrip({
    required this.totals,
    required this.keyPrefix,
    super.key,
  });

  final List<CurrencyDayTotal> totals;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final trading = totals.where((t) => t.currencyCode.isNotEmpty).toList();
    if (trading.isEmpty) return const SizedBox.shrink();
    final anySales = trading.any((t) => t.todayRevenueMinor != 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.adminSalesTodayByCurrency,
          key: Key('$keyPrefix-currency-totals-heading'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        if (!anySales)
          Text(
            l10n.adminNoSalesTodayYet,
            key: Key('$keyPrefix-no-sales-today'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: RestoflowSpacing.sm,
            runSpacing: RestoflowSpacing.xs,
            children: [
              for (final total in trading)
                RestoflowStatusPill(
                  key: Key('$keyPrefix-total-${total.currencyCode}'),
                  label:
                      '${formatCurrencyMinor(total.todayRevenueMinor, total.currencyCode)}'
                      '  ·  ${total.todayOrdersCount} ${l10n.adminKpiOrdersToday}',
                  tone: total.todayRevenueMinor > 0
                      ? RestoflowTone.success
                      : RestoflowTone.neutral,
                ),
            ],
          ),
      ],
    );
  }
}

String _sortLabel(AppLocalizations l10n, RestaurantOperationsSort sort) =>
    switch (sort) {
      RestaurantOperationsSort.nameAsc => l10n.adminSortNameAsc,
      RestaurantOperationsSort.nameDesc => l10n.adminSortNameDesc,
      RestaurantOperationsSort.organizationAsc => l10n.adminSortOrganizationAsc,
      RestaurantOperationsSort.organizationDesc =>
        l10n.adminSortOrganizationDesc,
      RestaurantOperationsSort.salesDesc => l10n.adminSortSalesDesc,
      RestaurantOperationsSort.salesAsc => l10n.adminSortSalesAsc,
      RestaurantOperationsSort.ordersDesc => l10n.adminSortOrdersDesc,
      RestaurantOperationsSort.ordersAsc => l10n.adminSortOrdersAsc,
    };
