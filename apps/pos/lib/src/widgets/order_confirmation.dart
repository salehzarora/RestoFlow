import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../format/money_format.dart';
import '../state/outbox_controller.dart';
import '../state/payment_controller.dart';
import '../state/submitted_order_view.dart';
import 'cash_payment_sheet.dart';
import 'receipt_preview.dart';

/// In-place confirmation shown inside the cart panel after a submit (RF-101):
/// success header, the order number, a "Submitted" status chip, the submitted
/// item summary, the subtotal, the sync status, and a New order action.
///
/// MODE-HONEST (demo-readiness sprint): demo shows its demo notices and the
/// manual "Sync now (demo)" flow; REAL mode auto-pushed at submit, so this
/// surface reports the true backend state ("Sent — the kitchen display
/// receives it automatically" / an honest failure with Retry) and never a
/// demo label. Pure presentation over an immutable [SubmittedOrderView].
class OrderConfirmation extends ConsumerWidget {
  const OrderConfirmation({
    required this.order,
    required this.onNewOrder,
    super.key,
  });

  final SubmittedOrderView order;
  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtotalText = MoneyFormatter.format(order.subtotal);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;

    // RF-115: live outbox/sync status for this order (null on the RF-101 path).
    final entries = ref.watch(outboxControllerProvider);
    final entry = _entryForId(entries, order.outboxEntryId);
    final outbox = ref.read(outboxControllerProvider.notifier);

