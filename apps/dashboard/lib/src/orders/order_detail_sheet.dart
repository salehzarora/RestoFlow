/// The order detail sheet + reprint center (ORDERS-HISTORY-001).
///
/// Opened from a history row. Loads the full order lazily through a scope-captured
/// loader (so it works whether the row came from the demo or the real repository,
/// without needing the Riverpod scope inside the dialog). Shows the header, items
/// (with modifiers / notes), the payment breakdown, a MONEY-FREE kitchen summary,
/// and the reprint center actions (receipt preview / kitchen-ticket preview /
/// copy code). No action mutates the order, payment, shift or a kitchen job.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_history_models.dart';
import '../format/money_format.dart';
import '../print/order_preview_builders.dart';
import '../state/order_history_providers.dart';
import 'order_complete_action.dart';
import 'order_history_screen.dart'
    show statusLabelFor, statusTone, orderTypeLabel;
import 'order_preview_dialog.dart';
import 'settlement_badge.dart';

/// Opens the detail sheet for [row]. The loader is captured from the current
/// (scoped) repository provider.
///
/// The dialog is mounted on the root overlay, ABOVE the Orders surface's scoped
/// [ProviderScope], so it is re-parented onto the SAME container via
/// [UncontrolledProviderScope]. Without that, the completion action inside would
/// read the root scope and miss the membership/transport overrides (and would
/// fail closed in real mode).
Future<void> showOrderDetailSheet(
  BuildContext context,
  WidgetRef ref,
  OrderHistoryRow row,
) {
  final container = ProviderScope.containerOf(context);
  Future<OrderDetail> loader() =>
      ref.read(orderHistoryRepositoryProvider).loadDetail(row.orderId);
  return showDialog<void>(
    context: context,
    builder: (context) => UncontrolledProviderScope(
      container: container,
      child: Dialog(
        key: const Key('order-detail-sheet'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: _OrderDetailPanel(row: row, loader: loader),
        ),
      ),
    ),
  );
}

class _OrderDetailPanel extends StatefulWidget {
  const _OrderDetailPanel({required this.row, required this.loader});

  final OrderHistoryRow row;
  final Future<OrderDetail> Function() loader;

  @override
  State<_OrderDetailPanel> createState() => _OrderDetailPanelState();
}

class _OrderDetailPanelState extends State<_OrderDetailPanel> {
  late Future<OrderDetail> _future = widget.loader();

