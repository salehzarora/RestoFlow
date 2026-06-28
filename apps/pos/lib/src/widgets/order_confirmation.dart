import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart';
import '../format/money_format.dart';
import '../state/outbox_controller.dart';
import '../state/payment_controller.dart';
import '../state/submitted_order_view.dart';
import 'cash_payment_sheet.dart';
import 'receipt_preview.dart';

/// In-place confirmation shown inside the cart panel after a local demo submit
/// (RF-101): success header, demo order number, a "Submitted" status chip, the
/// submitted item summary, the subtotal, a demo notice, and a New order action.
///
/// Pure presentation over an immutable [SubmittedOrderView]; the reset action is
/// delegated to [onNewOrder]. Nothing here calls a backend, kitchen, or printer.
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
                const SizedBox(height: RestoflowSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.posOrderNumberLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              order.orderNumber,
                              key: const Key('order-number'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
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
                              _StatusChip(label: l10n.posOrderStatusSubmitted),
                              if (payment != null)
                                _PaidStatusChip(label: l10n.posPaidChip),
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
                  _DemoNotice(message: l10n.posDemoOrderNotice),
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
                              orderNumber: order.orderNumber,
                              amountMinor: order.subtotalMinor,
                              currencyCode: order.currencyCode,
                            ),
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(l10n.posPayCash),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
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
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessHeader extends StatelessWidget {
  const _SuccessHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 44,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
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
        _InfoChip(
          icon: dineIn ? Icons.restaurant : Icons.takeout_dining,
          label: typeLabel,
        ),
        if (tableChipLabel != null)
          _InfoChip(icon: Icons.event_seat, label: tableChipLabel),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

/// Label + honest note + colour + icon for a sync state.
({String label, String note, Color color, Color onColor, IconData icon})
_syncVisual(OutboxSyncState state, ThemeData theme, AppLocalizations l10n) {
  final scheme = theme.colorScheme;
  switch (state) {
    case OutboxSyncState.inFlight:
      return (
        label: l10n.posSyncStateSending,
        note: l10n.posSyncDemoNotice,
        color: scheme.secondaryContainer,
        onColor: scheme.onSecondaryContainer,
        icon: Icons.sync,
      );
    case OutboxSyncState.applied:
      return (
        label: l10n.posSyncStateSynced,
        note: l10n.posSyncDemoNotice,
        color: scheme.primaryContainer,
        onColor: scheme.onPrimaryContainer,
        icon: Icons.cloud_done_outlined,
      );
    case OutboxSyncState.rejected:
    case OutboxSyncState.dead:
      return (
        label: l10n.posSyncStateFailed,
        note: l10n.posSyncDemoNotice,
        color: scheme.errorContainer,
        onColor: scheme.onErrorContainer,
        icon: Icons.error_outline,
      );
    case OutboxSyncState.created:
    case OutboxSyncState.pending:
    case OutboxSyncState.conflict:
    case OutboxSyncState.resolved:
      return (
        label: l10n.posSyncStatePending,
        note: l10n.posSyncStoredLocally,
        color: scheme.tertiaryContainer,
        onColor: scheme.onTertiaryContainer,
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
    required this.onSync,
    required this.onRetry,
  });

  final OutboxEntry? entry;
  final AppLocalizations l10n;
  final VoidCallback? onSync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = entry?.syncState ?? OutboxSyncState.pending;
    final visual = _syncVisual(state, theme, l10n);
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
                _SyncChip(
                  label: visual.label,
                  color: visual.color,
                  onColor: visual.onColor,
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
                  label: Text(l10n.posSyncNow),
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

class _SyncChip extends StatelessWidget {
  const _SyncChip({
    required this.label,
    required this.color,
    required this.onColor,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color onColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onColor),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: onColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A green "Paid" status chip (RF-116) shown on the order card once a cash
/// payment is recorded.
class _PaidStatusChip extends StatelessWidget {
  const _PaidStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: theme.colorScheme.onPrimary,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.md,
        vertical: RestoflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
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
      child: Row(
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
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
