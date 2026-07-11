/// The Dashboard "Activity log" surface (AUDIT-LOG-DASHBOARD-001).
///
/// A read-only, paginated, filterable operational audit timeline: who did what,
/// when, in which restaurant/branch, with a safe before→after and reason. Real
/// mode reads the `owner_audit_events` RPC (management-only, secret-scrubbed);
/// demo mode shows the in-memory dataset with an honest banner. It NEVER edits,
/// deletes, retries, or exposes raw payloads — the presentation mapper decides
/// what is safe to show. Loading / empty / filtered-empty / error / load-next
/// states throughout; RTL-safe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/audit_log_models.dart';
import '../data/audit_log_presentation.dart';
import '../state/audit_log_providers.dart';
import 'activity_detail_dialog.dart';

class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  void _apply(WidgetRef ref, AuditQuery Function(AuditQuery) update) {
    final notifier = ref.read(auditLogQueryProvider.notifier);
    notifier.state = update(notifier.state);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final query = ref.watch(auditLogQueryProvider);
    final state = ref.watch(auditLogControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // RF-125: the shared calm page header as a full-width band with a warm
        // hairline boundary above the scrolling timeline.
        RestoflowPageHeader(
          bordered: true,
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
          ),
          icon: Icons.history_outlined,
          title: l10n.activityLogTitle,
          subtitle: l10n.activityLogSubtitle,
          actions: [
            IconButton(
              key: const Key('activity-refresh'),
              tooltip: l10n.activityLogRefresh,
              onPressed: () =>
                  ref.read(auditLogControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            children: [
              if (isDemo)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: RestoflowSpacing.md,
                  ),
                  child: RestoflowNoticeBanner(
                    icon: Icons.science_outlined,
                    body: l10n.activityLogDemoNotice,
                  ),
                ),
              _FilterBar(
                query: query,
                onApply: (u) => _apply(ref, u),
                l10n: l10n,
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              _Body(state: state, l10n: l10n),
            ],
          ),
        ),
      ],
    );
  }
}

/// Range chips + category / branch / actor dropdowns + sensitive-only switch.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.query,
    required this.onApply,
    required this.l10n,
  });

  final AuditQuery query;
  final void Function(AuditQuery Function(AuditQuery)) onApply;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranges = <AuditRange, String>{
      AuditRange.today: l10n.ordersRangeToday,
      AuditRange.yesterday: l10n.ordersRangeYesterday,
      AuditRange.last7: l10n.ordersRangeLast7,
      AuditRange.last30: l10n.ordersRangeLast30,
    };
    final branches =
        ref.watch(auditBranchOptionsProvider).asData?.value ?? const [];
    final actors =
        ref.watch(auditActorOptionsProvider).asData?.value ?? const [];
    // Guard the dropdown value against a stale selection no longer in options.
    final branchValue =
        branches.any((b) => b.branchId == query.branch?.branchId)
        ? query.branch?.branchId
        : null;
    final actorValue =
        actors.any((a) => a.employeeProfileId == query.actor?.employeeProfileId)
        ? query.actor?.employeeProfileId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.xs,
          children: [
            for (final entry in ranges.entries)
              ChoiceChip(
                key: Key('activity-range-${entry.key.wire}'),
                label: Text(entry.value),
                selected: query.range == entry.key,
                onSelected: (_) => onApply((q) => q.copyWith(range: entry.key)),
              ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Wrap(
          spacing: RestoflowSpacing.md,
          runSpacing: RestoflowSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<AuditCategory>(
                key: const Key('activity-category-filter'),
                initialValue: query.category,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.activityLogFilterCategory,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final c in AuditCategory.values)
                    DropdownMenuItem<AuditCategory>(
                      value: c,
                      child: Text(_categoryFilterLabel(l10n, c)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onApply((q) => q.copyWith(category: v));
                },
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                key: const Key('activity-branch-filter'),
                initialValue: branchValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.activityLogFilterBranch,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.activityLogBranchAll),
                  ),
                  for (final b in branches)
                    DropdownMenuItem<String?>(
                      value: b.branchId,
                      child: Text(b.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) {
                    onApply((q) => q.copyWith(clearBranch: true));
                    return;
                  }
                  final opt = branches.firstWhere((b) => b.branchId == id);
                  onApply((q) => q.copyWith(branch: opt));
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: const Key('activity-actor-filter'),
                initialValue: actorValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.activityLogFilterActor,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.activityLogActorAll),
                  ),
                  for (final a in actors)
                    DropdownMenuItem<String?>(
                      value: a.employeeProfileId,
                      child: Text(a.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) {
                    onApply((q) => q.copyWith(clearActor: true));
                    return;
                  }
                  final opt = actors.firstWhere(
                    (a) => a.employeeProfileId == id,
                  );
                  onApply((q) => q.copyWith(actor: opt));
                },
              ),
            ),
            FilterChip(
              key: const Key('activity-sensitive-only'),
              label: Text(l10n.activityLogSensitiveOnly),
              avatar: const Icon(
                Icons.shield_outlined,
                size: RestoflowIconSizes.sm,
              ),
              selected: query.sensitiveOnly,
              onSelected: (v) => onApply((q) => q.copyWith(sensitiveOnly: v)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The list body: loading skeletons / error / empty / events + load-more.
class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.l10n});

  final AuditLogState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return Column(
        key: const Key('activity-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          RestoflowSkeleton(height: 76),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 76),
          SizedBox(height: RestoflowSpacing.sm),
          RestoflowSkeleton(height: 76),
        ],
      );
    }
    if (state.error != null) {
      return RestoflowStateView(
        key: const Key('activity-error'),
        icon: Icons.error_outline,
        title: l10n.activityLogError,
        message: l10n.activityLogErrorHint,
        tone: RestoflowTone.danger,
        actions: [
          FilledButton.tonal(
            onPressed: () =>
                ref.read(auditLogControllerProvider.notifier).refresh(),
            child: Text(l10n.activityLogRefresh),
          ),
        ],
      );
    }
    if (state.isEmpty) {
      return RestoflowStateView(
        key: const Key('activity-empty'),
        icon: Icons.history_outlined,
        title: l10n.activityLogEmpty,
        message: l10n.activityLogEmptyHint,
      );
    }
    final presenter = AuditEventPresenter(l10n, state.currencyCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in state.events)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: ActivityEventCard(
              view: presenter.present(event),
              l10n: l10n,
            ),
          ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
            child: Center(
              child: state.loadingMore
                  ? const RestoflowSkeleton(width: 160, height: 40)
                  : OutlinedButton.icon(
                      key: const Key('activity-load-more'),
                      onPressed: () => ref
                          .read(auditLogControllerProvider.notifier)
                          .loadMore(),
                      icon: const Icon(Icons.expand_more),
                      label: Text(l10n.activityLogLoadMore),
                    ),
            ),
          ),
      ],
    );
  }
}

