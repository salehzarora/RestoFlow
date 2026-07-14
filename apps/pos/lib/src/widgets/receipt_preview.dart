import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/payment.dart';
import '../format/money_format.dart';
import '../format/payment_method_label.dart';
import '../state/receipt_print_controller.dart';
import '../state/submitted_order_view.dart';
import 'receipt_print_preview.dart';

/// A receipt-style preview card (RF-116) for a paid order: receipt number,
/// Paid status, order meta, itemised lines, totals, cash received + change,
/// payment method + time. MODE-HONEST notes: demo shows its provisional/demo
/// disclaimers; a REAL paid order shows the true SERVER receipt number, so
/// only the "printing not connected" note remains. Pure presentation over the
/// [SubmittedOrderView] + [CashPayment]; nothing here prints.
class ReceiptPreview extends ConsumerWidget {
  const ReceiptPreview({required this.order, required this.payment, super.key});

  final SubmittedOrderView order;
  final CashPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    // TABLET-UX-001 (E): the receipt footer note must reflect the ACTUAL print
    // result, not a static "printer not connected" line that contradicts a
    // successful print. Watch this order's receipt print job.
    final printStatus = ref.watch(
      receiptPrintControllerProvider.select(
        (jobs) => jobs[order.identity.key]?.status,
      ),
    );
    final theme = Theme.of(context);
    final currency = payment.currencyCode;
    final dineIn = order.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;
    final paidAt = _formatTimestamp(payment.paidAt);

    return Card(
      key: const Key('receipt-preview-card'),
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(RestoflowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  // No letterSpacing: tracking breaks Arabic glyph joining
                  // under the ar default locale (D-014).
                  Text(
                    l10n.posReceiptTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  RestoflowStatusPill(
                    label: l10n.posPaidChip,
                    tone: RestoflowTone.success,
                    icon: Icons.check_circle,
                  ),
                ],
              ),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            _ReceiptLine(
              label: l10n.posReceiptNumberLabel,
              value: payment.receiptNumber,
            ),
            _ReceiptLine(
              label: l10n.posOrderNumberLabel,
              value: order.orderNumber,
            ),
            _ReceiptLine(label: l10n.posOrderTypeLabel, value: typeLabel),
            if (dineIn && order.tableLabel != null)
              _ReceiptLine(label: l10n.posTableLabel, value: order.tableLabel!),
            const _DashedRule(),
            for (final line in order.lines) ...[
              _ReceiptItemLine(
                label: '${line.quantity}× ${line.name}',
                value: MoneyFormatter.formatMinor(
                  line.lineTotalMinor,
                  line.currencyCode,
                ),
              ),
              // Modifier snapshots arrive pre-formatted ('name ×N').
              for (final modifier in line.modifiers)
                _ReceiptItemLine(label: '  + $modifier', value: ''),
              if (line.note != null)
                _ReceiptItemLine(
                  label: '  ${l10n.posItemNoteLabel}: ${line.note}',
                  value: '',
                ),
            ],
            const _DashedRule(),
            // RF-117: when there's a discount or tax, break out subtotal /
            // discount / tax above the grand total; otherwise the single Total
            // line keeps the plain receipt unchanged (grand == subtotal).
            if (order.discountTotalMinor > 0 || order.taxTotalMinor > 0) ...[
              _ReceiptLine(
                label: l10n.posCartSubtotal,
                value: MoneyFormatter.formatMinor(
                  order.subtotalMinor,
                  currency,
                ),
              ),
              if (order.discountTotalMinor > 0)
                _ReceiptLine(
                  label: l10n.posDiscountLabel,
                  value: MoneyFormatter.formatSignedDeltaMinor(
                    -order.discountTotalMinor,
                    currency,
                  ),
                  valueKey: const Key('receipt-discount'),
                ),
              if (order.taxTotalMinor > 0)
                _ReceiptLine(
                  label: taxLineLabel(l10n, order.taxRateBp),
                  value: MoneyFormatter.formatMinor(
                    order.taxTotalMinor,
                    currency,
                  ),
                  valueKey: const Key('receipt-tax'),
                ),
            ],
            // POS-ORDERS-AND-PAYMENT-001: a single customer-friendly "Order
            // total" (no subtotal/total duplication when they match), then
            // "Paid"/"Change" for cash — consistent with the printed receipt.
            _ReceiptLine(
              label: l10n.posReceiptOrderTotal,
              value: MoneyFormatter.formatMinor(
                order.grandTotalMinor,
                currency,
              ),
              emphasised: true,
              valueKey: const Key('receipt-total'),
            ),
            // CASH shows the tender + change; a non-cash tender records neither.
            if (payment.method.isCash) ...[
              const SizedBox(height: RestoflowSpacing.xs),
              _ReceiptLine(
                label: l10n.posReceiptPaid,
                value: MoneyFormatter.formatMinor(
                  payment.tenderedMinor,
                  currency,
                ),
                valueKey: const Key('receipt-cash'),
              ),
              _ReceiptLine(
                label: l10n.posReceiptChange,
                value: MoneyFormatter.formatMinor(
                  payment.changeMinor,
                  currency,
                ),
                valueKey: const Key('receipt-change'),
              ),
            ],
            const _DashedRule(),
            _ReceiptLine(
              label: l10n.posPaymentMethodLabel,
              value: paymentMethodLabel(l10n, payment.method),
            ),
            _ReceiptLine(label: l10n.posPaidAtLabel, value: paidAt),
            const SizedBox(height: RestoflowSpacing.sm),
            if (isDemo) ...[
              _Note(message: l10n.posReceiptProvisionalNote),
              _Note(message: l10n.posReceiptDemoNote),
            ] else if (printStatus == PrintJobStatus.sentToPrinter ||
                printStatus == PrintJobStatus.printed)
              // TABLET-UX-001 (E): the print actually succeeded — say so, and
              // never leave the stale "printer not connected" note behind.
              _Note(message: l10n.posReceiptPrintedNote)
            else if (printStatus == PrintJobStatus.notConfigured)
              // Honest ONLY when there is genuinely no printer configured; a
              // failed/pending job is surfaced (with Retry) by the print-status
              // line under the receipt, so this note stays quiet then.
              _Note(message: l10n.posReceiptNoPrinterNote),
            const SizedBox(height: RestoflowSpacing.sm),
            OutlinedButton.icon(
              key: const Key('open-print-preview-button'),
              onPressed: () => ReceiptPrintPreview.show(
                context,
                order: order,
                payment: payment,
              ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(l10n.printPreviewAction),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.valueKey,
  });

  final String label;
  final String value;
  final bool emphasised;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasised
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: RestoflowSpacing.sm),
          Text(value, key: valueKey, style: style),
        ],
      ),
    );
  }
}

class _ReceiptItemLine extends StatelessWidget {
  const _ReceiptItemLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dash = 4.0;
          const gap = 3.0;
          final count = (constraints.maxWidth / (dash + gap)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(
              count < 1 ? 1 : count,
              (_) => SizedBox(
                width: dash,
                height: 1,
                child: ColoredBox(color: theme.colorScheme.outlineVariant),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Expanded(
            child: Text(
              message,
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
