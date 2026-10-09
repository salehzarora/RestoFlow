import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show kitchenChangeSlipLabelsFromL10n;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_actions.dart';
import '../data/order_identity.dart' show PosOrderIdentity;
import '../data/payment.dart';
import '../data/order_detail_repository.dart';
import '../data/order_edit_slip_store.dart' show OrderEditSlipRecord;
import '../data/recent_order.dart';
import '../print/native_print_bridges.dart';
import '../print/pos_kitchen_ticket_printer.dart'
    show
        PosKitchenPrintOutcome,
        kitchenTicketPrintLabelsFromL10n,
        posKitchenReprintProvider;
import '../state/addition_controller.dart';
import '../state/cart_controller.dart';
import '../state/discount_controller.dart' show staffCapabilitiesProvider;
import '../state/order_edit_controller.dart';
import '../state/order_edit_slip_controller.dart'
    show
        orderEditPendingSlipsProvider,
        orderEditSlipSupersededBy,
        posKitchenChangeSlipReprintProvider;
import '../state/parked_carts_controller.dart';
import '../state/payment_controller.dart' show paymentControllerProvider;
import '../state/pos_offline_state.dart' show blockPosActionWhileOffline;
import '../state/pos_order_complete_controller.dart';
import '../state/pos_printer_assignments.dart';
import '../state/pos_receipt_logo.dart';
import '../state/receipt_print_controller.dart';
import '../state/submitted_order_view.dart';
import 'cancel_order_sheet.dart';
import 'cash_payment_sheet.dart';
import 'discount_sheet.dart';
import 'move_table_sheet.dart';
import 'order_edit_cart_widgets.dart'
    show
        OrderEditCartChoice,
        showOrderEditCartNotEmptyPrompt,
        showOrderEditResult;
import 'order_edit_messages.dart'
    show orderEditEntryMessage, orderEditRetryLabel;
import 'order_edit_slip_widgets.dart' show printOrderEditSlipAgain;
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

