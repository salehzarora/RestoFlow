import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/recent_order.dart';
import '../data/void_repository.dart';
import '../format/money_format.dart';
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

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    // Double-tap guard: the disabled button relies on a rebuild, so also refuse
    // re-entry synchronously — a cancel must never be pushed twice.
    if (_submitting) return;
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
          .voidOrder(orderId: widget.order.orderId ?? '', reason: reason);
      // The server confirmed the void -> mark the local order cancelled (drops
      // out of the unpaid count, no pay/reprint). Money-free.
      ref
          .read(posRecentOrdersControllerProvider.notifier)
          .markVoided(widget.order.orderNumber, reason);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.posOrderCancelledSnack)),
      );
    } on VoidException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.alreadyPaid
            ? l10n.posCancelPaidOrderError
            : e.permissionDenied
            ? l10n.posCancelPermissionDenied
            // MONEY-SETTLEMENT-CONSISTENCY-001: for a NON-CHARGEABLE (zero-total) order a
            // generic rejection is DETERMINISTICALLY the "already closed" case, so we can
            // name it instead of shrugging. The server refuses a void for exactly three
            // reasons: a role denial (returns permission_denied, handled above), a live
            // completed payment (returns alreadyPaid, handled above — and a zero-total
            // order can never have one, since the server now refuses a zero-value
            // payment), or an illegal source state, i.e. the order is already TERMINAL.
            // A comped order auto-completes on `served`, and this device is never told
            // (the POS does not pull orders back), so this is exactly the case that used
            // to surface as "Cancellation failed. Please try again." — advice that could
            // never work.
            : widget.order.isNonChargeable
            ? l10n.posCancelOrderClosed
            : l10n.posCancelOrderFailed;
      });
    }
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
      if (order.order.customerName case final name? when name.trim().isNotEmpty)
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
              enabled: !_submitting,
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
              child: FilledButton.icon(
                key: const Key('cancel-confirm-button'),
                onPressed: _submitting ? null : () => _submit(l10n),
                icon: _submitting
                    ? const RestoflowInlineSpinner()
                    : const Icon(Icons.block),
                label: Text(l10n.posCancelOrderConfirm),
                style: RestoflowButtonStyles.big(
                  context,
                ).copyWith(backgroundColor: WidgetStatePropertyAll(danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
