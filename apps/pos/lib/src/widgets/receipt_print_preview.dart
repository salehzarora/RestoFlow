import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/payment.dart';
import '../format/money_format.dart';
import '../print/print_document.dart';
import '../print/print_service.dart';
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
    // Mode-honest: the demo restaurant name / demo + provisional notes belong
    // to demo mode only — a REAL receipt shows the true server receipt number.
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
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
                          // No letterSpacing: tracking breaks Arabic glyph
                          // joining under the ar default locale (D-014).
                          Center(
                            child: Text(
                              isDemo
                                  ? l10n.receiptDemoRestaurantName
                                  : l10n.posReceiptTitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: RestoflowSpacing.xs),
                          Center(
                            child: RestoflowStatusPill(
                              label: l10n.posPaidChip,
                              tone: RestoflowTone.success,
                              icon: Icons.check_circle,
                            ),
                          ),
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
                            value: _formatReceiptTimestamp(payment.paidAt),
                          ),
                          const _Rule(),
                          for (final line in order.lines) ...[
                            _ItemLine(
                              label: '${line.quantity}× ${line.name}',
                              value: MoneyFormatter.formatMinor(
                                line.lineTotalMinor,
                                line.currencyCode,
                              ),
                            ),
                            // Snapshots arrive pre-formatted ('name ×N').
                            for (final modifier in line.modifiers)
                              _ItemLine(label: '  + $modifier', value: ''),
                            if (line.note != null)
                              _ItemLine(
                                label:
                                    '  ${l10n.posItemNoteLabel}: ${line.note}',
                                value: '',
                              ),
                          ],
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
                          if (isDemo) ...[
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
                          ] else
                            Center(
                              child: Text(
                                l10n.posReceiptNoPrinterNote,
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
            _PreviewActions(
              l10n: l10n,
              onPrint: () => ref
                  .read(printServiceProvider)
                  .printDocument(
                    buildReceiptDocument(l10n, order, payment, isDemo: isDemo),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds the ISOLATED print document for a paid receipt (RF-118). The printed
/// page contains ONLY these lines — never the POS menu/app behind the modal.
PrintDocument buildReceiptDocument(
  AppLocalizations l10n,
  SubmittedOrderView order,
  CashPayment payment, {
  bool isDemo = true,
}) {
  final currency = payment.currencyCode;
  final dineIn = order.orderType == OrderType.dineIn;
  // Built into a local (not an inline `title:` literal) so the RF-020
  // no-hardcoded-strings guard isn't tripped by this l10n-interpolated value.
  final docTitle = '${l10n.receiptPreviewTitle} ${order.orderNumber}';
  return PrintDocument(
    title: docTitle,
    lines: <PrintLine>[
      PrintLine.title(
        isDemo ? l10n.receiptDemoRestaurantName : l10n.posReceiptTitle,
      ),
      PrintLine.center(l10n.posPaidChip),
      PrintLine.rule(),
      PrintLine.kv(l10n.posReceiptNumberLabel, payment.receiptNumber),
      PrintLine.kv(l10n.posOrderNumberLabel, order.orderNumber),
      PrintLine.kv(
        l10n.posOrderTypeLabel,
        dineIn ? l10n.posOrderTypeDineIn : l10n.posOrderTypeTakeaway,
      ),
      if (dineIn && order.tableLabel != null)
        PrintLine.kv(l10n.posTableLabel, order.tableLabel!),
      PrintLine.kv(
        l10n.posPaidAtLabel,
        _formatReceiptTimestamp(payment.paidAt),
      ),
      PrintLine.rule(),
      for (final line in order.lines) ...[
        PrintLine.item(
          '${line.quantity}× ${line.name}',
          MoneyFormatter.formatMinor(line.lineTotalMinor, line.currencyCode),
        ),
        // Modifier snapshots arrive pre-formatted ('name ×N' for quantities).
        for (final modifier in line.modifiers)
          PrintLine.item('  + $modifier', ''),
        if (line.note != null)
          PrintLine.sub('${l10n.posItemNoteLabel}: ${line.note}'),
      ],
      PrintLine.rule(),
      PrintLine.kv(
        l10n.posReceiptTotal,
        MoneyFormatter.formatMinor(order.subtotalMinor, currency),
        emphasised: true,
      ),
      PrintLine.kv(
        l10n.posCashReceived,
        MoneyFormatter.formatMinor(payment.tenderedMinor, currency),
      ),
      PrintLine.kv(
        l10n.posChangeDue,
        MoneyFormatter.formatMinor(payment.changeMinor, currency),
      ),
      PrintLine.rule(),
      PrintLine.kv(l10n.posPaymentMethodLabel, l10n.posPaymentMethodCash),
      if (isDemo) ...[
        PrintLine.note(l10n.posReceiptProvisionalNote),
        PrintLine.note(l10n.posReceiptDemoNote),
      ] else
        PrintLine.note(l10n.posReceiptNoPrinterNote),
    ],
  );
}

String _formatReceiptTimestamp(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
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
class _PreviewActions extends StatelessWidget {
  const _PreviewActions({required this.l10n, required this.onPrint});

  final AppLocalizations l10n;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
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
            onPressed: onPrint,
            icon: const Icon(Icons.print, size: 18),
            label: Text(l10n.printPreviewPrint),
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
