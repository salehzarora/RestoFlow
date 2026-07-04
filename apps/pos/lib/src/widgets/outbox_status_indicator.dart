import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../state/outbox_controller.dart';

/// RF-114: a compact app-bar indicator of the order OUTBOX's aggregate sync
/// state, so the cashier can keep taking orders while earlier ones sync.
///
///  * FAILED  → "N failed — retry" (tap retries all failed; honest error, no
///    fake "sent").
///  * SYNCING → "Syncing…" with a spinner (a push is in flight).
///  * PENDING → "N pending sync" (queued locally, durable across refresh/restart).
///  * else    → "All orders synced" — shown ONLY for orders the backend confirmed.
///
/// Renders NOTHING when no order has been submitted this session (no clutter).
/// RTL-safe (a plain [Row]; the framework mirrors it under an RTL Directionality).
class OutboxStatusIndicator extends ConsumerWidget {
  const OutboxStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(outboxControllerProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    final failed = entries.where((e) => e.syncState.isFailed).length;
    final syncing = entries
        .where((e) => e.syncState == OutboxSyncState.inFlight)
        .length;
    final pending = entries.where((e) => e.syncState.isPending).length;

    final theme = Theme.of(context);
    final IconData icon;
    final String label;
    final Color color;
    VoidCallback? onTap;
    if (failed > 0) {
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
      label = l10n.posOutboxFailed(failed);
      onTap = () =>
          ref.read(outboxControllerProvider.notifier).retryAllFailed();
    } else if (syncing > 0) {
      icon = Icons.sync;
      color = theme.colorScheme.primary;
      label = l10n.posOutboxSyncing;
    } else if (pending > 0) {
      icon = Icons.schedule_outlined;
      color = theme.colorScheme.tertiary;
      label = l10n.posOutboxPending(pending);
    } else {
      icon = Icons.cloud_done_outlined;
      color = theme.colorScheme.primary;
      label = l10n.posOutboxSynced;
    }

    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: RestoflowSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing > 0)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: onTap != null ? '$label. ${l10n.posOutboxRetryAll}' : label,
      child: onTap == null
          ? Center(key: const Key('outbox-status-indicator'), child: chip)
          : InkWell(
              key: const Key('outbox-retry-all'),
              onTap: onTap,
              child: Center(child: chip),
            ),
    );
  }
}