  void _retry() => setState(() => _future = widget.loader());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.row.orderCode,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('order-detail-close'),
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: FutureBuilder<OrderDetail>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  key: Key('order-detail-loading'),
                  padding: EdgeInsets.all(RestoflowSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RestoflowSkeleton(height: 40),
                      SizedBox(height: RestoflowSpacing.sm),
                      RestoflowSkeleton(height: 120),
                      SizedBox(height: RestoflowSpacing.sm),
                      RestoflowSkeleton(height: 80),
                    ],
                  ),
                );
              }
              if (snap.hasError || !snap.hasData) {
                return RestoflowStateView(
                  key: const Key('order-detail-error'),
                  icon: Icons.error_outline,
                  title: l10n.ordersError,
                  message: l10n.ordersErrorHint,
                  tone: RestoflowTone.danger,
                  actions: [
                    FilledButton.tonal(
                      onPressed: _retry,
                      child: Text(l10n.ordersRefresh),
                    ),
                  ],
                );
              }
              return _DetailContent(detail: snap.data!, l10n: l10n);
            },
          ),
        ),
      ],
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail, required this.l10n});

  final OrderDetail detail;
  final AppLocalizations l10n;

  String _money(int minor) =>
      MoneyFormatter.formatMinor(minor, detail.currencyCode);

  @override
  Widget build(BuildContext context) {
    final counts = aggregateKitchenCounts(detail);
    return SingleChildScrollView(
      key: const Key('order-detail-content'),
      padding: const EdgeInsets.all(RestoflowSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ORDER-COMPLETION-001: the ONLY write on this surface. It renders
          // nothing unless the order is `served` AND the viewer may settle orders.
          OrderCompleteAction(detail: detail, l10n: l10n),
          _reprintBar(context),
          const SizedBox(height: RestoflowSpacing.lg),
          _infoCard(),
          const SizedBox(height: RestoflowSpacing.md),
          _itemsCard(),
          const SizedBox(height: RestoflowSpacing.md),
          _paymentCard(),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: RestoflowSpacing.md),
            _kitchenCard(counts),
          ],
        ],
      ),
    );
  }

  Widget _reprintBar(BuildContext context) {
    return Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.sm,
      children: [
        FilledButton.tonalIcon(
          key: const Key('order-receipt-preview-button'),
          onPressed: () => showOrderPreviewDialog(
            context,
            doc: buildOrderReceiptPreview(l10n, detail),
            hint: l10n.ordersReprintFromPosHint,
            previewKey: const Key('order-receipt-preview'),
          ),
          icon: const Icon(Icons.receipt_outlined),
          label: Text(l10n.receiptPreviewTitle),
        ),
        FilledButton.tonalIcon(
          key: const Key('order-kitchen-preview-button'),
          onPressed: () => showOrderPreviewDialog(
            context,
            doc: buildOrderKitchenTicketPreview(l10n, detail),
            hint: l10n.ordersReprintFromKdsHint,
            previewKey: const Key('order-kitchen-preview'),
          ),
          icon: const Icon(Icons.soup_kitchen_outlined),
          label: Text(l10n.kdsTicketPreviewTitle),
        ),
        OutlinedButton.icon(
          key: const Key('order-copy-code'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: detail.orderCode));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.ordersCopied)));
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: Text(l10n.ordersCopyCode),
        ),
      ],
    );
  }

  Widget _infoCard() {
    return RestoflowSectionCard(
      title: l10n.ordersDetailInfo,
      children: [
        _kv(statusLabelPill()),
        if (detail.createdAtLabel != null && detail.createdAtLabel!.isNotEmpty)
          _kv(_Row(l10n.ordersTimeLabel, detail.createdAtLabel!)),
        _kv(
          _Row(l10n.posOrderTypeLabel, orderTypeLabel(l10n, detail.orderType)),
        ),
        if (detail.tableLabel != null && detail.tableLabel!.isNotEmpty)
          _kv(_Row(l10n.posTableLabel, detail.tableLabel!)),
        _kv(
          _Row(
            l10n.ordersCustomerLabel,
            detail.customerName ?? l10n.ordersUnavailable,
          ),
        ),
        if (detail.staffName != null && detail.staffName!.isNotEmpty)
          _kv(_Row(l10n.ordersStaffLabel, detail.staffName!)),
        if (detail.branchName != null && detail.branchName!.isNotEmpty)
          _kv(_Row(l10n.ordersBranchLabel, detail.branchName!)),
        if (detail.receiptNumber != null && detail.receiptNumber!.isNotEmpty)
          _kv(_Row(l10n.posReceiptNumberLabel, detail.receiptNumber!)),
      ],
    );
  }

  Widget statusLabelPill() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.xs),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: RestoflowStatusPill(
          label: statusLabelFor(l10n, detail.status, detail.orderType),
          tone: statusTone(detail.status),
        ),
      ),
    );
  }

  Widget _itemsCard() {
    return RestoflowSectionCard(
      title: l10n.ordersDetailItems,
      children: [
        for (final item in detail.items) _ItemTile(item: item, money: _money),
      ],
    );
  }

  Widget _paymentCard() {
    final pay = detail.completedPayment;
    return RestoflowSectionCard(
      title: l10n.ordersDetailPayment,
      children: [
        _Row(l10n.ordersSubtotalLabel, _money(detail.subtotalMinor)),
        if (detail.discountTotalMinor > 0)
          _Row(
            l10n.ordersDiscountLabel,
            '-${_money(detail.discountTotalMinor)}',
          ),
        if (detail.taxTotalMinor > 0)
          _Row(l10n.ordersTaxLabel, _money(detail.taxTotalMinor)),
        _Row(
          l10n.posReceiptTotal,
          _money(detail.grandTotalMinor),
          emphasised: true,
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        // A payment row is shown when money actually moved. Otherwise state the
        // SETTLEMENT honestly: a zero-total order reads "No charge" (it owes nothing and
        // was never charged), NOT "Unpaid" — which would imply money is outstanding.
        if (pay != null)
          _Row(_paymentMethodLabel(l10n, pay.method), _money(pay.amountMinor))
        else
          _Row(
            l10n.ordersFilterPayment,
            settlementLabel(l10n, detail.settlement),
          ),
      ],
    );
  }

  Widget _kitchenCard(List<KitchenCountLine> counts) {
    return RestoflowSectionCard(
      key: const Key('order-detail-kitchen'),
      title: l10n.ordersDetailKitchen,
      children: [
        for (final c in counts)
          _Row(
            l10n.kdsMeatTotalLabel(formatCountQuantity(c.quantity), c.unit),
            '',
          ),
      ],
    );
  }

  Widget _kv(Widget child) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.xs),
    child: child,
  );
}

String _paymentMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'cash' => l10n.posPaymentMethodCash,
      'card' => l10n.posPaymentMethodCard,
      'bit' => l10n.posPaymentMethodBit,
      'external' => l10n.posPaymentMethodExternal,
      _ => method,
    };

/// A key/value row (left label muted, right value emphasised when a total).
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.emphasised = false});

  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: kRestoflowInk2,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// A line item with its modifiers, prep components and note.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.money});

  final OrderDetailItem item;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${item.quantity} × ${item.name}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (item.lineTotalMinor > 0)
                Text(
                  money(item.lineTotalMinor),
                  style: theme.textTheme.bodyLarge,
                ),
            ],
          ),
          for (final mod in item.modifiers)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, top: 1),
              child: Text(
                '+ ${mod.optionName}${mod.quantity > 1 ? ' ×${mod.quantity}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kRestoflowInk3,
                ),
              ),
            ),
          if (item.notes != null && item.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, top: 1),
              child: Text(
                '» ${item.notes}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: kRestoflowInk3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
