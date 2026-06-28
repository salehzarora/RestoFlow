import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/payment.dart';
import '../format/money_format.dart';
import '../state/submitted_order_view.dart';
import 'receipt_print_preview.dart';

/// A receipt-style preview card (RF-116) for a paid order: provisional receipt
/// number, Paid status, order meta, itemised lines, totals, cash received +
/// change, payment method + time, and an honest demo / no-printer note with a
/// disabled "Print receipt (demo)" action. Pure presentation over the
/// [SubmittedOrderView] + [CashPayment]; nothing here prints.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({required this.order, required this.payment, super.key});

  final SubmittedOrderView order;
  final CashPayment payment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  Text(
                    l10n.posReceiptTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: RestoflowSpacing.xs),
                  _PaidChip(label: l10n.posPaidChip),
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
            for (final line in order.lines)
              _ReceiptItemLine(
                label: '${line.quantity}× ${line.name}',
                value: MoneyFormatter.formatMinor(
                  line.lineTotalMinor,
                  line.currencyCode,
                ),
              ),
            const _DashedRule(),
            _ReceiptLine(
              label: l10n.posReceiptTotal,
              value: MoneyFormatter.formatMinor(order.subtotalMinor, currency),
              emphasised: true,
              valueKey: const Key('receipt-total'),
            ),
            const SizedBox(height: RestoflowSpacing.xs),
            _ReceiptLine(
              label: l10n.posCashReceived,
              value: MoneyFormatter.formatMinor(
                payment.tenderedMinor,
                currency,
              ),
              valueKey: const Key('receipt-cash'),
            ),
            _ReceiptLine(
              label: l10n.posChangeDue,
              value: MoneyFormatter.formatMinor(payment.changeMinor, currency),
              valueKey: const Key('receipt-change'),
            ),
            const _DashedRule(),
            _ReceiptLine(
              label: l10n.posPaymentMethodLabel,
              value: l10n.posPaymentMethodCash,
            ),
            _ReceiptLine(label: l10n.posPaidAtLabel, value: paidAt),
            const SizedBox(height: RestoflowSpacing.sm),
            _Note(message: l10n.posReceiptProvisionalNote),
            _Note(message: l10n.posReceiptDemoNote),
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

class _PaidChip extends StatelessWidget {
  const _PaidChip({required this.label});

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
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
