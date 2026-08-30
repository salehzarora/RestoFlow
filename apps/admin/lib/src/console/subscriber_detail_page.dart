/// The Platform Console SUBSCRIBER DETAIL page (ADMIN-125C.2).
///
/// Consumes `public.platform_admin_get_subscriber`, plus a SECOND, separately
/// audited read of `public.platform_admin_audit_search` scoped to this tenant.
///
/// WHAT IS NOT HERE, AND WHY: no member identities, no order or payment figure,
/// and no `created_by_app_user_id` / `creation_request_id`. The first two are
/// tenant business data that a platform operator has no need to read to answer
/// "is this subscriber set up correctly"; the last two identify a specific
/// person and a support ticket, and the server does not return them at all.
///
/// There are NO write controls: no suspend, no plan change, no impersonation.
/// This phase is read-only (DECISION D-026), and adding a button here would need
/// its own guarded, audited RPC and its own ticket.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/console_models.dart';
import '../state/platform_admin_providers.dart';
import 'console_widgets.dart';

class ConsoleSubscriberDetailPage extends ConsumerWidget {
  const ConsoleSubscriberDetailPage({
    required this.organizationId,
    required this.onBack,
    super.key,
  });

  final String organizationId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(subscriberDetailProvider(organizationId));

    final back = TextButton.icon(
      key: const Key('subscriber-detail-back'),
      onPressed: onBack,
      icon: Icon(
        Icons.arrow_back,
        size: RestoflowIconSizes.sm,
        textDirection: Directionality.of(context),
      ),
      label: Text(l10n.adminBackToSubscribers),
    );

