import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'package:restoflow_core/restoflow_core.dart';

import '../data/order_submission.dart';
import '../data/payment.dart' show CashPayment;
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../print/print_bridge.dart';
import '../state/outbox_controller.dart';
import '../state/payment_controller.dart';
import '../state/pos_auto_print_prefs.dart';
import '../state/pos_printer_assignments.dart';
import '../state/receipt_print_controller.dart';
import '../state/submitted_order_view.dart';
import 'cash_payment_sheet.dart';
import 'discount_sheet.dart';
import 'receipt_preview.dart';
import 'receipt_print_preview.dart';

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
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;

    // RF-115: live outbox/sync status for this order (null on the RF-101 path).
    final entries = ref.watch(outboxControllerProvider);
    final entry = _entryForId(entries, order.outboxEntryId);
    final outbox = ref.read(outboxControllerProvider.notifier);

    // RF-116: the recorded cash payment for this order, or null if unpaid.
    final payment = ref
        .watch(paymentControllerProvider)
        .paymentFor(order.orderNumber);

    // Part E: the receipt auto-print trigger. Fires ONLY on THIS order's
    // payment SUCCESS transition (a failed submit/payment never reaches a
    // non-null payment, and the controller is idempotent per order besides).
    // Cashier turned the toggle off => nothing at all; toggle would be on
    // but no printer => an honest notConfigured marker; otherwise the job is
    // PREPARED (this build has no bridge transport, so never "printed").
    ref.listen(paymentControllerProvider, (previous, next) {
      final paid = next.paymentFor(order.orderNumber);
      if (paid == null) return;
      if (previous?.paymentFor(order.orderNumber) != null) return;
      final assignments = switch (ref
          .read(posPrinterAssignmentsProvider)
          .valueOrNull) {
        Success(:final value) => value,
        _ => null,
      };
      // Demo / unconfigured / failed reads: no assignments, no auto-print.
      if (assignments == null) return;
      final stored = ref.read(posAutoPrintReceiptProvider).valueOrNull;
      if (stored == false) return; // explicitly off — show nothing
      final printer = assignments.hasEnabledPrinter;
      // RF-115: prepare, then — if a LOCAL bridge is configured — encode +
      // submit it. With no bridge the job stays honestly "prepared" (the prior
      // behavior). A confirmed bridge write flips it to "sent to printer";
      // never a fabricated hardware print.
      final bridge = ref.read(posPrintBridgeProvider);
      ref
          .read(receiptPrintControllerProvider.notifier)
          .prepareAndDispatch(
            orderNumber: order.orderNumber,
            hasEnabledPrinter: printer,
            buildDocument: () =>
                buildReceiptDocument(l10n, order, paid, isDemo: isDemo),
            submitToBridge: bridge == null ? null : bridge.submit,
          );
    });

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
                  // RF-117: subtotal always; discount/tax lines when present; the
                  // grand total (what the customer pays) is the loud figure once
                  // there's a discount or tax, else the subtotal keeps emphasis.
                  _OrderTotals(order: order, l10n: l10n),
                  const SizedBox(height: RestoflowSpacing.md),
                  // RF-141B: shared design-system notice (subtle info tone).
                  // Demo only — a REAL order was actually sent (or shows its
                  // honest failure above), so the demo disclaimer would lie.
                  if (isDemo)
                    RestoflowNoticeBanner(
                      body: l10n.posDemoOrderNotice,
                      tone: RestoflowTone.info,
                    ),
                ] else ...[
                  ReceiptPreview(order: order, payment: payment),
                  // RF-115: the HONEST receipt print-job status (prepared /
                  // sent to printer / bridge unavailable / not configured /
                  // failed — never a fake "printed") with a Retry action.
                  _ReceiptPrintStatusLine(
                    order: order,
                    payment: payment,
                    isDemo: isDemo,
                    l10n: l10n,
                  ),
                ],
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
                            // RF-116/RF-117: opens the payment sheet (cash or a
                            // non-cash tender). The e2e depends on this KEY.
                            key: const Key('pay-cash-button'),
                            onPressed: () => CashPaymentSheet.show(
                              context,
                              orderId: order.orderId,
                              orderNumber: order.orderNumber,
                              // RF-117: pay the GRAND total (subtotal − discount
                              // + tax), not the bare subtotal.
                              amountMinor: order.grandTotalMinor,
                              currencyCode: order.currencyCode,
                            ),
                            icon: const Icon(Icons.payments_outlined),
                            label: Text(l10n.posTakePayment),
                            style: RestoflowButtonStyles.big(context),
                          ),
                        ),
                        const SizedBox(height: RestoflowSpacing.sm),
                        // RF-117 part C: apply an order-level discount before
                        // payment (server-authoritative + authorized in real
                        // mode; local in demo). Hidden once a discount is
                        // applied so it is not stacked twice.
                        if (order.discountTotalMinor == 0)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const Key('apply-discount-button'),
                              onPressed: () => DiscountSheet.show(
                                context,
                                orderId: order.orderId ?? '',
                                subtotalMinor: order.subtotalMinor,
                                taxTotalMinor: order.taxTotalMinor,
                                currencyCode: order.currencyCode,
                              ),
                              icon: const Icon(Icons.percent),
                              label: Text(l10n.posApplyDiscount),
                            ),
                          ),
                        if (order.discountTotalMinor == 0)
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

