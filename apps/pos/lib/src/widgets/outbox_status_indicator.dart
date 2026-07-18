import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../pos_palette.dart' show kPosCompactAppBarWidth;
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

    // CONSERVATIVE aggregation (RF-114 Codex fix): "All orders synced" shows ONLY
    // when EVERY entry is `applied` (backend-confirmed). Non-final / ambiguous
    // states never fall through to synced.
    //  * failed    = rejected/dead      -> retryable; tap = retry all.
    //  * attention = conflict/resolved  -> needs review; NOT auto-retried, NOT synced.
    //  * syncing   = in_flight.
    //  * pending   = created/pending.
    // Priority (safest first): failed / attention  >  syncing  >  pending  >  synced.
    var failed = 0;
    var attention = 0;
    var syncing = 0;
    var pending = 0;
    for (final e in entries) {
      switch (e.syncState) {
        case OutboxSyncState.rejected:
        case OutboxSyncState.dead:
          failed++;
        case OutboxSyncState.conflict:
        case OutboxSyncState.resolved:
          attention++;
        case OutboxSyncState.inFlight:
          syncing++;
        case OutboxSyncState.created:
        case OutboxSyncState.pending:
          pending++;
        case OutboxSyncState.applied:
          break;
      }
    }

    final theme = Theme.of(context);
    // DESIGN-001: one semantic vocabulary for sync state everywhere — the
    // same tones the cart's pending chip and the confirmation's sync card use
    // (this indicator previously spoke raw scheme colors: error/primary/
    // tertiary). failed=danger, attention/pending=warning, syncing=info,
    // synced=success. Labels and keys are unchanged (pinned test contracts).
    final IconData icon;
    final String label;
    final Color color;
    VoidCallback? onTap;
    if (failed > 0) {
      icon = Icons.error_outline;
      color = RestoflowTone.danger.styleOf(theme).accent;
      label = l10n.posOutboxFailed(failed);
      onTap = () =>
          ref.read(outboxControllerProvider.notifier).retryAllFailed();
    } else if (attention > 0) {
      // conflict/resolved: retry-all re-queues only FAILED entries, so this is an
      // honest "attention needed" warning, not a retry affordance and NOT synced.
      icon = Icons.warning_amber_outlined;
      color = RestoflowTone.warning.styleOf(theme).accent;
      label = l10n.posOutboxAttention;
    } else if (syncing > 0) {
      icon = Icons.sync;
      color = RestoflowTone.info.styleOf(theme).accent;
      label = l10n.posOutboxSyncing;
    } else if (pending > 0) {
      icon = Icons.schedule_outlined;
      color = RestoflowTone.warning.styleOf(theme).accent;
      label = l10n.posOutboxPending(pending);
    } else {
      icon = Icons.cloud_done_outlined;
      color = RestoflowTone.success.styleOf(theme).accent;
      label = l10n.posOutboxSynced;
    }

    // PSC-001A compact app bar: below the compact width the TEXT label yields
    // (the five actions must all fit); the icon, spinner, colors, tap-to-retry
    // and the FULL label via tooltip + semantics all remain — the state is
    // never hidden, only its prose.
    final compact = MediaQuery.sizeOf(context).width < kPosCompactAppBarWidth;
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
          if (!compact) ...[
            const SizedBox(width: RestoflowSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
    final sized = compact
        ? Tooltip(
            key: const Key('outbox-status-compact'),
            message: label,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: chip,
            ),
          )
        : chip;

    return Semantics(
      button: onTap != null,
      label: onTap != null ? '$label. ${l10n.posOutboxRetryAll}' : label,
      child: onTap == null
          ? Center(key: const Key('outbox-status-indicator'), child: sized)
          : InkWell(
              key: const Key('outbox-retry-all'),
              onTap: onTap,
              child: Center(child: sized),
            ),
    );
  }
}