/// ORDER-REPRINT-CHOOSER-038 — which document the operator asked for.
enum _ReprintChoice { customer, kitchen }

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
    this.onPaymentSuccess,
    this.onCancelClosed,
    this.onCompleteFinished,
  });

  final PosRecentOrder order;
  final AppLocalizations l10n;
  final PosOrderActions actions;

  /// POS-OPEN-ORDER-PAYMENT-DISMISS-019: invoked ONLY after
  /// [CashPaymentSheet.show] resolves TRUE (the one authoritative success
  /// edge). The detail preview passes its own dismissal here so a paid order
  /// never leaves a stale, still-payable panel behind the closed payment
  /// sheet; the Orders sheet passes nothing and keeps its current behavior
  /// (rows re-resolve from the authoritative refresh in place). Cancel,
  /// failure, refusal and both pre-open gates never fire it.
  final VoidCallback? onPaymentSuccess;

  /// STALE-TABLE-ORDER-RECOVERY-001: fired after the cancel sheet closes
  /// (whatever its outcome) so a host that holds its OWN copy of the order
  /// (the table recovery sheet) can re-read it by id. Null for the
  /// store-backed surfaces, which already observe the void.
  final VoidCallback? onCancelClosed;

  /// STALE-TABLE-ORDER-RECOVERY-001: fired after the printer-only Complete
  /// call returns (whatever its outcome), for hosts holding their own copy
  /// of the order. Null for the store-backed surfaces.
  final VoidCallback? onCompleteFinished;

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
                : () async {
                    await ref
                        .read(posOrderCompleteControllerProvider.notifier)
                        .complete(order.orderId ?? '');
                    onCompleteFinished?.call();
                  },
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
      // PAYMENT-ATTEMPT-RECOVERY-001: an UNRESOLVED payment attempt for this
      // order (a lost reply, a sheet closed mid-recovery) is shown on the row
      // itself, so a cashier sees it before reaching for the customer's money
      // again. The button still opens the ONE sheet, which comes up in
      // recovery mode for it.
      final pendingAttempt = ref.watch(
        paymentControllerProvider.select(
          (s) => s.pendingAttemptFor(order.identity),
        ),
      );
      if (pendingAttempt != null) {
        children.add(
          RestoflowStatusPill(
            key: Key('$keyPrefix-payment-unconfirmed-${order.orderNumber}'),
            label: l10n.posPaymentUnconfirmedChip,
            tone: RestoflowTone.warning,
          ),
        );
      }
      children.add(
        OrderActionButton(
          child: FilledButton.icon(
            key: Key('$keyPrefix-pay-${order.orderNumber}'),
            onPressed: () async {
              final paid = await CashPaymentSheet.show(
                context,
                identity: order.identity,
                orderId: order.orderId,
                orderNumber: order.orderNumber,
                // AUTHORITATIVE total + revision. The sheet no longer receives
                // the submit-time figure it used to be handed.
                amountMinor: order.grandTotalMinor,
                currencyCode: order.currencyCode,
                expectedRevision: order.revision,
                // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass B] The
                // central policy's own verdict, carried straight through. It
                // is already false whenever this button is drawn (an
                // unacknowledged submit withdraws `canPay`); passing it keeps
                // the ONE entry point able to refuse honestly if that ever
                // stops being true.
                submitUnacknowledged: actions.submitUnacknowledged,
              );
              // 019: success — and ONLY success — hands control back to the
              // surface that opened this row (the preview dismisses itself);
              // the payment sheet has already closed by the time this resolves.
              if (paid) onPaymentSuccess?.call();
            },
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(l10n.posTakePayment),
          ),
        ),
      );
    }

    // DEFERRED-PAYMENT-RECEIPTS-001: the customer-facing BILL for an order that
    // is still unpaid. It sits BESIDE Collect payment rather than replacing it.
    //
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] Gated on its OWN
    // policy field, no longer on `canPay`. Pass B added the
    // server-acknowledgement requirement to `canPay` — correctly, since
    // `record_payment` cannot work for an order the server has never seen — and
    // that silently took the pre-bill away from an order taken during an outage,
    // which is the exact order a customer is standing there waiting to be billed
    // for. Printing calls no server, so it needs no server acceptance;
    // [PosOrderActions.canPrintBill] keeps every other money interlock.
    //
    // It is deliberately NOT wrapped in `blockPosActionWhileOffline`: that gate
    // exists for server-authorized MUTATIONS, and a bill is a read-only local
    // render.
    if (actions.canPrintBill) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-print-bill-${order.orderNumber}'),
            // 040: the control now ASKS which document. Labelled «طباعة» /
            // "Print", not "reprint": an unpaid pre-bill has not necessarily
            // been printed before, so "reprint" would be a lie on this row.
            onPressed: () => _openOpenOrderPrintChooser(context, ref),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.posPrintAction),
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
            onPressed: () async {
              await CancelOrderSheet.show(context, order: order);
              onCancelClosed?.call();
            },
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

    // ORDER-EDIT-001E: edit a SENT order in place (remove, change quantity,
    // modify, add) — right after Add items (ORDER_EDIT_DESIGN §7.1 step 1).
    // Drawn only when the central policy says so (`canEditOrder`: the
    // add-items interlocks, an acknowledged submit, the branch switch ON and a
    // role the server accepts); the label is the existing, translated
    // "Edit order".
    if (actions.canEditOrder) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-edit-order-${order.orderNumber}'),
            onPressed: () => _startEdit(context, ref),
            icon: const Icon(Icons.edit_note, size: 18),
            label: Text(l10n.posRecoveryEditOrder),
          ),
        ),
      );
    }

    // ORDER-EDIT-001E: an edit of this order whose outcome is unknown (or that
    // is applied but not yet proven) blocks the order's money actions until it
    // is resolved — so its retry rides the row itself, whatever else the
    // policy withdrew (the policy's `canRetryEdit` keeps every host drawing
    // the row for it). It replays the SAME identity; it never mints a new
    // one — and for an APPLIED edit it only refreshes, so it says so.
    final editOrderId = order.orderId;
    final retryable = editOrderId == null || editOrderId.isEmpty
        ? null
        : ref.watch(
            orderEditControllerProvider.select(
              (s) => s.retryableRecordFor(editOrderId),
            ),
          );
    if (editOrderId != null && retryable != null) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-edit-retry-${order.orderNumber}'),
            onPressed: () => _retryEdit(context, editOrderId),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(orderEditRetryLabel(l10n, retryable)),
          ),
        ),
      );
    }

    // ORDER-EDIT-001F: this order's paper change slip did not reach the
    // kitchen printer — its Print again rides the row too (the twin of the
    // menu screen's banner), for the newest unsent slip of the order.
    final slipEditId = editOrderId == null || editOrderId.isEmpty
        ? null
        : ref.watch(
            orderEditPendingSlipsProvider.select((pending) {
              OrderEditSlipRecord? newest;
              for (final r in pending) {
                if (r.orderId == editOrderId &&
                    (newest == null || r.editNumber > newest.editNumber)) {
                  newest = r;
                }
              }
              return newest == null || orderEditSlipSupersededBy(order, newest)
                  ? null
                  : newest.orderEditId;
            }),
          );
    if (slipEditId != null) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-edit-slip-print-again-${order.orderNumber}'),
            onPressed: () =>
                printOrderEditSlipAgain(context, orderEditId: slipEditId),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.posOrderEditPrintAgain),
          ),
        ),
      );
    }

    if (actions.canOpenReceipt) {
      children.add(
        OrderActionButton(
          child: OutlinedButton.icon(
            key: Key('$keyPrefix-reprint-${order.orderNumber}'),
            onPressed: () => _openReprintChooser(context, ref),
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
      // MONEY-CODEX-FINAL-CLOSURE-005: two refusals that are NOT "clear your
      // cart" and must not be reported as though they were — one resolves by
      // itself in a moment, the other needs a person.
      case AdditionEntryResult.blockedHydrating:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.posAdditionLoadingPending)),
        );
      case AdditionEntryResult.blockedConflict:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.posAdditionConflictBlocked)),
        );
    }
  }

  /// ORDER-EDIT-001E: the "Edit order" entry (design §7.1 points 1-2).
  ///
  /// Editing is ONLINE-ONLY (API_CONTRACT §4.45.1): the kitchen has to be told,
  /// so offline the tap is refused at this entry with the edit's own reason —
  /// the controller is never called, and nothing is reserved, fetched or
  /// loaded. The entry transition itself (the reservation, the authoritative
  /// load and the cart's edit mode) is owned by
  /// [OrderEditController.enterForOrder]; this only says what it came to.
  ///
  /// A cart holding other work is not a dead end: the cashier may park it or
  /// clear it, and the entry runs again (design §7.1 point 2).
  Future<void> _startEdit(BuildContext context, WidgetRef ref) async {
    final orderId = order.orderId;
    if (orderId == null) return;
    if (blockPosActionWhileOffline(
      context,
      message: l10n.posOrderEditNeedsConnection,
    )) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Captured BEFORE the first await: the row's ref dies with the tree, the
    // container and the notifiers it owns do not.
    final container = ProviderScope.containerOf(context, listen: false);
    final edit = container.read(orderEditControllerProvider.notifier);
    var entry = await edit.enterForOrder(orderId);
    if (entry == OrderEditEntryResult.cartNotEmpty) {
      if (!context.mounted) return;
      final choice = await showOrderEditCartNotEmptyPrompt(
        context,
        canPark: container.read(parkedCartsControllerProvider.notifier).canPark,
      );
      switch (choice) {
        case null:
          return;
        case OrderEditCartChoice.park:
          final parked = await container
              .read(parkedCartsControllerProvider.notifier)
              .park();
          if (parked != ParkResult.parked) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  parked == ParkResult.blockedByAddition
                      ? l10n.posParkedBlockedByAddition
                      : l10n.posParkedParkFailed,
                ),
              ),
            );
            return;
          }
        case OrderEditCartChoice.clear:
          if (container.read(cartControllerProvider.notifier).clear() !=
              CartMutationResult.applied) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.posOrderEditCartNotEmptyBody)),
            );
            return;
          }
      }
      entry = await edit.enterForOrder(orderId);
    }
    if (entry == OrderEditEntryResult.entered) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    // The switch is fresher on the authoritative detail than in the session
    // probe: re-read the probe so the button follows.
    if (entry == OrderEditEntryResult.featureDisabled) {
      container.invalidate(staffCapabilitiesProvider);
    }
    final message = orderEditEntryMessage(l10n, entry);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// ORDER-EDIT-001E: the row's retry of an edit whose outcome is unknown
  /// (this session's, or a record restored after a restart): it replays the
  /// FROZEN identity and payload verbatim — or, for an edit the server already
  /// applied, retries only the authoritative refresh. Never a new identity.
  Future<void> _retryEdit(BuildContext context, String orderId) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final edit = container.read(orderEditControllerProvider.notifier);
    final result = await edit.retryOrder(orderId);
    final slipEditId = result.applied?.orderEditId;
    showOrderEditResult(
      messenger,
      l10n,
      result,
      onRefresh: () => edit.retryOrder(orderId),
      // ORDER-EDIT-001F: the paper slip did not print — Print again.
      onPrintSlipAgain: slipEditId == null
          ? null
          : () {
              if (context.mounted) {
                printOrderEditSlipAgain(context, orderEditId: slipEditId);
              }
            },
      onPrintBill: () => printOrderBill(
        container: container,
        messenger: messenger,
        l10n: l10n,
        orderId: orderId,
        identity: order.identity,
        localView: order.order,
      ),
    );
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
  /// Prints the customer-facing UNPAID bill for this order (unlike [_reprint],
  /// through the canonical readiness lifecycle — see [printOrderBill]).
  ///
  /// ORDER-EDIT-001E: the body moved to the top-level [printOrderBill] so the
  /// edit's "Bill changed: print new bill?" action prints the SAME document
  /// through the SAME job; this row's behaviour is unchanged.
  Future<void> _printBill(BuildContext context, WidgetRef ref) =>
      printOrderBill(
        container: ProviderScope.containerOf(context, listen: false),
        messenger: ScaffoldMessenger.of(context),
        l10n: l10n,
        orderId: order.orderId,
        identity: order.identity,
        localView: order.order,
        isMounted: () => context.mounted,
      );

  /// ORDER-REPRINT-CHOOSER-038 — the reprint control now ASKS which document.
  ///
  /// Before this, tapping reprint went straight to the customer receipt, and a
  /// kitchen ticket could only be reprinted from the confirmation screen that
  /// dies the moment the next order starts. Both documents are reachable here,
  /// and each one goes to ITS OWN configured printer:
  ///
  ///   * customer  -> the existing receipt composer + print bridge, untouched;
  ///   * kitchen   -> the canonical kitchen seam the automatic and immediate
  ///                  manual prints already use.
  ///
  /// There is no cross-purpose fallback in either direction: an unavailable
  /// kitchen printer produces a KITCHEN error and prints nothing, and the same
  /// holds for the receipt side. Dismissing the sheet prints nothing at all.
  /// ORDER-REPRINT-CHOOSER-038 / OPEN-ORDER-PRINT-CHOOSER-040 — the ONE
  /// chooser both order states use.
  ///
  /// The two contexts differ only in wording and in which customer-facing
  /// document the first option prints:
  ///
  ///   * a CLOSED/paid order reprints the customer RECEIPT;
  ///   * an OPEN/unpaid order prints the current customer BILL (pre-bill).
  ///
  /// The second option is the same kitchen ticket in both. Keeping one sheet
  /// means the routing rule — each document to its own printer, never a
  /// cross-purpose fallback — has a single implementation to be right about.
  Future<_ReprintChoice?> _showPrintChooser(
    BuildContext context, {
    required String sheetKey,
    required String title,
    required String customerLabel,
    required String customerHint,
    required IconData customerIcon,
    required String customerKey,
    required String kitchenKey,
    required String cancelKey,
  }) => showModalBottomSheet<_ReprintChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        key: Key(sheetKey),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RestoflowSpacing.lg,
              RestoflowSpacing.xs,
              RestoflowSpacing.lg,
              RestoflowSpacing.sm,
            ),
            child: Text(
              title,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            key: Key(customerKey),
            leading: Icon(customerIcon),
            title: Text(customerLabel),
            subtitle: Text(customerHint),
            minVerticalPadding: RestoflowSpacing.md,
            onTap: () =>
                Navigator.of(sheetContext).pop(_ReprintChoice.customer),
          ),
          ListTile(
            key: Key(kitchenKey),
            leading: const Icon(Icons.soup_kitchen_outlined),
            title: Text(l10n.posReprintKitchenTicket),
            subtitle: Text(l10n.posReprintKitchenTicketHint),
            minVerticalPadding: RestoflowSpacing.md,
            onTap: () => Navigator.of(sheetContext).pop(_ReprintChoice.kitchen),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RestoflowSpacing.lg,
              RestoflowSpacing.sm,
              RestoflowSpacing.lg,
              RestoflowSpacing.lg,
            ),
            child: TextButton(
              key: Key(cancelKey),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(l10n.adminCancel),
            ),
          ),
        ],
      ),
    ),
  );

  /// OPEN-ORDER-PRINT-CHOOSER-040 — the OPEN/unpaid order's print chooser.
  ///
  /// The gap this closes: an open order only ever offered «طباعة الحساب», so
  /// once the cart moved on there was no way to put a kitchen ticket back on
  /// the pass for an order still being served. The bill option runs the
  /// EXISTING pre-bill path untouched; the kitchen option runs the same
  /// canonical seam the closed-order chooser uses.
  Future<void> _openOpenOrderPrintChooser(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await _showPrintChooser(
      context,
      sheetKey: 'print-chooser',
      title: l10n.posPrintChooserTitle,
      customerLabel: l10n.posPrintCustomerBill,
      customerHint: l10n.posPrintCustomerBillHint,
      customerIcon: Icons.receipt_long_outlined,
      customerKey: 'print-choice-bill',
      kitchenKey: 'print-choice-kitchen',
      cancelKey: 'print-choice-cancel',
    );
    if (!context.mounted) return;
    switch (choice) {
      case null:
        return;
      case _ReprintChoice.customer:
        await _printBill(context, ref);
      case _ReprintChoice.kitchen:
        await _reprintKitchenTicket(context, ref);
    }
  }

  Future<void> _openReprintChooser(BuildContext context, WidgetRef ref) async {
    final choice = await _showPrintChooser(
      context,
      sheetKey: 'reprint-chooser',
      title: l10n.posReprintChooserTitle,
      customerLabel: l10n.posReprintCustomerReceipt,
      customerHint: l10n.posReprintCustomerReceiptHint,
      customerIcon: Icons.receipt_long_outlined,
      customerKey: 'reprint-choice-customer',
      kitchenKey: 'reprint-choice-kitchen',
      cancelKey: 'reprint-choice-cancel',
    );
    if (!context.mounted) return;
    // Cancel, back and a barrier dismiss all land here: NOTHING is printed.
    switch (choice) {
      case null:
        return;
      case _ReprintChoice.customer:
        await _reprintCustomerReceipt(context, ref);
      case _ReprintChoice.kitchen:
        await _reprintKitchenTicket(context, ref);
    }
  }

  /// The KITCHEN half. Prints the SELECTED historical order's snapshot — never
  /// the current cart — through `printKitchenTicketAndSettleOwedClaims`, the
  /// same seam the confirmation screen's manual print and the automatic
  /// on-submit print already use. That seam owns kitchen-printer resolution,
  /// so no transport code is duplicated here and the receipt printer is never
  /// consulted.
  ///
  /// Print-only: it composes and sends. It creates no order, resubmits
  /// nothing, and changes no order, payment, table or kitchen status. (The
  /// seam may SETTLE an owed direct-print claim on success — that is
  /// pre-existing print bookkeeping recording that the ticket physically went
  /// out, not a business-state change.)
  ///
  /// ORDER-EDIT-001F (decision D6, "R2"): an EDITED order (`editCount > 0`)
  /// never reprints its order-time snapshot — removed food would come back on
  /// paper. It prints the ORDER-NOW change slip from the authoritative detail
  /// instead ([posKitchenChangeSlipReprintProvider]). An unedited order is
  /// byte-identical to before.
  Future<void> _reprintKitchenTicket(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    final orderId = order.orderId;
    if (order.editCount > 0 && !isDemo && orderId != null) {
      final result = await ref.read(posKitchenChangeSlipReprintProvider)(
        read: container.read,
        orderId: orderId,
        labels: kitchenTicketPrintLabelsFromL10n(l10n),
        changeLabels: kitchenChangeSlipLabelsFromL10n(l10n),
      );
      final outcome = result.outcome;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome != null
                ? _kitchenReprintSnack(outcome)
                : result.fetchFailed
                ? l10n.posReprintKitchenFetchFailed
                : l10n.posReprintKitchenUnavailable,
          ),
        ),
      );
      return;
    }
    // KIOSK-PRINT-114B.5A: a DEVICE-OWNED order prints its local order-time
    // snapshot exactly as before. A BRANCH-DISCOVERED order (a kiosk order, or
    // one taken on another till) has no local snapshot — it used to refuse here
    // and nothing printed — so it is now resolved from the AUTHORITATIVE
    // detail, the same source the receipt reprint already trusts.
    final local = order.order;
    final view =
        local ??
        await authoritativeKitchenSource(
          isDemoMode: isDemo,
          orderId: order.orderId,
          localView: null,
          repository: ref.read(orderDetailRepositoryProvider),
        );
    if (view == null) {
      // Honest KITCHEN-only refusal — never a silent receipt instead. Demo /
      // no server identity: there is nothing to fetch; otherwise the fetch
      // itself failed (offline, malformed) — say so, print nothing.
      final message = (isDemo || order.orderId == null)
          ? l10n.posReprintKitchenUnavailable
          : l10n.posReprintKitchenFetchFailed;
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final outcome = await ref.read(posKitchenReprintProvider)(
      container: container,
      order: view,
      labels: kitchenTicketPrintLabelsFromL10n(l10n),
    );
    messenger.showSnackBar(
      SnackBar(content: Text(_kitchenReprintSnack(outcome))),
    );
    // 114B.5A DETAIL-SOURCED LIMITATION (until 114B.5B): the authoritative
    // detail carries no prep/meat snapshots, so a branch-discovered reprint
    // prints WITHOUT the whole-order counts block. Say so — informational,
    // after the honest print outcome; never a silent omission.
    if (local == null &&
        outcome == PosKitchenPrintOutcome.printed &&
        view.lines.every(
          (l) => l.kitchenMeats.isEmpty && l.prepComponents.isEmpty,
        )) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posReprintKitchenCountsUnavailable)),
      );
    }
  }

  /// The honest kitchen-print snack for a manual reprint's [outcome].
  String _kitchenReprintSnack(PosKitchenPrintOutcome outcome) =>
      switch (outcome) {
        PosKitchenPrintOutcome.printed => l10n.posKitchenTicketPrintedSnack,
        PosKitchenPrintOutcome.noPrinterConfigured ||
        PosKitchenPrintOutcome.unavailable =>
          l10n.posKitchenPrinterNotConfiguredSnack,
        PosKitchenPrintOutcome.failed ||
        PosKitchenPrintOutcome.ineligibleOrder =>
          l10n.posKitchenTicketPrintFailedSnack,
      };

  Future<void> _reprintCustomerReceipt(
    BuildContext context,
    WidgetRef ref,
  ) async {
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

/// Prints the customer-facing UNPAID bill for one order — the order row's
/// Print → Bill, and (ORDER-EDIT-001E, decision D7) the edit's "Bill changed:
/// print new bill?" action, which reprints the SAME document under the SAME
/// job key once an edit changed a bill this till had presented.
///
/// Read-only with respect to the order: it never calls payment, never
/// transitions status or settlement, never touches the table or the outbox. A
/// print failure is a print failure only.
///
/// It resolves the bridge through `posActivePrintBridgeReadyProvider` and goes
/// through the canonical readiness lifecycle, so the FIRST bill after a cold
/// start is not lost to a synchronously-sampled null bridge.
///
/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass C] It does NOT require a
/// server round-trip. [printableUnpaidOrderSource] prefers the authoritative
/// detail and falls back to this device's stored snapshot when that call fails
/// — which offline it always does — and the printed document says so. Every
/// other input was already local: the printer transport/config
/// (SharedPreferences), the restaurant name (the loaded assignments snapshot)
/// and the logo (a durable raster cache).
///
/// Reads through [container] (not a widget ref), so the action still works
/// when the surface that offered it has gone; [isMounted] gates the final
/// outcome message for a caller whose context may have.
Future<void> printOrderBill({
  required ProviderContainer container,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required String? orderId,
  required PosOrderIdentity identity,
  required SubmittedOrderView? localView,
  bool Function()? isMounted,
}) async {
  final isDemo = container.read(runtimeConfigProvider).isDemoMode;
  final source = await printableUnpaidOrderSource(
    isDemoMode: isDemo,
    orderId: orderId,
    localView: localView,
    repository: container.read(orderDetailRepositoryProvider),
  );
  // FAIL CLOSED: no server answer AND no local snapshot means there is no
  // honest document to build, so nothing is printed at all.
  if (source == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.posReceiptUnavailableRetry)),
    );
    return;
  }
  // A DISTINCT key from the paid receipt: the two documents are separate jobs
  // for one order, and the bill is intentionally repeatable.
  final billKey = 'bill:${identity.key}';
  final printer = container.read(receiptPrintControllerProvider.notifier);
  await printer.requestRepeatableDocument(
    orderKey: billKey,
    resolveReadiness: container.read(posReceiptReadinessResolverProvider),
    awaitLogoReady: () =>
        container.read(posReceiptLogoAssetProvider.notifier).firstResolution,
    buildDocument: () => buildBillDocument(
      l10n,
      source.view,
      isDemo: isDemo,
      restaurantName: container.read(posRestaurantNameProvider),
      branding: container.read(posReceiptLogoAssetProvider),
      isLocalReference: source.isLocalSnapshot,
    ),
    resolveBridge: () async => (await container.read(
      posActivePrintBridgeReadyProvider.future,
    ))?.submit,
  );
  if (!(isMounted?.call() ?? true) || !messenger.mounted) return;
  // OUTCOME-AWARE. The old message claimed "Printing bill" whatever happened —
  // including with no printer configured or an unreachable one, which is how a
  // cashier ends up believing a customer was handed paper that never existed.
  // The job's own status is the same one every other print surface reads.
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        _billPrintFailed(printer.jobFor(billKey)?.status)
            ? l10n.posPrintBillFailed
            : l10n.posPrintBillStarted,
      ),
    ),
  );
}

/// Whether a finished bill request must be reported as a FAILURE.
///
/// It reports failure only on the statuses that mean nothing reached a
/// printer: no printer configured, a bridge that could not be reached, and an
/// outright build/send failure. `sentToPrinter` (and `printed`) are successes;
/// `prepared` is NOT a failure — a demo/sink bridge legitimately accepts a
/// document without hardware, and that path has always been honest about being
/// only prepared. A null job (nothing was recorded) is treated as a failure
/// rather than a claim.
bool _billPrintFailed(PrintJobStatus? status) => switch (status) {
  PrintJobStatus.sentToPrinter ||
  PrintJobStatus.printed ||
  PrintJobStatus.prepared ||
  PrintJobStatus.waitingForPrinter => false,
  PrintJobStatus.notConfigured ||
  PrintJobStatus.bridgeUnavailable ||
  PrintJobStatus.failed ||
  null => true,
};