    // RF-116: the recorded cash payment for this order, or null if unpaid.
    final payment = ref
        .watch(paymentControllerProvider)
        .paymentFor(order.orderNumber);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(RestoflowSpacing.lg),
              children: [
                _SuccessHeader(title: l10n.posOrderSubmittedTitle),
                const SizedBox(height: RestoflowSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              l10n.posOrderNumberLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: RestoflowSpacing.sm),
                            // Design-polish: the number the cashier calls out
                            // gets the card's largest type; long provisional
                            // codes scale down instead of overflowing (the
                            // Text keeps its full data for the key finder).
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    order.orderNumber,
                                    key: const Key('order-number'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Wrap(
                            spacing: RestoflowSpacing.sm,
                            runSpacing: RestoflowSpacing.xs,
                            children: [
                              // RF-141B: shared status pills (info = submitted,
                              // success = paid).
                              RestoflowStatusPill(
                                label: l10n.posOrderStatusSubmitted,
                                tone: RestoflowTone.info,
                              ),
                              if (payment != null)
                                RestoflowStatusPill(
                                  label: l10n.posPaidChip,
                                  tone: RestoflowTone.success,
                                  icon: Icons.check_circle,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        _ServiceModeRow(order: order, l10n: l10n),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.md),
                _SyncStatusCard(
                  entry: entry,
                  l10n: l10n,
                  isDemo: isDemo,
                  onSync: entry != null && entry.syncState.isPending
                      ? () => outbox.pushEntry(entry.id)
                      : null,
                  onRetry: entry != null && entry.syncState.isFailed
                      ? () => outbox.retryEntry(entry.id)
                      : null,
                ),
                const SizedBox(height: RestoflowSpacing.md),
                if (payment == null) ...[
                  for (final line in order.lines) _ConfirmationLine(line: line),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.posCartSubtotal,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        subtotalText,
                        key: const Key('confirmation-subtotal'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RestoflowSpacing.md),
                  // RF-141B: shared design-system notice (subtle info tone).
                  // Demo only — a REAL order was actually sent (or shows its
                  // honest failure above), so the demo disclaimer would lie.
                  if (isDemo)
                    RestoflowNoticeBanner(
                      body: l10n.posDemoOrderNotice,
                      tone: RestoflowTone.info,
                    ),
                ] else
                  ReceiptPreview(order: order, payment: payment),
              ],
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            child: SafeArea(
              top: false,
              child: payment == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('pay-cash-button'),
                            onPressed: () => CashPaymentSheet.show(
                              context,
                              orderId: order.orderId,
                              orderNumber: order.orderNumber,
                              amountMinor: order.subtotalMinor,
                              currencyCode: order.currencyCode,
                            ),
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(l10n.posPayCash),
                            style: RestoflowButtonStyles.big(context),
                          ),
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: onNewOrder,
                            icon: const Icon(Icons.add),
                            label: Text(l10n.posNewOrder),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onNewOrder,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.posNewOrder),
                        style: RestoflowButtonStyles.big(context),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design-polish: a compact HORIZONTAL success header (true-green tone) —
/// the confirmation is a ~10-second interaction, so the old 72px hero circle
/// gave way to content the cashier actually needs on-screen.
class _SuccessHeader extends StatelessWidget {
  const _SuccessHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = RestoflowTone.success.styleOf(theme);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: success.container,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: RestoflowIconSizes.lg,
            color: success.accent,
          ),
        ),
        const SizedBox(width: RestoflowSpacing.md),
        Flexible(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The submitted order's service mode (RF-114): an order-type chip plus, for a
/// dine-in order, the assigned table chip.
class _ServiceModeRow extends StatelessWidget {
  const _ServiceModeRow({required this.order, required this.l10n});

  final SubmittedOrderView order;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dineIn = order.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final tableLabel = order.tableLabel;
    final tableChipLabel = tableLabel == null
        ? null
        : '${l10n.posTableLabel} $tableLabel';

    return Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.xs,
      children: [
        // RF-141B: shared design-system status pills (neutral tone).
        RestoflowStatusPill(
          icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
          label: typeLabel,
        ),
        if (tableChipLabel != null)
          RestoflowStatusPill(icon: Icons.event_seat, label: tableChipLabel),
      ],
    );
  }
}

/// The live outbox entry whose id is [id], or null.
OutboxEntry? _entryForId(List<OutboxEntry> entries, String? id) {
  if (id == null) return null;
  for (final e in entries) {
    if (e.id == id) return e;
  }
  return null;
}

/// Label + honest note + semantic [RestoflowTone] + icon for a sync state
/// (RF-141B: tones map to the shared design-system status pill). The note is
/// MODE-HONEST: demo says "demo sync", real describes the true backend state.
({String label, String note, RestoflowTone tone, IconData icon}) _syncVisual(
  OutboxSyncState state,
  AppLocalizations l10n, {
  required bool isDemo,
}) {
  switch (state) {
    case OutboxSyncState.inFlight:
      return (
        label: l10n.posSyncStateSending,
        note: isDemo ? l10n.posSyncDemoNotice : l10n.posSyncSendingReal,
        tone: RestoflowTone.info,
        icon: Icons.sync,
      );
    case OutboxSyncState.applied:
      return (
        label: l10n.posSyncStateSynced,
        note: isDemo ? l10n.posSyncDemoNotice : l10n.posSyncSentReal,
        tone: RestoflowTone.success,
        icon: Icons.cloud_done_outlined,
      );
    case OutboxSyncState.rejected:
    case OutboxSyncState.dead:
      return (
        label: l10n.posSyncStateFailed,
        note: isDemo ? l10n.posSyncDemoNotice : l10n.posSyncFailedReal,
        tone: RestoflowTone.danger,
        icon: Icons.error_outline,
      );
    case OutboxSyncState.created:
    case OutboxSyncState.pending:
    case OutboxSyncState.conflict:
    case OutboxSyncState.resolved:
      return (
        label: l10n.posSyncStatePending,
        note: l10n.posSyncStoredLocally,
        tone: RestoflowTone.warning,
        icon: Icons.schedule,
      );
  }
}

/// The order's client outbox / sync status (RF-115): a state chip, an honest
/// "demo / stored locally" note, the compact outbox reference, and a Sync now /
/// Retry action.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.entry,
    required this.l10n,
    required this.isDemo,
    required this.onSync,
    required this.onRetry,
  });

  final OutboxEntry? entry;
  final AppLocalizations l10n;
  final bool isDemo;
  final VoidCallback? onSync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = entry?.syncState ?? OutboxSyncState.pending;
    final visual = _syncVisual(state, l10n, isDemo: isDemo);
    final opRef = entry?.localOperationId;
    final sending = state == OutboxSyncState.inFlight;
    final refLine = opRef == null ? null : '${l10n.posOutboxRefLabel}: $opRef';

    return Card(
      key: const Key('sync-status-card'),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.posSyncSectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                RestoflowStatusPill(
                  label: visual.label,
                  tone: visual.tone,
                  icon: visual.icon,
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    visual.note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (refLine != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                refLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (sending) ...[
              const SizedBox(height: RestoflowSpacing.md),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Text(
                    l10n.posSyncStateSending,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ] else if (onSync != null) ...[
              const SizedBox(height: RestoflowSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('sync-now-button'),
                  onPressed: onSync,
                  icon: const Icon(Icons.sync, size: 18),
                  // Demo keeps the honest "(demo)" label; a REAL pending entry
                  // (auto-push interrupted) offers a plain "Send now".
                  label: Text(isDemo ? l10n.posSyncNow : l10n.posSyncSendNow),
                ),
              ),
            ] else if (onRetry != null) ...[
              const SizedBox(height: RestoflowSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('sync-retry-button'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.posSyncRetry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine({required this.line});

  final SubmittedLineView line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${line.quantity}× ${line.name}';
    final lineTotalText = MoneyFormatter.format(line.lineTotal);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                lineTotalText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // Selected modifiers (snapshots) — the deltas are in the total.
          for (final modifier in line.modifiers)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              child: Text(
                '+ $modifier',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
