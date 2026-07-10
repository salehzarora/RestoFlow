import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_submission.dart' show OutboxSyncState;
import '../data/recent_order.dart';
import '../format/money_format.dart';
import '../print/native_print_bridges.dart' show posActivePrintBridgeProvider;
import '../state/outbox_controller.dart';
import '../state/receipt_print_controller.dart';
import '../state/recent_orders_controller.dart';
import 'cancel_order_sheet.dart';
import 'cash_payment_sheet.dart';
import 'receipt_print_preview.dart';

/// POS-ORDERS-AND-PAYMENT-001: an app-bar button that opens the recent/unpaid
/// orders surface, badged with the current unpaid count so the cashier can see
/// at a glance that orders are waiting for payment.
class RecentOrdersButton extends ConsumerWidget {
  const RecentOrdersButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final orders = ref.watch(posRecentOrdersControllerProvider);
    final unpaid = orders.where((o) => !o.isPaid).length;
    final icon = IconButton(
      key: const Key('recent-orders-button'),
      tooltip: l10n.posRecentOrdersTitle,
      icon: const Icon(Icons.receipt_long_outlined),
      onPressed: () => RecentOrdersSheet.show(context),
    );
    if (unpaid == 0) return icon;
    return Badge.count(count: unpaid, child: icon);
  }
}

/// The recent/unpaid orders bottom sheet: a lightweight, cashier-first surface
/// for the last 2 days' orders — filter by all/unpaid/paid, complete payment on
/// an unpaid order, and reprint a paid order's receipt. All money is the stored
/// snapshot (never recomputed). RTL-safe + tri-lingual.
class RecentOrdersSheet extends ConsumerStatefulWidget {
  const RecentOrdersSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const RecentOrdersSheet(),
  );

  @override
  ConsumerState<RecentOrdersSheet> createState() => _RecentOrdersSheetState();
}

enum _RecentFilter { all, unpaid, paid }

