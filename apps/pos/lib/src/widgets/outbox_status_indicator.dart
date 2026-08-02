import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../pos_palette.dart' show kPosCompactAppBarWidth;
import '../state/local_storage_health_provider.dart';
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
///  * STORAGE → "This device could not save an order" / "N local records cannot
///    be read" (MONEY-DURABLE-STORES-003B). Ranked ABOVE everything else and
///    shown even with an empty queue: a till whose storage refused a write, or
///    which is holding records it cannot decode, must never present the same
///    confident face as a healthy one — least of all "All orders synced".
///
/// Renders NOTHING when no order has been submitted this session AND local
/// storage is healthy (no clutter).
/// RTL-safe (a plain [Row]; the framework mirrors it under an RTL Directionality).
class OutboxStatusIndicator extends ConsumerWidget {
  const OutboxStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(outboxControllerProvider);
    final storage = ref.watch(posLocalStorageHealthProvider);
    if (entries.isEmpty && storage.isHealthy) return const SizedBox.shrink();

    // CONSERVATIVE aggregation (RF-114 Codex fix): "All orders synced" shows ONLY
    // when EVERY entry is `applied` (backend-confirmed). Non-final / ambiguous
    // states never fall through to synced.
    //  * failed    = RETRYABLE rejected/dead -> tap = retry all.
    //  * resolved  = terminal + provably never created -> tap = clear them.
    //  * attention = conflict/resolved, and any OTHER permanent rejection ->
    //                needs review; NOT auto-retried, NOT synced, NOT "retry".
    //  * syncing   = in_flight.
    //  * pending   = created/pending.
    // Priority (safest first): failed / attention  >  syncing  >  pending  >  synced.
    // SINGLE-DEVICE-ADDITION-CLOSE-AND-STALE-FAILURES-007: `failed` used to lump
    // RETRYABLE failures together with PERMANENT business rejections and offer
    // "N failed — retry" for both. `retryAllFailed` deliberately skips the
    // permanent ones (replaying that identity returns the same stored refusal for
    // ever), so the number could never move — the cashier saw the same entries
    // after every restart and only ending the shift appeared to clear them.
    // They are counted separately now, and the terminal ones get an action that
    // can actually finish them.
    var failed = 0;
    var resolved = 0;
    var attention = 0;
    var syncing = 0;
    var pending = 0;
    for (final e in entries) {
      if (e.isDismissibleResolvedFailure) {
        resolved++;
        continue;
      }
      // 007 self-review — DEFENCE, not a live defect, and stated as such.
      // A permanent business rejection that is NOT dismissible cannot occur in
      // this queue today: only `order.submit` is ever enqueued here (a payment
      // or a table operation is dispatched straight to `sync_push` and never
      // becomes an [OutboxEntry]), and a permanently-rejected `order.submit` is
      // dismissible by definition. Should that ever change, the invariant this
      // branch protects still holds: `retryAllFailed` deliberately SKIPS a
      // permanent rejection, so offering "retry" for one would show a number
      // that can never fall — and because `failed` outranks `resolved`, it
      // would also wedge the clear affordance shut. Such an entry needs a
      // person, which is what `attention` says.
      if (e.hasDefinitiveVerdict) {
        attention++;
        continue;
      }
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
    // MONEY-DURABLE-STORES-003B: local storage first. A refused durable write
    // means an order could not be saved (and was therefore NOT sent);
    // undecodable records are being preserved but will never sync. Either way
    // the queue counts below describe only what the app can still see, so
    // reporting them as the whole truth would be the lie this phase removes.
    if (!storage.isHealthy) {
      icon = Icons.sd_card_alert_outlined;
      color = RestoflowTone.danger.styleOf(theme).accent;
      label = storage.writeRefused
          ? l10n.posStorageWriteRefused
          : l10n.posStorageUnreadable(storage.unreadableRecords);
    } else if (failed > 0) {
      icon = Icons.error_outline;
      color = RestoflowTone.danger.styleOf(theme).accent;
      label = l10n.posOutboxFailed(failed);
      onTap = () =>
          ref.read(outboxControllerProvider.notifier).retryAllFailed();
    } else if (resolved > 0) {
      // TERMINAL and provably never applied: the server refused the submit
      // before it created anything. Retrying is meaningless, so the action here
      // CLEARS them instead — no shift change, and nothing uncertain is touched.
      icon = Icons.playlist_remove_outlined;
      color = RestoflowTone.warning.styleOf(theme).accent;
      label = l10n.posOutboxResolvedFailures(resolved);
      onTap = () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        // The clear is DURABLE-OR-NOTHING (see `dismissResolvedFailures`), so a
        // device whose storage refuses the write removes nothing and must be
        // told nothing went — never a confident "cleared" over entries that
        // will be back on the next start. The reason is already on screen: a
        // refused write marks the store degraded, and storage health outranks
        // every queue state in this same chip.
        var removed = 0;
        try {
          removed = await ref
              .read(outboxControllerProvider.notifier)
              .dismissResolvedFailures();
        } catch (_) {
          removed = 0;
        }
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.posOutboxClearResolvedDone(removed))),
        );
      };
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

    // The storage warning spells out what it means for the operator; the icon
    // alone would only say "something is wrong".
    final spoken = !storage.isHealthy
        ? '$label. ${l10n.posStorageNeedsAttention}'
        : onTap == null
        ? label
        // The two tap affordances do DIFFERENT things; a screen reader must not
        // be told "Retry all" when the action clears resolved failures.
        : failed > 0
        ? '$label. ${l10n.posOutboxRetryAll}'
        : '$label. ${l10n.posOutboxClearResolved}';

    return Semantics(
      button: onTap != null,
      label: spoken,
      child: onTap == null
          ? Center(key: const Key('outbox-status-indicator'), child: sized)
          : InkWell(
              key: failed > 0
                  ? const Key('outbox-retry-all')
                  : const Key('outbox-clear-resolved'),
              onTap: onTap,
              child: Center(child: sized),
            ),
    );
  }
}
