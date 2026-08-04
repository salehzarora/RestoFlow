import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/local_storage_health_provider.dart';
import '../state/outbox_controller.dart';
import 'outbox_status_summary.dart';

/// POS-SYNC-VISIBILITY-001 — the READ-ONLY-FIRST synchronization details sheet.
///
/// Opening this sheet mutates NOTHING. That is the whole point: the header chip
/// used to *be* the action — a single tap ran retry-all or clear-resolved
/// depending on which state happened to be showing. An operator who taps a
/// status light to read it should never discover afterwards that they re-queued
/// the till's failed orders. Reading and acting are now separate, and every
/// action here is behind an explicit confirmation.
///
/// It reports only what the outbox model actually knows. There is deliberately
/// no "delivery unconfirmed" total: that outcome exists per-order at submit
/// time and is never aggregated, so inventing a count here would be a number
/// nobody could reconcile.
class PosSyncDetailsSheet extends ConsumerWidget {
  const PosSyncDetailsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const PosSyncDetailsSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = ref.watch(outboxControllerProvider);
    final storage = ref.watch(posLocalStorageHealthProvider);
    final s = PosOutboxStatusSummary.from(entries: entries, storage: storage);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          key: const Key('sync-details-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.posSyncDetailsTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            // The same headline the header chip shows, so the two can never
            // disagree in front of an operator mid-migration.
            Row(
              children: [
                Icon(s.icon, size: 20, color: s.toneOf(theme)),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    s.label(l10n),
                    key: const Key('sync-details-headline'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: s.toneOf(theme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              s.explanation(l10n),
              key: const Key('sync-details-explanation'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            const Divider(height: 1, color: kRestoflowHairline),
            const SizedBox(height: RestoflowSpacing.sm),

            // Counts the model genuinely holds. Zero rows are shown too: on a
            // migration gate "0" that was read is worth more than a row that
            // was never rendered.
            _CountRow(
              keyName: 'sync-count-pending',
              label: l10n.posSyncDetailsRowPending,
              value: s.pending,
            ),
            _CountRow(
              keyName: 'sync-count-syncing',
              label: l10n.posSyncDetailsRowSyncing,
              value: s.syncing,
            ),
            _CountRow(
              keyName: 'sync-count-failed',
              label: l10n.posSyncDetailsRowFailed,
              value: s.failed,
            ),
            _CountRow(
              keyName: 'sync-count-resolved',
              label: l10n.posSyncDetailsRowResolved,
              value: s.resolved,
            ),
            _CountRow(
              keyName: 'sync-count-attention',
              label: l10n.posSyncDetailsRowAttention,
              value: s.attention,
            ),

            if (!storage.isHealthy) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                l10n.posStorageNeedsAttention,
                key: const Key('sync-storage-warning'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: RestoflowTone.danger.styleOf(theme).accent,
                ),
              ),
            ],

            const SizedBox(height: RestoflowSpacing.md),
            // Actions appear ONLY when they apply, and each one asks first.
            //
            // Nothing is offered while the durable store is unhealthy: a retry
            // cannot fix a device that refused the write, and offering one
            // would imply it might. Unlike the old chip - which could surface
            // only ONE affordance at a time - both actions may appear here when
            // both genuinely apply; a details surface has room to be complete.
            if (storage.isHealthy && s.failed > 0)
              _ConfirmedAction(
                buttonKey: const Key('outbox-retry-all'),
                label: l10n.posOutboxRetryAll,
                confirmTitle: l10n.posSyncRetryConfirmTitle,
                confirmBody: l10n.posSyncRetryConfirmBody,
                confirmAction: l10n.posOutboxRetryAll,
                run: () => ref
                    .read(outboxControllerProvider.notifier)
                    .retryAllFailed(),
                doneMessage: (_) => l10n.posSyncRetryStarted,
              ),
            if (storage.isHealthy && s.resolved > 0)
              _ConfirmedAction(
                buttonKey: const Key('outbox-clear-resolved'),
                label: l10n.posOutboxClearResolved,
                confirmTitle: l10n.posSyncClearConfirmTitle,
                confirmBody: l10n.posSyncClearConfirmBody,
                confirmAction: l10n.posOutboxClearResolved,
                run: () async {
                  final removed = await ref
                      .read(outboxControllerProvider.notifier)
                      .dismissResolvedFailures();
                  return removed;
                },
                doneMessage: (r) =>
                    l10n.posOutboxClearResolvedDone((r as int?) ?? 0),
              ),

            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('sync-details-close'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.posSyncDetailsClose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.keyName,
    required this.label,
    required this.value,
  });

  final String keyName;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Semantics(
        // One spoken string, so a screen reader never reads a bare number.
        label: '$label: $value',
        excludeSemantics: true,
        child: Row(
          key: Key(keyName),
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A destructive-ish action that always asks first and cannot be double-fired.
class _ConfirmedAction extends StatefulWidget {
  const _ConfirmedAction({
    required this.buttonKey,
    required this.label,
    required this.confirmTitle,
    required this.confirmBody,
    required this.confirmAction,
    required this.run,
    required this.doneMessage,
  });

  final Key buttonKey;
  final String label;
  final String confirmTitle;
  final String confirmBody;
  final String confirmAction;
  final Future<Object?> Function() run;
  final String Function(Object?) doneMessage;

  @override
  State<_ConfirmedAction> createState() => _ConfirmedActionState();
}

class _ConfirmedActionState extends State<_ConfirmedAction> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          key: widget.buttonKey,
          // Null while running: the guard is the disabled button itself, so a
          // second tap cannot queue a duplicate sweep.
          onPressed: _running ? null : _confirmThenRun,
          child: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.label),
        ),
      ),
    );
  }

  Future<void> _confirmThenRun() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('sync-action-confirm'),
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmBody),
        actions: [
          TextButton(
            key: const Key('sync-action-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.posShiftCancelAction),
          ),
          FilledButton(
            key: const Key('sync-action-confirm-run'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.confirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _running = true);
    Object? result;
    try {
      result = await widget.run();
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() => _running = false);
    messenger?.showSnackBar(
      SnackBar(content: Text(widget.doneMessage(result))),
    );
  }
}