/// One event row card: icon + title, actor · time, scope, category / denied pill.
class ActivityEventCard extends StatelessWidget {
  const ActivityEventCard({required this.view, required this.l10n, super.key});

  final AuditEventView view;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = view.tone.styleOf(theme);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      child: InkWell(
        key: Key('activity-card-${view.eventId}'),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        onTap: () => showActivityDetailDialog(context, view, l10n),
        child: Container(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: kRestoflowHairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: style.container,
                  borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  view.icon,
                  size: RestoflowIconSizes.sm,
                  color: style.onContainer,
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            view.title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (view.occurredAtLabel.isNotEmpty)
                          Text(
                            view.occurredAtLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: kRestoflowInk3,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    Text(
                      [
                        view.actorLabel,
                        if (view.scopeLabel != null) view.scopeLabel!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kRestoflowInk2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RestoflowSpacing.sm),
                    Wrap(
                      spacing: RestoflowSpacing.xs,
                      runSpacing: RestoflowSpacing.xs,
                      children: [
                        RestoflowStatusPill(
                          label: view.categoryLabel,
                          tone: view.tone,
                          dense: true,
                        ),
                        if (view.isDenied)
                          RestoflowStatusPill(
                            label: l10n.activityLogDenied,
                            tone: RestoflowTone.warning,
                            icon: Icons.block_outlined,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Icon(Icons.chevron_right, color: kRestoflowInk3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The category label for a FILTER option (adds "All categories").
String _categoryFilterLabel(AppLocalizations l10n, AuditCategory c) =>
    switch (c) {
      AuditCategory.all => l10n.activityLogCategoryAll,
      AuditCategory.orders => l10n.activityLogCategoryOrders,
      AuditCategory.voids => l10n.activityLogCategoryVoids,
      AuditCategory.discounts => l10n.activityLogCategoryDiscounts,
      AuditCategory.payments => l10n.activityLogCategoryPayments,
      AuditCategory.shifts => l10n.activityLogCategoryShifts,
      AuditCategory.staff => l10n.activityLogCategoryStaff,
      AuditCategory.access => l10n.activityLogCategoryAccess,
      AuditCategory.devices => l10n.activityLogCategoryDevices,
      AuditCategory.settings => l10n.activityLogCategorySettings,
      AuditCategory.menu => l10n.activityLogCategoryMenu,
      AuditCategory.tables => l10n.activityLogCategoryTables,
      AuditCategory.organization => l10n.activityLogCategoryOrganization,
    };
