/// The Platform Console SUBSCRIBERS page (ADMIN-125C.2).
///
/// Consumes `public.platform_admin_list_subscribers`. "Subscriber" is the
/// owner-facing name for the existing ORGANIZATION tenant — not a new entity.
///
/// Search, filters, sort and paging all happen ON THE SERVER. That is not a
/// performance nicety: the console is cross-tenant, so pulling every
/// organization down to filter in the browser would mean shipping the whole
/// tenant list to the client on every visit, and the audit log would record one
/// undifferentiated "read everything" instead of the narrow read the operator
/// actually made.
///
/// Row taps open the detail BY `organization_id`. The pre-125C.2 client mapped
/// organizations without their id at all, which is precisely why no detail view
/// could exist.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/console_models.dart';
import '../state/platform_admin_providers.dart';
import 'console_widgets.dart';

/// The plan codes offered in the plan filter. `plans` is a tiny, stable seed
/// table (`free`, `basic`); the console does not read it separately just to
/// populate a two-item dropdown, and an unknown code simply matches nothing.
const List<String> kKnownPlanCodes = <String>['free', 'basic'];

class ConsoleSubscribersPage extends ConsumerWidget {
  const ConsoleSubscribersPage({required this.onOpenSubscriber, super.key});

  /// Opens the read-only detail for an organization id.
  final void Function(String organizationId) onOpenSubscriber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(subscriberQueryProvider);
    final async = ref.watch(subscriberPageProvider(query));

    void setQuery(SubscriberQuery next) =>
        ref.read(subscriberQueryProvider.notifier).state = next;

    final filters = ConsoleFilterBar(
      isFiltered:
          query.search != null ||
          query.organizationStatus != null ||
          query.planCode != null ||
          query.subscriptionStatus != null ||
          query.sort != SubscriberSort.nameAsc,
      onClear: () => setQuery(const SubscriberQuery()),
      children: [
        ConsoleSearchField(
          fieldKey: const Key('subscribers-search'),
          value: query.search,
          // Every filter change rewinds to page 1: keeping the old offset after
          // narrowing the results is how a console shows a blank page over data
          // that is definitely there.
          onSubmitted: (value) =>
              setQuery(query.copyWith(search: value).resetToFirstPage()),
        ),
        ConsoleFilterDropdown<String>(
          key: const Key('subscribers-org-status-filter'),
          label: l10n.adminFilterOrganizationStatus,
          value: query.organizationStatus,
          options: kOrganizationStatuses,
          labelOf: (status) => localizedStatus(l10n, status),
          onChanged: (value) => setQuery(
            query.copyWith(organizationStatus: value).resetToFirstPage(),
          ),
        ),
        ConsoleFilterDropdown<String>(
          key: const Key('subscribers-plan-filter'),
          label: l10n.adminPlanLabel,
          value: query.planCode,
          options: kKnownPlanCodes,
          labelOf: (code) => code,
          onChanged: (value) =>
              setQuery(query.copyWith(planCode: value).resetToFirstPage()),
        ),
        ConsoleFilterDropdown<String>(
          key: const Key('subscribers-subscription-status-filter'),
          label: l10n.adminFilterSubscriptionStatus,
          value: query.subscriptionStatus,
          options: kSubscriptionStatuses,
          labelOf: (status) => localizedStatus(l10n, status),
          onChanged: (value) => setQuery(
            query.copyWith(subscriptionStatus: value).resetToFirstPage(),
          ),
        ),
        ConsoleFilterDropdown<SubscriberSort>(
          key: const Key('subscribers-sort'),
          label: l10n.adminSortLabel,
          value: query.sort,
          options: SubscriberSort.values,
          allLabel: l10n.adminSortNameAsc,
          labelOf: (sort) => _sortLabel(l10n, sort),
          onChanged: (value) => setQuery(
            query
                .copyWith(sort: value ?? SubscriberSort.nameAsc)
                .resetToFirstPage(),
          ),
        ),
      ],
    );

    return ConsolePage(
      title: l10n.adminNavSubscribers,
      subtitle: l10n.adminConsoleReadOnly,
      icon: Icons.domain_outlined,
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
              onRetry: () => ref.invalidate(subscriberPageProvider(query)),
            ),
          ),
          data: (page) => page.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: RestoflowSpacing.xl),
                  child: ConsoleEmpty(
                    stateKey: const Key('subscribers-empty'),
                    message: l10n.adminNoSubscribers,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RestoflowSectionCard(
                      key: const Key('subscribers-card'),
                      children: [
                        for (final row in page.rows)
                          _SubscriberTile(
                            row: row,
                            l10n: l10n,
                            onTap: () => onOpenSubscriber(row.organizationId),
                          ),
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

class _SubscriberTile extends StatelessWidget {
  const _SubscriberTile({
    required this.row,
    required this.l10n,
    required this.onTap,
  });

  final SubscriberRow row;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '${l10n.adminKpiRestaurants}: ${row.restaurantsCount}',
      '${l10n.adminBranchesLabel}: ${row.branchesCount}',
      '${l10n.adminMembersLabel}: ${row.activeMembershipsCount}',
      '${l10n.adminCreatedLabel} ${row.createdAtLabel}',
      '${l10n.adminDefaultCurrency}: ${row.defaultCurrency}',
      if (row.currentPeriodEndLabel case final end?)
        '${l10n.adminPeriodEnd}: $end',
    ];
    return ConsoleListRow(
      key: Key('subscriber-row-${row.organizationId}'),
      title: row.organizationName,
      meta: meta,
      onTap: onTap,
      trailing: [
        // A tenant with no plan gets a plain, honest label — NOT an em dash, and
        // not a blank cell that reads like the console failed to load it.
        if (row.hasSubscription) ...[
          Text(
            row.planDisplayName ?? row.planCode ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          ConsoleStatusPill(status: row.subscriptionStatus!),
        ] else
          RestoflowStatusPill(
            key: Key('subscriber-no-subscription-${row.organizationId}'),
            label: l10n.adminNoSubscription,
          ),
        ConsoleStatusPill(status: row.organizationStatus),
      ],
    );
  }
}

String _sortLabel(AppLocalizations l10n, SubscriberSort sort) => switch (sort) {
  SubscriberSort.nameAsc => l10n.adminSortNameAsc,
  SubscriberSort.nameDesc => l10n.adminSortNameDesc,
  SubscriberSort.createdAsc => l10n.adminSortOldestFirst,
  SubscriberSort.createdDesc => l10n.adminSortNewestFirst,
  SubscriberSort.periodEndAsc => l10n.adminSortPeriodEndAsc,
  SubscriberSort.periodEndDesc => l10n.adminSortPeriodEndDesc,
};