/// The receipt print-job status under the receipt card (RF-115): renders
/// nothing while no job exists (auto-print off / not yet triggered), and the
/// HONEST status otherwise — prepared / sent to printer / bridge unavailable /
/// not configured / failed. "Printed" (hardware-confirmed) is unreachable by
/// design. A Retry action re-runs a failed / bridge-unavailable / not-configured
/// job through the same pipeline.
class _ReceiptPrintStatusLine extends ConsumerWidget {
  const _ReceiptPrintStatusLine({
    required this.order,
    required this.payment,
    required this.isDemo,
    required this.l10n,
  });

  final SubmittedOrderView order;
  final CashPayment payment;
  final bool isDemo;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(
      receiptPrintControllerProvider.select((jobs) => jobs[order.orderNumber]),
    );
    if (job == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (label, tone, icon) = switch (job.status) {
      PrintJobStatus.prepared => (
        l10n.printStatusPrepared,
        RestoflowTone.info,
        Icons.print_outlined,
      ),
      PrintJobStatus.sentToPrinter => (
        l10n.printStatusSentToPrinter,
        RestoflowTone.success,
        Icons.print,
      ),
      PrintJobStatus.bridgeUnavailable => (
        l10n.printStatusBridgeUnavailable,
        RestoflowTone.warning,
        Icons.print_disabled,
      ),
      PrintJobStatus.printed => (
        l10n.printStatusPrinted,
        RestoflowTone.success,
        Icons.print,
      ),
      PrintJobStatus.failed => (
        l10n.printStatusFailed,
        RestoflowTone.danger,
        Icons.print_disabled,
      ),
      PrintJobStatus.notConfigured => (
        l10n.printStatusNotConfigured,
        RestoflowTone.neutral,
        Icons.print_disabled,
      ),
    };
    final style = tone.styleOf(theme);
    final canRetry =
        job.status == PrintJobStatus.failed ||
        job.status == PrintJobStatus.bridgeUnavailable ||
        job.status == PrintJobStatus.notConfigured;
    return Padding(
      key: const Key('receipt-print-status'),
      padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RestoflowIconSizes.sm, color: style.accent),
          const SizedBox(width: RestoflowSpacing.xs),
          Expanded(
            child: Text(
              '${l10n.posReceiptPrintLabel}: $label',
              style: theme.textTheme.bodySmall?.copyWith(color: style.accent),
            ),
          ),
          if (canRetry) ...[
            const SizedBox(width: RestoflowSpacing.xs),
            TextButton.icon(
              key: const Key('receipt-print-retry'),
              onPressed: () => _retry(ref),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.printRetryAction),
            ),
          ],
        ],
      ),
    );
  }

  void _retry(WidgetRef ref) {
    final assignments = switch (ref
        .read(posPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    final bridge = ref.read(posPrintBridgeProvider);
    ref
        .read(receiptPrintControllerProvider.notifier)
        .retry(
          orderNumber: order.orderNumber,
          hasEnabledPrinter: assignments?.hasEnabledPrinter ?? false,
          buildDocument: () =>
              buildReceiptDocument(l10n, order, payment, isDemo: isDemo),
          submitToBridge: bridge == null ? null : bridge.submit,
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
                  const RestoflowInlineSpinner(size: 16),
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

/// The pre-payment order totals (RF-117): subtotal always; a discount line
/// (signed) and a tax line ("Tax (17%)") when present; and the GRAND total when
/// either is present. With neither, the subtotal keeps the loud emphasis (the
/// `confirmation-subtotal` figure) so the existing plain-order confirmation is
/// unchanged. Integer minor units throughout.
class _OrderTotals extends StatelessWidget {
  const _OrderTotals({required this.order, required this.l10n});

  final SubmittedOrderView order;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final currency = order.currencyCode;
    final hasBreakdown =
        order.discountTotalMinor > 0 || order.taxTotalMinor > 0;
    return Column(
      children: [
        _TotalsRow(
          label: l10n.posCartSubtotal,
          value: MoneyFormatter.formatMinor(order.subtotalMinor, currency),
          valueKey: const Key('confirmation-subtotal'),
          // Loud only when it IS the payable figure (no tax/discount).
          emphasised: !hasBreakdown,
        ),
        if (order.discountTotalMinor > 0) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          _TotalsRow(
            label: l10n.posDiscountLabel,
            value: MoneyFormatter.formatSignedDeltaMinor(
              -order.discountTotalMinor,
              currency,
            ),
            valueKey: const Key('confirmation-discount'),
          ),
        ],
        if (order.taxTotalMinor > 0) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          _TotalsRow(
            label: taxLineLabel(l10n, order.taxRateBp),
            value: MoneyFormatter.formatMinor(order.taxTotalMinor, currency),
            valueKey: const Key('confirmation-tax'),
          ),
        ],
        if (hasBreakdown) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          _TotalsRow(
            label: l10n.posGrandTotal,
            value: MoneyFormatter.formatMinor(order.grandTotalMinor, currency),
            valueKey: const Key('confirmation-grand-total'),
            emphasised: true,
          ),
        ],
      ],
    );
  }
}

/// A label/value row for [_OrderTotals]; [emphasised] makes the value the loud
/// primary figure (subtotal when plain, grand total when there's a breakdown).
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.valueKey,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = emphasised
        ? theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          )
        : theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        const SizedBox(width: RestoflowSpacing.sm),
        Text(value, key: valueKey, style: valueStyle),
      ],
    );
  }
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine({required this.line});

  final SubmittedLineView line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          // Selected modifiers (snapshots, pre-formatted 'name ×N' for
          // quantities) — the deltas are in the total.
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
          // The cashier's per-item note, mirroring the cart line.
          if (line.note != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: RestoflowSpacing.md,
              ),
              child: Text(
                '${l10n.posItemNoteLabel}: ${line.note}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