class _RecentOrdersSheetState extends ConsumerState<RecentOrdersSheet> {
  _RecentFilter _filter = _RecentFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final orders = ref.watch(posRecentOrdersControllerProvider);
    final entries = ref.watch(outboxControllerProvider);
    final syncByNumber = <String, OutboxSyncState>{
      for (final e in entries) e.summary.orderNumber: e.syncState,
    };
    final filtered = <PosRecentOrder>[
      for (final o in orders)
        if (switch (_filter) {
          _RecentFilter.all => true,
          // MONEY-VOID-001: a cancelled (voided) order is no longer active work,
          // so it drops out of the "unpaid" filter (still visible under "all").
          _RecentFilter.unpaid => !o.isPaid && !o.isVoided,
          _RecentFilter.paid => o.isPaid,
        })
          o,
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('recent-orders-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.posRecentOrdersTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        l10n.posRecentOrdersWindow,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Wrap(
              spacing: RestoflowSpacing.sm,
              children: [
                for (final entry in <(_RecentFilter, String)>[
                  (_RecentFilter.all, l10n.posRecentFilterAll),
                  (_RecentFilter.unpaid, l10n.posRecentFilterUnpaid),
                  (_RecentFilter.paid, l10n.posRecentFilterPaid),
                ])
                  ChoiceChip(
                    key: Key('recent-filter-${entry.$1.name}'),
                    label: Text(entry.$2),
                    selected: _filter == entry.$1,
                    onSelected: (_) => setState(() => _filter = entry.$1),
                  ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: RestoflowSpacing.xl,
                      ),
                      child: RestoflowStateView(
                        key: const Key('recent-orders-empty'),
                        icon: Icons.receipt_long_outlined,
                        title: l10n.posRecentEmpty,
                        message: l10n.posRecentEmptyHint,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: RestoflowSpacing.sm),
                      itemBuilder: (context, i) => _RecentOrderCard(
                        order: filtered[i],
                        syncState: syncByNumber[filtered[i].orderNumber],
                        l10n: l10n,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentOrderCard extends ConsumerWidget {
  const _RecentOrderCard({
    required this.order,
    required this.syncState,
    required this.l10n,
  });

  final PosRecentOrder order;
  final OutboxSyncState? syncState;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final o = order.order;
    final paid = order.isPaid;
    final dineIn = o.orderType == OrderType.dineIn;
    final subtitle = <String>[
      dineIn ? l10n.posOrderTypeDineIn : l10n.posOrderTypeTakeaway,
      if (dineIn && o.tableLabel != null)
        '${l10n.posTableLabel} ${o.tableLabel}',
      if (o.customerName case final c?) c,
      l10n.ordersItemsCount(o.itemCount),
    ].join(' · ');

    return Container(
      key: Key('recent-order-${order.orderNumber}'),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            o.orderNumber,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Text(
                          _time(order.submittedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Text(
                MoneyFormatter.formatMinor(o.grandTotalMinor, o.currencyCode),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.xs,
            runSpacing: RestoflowSpacing.xs,
            children: [
              // MONEY-VOID-001: a cancelled order shows a single danger
              // "Cancelled" pill instead of the paid/unpaid + sync pills (the
              // void is terminal; the submit sync state is no longer relevant).
              if (order.isVoided)
                RestoflowStatusPill(
                  key: Key('recent-cancelled-${order.orderNumber}'),
                  label: l10n.posOrderCancelledChip,
                  tone: RestoflowTone.danger,
                  icon: Icons.block,
                )
              else ...[
                RestoflowStatusPill(
                  label: paid ? l10n.posPaidChip : l10n.posUnpaidChip,
                  tone: paid ? RestoflowTone.success : RestoflowTone.warning,
                  icon: paid ? Icons.check_circle_outline : Icons.schedule,
                ),
                if (syncState != null && syncState!.isFailed)
                  RestoflowStatusPill(
                    label: l10n.posRecentSyncFailed,
                    tone: RestoflowTone.danger,
                    icon: Icons.sync_problem,
                  )
                else if (syncState != null && syncState!.isPending)
                  RestoflowStatusPill(
                    label: l10n.posRecentSyncPending,
                    tone: RestoflowTone.info,
                    icon: Icons.sync,
                  ),
              ],
            ],
          ),
          // MONEY-VOID-001: a cancelled (voided) order is terminal + money-free
          // — no Take payment, no receipt reprint. The action row is omitted.
          if (!order.isVoided) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            Row(
              children: [
                if (!paid) ...[
                  Expanded(
                    child: FilledButton.icon(
                      key: Key('recent-pay-${order.orderNumber}'),
                      onPressed: () => CashPaymentSheet.show(
                        context,
                        orderId: o.orderId,
                        orderNumber: o.orderNumber,
                        amountMinor: o.grandTotalMinor,
                        currencyCode: o.currencyCode,
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(l10n.posTakePayment),
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  // A deliberate, distinct destructive action to CANCEL a wrong
                  // unpaid order (danger outline; opens a reason+confirm sheet,
                  // never a one-tap cancel). The server enforces the
                  // manager/owner role gate.
                  OutlinedButton.icon(
                    key: Key('recent-cancel-${order.orderNumber}'),
                    onPressed: () =>
                        CancelOrderSheet.show(context, order: order),
                    icon: const Icon(Icons.block, size: 18),
                    label: Text(l10n.posCancelOrderAction),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RestoflowTone.danger
                          .styleOf(theme)
                          .accent,
                      side: BorderSide(
                        color: RestoflowTone.danger.styleOf(theme).accent,
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('recent-reprint-${order.orderNumber}'),
                      onPressed: () => _reprint(context, ref),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(l10n.posRecentReprintAction),
                    ),
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: TextButton.icon(
                      key: Key('recent-view-${order.orderNumber}'),
                      onPressed: () => ReceiptPrintPreview.show(
                        context,
                        order: o,
                        payment: order.payment!,
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(l10n.receiptPreviewTitle),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Reprints the STORED receipt for a paid order: rebuilds the customer receipt
  /// document from the stored order+payment snapshot and re-sends it through the
  /// active POS printer (native Wi-Fi/Bluetooth + raster ar/he path preserved).
  /// It creates NO order and NO payment. Honest fallback when no printer.
  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final payment = order.payment;
    if (payment == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final bridge = ref.read(posActivePrintBridgeProvider);
    if (bridge == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.printStatusNotConfigured)),
      );
      return;
    }
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    final document = buildReceiptDocument(
      l10n,
      order.order,
      payment,
      isDemo: isDemo,
    );
    await ref
        .read(receiptPrintControllerProvider.notifier)
        .reprint(
          orderNumber: order.orderNumber,
          document: document,
          submitToBridge: bridge.submit,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posRecentReprintStarted)),
    );
  }

  String _time(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}
