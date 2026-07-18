import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'package:restoflow_core/restoflow_core.dart';

import '../data/order_actions.dart';
import '../data/order_submission.dart';
import '../data/payment.dart' show CashPayment;
import '../data/recent_order.dart';
import '../format/money_format.dart';
import '../state/cart_controller.dart' show cartControllerProvider;
import '../format/payment_method_label.dart';
import '../print/native_print_bridges.dart';
import '../state/discount_controller.dart' show staffCapabilitiesProvider;
import '../state/draft_recovery_controller.dart';
import '../state/outbox_controller.dart';
import '../state/payment_controller.dart';
import '../state/recent_orders_controller.dart';
import '../state/pos_auto_print_prefs.dart';
import '../state/pos_printer_assignments.dart';
import '../state/receipt_print_controller.dart';
import '../state/submitted_order_view.dart';
import 'cash_payment_sheet.dart';
import 'discount_sheet.dart';
import 'order_status_pills.dart';
import 'recovery_coordinator.dart';
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

    // PILOT-OPERATIONS-CORRECTIONS-001 — a PERMANENTLY rejected item_unavailable
    // NEW order has NO server order: it must NEVER offer payment / discount / void
    // / receipt (those pretend an order exists). Instead the cashier recovers —
    // restore the exact draft to the cart, or discard the attempt (no server void).
    final isRejectedDraft =
        entry != null &&
        entry.isPermanentBusinessRejection &&
        entry.lastErrorCode == 'item_unavailable';
    // A2: the recovery for THIS submit, keyed by its outbox entry and offered ONLY when
    // the CURRENT operational context matches its binding — a PIN switch / branch /
    // device change makes the previous employee's draft inaccessible immediately.
    final recoveries = ref.watch(posDraftRecoveryProvider);
    final binding = ref.watch(posRecoveryBindingProvider);
    final recovery = () {
      final r = recoveries[order.outboxEntryId];
      return (r != null && r.binding.matches(binding)) ? r : null;
    }();
    final canRestoreDraft = isRejectedDraft && recovery != null;
    // Cart-safety (final): while a frozen addition attempt owns the cart the
    // Restore action is DISABLED — the coordinator refuses it regardless.
    final cartLocked = ref.watch(
      cartControllerProvider.select((c) => c.lockedByAddition),
    );
    // Finding 3: clearing an accepted recovery now lives in the recovery CONTROLLER
    // (it watches the outbox), so an applied order clears its recovery even if this
    // confirmation is never opened / is unmounted / the app navigated away. No widget
    // listener here — a stale draft can never be restored over a real order regardless.

    // RF-116: the recorded cash payment for THIS order, or null if unpaid. Looked up
    // by IDENTITY: keyed by the display code, a payment taken for another order that
    // shared this one's code would show up here as though this order were paid.
    final payment = ref
        .watch(paymentControllerProvider)
        .paymentFor(order.identity);

    // POS-OPERATIONS-SYNC-001 (review correction) — THIS SCREEN IS NOW BOUND TO THE
    // AUTHORITATIVE ORDER, NOT TO A FROZEN SUBMIT-TIME SNAPSHOT.
    //
    // It used to render a static SubmittedOrderView and decide its own actions. While
    // it sat open — and a confirmation screen sits open for a long time — the order
    // could be comped to zero, paid on another till, completed by the kitchen, or
    // voided, and this screen would carry on showing the old total and offering
    // Take payment on an order that no longer existed in that state. The operational
    // centre was correct and this path quietly was not, which is worse than both being
    // wrong: it meant the fix looked done.
    //
    // WATCHING the reconciled row means a reconciliation that lands while the screen
    // is open rebuilds it. No reopen, no reconstruction.
    // AUTHORITATIVE means THE SERVER HAS ACTUALLY SPOKEN — a reconciled row carrying a
    // snapshot. A row that merely EXISTS is not authority: before the first pull it
    // holds the same submit-time figures we already have, and preferring it would
    // shadow the locally-applied discount the cart keeps current. Where there is no
    // snapshot we fall back to the existing safe behaviour and fabricate nothing.
    final row = _authoritativeRow(
      ref.watch(posRecentOrdersControllerProvider),
      order.orderId,
    );
    final authoritative = row?.snapshot == null ? null : row;
    final caps = ref.watch(staffCapabilitiesProvider).value;

    // The SAME central policy the operational centre uses. There is exactly one
    // definition of "may this cashier do this", and a second one here is precisely
    // how the two screens drifted apart.
    final actions = authoritative == null
        ? null
        : resolveOrderActions(authoritative, capabilities: caps);

    // AUTHORITATIVE money. Falls back to the submit-time view ONLY when the server has
    // said nothing yet (offline, first moments after submit) -- we never fabricate a
    // newer state, and the server stays the authority either way.
    final grandTotalMinor =
        authoritative?.grandTotalMinor ?? order.grandTotalMinor;
    final effectiveSubtotal =
        authoritative?.subtotalMinor ?? order.subtotalMinor;
    final effectiveTax = authoritative?.taxTotalMinor ?? order.taxTotalMinor;
    final effectiveDiscount =
        authoritative?.discountTotalMinor ?? order.discountTotalMinor;
    final expectedRevision = authoritative?.revision;

    // Actions come from the policy when we HAVE authority. Before the first snapshot
    // arrives we keep the existing, safe behaviour rather than blanking the screen.
    // A rejected draft has no order — NEVER offer payment or discount for it.
    final canPay = isRejectedDraft
        ? false
        : (actions?.canPay ?? (payment == null));
    final canDiscount = isRejectedDraft
        ? false
        : (actions?.canDiscount ??
              (payment == null && order.discountTotalMinor == 0));

    // The money the screen SHOWS. Realigned to the server's figures so a comp applied
    // while this screen was open cannot keep printing the old total. The order LINES
    // are untouched -- they are the order-time price snapshot (D-008).
    final displayOrder = order.copyWith(
      subtotalMinor: effectiveSubtotal,
      discountTotalMinor: effectiveDiscount,
      taxTotalMinor: effectiveTax,
    );

    // Part E: the receipt auto-print trigger. Fires ONLY on THIS order's
    // payment SUCCESS transition (a failed submit/payment never reaches a
    // non-null payment, and the controller is idempotent per order besides).
    // Cashier turned the toggle off => nothing at all; toggle would be on
    // but no printer => an honest notConfigured marker; otherwise the job is
    // PREPARED (this build has no bridge transport, so never "printed").
    ref.listen(paymentControllerProvider, (previous, next) {
      final paid = next.paymentFor(order.identity);
      if (paid == null) return;
      if (previous?.paymentFor(order.identity) != null) return;
      final assignments = switch (ref
          .read(posPrinterAssignmentsProvider)
          .valueOrNull) {
        Success(:final value) => value,
        _ => null,
      };
      // ANDROID-003: a native (Wi-Fi/Bluetooth) printer configured on THIS
      // device counts as a printer even without a backend assignment.
      final nativeConfigured = ref.read(posHasNativePrinterProvider);
      // Demo / unconfigured reads with NO native printer: no auto-print.
      if (assignments == null && !nativeConfigured) return;
      final stored = ref.read(posAutoPrintReceiptProvider).valueOrNull;
      if (stored == false) return; // explicitly off — show nothing
      final printer =
          (assignments?.hasEnabledPrinter ?? false) || nativeConfigured;
      // ANDROID-003: dispatch through the RESOLVED print target — a native
      // network/Bluetooth transport on Android, else the RF-115 loopback bridge.
      // With no target the job stays honestly "prepared"; a confirmed transport
      // write flips it to "sent to printer"; never a fabricated hardware print.
      final bridge = ref.read(posActivePrintBridgeProvider);
      ref
          .read(receiptPrintControllerProvider.notifier)
          .prepareAndDispatch(
            // The receipt is keyed to THIS order. Keyed by the display code, a second
            // order sharing it found a job already prepared and never got a receipt.
            orderKey: order.identity.key,
            hasEnabledPrinter: printer,
            // The RECEIPT prints the REALIGNED money, exactly like the totals on
            // screen. This branch used to hand the FROZEN submit-time view to the
            // printer, so an order discounted on another till printed "Total 40.00 /
            // Paid 30.00" — an incoherent financial document — while the orders
            // centre's reprint (built from the reconciled row) printed 30.00 for the
            // very same order. The LINES are untouched: they are the order-time
            // price snapshot (D-008) and are never recomputed.
            buildDocument: () =>
                buildReceiptDocument(l10n, displayOrder, paid, isDemo: isDemo),
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
                          child: authoritative == null
                              // NO AUTHORITY YET (offline, or the first moments after
                              // submit). The safe local fallback, unchanged: we know we
                              // submitted it, and we invent nothing else.
                              ? Wrap(
                                  spacing: RestoflowSpacing.sm,
                                  runSpacing: RestoflowSpacing.xs,
                                  children: [
                                    RestoflowStatusPill(
                                      key: const Key(
                                        'confirmation-local-status',
                                      ),
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
                                )
                              // THE SERVER HAS SPOKEN. Its lifecycle status and its
                              // three-valued settlement, in the SAME words the
                              // operational centre uses.
                              //
                              // This screen used to show a hard-coded "Submitted" chip
                              // for as long as it stayed open, and a "Paid" chip driven
                              // by a LOCAL payment marker. So an order the kitchen had
                              // completed still read "Submitted"; and an order comped to
                              // zero — which nobody paid and nobody can pay — read
                              // neither Paid nor No charge, just an unpaid order for 0.
                              : OrderStatusPills(
                                  serverStatus: authoritative.serverStatus,
                                  settlement: authoritative.settlement,
                                  keySuffix: 'confirmation',
                                  // RESTAURANT-OPERATIONS-V1-001: a takeaway's
                                  // `served` renders "Picked up" here too — the
                                  // confirmation speaks the same words as the
                                  // orders centre.
                                  orderType: authoritative.orderType,
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
                  // REVIEW B2: no Retry for a PERMANENT business rejection —
                  // the server ledgered the verdict under this operation
                  // identity and replays it verbatim; a button claiming
                  // otherwise is a lie. The typed note above (item names,
                  // menu refreshed) already directs the cashier to re-enter
                  // the order deliberately. Transport-ish failures (no
                  // recorded verdict) keep Retry: an idempotent re-push is
                  // safe and meaningful there.
                  onRetry:
                      entry != null &&
                          entry.syncState.isFailed &&
                          !entry.isPermanentBusinessRejection
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
                  _OrderTotals(order: displayOrder, l10n: l10n),
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
                  // The REALIGNED view, same as the printed document: the receipt a
                  // cashier reads on screen and the one that comes off the printer
                  // must be the same document, and both must say what was actually
                  // charged — not what the order cost when it was submitted.
                  ReceiptPreview(order: displayOrder, payment: payment),
                  // RF-115: the HONEST receipt print-job status (prepared /
                  // sent to printer / bridge unavailable / not configured /
                  // failed — never a fake "printed") with a Retry action.
                  _ReceiptPrintStatusLine(
                    order: displayOrder,
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
              child: isRejectedDraft
                  ? Column(
                      key: const Key('recovery-actions'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: RestoflowSpacing.sm,
                          ),
                          child: RestoflowNoticeBanner(
                            key: const Key('recovery-not-created'),
                            tone: RestoflowTone.warning,
                            icon: Icons.info_outline,
                            body: l10n.posRecoveryOrderNotCreated,
                          ),
                        ),
                        if (canRestoreDraft)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const Key('recovery-back-to-cart'),
                              // Finding 1B: the ONE shared coordinator. On the
                              // confirmation the cart is empty, so it restores directly
                              // (restoreDraft dismisses this confirmation); if a cart is
                              // present it enforces the Replace / Keep-current / Cancel
                              // decision — identically to the Recent Orders entry point.
                              onPressed: cartLocked
                                  ? null
                                  : () async {
                                      final outcome =
                                          await PosRecoveryCoordinator(
                                            ref,
                                          ).restore(context, recovery);
                                      // Keep-current retired the shell but left the
                                      // cart; the confirmation still shows the
                                      // (retired) order, so dismiss it to that kept
                                      // cart. A locked-cart refusal changes nothing.
                                      if (outcome ==
                                          PosRecoveryOutcome.keptCurrent) {
                                        onNewOrder();
                                      }
                                    },
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(l10n.posRecoveryBackToCart),
                              style: RestoflowButtonStyles.big(context),
                            ),
                          ),
                        if (canRestoreDraft)
                          const SizedBox(height: RestoflowSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('recovery-discard'),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (dctx) => AlertDialog(
                                  title: Text(
                                    l10n.posRecoveryDiscardConfirmTitle,
                                  ),
                                  content: Text(
                                    l10n.posRecoveryDiscardConfirmBody,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(dctx).pop(false),
                                      child: Text(l10n.posShiftCancelAction),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(dctx).pop(true),
                                      child: Text(l10n.posRecoveryDiscardDraft),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              // Finding 1B: the shared coordinator retires the shell +
                              // clears ONLY this submit's recovery — NO server void, NO
                              // order-cancelled audit (no order was created). With no
                              // matching recovery (already cleared, or a scope mismatch)
                              // it still retires the orphan shell. Then dismiss.
                              final coordinator = PosRecoveryCoordinator(ref);
                              final r = recovery;
                              if (r != null) {
                                coordinator.discard(r);
                              } else {
                                // Finding 2: fail-closed orphan dismissal — the coordinator
                                // refuses if a recovery under ANY binding still exists for
                                // this outbox entry (another session's draft stays intact).
                                coordinator.discardOrphanShell(
                                  order.identity,
                                  outboxEntryId: order.outboxEntryId,
                                );
                              }
                              onNewOrder();
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: Text(l10n.posRecoveryDiscardDraft),
                          ),
                        ),
                      ],
                    )
                  : payment == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // AUTHORITATIVE gating. `payment == null` is a LOCAL marker:
                        // it cannot know the order was comped to zero, completed by
                        // the kitchen, or paid on another till. The policy can.
                        if (canPay)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              // RF-116/RF-117: opens the payment sheet (cash or a
                              // non-cash tender). The e2e depends on this KEY.
                              key: const Key('pay-cash-button'),
                              onPressed: () => CashPaymentSheet.show(
                                context,
                                identity: order.identity,
                                orderId: order.orderId,
                                orderNumber: order.orderNumber,
                                // The AUTHORITATIVE grand total, not the submit-time
                                // one: an order comped to zero while this screen was
                                // open must not open a payment sheet for the old 40.
                                amountMinor: grandTotalMinor,
                                currencyCode: order.currencyCode,
                                expectedRevision: expectedRevision,
                              ),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(l10n.posTakePayment),
                              style: RestoflowButtonStyles.big(context),
                            ),
                          ),
                        if (canPay) const SizedBox(height: RestoflowSpacing.sm),
                        // RF-117 part C: apply an order-level discount before
                        // payment (server-authoritative + authorized in real
                        // mode; local in demo). Hidden once a discount is
                        // applied so it is not stacked twice.
                        if (canDiscount && effectiveDiscount == 0)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const Key('apply-discount-button'),
                              onPressed: () => DiscountSheet.show(
                                context,
                                orderId: order.orderId ?? '',
                                subtotalMinor: effectiveSubtotal,
                                taxTotalMinor: effectiveTax,
                                currencyCode: order.currencyCode,
                                expectedRevision: expectedRevision,
                              ),
                              icon: const Icon(Icons.percent),
                              label: Text(l10n.posApplyDiscount),
                            ),
                          ),
                        if (canDiscount && effectiveDiscount == 0)
                          const SizedBox(height: RestoflowSpacing.sm),
                        // POS-ORDERS-AND-PAYMENT-001: "Pay later" leaves the order
                        // UNPAID (already recorded in Recent orders at submit) and
                        // starts the next order — no fake payment, no cash
                        // movement. The order still goes to the kitchen normally.
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            key: const Key('pay-later-button'),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.posPayLaterSavedSnack),
                                ),
                              );
                              onNewOrder();
                            },
                            icon: const Icon(Icons.schedule),
                            label: Text(l10n.posPayLaterAction),
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
      receiptPrintControllerProvider.select((jobs) => jobs[order.identity.key]),
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
    // ANDROID-003: retry through the resolved native/loopback target.
    final nativeConfigured = ref.read(posHasNativePrinterProvider);
    final bridge = ref.read(posActivePrintBridgeProvider);
    ref
        .read(receiptPrintControllerProvider.notifier)
        .retry(
          orderKey: order.identity.key,
          hasEnabledPrinter:
              (assignments?.hasEnabledPrinter ?? false) || nativeConfigured,
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
  String? errorCode,
  String? errorDetail,
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
      // RESTAURANT-OPERATIONS-V1-001: the TYPED acceptance refusals get their
      // own honest instruction instead of the generic failure line. The cart
      // is already cleared at this point, so "re-enter the order" is the true
      // recovery path — matched on the server's EXACT stable codes only.
      final String rejectedNote;
      if (isDemo) {
        rejectedNote = l10n.posSyncDemoNotice;
      } else if (errorCode == 'item_unavailable') {
        rejectedNote = l10n.posSyncItemUnavailable(errorDetail ?? '—');
      } else if (errorCode == 'table_not_available') {
        rejectedNote = l10n.posSyncTableUnavailable;
      } else {
        rejectedNote = l10n.posSyncFailedReal;
      }
      return (
        label: l10n.posSyncStateFailed,
        note: rejectedNote,
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
    final visual = _syncVisual(
      state,
      l10n,
      isDemo: isDemo,
      errorCode: entry?.lastErrorCode,
      errorDetail: entry?.lastErrorDetail,
    );
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

/// The AUTHORITATIVE reconciled row for this order, or null when the server has not
/// spoken about it yet (offline, or the first moments after submit).
///
/// Looked up by the SERVER ORDER ID -- never by the display code, which is a
/// shortened human reference and not an identity.
PosRecentOrder? _authoritativeRow(List<PosRecentOrder> rows, String? orderId) {
  if (orderId == null || orderId.isEmpty) return null;
  for (final r in rows) {
    if (r.orderId == orderId) return r;
  }
  return null;
}
