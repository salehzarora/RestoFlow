import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/recent_order.dart';
import '../data/void_repository.dart';
import '../format/money_format.dart';
import '../state/order_sync_controller.dart';
import '../state/recent_orders_controller.dart';
import '../state/void_controller.dart';

/// MONEY-VOID-001: the modal "Cancel order" confirmation for a WRONG UNPAID
/// order. Shows the order code / customer / total, a clear danger warning, and a
/// REQUIRED cancellation reason, then pushes the SERVER-AUTHORITATIVE
/// `order.void` op (real mode) or a demo-local success via [VoidRepository]. On
/// success it marks the order cancelled locally + snackbars; on the honest
/// server refusals it shows an inline reason ("only a manager can cancel this",
/// "a paid order cannot be cancelled") — never a fake success. The Confirm
/// button is the double-tap guard (disabled while submitting). Money-free: no
/// payment is created/deleted and no total is recomputed.
class CancelOrderSheet extends ConsumerStatefulWidget {
  const CancelOrderSheet({required this.order, super.key});

  /// The recent order being cancelled (its order id + display fields).
  final PosRecentOrder order;

  static Future<void> show(
    BuildContext context, {
    required PosRecentOrder order,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CancelOrderSheet(order: order),
  );

  @override
  ConsumerState<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends ConsumerState<CancelOrderSheet> {
  final TextEditingController _reasonController = TextEditingController();
  bool _submitting = false;

  /// The last failure message to show inline, or null when there is none.
  String? _error;

  /// POS-OPERATIONS-SYNC-001 (stabilization) — THIS SHEET IS NOW STALE.
  ///
  /// Set on the two refusals no retry from THIS sheet can ever satisfy: a typed
  /// `conflict` (the order moved; this sheet's `widget.order.revision` is the one the
  /// server just rejected, and it is immutable here) and `order_not_voidable` (the
  /// server says the order is already terminal). Both paths reconcile the row, so the
  /// truth is on screen behind the sheet — but the sheet itself used to keep Confirm
  /// enabled over the stale revision, re-sending a request that cannot ever succeed
  /// while its own error text said "refresh and try again". Now the message can come
  /// true: Confirm is REPLACED by Close, and a new deliberate attempt starts from the
  /// refreshed order.
  bool _staleAfterRefusal = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    // Double-tap guard: the disabled button relies on a rebuild, so also refuse
    // re-entry synchronously — a cancel must never be pushed twice.
    if (_submitting) return;
    // BELT AND BRACES: a retired sheet holds the revision the server just refused;
    // it must be impossible to re-send it even by another route.
    if (_staleAfterRefusal) return;
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = l10n.posCancellationReasonRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(voidRepositoryProvider)
          .voidOrder(
            orderId: widget.order.orderId ?? '',
            reason: reason,
            // POS-OPERATIONS-SYNC-001: the AUTHORITATIVE revision. The POS stored none
            // before this phase and sent none, so app.void_order's optimistic-
            // concurrency check could never fire and a cancel could land on an order
            // that had already moved (paid on another till, bumped by the kitchen).
            expectedRevision: widget.order.revision,
          );
      // The server confirmed the void -> mark the local order cancelled (drops
      // out of the unpaid count, no pay/reprint). Money-free.
      ref
          .read(posRecentOrdersControllerProvider.notifier)
          // BY IDENTITY: cancelling this order must not cancel a different one that
          // happens to share its printed code.
          .markVoided(widget.order.identity, reason);
      // POS-OPERATIONS-SYNC-001: void_order returns only {status, revision} — take
      // the authoritative snapshot so the row carries the server's terminal status
      // and revision, not just this device's local marker.
      await _reconcile();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posOrderCancelledSnack)),
      );
    } on VoidException catch (e) {
      if (!mounted) return;
      // POS-OPERATIONS-SYNC-001: a typed refusal means our picture of this order is
      // WRONG, and showing the right message on top of a stale row explains nothing.
      //
      //   order_not_voidable -> the server says it is already terminal. Reconcile, so
      //     the row goes terminal and STOPS offering Cancel at all. Telling the
      //     cashier "already closed" while leaving the Cancel button live would be a
      //     message that argues with its own screen.
      //   conflict           -> someone else moved it. Fetch the truth; NEVER blindly
      //     retry the mutation.
      //
      // permission_denied / already-paid / transport are NOT staleness: the order is
      // exactly as we thought, we simply may not do this to it. No refetch.
      if (e.notVoidable || e.conflict) {
        await _reconcile();
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Retire the sheet on the refusals a retry can never satisfy. Permission
        // denials, an already-paid order and transport failures are NOT staleness:
        // the order is exactly as we thought, so the same deliberate entry may be
        // retried once the obstacle is resolved.
        _staleAfterRefusal = e.notVoidable || e.conflict;
        // MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): TYPED dispatch on the server's
        // exact domain codes. The previous version INFERRED "already closed" from a
        // zero-total order whenever the rejection was generic — which meant a dropped
        // network could tell the operator an order was closed when it was not. Only the
        // server's `order_not_voidable` may ever claim that now; everything else stays
        // honestly distinct, and an unknown failure stays unknown.
        _error = switch (e) {
          VoidException(alreadyPaid: true) => l10n.posCancelPaidOrderError,
          VoidException(permissionDenied: true) =>
            l10n.posCancelPermissionDenied,
          VoidException(notVoidable: true) => l10n.posCancelOrderClosed,
          VoidException(conflict: true) => l10n.posCancelOrderConflict,
          // Transport, malformed envelope, and any unknown rejection: a generic,
          // retryable failure. We do NOT know the order's state and must not pretend to.
          _ => l10n.posCancelOrderFailed,
        };
      });
    }
  }

  /// Pulls the authoritative snapshot for THIS order. Never throws — the
  /// coordinator records its own failure, and a failed refresh must not turn a
  /// SUCCESSFUL void into an error the cashier sees.
  Future<void> _reconcile() async {
    final orderId = widget.order.orderId;
    if (orderId == null || orderId.isEmpty) return;
    await ref.read(posOrderSyncControllerProvider.notifier).refreshOrders(
      <String>[orderId],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final order = widget.order;
    final danger = RestoflowTone.danger.styleOf(theme).accent;

    final infoParts = <String>[
      order.orderNumber,
      // Null for a branch-discovered order — another till took it and we never saw
      // its customer. We show what we have, and invent nothing.
      if (order.order?.customerName case final name?
          when name.trim().isNotEmpty)
        name.trim(),
      MoneyFormatter.formatMinor(order.grandTotalMinor, order.currencyCode),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('cancel-order-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.block, color: danger),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.posCancelOrderAction,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            Text(
              // The order being cancelled — code · customer · total (LTR money).
              infoParts.join('  ·  '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            RestoflowNoticeBanner(
              key: const Key('cancel-order-warning'),
              tone: RestoflowTone.danger,
              icon: Icons.warning_amber_outlined,
              body: l10n.posCancelOrderWarning,
            ),
            const SizedBox(height: RestoflowSpacing.md),
            TextField(
              key: const Key('cancel-reason-field'),
              controller: _reasonController,
              enabled: !_submitting && !_staleAfterRefusal,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: l10n.posCancellationReasonLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                key: const Key('cancel-order-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: RestoflowIconSizes.sm,
                    color: danger,
                  ),
                  const SizedBox(width: RestoflowSpacing.xs),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isDemo) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              RestoflowNoticeBanner(
                body: l10n.posCancelDemoNote,
                tone: RestoflowTone.info,
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _staleAfterRefusal
                  // RETIRED. The revision this sheet holds is the one the server just
                  // refused (conflict), or the order is already terminal
                  // (order_not_voidable) — either way, no re-send from here can ever
                  // succeed. The typed message above says why; this button lets the
                  // cashier acknowledge it and act again from the refreshed order.
                  ? FilledButton.icon(
                      key: const Key('cancel-conflict-close-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.posOrdersConflictClose),
                      style: RestoflowButtonStyles.big(context),
                    )
                  : FilledButton.icon(
                      key: const Key('cancel-confirm-button'),
                      onPressed: _submitting ? null : () => _submit(l10n),
                      icon: _submitting
                          ? const RestoflowInlineSpinner()
                          : const Icon(Icons.block),
                      label: Text(l10n.posCancelOrderConfirm),
                      style: RestoflowButtonStyles.big(context).copyWith(
                        backgroundColor: WidgetStatePropertyAll(danger),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
