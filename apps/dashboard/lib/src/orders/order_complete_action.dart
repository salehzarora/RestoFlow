/// The "Complete order" action — a RECOVERY step (ORDER-COMPLETION-001, reframed
/// by ORDER-AUTO-COMPLETION-001).
///
/// The ONE write the Dashboard performs on an order: move an eligible `served`
/// order to the canonical terminal state `completed`. It is deliberately NOT a
/// payment, a settlement, a refund, a void or a status picker — there is no
/// next-status choice anywhere, and the server hard-codes the target.
///
/// Since ORDER-AUTO-COMPLETION-001 a served order that is fully paid closes
/// ITSELF, so this action is no longer how an order normally ends: it is the
/// fallback for an order the rule did not close (one served and paid before the
/// rule existed, or one whose automatic step failed soft). When the order IS served
/// and fully paid, we say so plainly — reaching for this button means something is
/// off, and hiding that would be dishonest.
///
/// It appears ONLY when the order is eligible under the canonical state machine
/// (`served`), and only for a settlement role. For an UNPAID order it renders
/// DISABLED with a plain explanation (DECISION D-025: fulfillment closes only once
/// payment is completed) — and the server independently refuses, so the disabled
/// button is a courtesy, never the control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_completion_repository.dart';
import '../data/order_history_models.dart';
import '../state/dashboard_providers.dart';
import '../state/order_completion_providers.dart';

/// Whether [role] may settle orders — the SAME allowlist the server enforces
/// (`cashier` / `manager` / `restaurant_owner` / `org_owner`). `kitchen_staff` and
/// the read-only `accountant` may NOT.
///
/// A null membership is demo mode (there is no real identity to authorize), so the
/// action is offered; in real mode the server is the authority regardless — this
/// only decides whether the button is worth showing.
bool canCompleteOrders(MembershipRole? role) => switch (role) {
  null => true,
  MembershipRole.orgOwner ||
  MembershipRole.restaurantOwner ||
  MembershipRole.manager ||
  MembershipRole.cashier => true,
  MembershipRole.kitchenStaff || MembershipRole.accountant => false,
};

/// The completion action + its outcome, rendered inside the order detail sheet.
class OrderCompleteAction extends ConsumerWidget {
  const OrderCompleteAction({
    required this.detail,
    required this.l10n,
    super.key,
  });

  final OrderDetail detail;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ELIGIBILITY IS THE CANONICAL STATE, not the surface: only a `served` order
    // may be completed. submitted / accepted / preparing / ready / completed /
    // cancelled / voided all render nothing at all.
    if (detail.status != 'served') return const SizedBox.shrink();

    final role = ref.watch(dashboardMembershipProvider)?.role;
    if (!canCompleteOrders(role)) return const SizedBox.shrink();

    final state = ref.watch(orderCompletionControllerProvider(detail.orderId));
    // The SETTLEMENT test, not a marker test — the same one the server applies
    // (`app.order_is_fully_settled`): the completed payment must cover the order's
    // CURRENT total. An under-covered order is refused by the server, so offering an
    // enabled button for it would be a lie.
    final paid = detail.isFullySettled;

