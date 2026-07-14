import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_reconciler.dart' show isCountedUnpaid, unpaidOrderCount;
import '../data/order_submission.dart' show OutboxSyncState;
import '../data/recent_order.dart';
import '../format/money_format.dart';
import '../print/native_print_bridges.dart' show posActivePrintBridgeProvider;
import '../state/order_sync_controller.dart';
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
    // POS-OPERATIONS-SYNC-001: ONE canonical predicate, shared with the controller's
    // count and the filter below. This was a hand-rolled copy that re-derived
    // settlement from the STALE submit-time total — which is precisely how a comped
    // order sat in the badge forever. Watching the list keeps it reactive.
    final unpaid = unpaidOrderCount(orders);
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

  /// Held so [dispose] can release the consumer WITHOUT touching `ref` — Riverpod
  /// forbids reading a ref after the widget is disposed, and a "stop polling" that
  /// throws on the way out would leave the timer running forever.
  PosOrderSyncController? _sync;

  @override
  void initState() {
    super.initState();
    // POS-OPERATIONS-SYNC-001: opening this surface is a refresh trigger, and it
    // arms the periodic tick for as long as the surface is up. The coordinator owns
    // the timer — a Timer living in a widget is how you end up polling a POS that
    // has been sitting in a drawer since Tuesday.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = ref.read(posOrderSyncControllerProvider.notifier);
      _sync = sync;
      sync.addVisibleConsumer();
    });
  }

  @override
  void dispose() {
    // The tick STOPS with the sheet. Nothing keeps polling behind a closed screen.
    _sync?.removeVisibleConsumer();
    super.dispose();
  }

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
          // POS-OPERATIONS-SYNC-001: the filter and the badge now ask the SAME
          // question, so they can never disagree about what "unpaid" means.
          _RecentFilter.unpaid => isCountedUnpaid(o),
          _RecentFilter.paid => o.isFullySettled,
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
    // SETTLEMENT ("does it still owe money?") drives what we SAY. The payment MARKER
    // ("was money taken?") drives what we OFFER: a receipt can only be reprinted when a
    // payment exists, and the server's void guard blocks exactly on a live completed
    // payment. Conflating the two is what made the POS lie.
    final settled = order.isFullySettled;
    final hasPayment = order.payment != null;
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
                // MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not the payment marker.
                // A NON-CHARGEABLE (zero-total) order reads "No charge" — it is neither
                // Paid (no money was taken) nor Unpaid (nothing is owed). An
                // UNDER-COVERED order reads Unpaid, because money IS still owed.
                if (order.isNonChargeable)
                  RestoflowStatusPill(
                    key: Key('recent-nocharge-${order.orderNumber}'),
                    label: l10n.posNoChargeChip,
                    tone: RestoflowTone.neutral,
                    icon: Icons.money_off_outlined,
                  )
                else
                  RestoflowStatusPill(
                    label: settled ? l10n.posPaidChip : l10n.posUnpaidChip,
                    tone: settled
                        ? RestoflowTone.success
                        : RestoflowTone.warning,
                    icon: settled ? Icons.check_circle_outline : Icons.schedule,
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
          // MONEY-SETTLEMENT-CONSISTENCY-001: a TERMINAL order (cancelled/voided, or a
          // `completed` one — including a comped order the served+settled rule closed by
          // itself) accepts NO mutation. It must not offer Take payment or Cancel: the
          // server would refuse them, and a button that always fails is a lie. Reprint
          // stays available whenever a receipt actually exists.
          if (!order.isTerminal || hasPayment) ...[
            const SizedBox(height: RestoflowSpacing.sm),
            // A NON-CHARGEABLE (zero-total) order owes nothing, and the server REFUSES a
            // payment for it (no zero-value payment row, no burned receipt number). Say
            // so plainly instead of showing a control that cannot work.
            if (!order.isTerminal && order.isNonChargeable && !hasPayment)
              Padding(
                key: Key('recent-nocharge-note-${order.orderNumber}'),
                padding: const EdgeInsetsDirectional.only(
                  bottom: RestoflowSpacing.sm,
                ),
                child: Text(
                  l10n.posNoChargeNoPayment,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Row(
              children: [
                if (!hasPayment) ...[
                  // Offered only when there is genuinely money to collect.
                  if (!order.isNonChargeable) ...[
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
                  ],
                  // CANCEL mirrors the SERVER's void rule — a live completed payment
                  // blocks a void, and a terminal order cannot be voided at all. It is
                  // NOT gated on the payment marker as a stand-in for "settled": a
                  // zero-total order that is still ACTIVE remains cancellable, exactly as
                  // the server allows.
                  Expanded(
                    child: OutlinedButton.icon(
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
                  ),
                ] else ...[
                  // A receipt exists -> it can be reprinted and viewed. Gated on the
                  // PAYMENT ROW (not settlement): a comped order has no receipt to show.
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
