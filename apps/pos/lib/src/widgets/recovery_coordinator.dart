import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/order_identity.dart';
import '../state/cart_controller.dart';
import '../state/draft_recovery_controller.dart';
import '../state/order_setup_controller.dart';
import '../state/recent_orders_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 (Finding 1B) — the ONE shared coordinator for
/// rejected-draft recovery, used identically by BOTH entry points: the rejected
/// [OrderConfirmation] surface and the Recent Orders sheet. It exists so the two never
/// implement inconsistent restore/discard logic (which is how "Keep current" ended up
/// resetting the current cart).
///
/// It receives the exact rejected recovery record (keyed by its outbox entry identity)
/// and the current cart / order-setup / scope state via [ref], and enforces:
///
///   * EMPTY current cart  -> restore the selected draft directly.
///   * NON-EMPTY current cart -> an explicit Replace / Keep-current / Cancel decision;
///     never a silent overwrite, never an automatic merge.
///   * Keep current -> leave the current cart + setup EXACTLY as they are; only retire
///     the selected shell + clear the selected recovery (never a cart/setup reset,
///     never a server void or cancellation audit).
///   * Cancel -> change nothing at all.
///   * Replace -> replace the cart once with the restored draft (order type, table,
///     customer name, lines/quantities/modifiers/notes); a resubmit mints a fresh
///     operation identity (a new submitOrderFromCart), never a retry of the ledgered
///     rejection.
class PosRecoveryCoordinator {
  const PosRecoveryCoordinator(this.ref);

  final WidgetRef ref;

  /// Restore [recovery] into the cart with current-cart protection. Returns the outcome
  /// so the caller can react (e.g. close the source sheet). [context] is used only to
  /// show the Replace / Keep-current / Cancel decision when the cart is non-empty.
  Future<PosRecoveryOutcome> restore(
    BuildContext context,
    PosDraftRecovery recovery,
  ) async {
    // Cart-safety (final): while a frozen addition attempt owns the cart the
    // recovery flow REFUSES UP FRONT — before any dialog, before any choice,
    // before any retirement. Without this, the non-empty locked cart reached
    // the Replace / Keep-current dialog and "Keep current" permanently
    // retired the shell + record while the addition was still in flight.
    // Nothing changes here: the cart, the addition attempt, the shell and the
    // recovery record all stay exactly as they are, and the same recovery
    // remains fully available after the lock releases.
    if (ref.read(cartControllerProvider).lockedByAddition) {
      return PosRecoveryOutcome.lockedByAddition;
    }
    // A non-empty cart (real lines) is work the operator built while this attempt was
    // pending — never silently overwrite it.
    if (ref.read(cartControllerProvider).isNotEmpty) {
      final choice = await _askRestoreChoice(context);
      if (!context.mounted) return PosRecoveryOutcome.cancelled;
      switch (choice) {
        case null:
        case _RestoreChoice.cancel:
          // Cancel: nothing changes — the shell and recovery both remain available.
          return PosRecoveryOutcome.cancelled;
        case _RestoreChoice.keepCurrent:
          // Keep current: retire the selected shell + clear ITS recovery ONLY. The
          // current cart and setup are left EXACTLY as they are — no reset, no void.
          _retire(recovery);
          return PosRecoveryOutcome.keptCurrent;
        case _RestoreChoice.replace:
          break; // fall through to the single restore below
      }
    }
    // Empty cart, or an explicit Replace: restore exactly once. Cart-safety:
    // while a frozen addition attempt owns the cart the restore REFUSES —
    // nothing is overwritten, the shell and its recovery both remain.
    final restored = ref
        .read(cartControllerProvider.notifier)
        .restoreDraft(recovery.draft);
    if (restored != CartMutationResult.applied) {
      return PosRecoveryOutcome.cancelled;
    }
    final setup = ref.read(orderSetupControllerProvider.notifier);
    setup.setOrderType(recovery.orderType);
    final table = recovery.table;
    if (table != null) setup.assignTable(table);
    setup.setCustomerName(recovery.customerName);
    _retire(recovery);
    return PosRecoveryOutcome.restored;
  }

  /// Discard [recovery]: retire its shell + clear ITS recovery ONLY. No server void, no
  /// cancellation audit, the current cart untouched, other recoveries untouched.
  void discard(PosDraftRecovery recovery) => _retire(recovery);

  /// Finding 1A + Finding 2: dismiss a rejected shell that is a TRUE ORPHAN — no recovery
  /// record exists for it under ANY binding (e.g. after a restart, when the in-memory
  /// recovery is gone but the persisted shell remains). Retires ONLY the shell; no server
  /// void, no cancellation audit.
  ///
  /// FAIL CLOSED (Finding 2): when a recovery still exists for [outboxEntryId] — this
  /// session's, or ANOTHER PIN session's — this refuses and returns false. A matching
  /// recovery must be resolved through [discard]/[restore]; a NON-matching one belongs to
  /// another session, and retiring its shell would strip that operator's only handle back
  /// to their rejected draft. Only its owner may resolve it. Returns true iff the orphan
  /// shell was actually retired.
  bool discardOrphanShell(PosOrderIdentity identity, {String? outboxEntryId}) {
    if (ref
        .read(posDraftRecoveryProvider.notifier)
        .hasRecoveryFor(outboxEntryId)) {
      return false; // a recovery is still held (possibly another session's) — keep it
    }
    ref
        .read(posRecentOrdersControllerProvider.notifier)
        .retireLocalRejected(identity);
    return true;
  }

  void _retire(PosDraftRecovery recovery) {
    // Retire the neverCreated shell by the EXACT submit/outbox identity, then clear the
    // exact matching recovery. Both key on recovery.outboxEntryId.
    ref
        .read(posRecentOrdersControllerProvider.notifier)
        .retireLocalRejectedByOutboxEntry(recovery.outboxEntryId);
    ref.read(posDraftRecoveryProvider.notifier).clear(recovery.outboxEntryId);
  }

  /// The explicit three-way choice shown when restoring would overwrite a non-empty
  /// cart. Shared by both entry points so the wording and options never drift.
  Future<_RestoreChoice?> _askRestoreChoice(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<_RestoreChoice>(
      context: context,
      builder: (dctx) => AlertDialog(
        key: const Key('recovery-replace-dialog'),
        title: Text(l10n.posRecoveryReplaceCartTitle),
        content: Text(l10n.posRecoveryReplaceCartBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(_RestoreChoice.cancel),
            child: Text(l10n.posShiftCancelAction),
          ),
          TextButton(
            key: const Key('recovery-keep-cart'),
            onPressed: () => Navigator.of(dctx).pop(_RestoreChoice.keepCurrent),
            child: Text(l10n.posRecoveryKeepCartAction),
          ),
          FilledButton(
            key: const Key('recovery-replace-cart'),
            onPressed: () => Navigator.of(dctx).pop(_RestoreChoice.replace),
            child: Text(l10n.posRecoveryReplaceCartAction),
          ),
        ],
      ),
    );
  }
}

/// The operator's explicit choice when restoring a rejected draft would overwrite a
/// non-empty current cart (Finding 1B current-cart protection).
enum _RestoreChoice { replace, keepCurrent, cancel }

/// The outcome of [PosRecoveryCoordinator.restore], so the caller can close its sheet.
enum PosRecoveryOutcome {
  restored,
  keptCurrent,
  cancelled,

  /// A frozen addition attempt owns the cart — the recovery flow was refused
  /// BEFORE any dialog or retirement; the shell and record remain available.
  lockedByAddition,
}