    return async.when(
      loading: () => ConsolePage(
        title: l10n.adminSubscriberDetailTitle,
        icon: Icons.domain_outlined,
        leading: back,
        children: const [ConsoleLoading()],
      ),
      // An unknown or tombstoned tenant raises the SAME 42501 as a denial, so
      // this renders the access-denied state either way — the console must not
      // become a way to discover which organization ids exist.
      error: (error, _) => ConsolePage(
        title: l10n.adminSubscriberDetailTitle,
        icon: Icons.domain_outlined,
        leading: back,
        children: [
          ConsoleErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(subscriberDetailProvider(organizationId)),
          ),
        ],
      ),
      data: (detail) => _Content(
        detail: detail,
        organizationId: organizationId,
        l10n: l10n,
        back: back,
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.detail,
    required this.organizationId,
    required this.l10n,
    required this.back,
  });

  final SubscriberDetail detail;
  final String organizationId;
  final AppLocalizations l10n;
  final Widget back;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = detail.organization;
    final counts = detail.counts;
    final subscription = detail.subscription;

    final organizationCard = RestoflowSectionCard(
      key: const Key('subscriber-organization-card'),
      title: l10n.adminOrganizationHeading,
      children: [
        ConsoleFact(label: l10n.adminOrganizationHeading, value: org.name),
        ConsoleFact(
          label: l10n.adminFilterOrganizationStatus,
          value: org.status,
          valueWidget: ConsoleStatusPill(status: org.status),
        ),
        ConsoleFact(label: l10n.adminCreatedLabel, value: org.createdAtLabel),
        ConsoleFact(
          label: l10n.adminDefaultCurrency,
          value: org.defaultCurrency,
        ),
      ],
    );

    final countsCard = RestoflowSectionCard(
      key: const Key('subscriber-counts-card'),
      title: l10n.adminCountsHeading,
      children: [
        ConsoleFact(
          label: l10n.adminKpiRestaurants,
          value: counts.restaurantsCount.toString(),
        ),
        ConsoleFact(
          label: l10n.adminBranchesLabel,
          value: counts.branchesCount.toString(),
        ),
        ConsoleFact(
          label: l10n.adminKpiActiveMemberships,
          value: counts.activeMembershipsCount.toString(),
        ),
      ],
    );

    final subscriptionCard = RestoflowSectionCard(
      key: const Key('subscriber-subscription-card'),
      title: l10n.adminSubscriptionHeading,
      children: subscription == null
          ? [
              // The state EVERY production tenant is in today. Said plainly,
              // rather than left as four empty rows.
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: RestoflowSpacing.sm,
                ),
                child: Text(
                  l10n.adminNoSubscriptionConfigured,
                  key: const Key('subscriber-no-subscription'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ]
          : [
              ConsoleFact(
                label: l10n.adminPlanLabel,
                value: subscription.planDisplayName,
              ),
              ConsoleFact(
                label: l10n.adminFilterSubscriptionStatus,
                value: subscription.status,
                valueWidget: ConsoleStatusPill(status: subscription.status),
              ),
              ConsoleFact(
                label: l10n.adminPeriodStart,
                value: subscription.currentPeriodStartLabel ?? '',
              ),
              ConsoleFact(
                label: l10n.adminPeriodEnd,
                value: subscription.currentPeriodEndLabel ?? '',
              ),
            ],
    );

    // ADMIN-126: who to actually contact about this tenant. Active organization
    // owners only — a support console needs the signatory, not the roster, and
    // showing every member here would be an unnecessary spread of staff PII.
    final ownerCard = RestoflowSectionCard(
      key: const Key('subscriber-owner-contact-card'),
      title: l10n.adminOwnerContact,
      children: [
        if (detail.ownerContacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
            child: Text(
              // Said plainly: an empty panel would read as a failed load rather
              // than as the real answer.
              l10n.adminNoOwnerContact,
              key: const Key('subscriber-no-owner-contact'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final email in detail.ownerContacts)
            ConsoleListRow(
              key: Key('subscriber-owner-$email'),
              title: email,
              trailing: const [
                Icon(Icons.mail_outline, size: RestoflowIconSizes.sm),
              ],
            ),
      ],
    );

    final restaurantsCard = RestoflowSectionCard(
      key: const Key('subscriber-restaurants-card'),
      title: l10n.adminKpiRestaurants,
      children: [
        if (detail.restaurants.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
            child: Text(l10n.adminNoRestaurants),
          )
        else
          for (final restaurant in detail.restaurants)
            ConsoleListRow(
              key: Key('subscriber-restaurant-${restaurant.id}'),
              title: restaurant.name,
              meta: ['${l10n.adminBranchesLabel}: ${restaurant.branchesCount}'],
              trailing: [ConsoleStatusPill(status: restaurant.status)],
            ),
      ],
    );

    return ConsolePage(
      title: org.name,
      subtitle: l10n.adminSubscriberDetailTitle,
      icon: Icons.domain_outlined,
      leading: back,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= RestoflowBreakpoints.wide;
            if (!twoColumn) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: withSectionGaps([
                  organizationCard,
                  ownerCard,
                  countsCard,
                  subscriptionCard,
                  restaurantsCard,
                ]),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: withSectionGaps([
                      organizationCard,
                      ownerCard,
                      countsCard,
                    ]),
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.lg),
                Expanded(
                  child: Column(
                    children: withSectionGaps([
                      subscriptionCard,
                      restaurantsCard,
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        _ScopedActivity(organizationId: organizationId, l10n: l10n),
      ],
    );
  }
}

/// The audit rows that target THIS tenant.
///
/// A separate, separately-audited read: it uses the same
/// `platform_admin_audit_search` contract with `p_target_organization_id` set,
/// so the platform log records that the operator inspected this subscriber's
/// history — not just that they opened its page.
class _ScopedActivity extends ConsumerWidget {
  const _ScopedActivity({required this.organizationId, required this.l10n});

  final String organizationId;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = AuditQuery(
      limit: kScopedActivityLimit,
      targetOrganizationId: organizationId,
    );
    final async = ref.watch(auditPageProvider(query));
    return RestoflowSectionCard(
      key: const Key('subscriber-activity-card'),
      title: l10n.adminRecentPlatformActivity,
      children: [
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.lg),
            child: ConsoleLoading(stateKey: Key('subscriber-activity-loading')),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.lg),
            child: ConsoleErrorView(
              error: error,
              onRetry: () => ref.invalidate(auditPageProvider(query)),
            ),
          ),
          data: (page) => page.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: RestoflowSpacing.sm,
                  ),
                  child: Text(
                    l10n.adminNoActivityForSubscriber,
                    key: const Key('subscriber-activity-empty'),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final event in page.rows)
                      ConsoleListRow(
                        key: Key('subscriber-activity-${event.id}'),
                        title: event.reason,
                        meta: [
                          event.occurredAtLabel,
                          '${l10n.adminAuditActorLabel}: ${event.actorShortId}',
                        ],
                        trailing: [RestoflowStatusPill(label: event.action)],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// How many scoped audit rows a subscriber detail shows. Short on purpose — the
/// full history lives on the Audit log page, which can page through all of it.
const int kScopedActivityLimit = 10;
