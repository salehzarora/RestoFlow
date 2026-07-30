import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions.dart';
import '../data/payment.dart';
import '../data/order_detail_repository.dart';
import '../data/recent_order.dart';
import '../print/native_print_bridges.dart';
import '../state/addition_controller.dart';
import '../state/cart_controller.dart';
import '../state/pos_order_complete_controller.dart';
import '../state/pos_printer_assignments.dart';
import '../state/pos_receipt_logo.dart';
import '../state/receipt_print_controller.dart';
import '../state/submitted_order_view.dart';
import 'cancel_order_sheet.dart';
import 'cash_payment_sheet.dart';
import 'discount_sheet.dart';
import 'move_table_sheet.dart';
import 'receipt_print_preview.dart';

/// ORDER-DETAIL-PREVIEW-001 — the SHARED order action row.
///
/// Extracted MECHANICALLY from the private `_ActionRow` in
/// `recent_orders_sheet.dart`: same buttons, same order, same central
/// [PosOrderActions] eligibility, same handlers, same destructive styling, same
/// `Wrap` layout. The ONLY addition is [keyPrefix], so the Orders sheet and the
/// read-only detail preview can render the identical row while remaining
/// separately addressable in tests.
///
/// Eligibility is NOT duplicated here and payment/print/RPC commands are NOT
/// re-implemented: this widget draws what `resolveOrderActions` already decided
/// and calls the handlers that already existed.

/// The trailing actions — EVERY one of them decided by the central policy. A control
/// that the server would refuse is not drawn at all: a button that always fails is a
/// lie, and under a lunch rush it is an expensive one.
class OrderActionRow extends ConsumerWidget {
  const OrderActionRow({
    super.key,
    required this.order,
    required this.l10n,
    required this.actions,
    this.keyPrefix = 'recent',
  });

  final PosRecentOrder order;
  final AppLocalizations l10n;
  final PosOrderActions actions;

  /// ORDER-DETAIL-PREVIEW-001: the Widget-key namespace. It defaults to
  /// `recent`, so every key this row emits in the Orders sheet is BYTE-IDENTICAL
  /// to the one it emitted before this widget was extracted. The read-only
  /// detail preview renders the SAME row with `preview`, so the two surfaces are
  /// addressable apart while sharing one eligibility object, one set of
  /// callbacks and one set of handlers.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap B): the printer-only Complete safety
    // net — shown ONLY when the central policy allowed it (served + fully settled +
    // verified printer_only + authorized + not terminal + none in flight). One tap
    // sends exactly one order.status(completed) op; a second is suppressed while it
    // runs. On success the order leaves the board + its table frees (derived
    // occupancy); no payment, no resubmit, no reprint. The server re-enforces.
    if (actions.canComplete) {
      final completing = ref
          .watch(posOrderCompleteControllerProvider)
          .contains(order.orderId);
      children.add(
        OrderActionButton(
          child: FilledButton.icon(
            key: Key('$keyPrefix-complete-${order.orderNumber}'),
            onPressed: completing
                ? null
                : () => ref
                      .read(posOrderCompleteControllerProvider.notifier)
                      .complete(order.orderId ?? ''),
            icon: completing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(l10n.posCompleteOrder),
          ),
        ),
      );
    }

    if (actions.canPay) {
      children.add(
        OrderActionButton(
          child: FilledButton.icon(
            key: Key('$keyPrefix-pay-${order.orderNumber}'),
            onPressed: () => CashPaymentSheet.show(
              context,
              identity: order.identity,
              orderId: order.orderId,
              orderNumber: order.orderNumber,
              // AUTHORITATIVE total + revision. The sheet no longer receives the
              // submit-time figure it used to be handed.
              amountMinor: order.grandTotalMinor,
              currencyCode: order.currencyCode,
              expectedRevision: order.revision,
            ),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(l10n.posTakePayment),
          ),
        ),
      );
    }

