import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/payment.dart';
import '../format/money_format.dart';
import '../print/browser_print.dart';
import '../state/submitted_order_view.dart';

/// A browser-style RECEIPT print preview (RF-118): a narrow "paper" receipt over
/// the paid order ([SubmittedOrderView] + [CashPayment]), shown in a dialog with
/// Close + Print (browser) actions. This is a print PREVIEW — the Print button
/// triggers the browser's print on web (no-op elsewhere). Not a hardware printer.
class ReceiptPrintPreview extends ConsumerWidget {
  const ReceiptPrintPreview({
    required this.order,
    required this.payment,
    super.key,
  });

  final SubmittedOrderView order;
  final CashPayment payment;

  static Future<void> show(
    BuildContext context, {
    required SubmittedOrderView order,
    required CashPayment payment,
  }) => showDialog<void>(
    context: context,
    builder: (_) => ReceiptPrintPreview(order: order, payment: payment),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = payment.currencyCode;
    final dineIn = order.orderType == OrderType.dineIn;
    final typeLabel = dineIn
        ? l10n.posOrderTypeDineIn
        : l10n.posOrderTypeTakeaway;

    return Dialog(
      key: const Key('receipt-print-preview'),
      insetPadding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewHeader(title: l10n.receiptPreviewTitle),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(RestoflowSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Container(
                      padding: const EdgeInsets.all(RestoflowSpacing.lg),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Text(
                              l10n.receiptDemoRestaurantName,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: RestoflowSpacing.xs),
                          Center(child: _PaidChip(label: l10n.posPaidChip)),
                          const SizedBox(height: RestoflowSpacing.md),
                          _Line(
                            label: l10n.posReceiptNumberLabel,
                            value: payment.receiptNumber,
                          ),
                          _Line(
                            label: l10n.posOrderNumberLabel,
                            value: order.orderNumber,
                          ),
                          _Line(
                            label: l10n.posOrderTypeLabel,
                            value: typeLabel,
                          ),
                          if (dineIn && order.tableLabel != null)
                            _Line(
                              label: l10n.posTableLabel,
                              value: order.tableLabel!,
                            ),
                          _Line(
                            label: l10n.posPaidAtLabel,
                            value: _formatTimestamp(payment.paidAt),
                          ),
                          const _Rule(),
                          for (final line in order.lines)
                            _ItemLine(
                              label: '${line.quantity}× ${line.name}',
                              value: MoneyFormatter.formatMinor(
                                line.lineTotalMinor,
                                line.currencyCode,
                              ),
                            ),
                          const _Rule(),
                          _Line(
                            label: l10n.posReceiptTotal,
                            value: MoneyFormatter.formatMinor(
                              order.subtotalMinor,
                              currency,
                            ),
                            emphasised: true,
                            valueKey: const Key('preview-total'),
                          ),
                          _Line(
                            label: l10n.posCashReceived,
                            value: MoneyFormatter.formatMinor(
                              payment.tenderedMinor,
                              currency,
                            ),
                            valueKey: const Key('preview-cash'),
                          ),
                          _Line(
                            label: l10n.posChangeDue,
                            value: MoneyFormatter.formatMinor(
                              payment.changeMinor,
                              currency,
                            ),
                            valueKey: const Key('preview-change'),
                          ),
                          const _Rule(),
                          _Line(
                            label: l10n.posPaymentMethodLabel,
                            value: l10n.posPaymentMethodCash,
                          ),
                          const SizedBox(height: RestoflowSpacing.sm),
                          Center(
                            child: Text(
                              l10n.posReceiptProvisionalNote,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              l10n.posReceiptDemoNote,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            _PreviewActions(l10n: l10n),
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

/// Shared preview header (title + close icon).
class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        RestoflowSpacing.lg,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
        RestoflowSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.print_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('preview-close-icon'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
          ),
        ],
      ),
    );
  }
}

/// Shared preview footer: an honest browser-print hint + Close / Print actions.
class _PreviewActions extends ConsumerWidget {
  const _PreviewActions({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.printPreviewHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          TextButton(
            key: const Key('preview-close-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.printPreviewClose),
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          FilledButton.icon(
            key: const Key('preview-print-button'),
            onPressed: () => ref.read(printActionProvider)(),
            icon: const Icon(Icons.print, size: 18),
            label: Text(l10n.printPreviewPrint),
          ),
        ],
      ),
    );
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
            size: 14,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
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

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.label, required this.value});

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
              maxLines: 2,
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

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
      child: DottedRule(),
    );
  }
}

/// A simple dotted horizontal rule for the receipt "paper".
class DottedRule extends StatelessWidget {
  const DottedRule({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 3.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List<Widget>.generate(
            count < 1 ? 1 : count,
            (_) => SizedBox(
              width: dash,
              height: 1,
              child: ColoredBox(color: color),
            ),
          ),
        );
      },
    );
  }
}
