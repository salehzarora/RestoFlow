import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/ready_notifications_store.dart';
import '../state/order_sync_controller.dart';
import '../state/ready_notifications_controller.dart';
import '../state/recent_orders_controller.dart';
import 'order_status_pills.dart' show orderStatusLabel;
import 'recent_orders_sheet.dart';

/// PSC-001A — the READY-NOTIFICATION HISTORY sheet (the bell's surface).
///
/// A compact, honest local history: what became ready, when, and what state
/// that work is in NOW. Acknowledgement lives on the BELL: the tap that
/// opens this sheet already marked the then-retained records read (persisted
/// first), so no separate "Mark all read" action exists here. The sheet
/// itself never marks anything merely for being visible — a notification
/// arriving while it is open stays unread until the next bell tap (or its
/// own row-open). Opening triggers ONE cursorless status-reconciliation
/// sweep (the keyset discovery feed never re-delivers consumed rows, so
/// current statuses come from this sweep + the live recent-orders
/// snapshots).
class ReadyNotificationsSheet extends ConsumerStatefulWidget {
  const ReadyNotificationsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const ReadyNotificationsSheet(),
  );

  @override
  ConsumerState<ReadyNotificationsSheet> createState() =>
      _ReadyNotificationsSheetState();
}

class _ReadyNotificationsSheetState
    extends ConsumerState<ReadyNotificationsSheet> {
  /// The history reveals in pages of 8, newest first; every OPEN starts back
  /// at the newest page (this is State, so a reopened sheet resets).
  static const int _pageSize = 8;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The sheet-open STATUS sweep: refreshes current statuses of known
      // records; adds nothing, alerts nothing, moves no discovery cursor.
      unawaited(
        ref
            .read(posReadyNotificationsControllerProvider.notifier)
            .reconcileStatuses(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(posReadyNotificationsControllerProvider);
    // Newest first by readyAt; a record arriving while the sheet is open
    // sorts into position. Only the first [_visibleCount] render — "Show
    // more" reveals the next page of 8 until everything retained is visible.
    final ordered = [...state.records]
      ..sort((a, b) => b.readyAtTime.compareTo(a.readyAtTime));
    final visible = ordered.length <= _visibleCount
        ? ordered
        : ordered.sublist(0, _visibleCount);
    final recentOrders = ref.watch(posRecentOrdersControllerProvider);
    // Render-time parent-status join: the recent-orders snapshots are the
    // freshest parent truth this till already holds — zero extra RPCs.
    final parentStatusByOrderId = <String, String>{
      for (final o in recentOrders)
        if (o.orderId != null && o.serverStatus != null)
          o.orderId!: o.serverStatus!,
    };

    final String subtitle;
    if (state.degraded) {
      subtitle = l10n.posReadyPollingDegraded;
    } else if (state.lastUpdatedAt != null) {
      subtitle = l10n.posOrdersLastUpdated(_hhmm(state.lastUpdatedAt!));
    } else {
      subtitle = '';
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        0,
        RestoflowSpacing.lg,
        RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const Key('ready-notifications-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.posReadyHistoryTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        key: const Key('ready-sheet-subtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('ready-refresh-button'),
                tooltip: l10n.posOrdersRefresh,
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  final controller = ref.read(
                    posReadyNotificationsControllerProvider.notifier,
                  );
                  // Manual refresh: an immediate discovery poll (bypasses the
                  // error backoff by joining/starting the cycle now) AND the
                  // status sweep.
                  unawaited(controller.refreshNow());
                  unawaited(controller.reconcileStatuses());
                },
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Flexible(
            child: state.loading && state.records.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: RestoflowSpacing.xl,
                    ),
                    child: Center(
                      child: SizedBox(
                        key: Key('ready-sheet-loading'),
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : state.records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: RestoflowSpacing.xl,
                    ),
                    child: RestoflowStateView(
                      key: const Key('ready-sheet-empty'),
                      icon: Icons.notifications_none_outlined,
                      title: l10n.posReadyEmpty,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: RestoflowSpacing.xs),
                    itemBuilder: (context, i) {
                      final record = visible[i];
                      return _ReadyNotificationRow(
                        record: record,
                        l10n: l10n,
                        // Initial units show the LIVE parent status when the
                        // till holds a fresher snapshot; rounds show the
                        // round's own (sweep-refreshed) status.
                        currentStatus: record.isServiceRound
                            ? record.workUnitStatus
                            : (parentStatusByOrderId[record.orderId] ??
                                  record.parentOrderStatus),
                      );
                    },
                  ),
          ),
          if (ordered.length > _visibleCount)
            TextButton(
              key: const Key('ready-show-more'),
              onPressed: () => setState(() => _visibleCount += _pageSize),
              child: Text(l10n.posReadyShowMore),
            ),
        ],
      ),
    );
  }
}

class _ReadyNotificationRow extends ConsumerWidget {
  const _ReadyNotificationRow({
    required this.record,
    required this.l10n,
    required this.currentStatus,
  });

  final PosReadyNotificationRecord record;
  final AppLocalizations l10n;
  final String currentStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final typeLine = record.isServiceRound
        ? l10n.posReadyAdditionReady(record.roundNumber ?? 0)
        : l10n.posReadyOrderReady;
    final table = record.tableLabel;
    final title = table == null || table.trim().isEmpty
        ? record.orderCode
        : '${record.orderCode} · ${l10n.posTableLabel} $table';
    return InkWell(
      key: Key('ready-row-${record.identityKey}'),
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      onTap: () => openReadyNotification(context, ref, record),
      child: Container(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              record.isServiceRound
                  ? Icons.playlist_add
                  : Icons.restaurant_menu_outlined,
              size: RestoflowIconSizes.md,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: record.read
                          ? FontWeight.w600
                          : FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$typeLine · '
                    '${l10n.posReadyAtTime(_hhmm(record.readyAtTime.toLocal()))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: RestoflowSpacing.sm),
            RestoflowStatusPill(
              label: orderStatusLabel(l10n, currentStatus),
              tone: _toneFor(currentStatus),
            ),
            if (!record.read) ...[
              const SizedBox(width: RestoflowSpacing.sm),
              Semantics(
                label: l10n.posReadyUnreadLabel,
                child: Container(
                  key: Key('ready-unread-${record.identityKey}'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static RestoflowTone _toneFor(String status) => switch (status) {
    'ready' => RestoflowTone.success,
    'voided' || 'cancelled' => RestoflowTone.danger,
    _ => RestoflowTone.info,
  };
}

/// The ONE open-order action every notification surface uses: mark THAT
/// notification read, freshen the parent order (targeted, cursor-free), and
/// open the orders centre FOCUSED on it — the existing authoritative
/// action-policy card, never a second order-detail implementation. Opening
/// mutates nothing server-side.
void openReadyNotification(
  BuildContext context,
  WidgetRef ref,
  PosReadyNotificationRecord record,
) {
  final navigator = Navigator.of(context);
  ref
      .read(posReadyNotificationsControllerProvider.notifier)
      .markRead(record.identityKey);
  unawaited(
    ref.read(posOrderSyncControllerProvider.notifier).refreshOrders([
      record.orderId,
    ]),
  );
  if (navigator.canPop()) navigator.pop();
  RecentOrdersSheet.show(navigator.context, focusOrderId: record.orderId);
}

String _hhmm(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}