    // DEFERRED-PAYMENT-RECEIPTS-001: the customer-facing BILL for an order that
    // is still unpaid. Gated on the SAME authoritative `canPay` the payment
    // action uses, so it appears exactly while money is still owed and never on
    // a paid, cancelled or otherwise ineligible order — and it sits BESIDE
    // Collect payment rather than replacing it.
    if (actions.canPay) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-print-bill-${order.orderNumber}'),
            onPressed: () => _printBill(context, ref),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(l10n.posPrintBillAction),
          ),
        ),
      );
    }

    if (actions.canDiscount) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-discount-${order.orderNumber}'),
            onPressed: () => DiscountSheet.show(
              context,
              orderId: order.orderId ?? '',
              subtotalMinor: order.subtotalMinor,
              taxTotalMinor: order.taxTotalMinor,
              currencyCode: order.currencyCode,
              expectedRevision: order.revision,
            ),
            icon: const Icon(Icons.percent, size: 18),
            label: Text(l10n.posApplyDiscount),
          ),
        ),
      );
    }

    if (actions.canVoid) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-cancel-${order.orderNumber}'),
            onPressed: () => CancelOrderSheet.show(context, order: order),
            icon: const Icon(Icons.block, size: 18),
            label: Text(l10n.posCancelOrderAction),
            style: OutlinedButton.styleFrom(
              foregroundColor: RestoflowTone.danger.styleOf(theme).accent,
              side: BorderSide(
                color: RestoflowTone.danger.styleOf(theme).accent,
              ),
            ),
          ),
        ),
      );
    }

    if (actions.canMoveTable) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-move-table-${order.orderNumber}'),
            onPressed: () => MoveTableSheet.show(context, order: order),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(l10n.posMoveTableAction),
          ),
        ),
      );
    }

    // PSC-001C: extend an eligible dine-in order with a NEW service round. The
    // authoritative existing items load first (pos_order_detail) so the cart
    // enters addition mode showing server truth — never a local guess.
    if (actions.canAddItems) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-add-items-${order.orderNumber}'),
            onPressed: () => _startAddition(context, ref),
            icon: const Icon(Icons.playlist_add, size: 18),
            label: Text(l10n.posAddItemsAction),
          ),
        ),
      );
    }

    if (actions.canOpenReceipt) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-reprint-${order.orderNumber}'),
            onPressed: () => _reprint(context, ref),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.posRecentReprintAction),
          ),
        ),
      );
      children.add(
        OrderActionButton(
          child: TextButton.icon(
            key: Key('$keyPrefix-view-${order.orderNumber}'),
            onPressed: () => _viewReceipt(context, ref),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(l10n.receiptPreviewTitle),
          ),
        ),
      );
    }

    // A WRAP, not a Row: on a phone the actions stack instead of being squeezed
    // below a usable touch target, and on a tablet they sit on one line.
    return Wrap(
      spacing: RestoflowSpacing.sm,
      runSpacing: RestoflowSpacing.sm,
      children: children,
    );
  }

  /// PSC-001C: enters ADDITION MODE for this order and closes the sheet so
  /// the cashier lands on the menu with the "Adding to #CODE" cart banner.
  ///
  /// Finding 1 (correction): the COMPLETE entry transition is owned by
  /// [AdditionController.enterForOrder] — it reserves the target BEFORE the
  /// authoritative load and re-verifies the token + still-empty cart before
  /// committing, so a cart line added during the load can never silently
  /// become an addition. The [canBeginAddition] call below is an EARLY
  /// CONVENIENCE check only (instant feedback without a fetch); it is not
  /// the guarantee.
  Future<void> _startAddition(BuildContext context, WidgetRef ref) async {
    final orderId = order.orderId;
    if (orderId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!canBeginAddition(
      addition: ref.read(additionControllerProvider),
      cartIsEmpty: ref.read(cartControllerProvider).isEmpty,
      orderId: orderId,
    )) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posAdditionClearCartFirst)),
      );
      return;
    }
    final entry = await ref
        .read(additionControllerProvider.notifier)
        .enterForOrder(orderId);
    switch (entry) {
      case AdditionEntryResult.entered:
        if (navigator.canPop()) navigator.pop();
      case AdditionEntryResult.detailUnavailable:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.posAdditionFailedRetry)),
        );
      case AdditionEntryResult.superseded:
        break; // a newer entry owns the flow — nothing to report here
      case AdditionEntryResult.blockedPendingAttempt:
      case AdditionEntryResult.blockedDifferentTarget:
      case AdditionEntryResult.cartNotEmpty:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.posAdditionClearCartFirst)),
        );
    }
  }

  /// The COMBINED order view + payment for the receipt surfaces — the ONE
  /// [authoritativeReceiptSource] policy: a server-backed order's receipt
  /// comes from `pos_order_detail` (Finding 4 — a failed load/parse is an
  /// honest retry, NEVER a silent partial local receipt that could miss
  /// another till's additions); demo keeps its self-contained local record.
  Future<(SubmittedOrderView, CashPayment)?> _receiptSource(WidgetRef ref) =>
      authoritativeReceiptSource(
        isDemoMode: ref.read(runtimeConfigProvider).isDemoMode,
        orderId: order.orderId,
        localView: order.order,
        localPayment: order.payment,
        repository: ref.read(orderDetailRepositoryProvider),
      );

  Future<void> _viewReceipt(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await _receiptSource(ref);
    if (source == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posReceiptUnavailableRetry)),
      );
      return;
    }
    if (!context.mounted) return;
    ReceiptPrintPreview.show(context, order: source.$1, payment: source.$2);
  }

  /// Reprints the receipt from the COMBINED authoritative source — see
  /// [_receiptSource]; an unavailable source is an honest retry message,
  /// never a partial receipt presented as complete.
  /// Prints the customer-facing UNPAID bill for this order.
  ///
  /// Read-only with respect to the order: it never calls payment, never
  /// transitions status or settlement, never touches the table or the outbox. A
  /// print failure is a print failure only.
  ///
  /// Unlike [_reprint] this resolves the bridge through
  /// `posActivePrintBridgeReadyProvider` and goes through the canonical
  /// readiness lifecycle, so the FIRST bill after a cold start is not lost to a
  /// synchronously-sampled null bridge.
  Future<void> _printBill(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    final view = await authoritativeUnpaidOrderSource(
      isDemoMode: isDemo,
      orderId: order.orderId,
      localView: order.order,
      repository: ref.read(orderDetailRepositoryProvider),
    );
    if (view == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posReceiptUnavailableRetry)),
      );
      return;
    }
    await ref
        .read(receiptPrintControllerProvider.notifier)
        .requestRepeatableDocument(
          // A DISTINCT key from the paid receipt: the two documents are separate
          // jobs for one order, and the bill is intentionally repeatable.
          orderKey: 'bill:${order.identity.key}',
          resolveReadiness: ref.read(posReceiptReadinessResolverProvider),
          awaitLogoReady: () =>
              ref.read(posReceiptLogoAssetProvider.notifier).firstResolution,
          buildDocument: () => buildBillDocument(
            l10n,
            view,
            isDemo: isDemo,
            restaurantName: ref.read(posRestaurantNameProvider),
            branding: ref.read(posReceiptLogoAssetProvider),
          ),
          resolveBridge: () async => (await ref.read(
            posActivePrintBridgeReadyProvider.future,
          ))?.submit,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.posPrintBillStarted)));
  }

  Future<void> _reprint(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final bridge = ref.read(posActivePrintBridgeProvider);
    if (bridge == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.printStatusNotConfigured)),
      );
      return;
    }
    final source = await _receiptSource(ref);
    if (source == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posReceiptUnavailableRetry)),
      );
      return;
    }
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    final document = buildReceiptDocument(
      l10n,
      source.$1,
      source.$2,
      isDemo: isDemo,
      restaurantName: ref.read(posRestaurantNameProvider),
      // PRINT-BRANDING-LOGO-001: old-order reprints use the CURRENT logo (no
      // order-time snapshot); null -> text-only.
      branding: ref.read(posReceiptLogoAssetProvider),
    );
    await ref
        .read(receiptPrintControllerProvider.notifier)
        .reprint(
          // The receipt belongs to THIS order, keyed by its identity — not to whichever
          // order shares its printed code.
          orderKey: order.identity.key,
          document: document,
          submitToBridge: bridge.submit,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posRecentReprintStarted)),
    );
  }
}

/// One action control, sized so it stays a real touch target on a phone and does
/// not stretch absurdly wide on a tablet. (It is deliberately NOT `Expanded`: these
/// live in a `Wrap`, which is not a Flex, and `Expanded` there is a crash.)
class OrderActionButton extends StatelessWidget {
  const OrderActionButton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 148, minHeight: 44),
    child: child,
  );
}