    if (state.completed) {
      return _Banner(
        key: const Key('order-complete-success'),
        tone: RestoflowTone.success,
        icon: Icons.check_circle_outline,
        message: l10n.ordersCompleteSuccess,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // D-025: an unpaid order cannot close. Explain WHY, rather than showing a
        // dead control with no reason.
        if (!paid)
          _Banner(
            key: const Key('order-complete-unpaid-blocked'),
            tone: RestoflowTone.warning,
            icon: Icons.schedule,
            message: l10n.ordersCompleteBlockedUnpaid,
          ),
        // Served AND fully paid, yet still open: the automatic rule should already
        // have closed this. Say so — this button is a recovery step, not routine.
        if (paid)
          _Banner(
            key: const Key('order-complete-recovery-note'),
            tone: RestoflowTone.info,
            icon: Icons.build_circle_outlined,
            message: l10n.ordersCompleteRecoveryNote,
          ),
        if (state.error != null)
          _Banner(
            key: const Key('order-complete-error'),
            tone: RestoflowTone.danger,
            icon: Icons.error_outline,
            message: _errorMessage(l10n, state.error!),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const Key('order-complete-button'),
            // Disabled while a request is in flight (no duplicate write) and for an
            // unpaid order (D-025). A null onPressed also removes it from the
            // focus traversal, so it cannot be activated by keyboard either.
            onPressed: (state.submitting || !paid)
                ? null
                : () => _confirmAndComplete(context, ref),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44), // ≥44dp hit target
              padding: const EdgeInsets.symmetric(
                horizontal: RestoflowSpacing.lg,
              ),
            ),
            icon: state.submitting
                ? const SizedBox(
                    width: RestoflowIconSizes.sm,
                    height: RestoflowIconSizes.sm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.task_alt_outlined),
            label: Text(l10n.ordersCompleteAction),
          ),
        ),
        // Retry is offered ONLY after a transport failure: a domain refusal would
        // just be refused again, and a write is never blind-retried.
        if (state.isRetryable && !state.submitting)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('order-complete-retry'),
              onPressed: () => ref
                  .read(
                    orderCompletionControllerProvider(detail.orderId).notifier,
                  )
                  .complete(),
              child: Text(l10n.ordersCompleteRetry),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAndComplete(BuildContext context, WidgetRef ref) async {
    // The ONE settlement predicate — the same one that gated the button.
    final settled = detail.isFullySettled;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('order-complete-confirm'),
        title: Text(l10n.ordersCompleteConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The SAFE order reference — never the order UUID.
            Text(l10n.ordersCompleteConfirmBody(detail.orderCode)),
            const SizedBox(height: RestoflowSpacing.md),
            Row(
              children: [
                Text(
                  l10n.ordersCompletePaymentLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                // THE SAME predicate that gates the button above — never a second
                // definition. A marker (`completedPayment != null`) would say
                // "Unpaid" for a settled ZERO-TOTAL order while the button next to it
                // was enabled, and would say "Paid" for an UNDER-COVERED one the
                // server will refuse. The dialog must not contradict its own gate.
                RestoflowStatusPill(
                  label: settled ? l10n.dashboardPaid : l10n.dashboardUnpaid,
                  tone: settled ? RestoflowTone.success : RestoflowTone.warning,
                  icon: settled ? Icons.check_circle_outline : Icons.schedule,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('order-complete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('order-complete-confirm-cta'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ordersCompleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(orderCompletionControllerProvider(detail.orderId).notifier)
        .complete();
  }
}

/// The localized message for a completion refusal. A raw technical error string is
/// NEVER shown to the user.
String _errorMessage(AppLocalizations l10n, OrderCompletionError error) =>
    switch (error) {
      OrderCompletionError.notPaid => l10n.ordersCompleteErrorNotPaid,
      OrderCompletionError.invalidState => l10n.ordersCompleteErrorInvalidState,
      OrderCompletionError.permissionDenied => l10n.ordersCompleteErrorDenied,
      OrderCompletionError.conflict => l10n.ordersCompleteErrorConflict,
      OrderCompletionError.notFound => l10n.ordersCompleteErrorNotFound,
      OrderCompletionError.transient => l10n.ordersCompleteErrorTransient,
    };

/// A toned, ICON + TEXT strip (never colour alone).
class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.message,
    super.key,
  });

  final RestoflowTone tone;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final style = tone.styleOf(Theme.of(context));
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: RestoflowSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(RestoflowSpacing.sm),
        decoration: BoxDecoration(
          color: style.container,
          borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: RestoflowIconSizes.sm, color: style.onContainer),
            const SizedBox(width: RestoflowSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: style.onContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
