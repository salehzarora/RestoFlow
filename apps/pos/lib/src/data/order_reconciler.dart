/// POS-OPERATIONS-SYNC-001 — the ONE place a server snapshot is merged into local
/// POS state.
///
/// PURE. No I/O, no clock, no providers — merge rules only, so every rule below is
/// directly testable and there is exactly one of each. The controller owns the
/// timing; this file owns the truth.
library;

import 'order_snapshot.dart';
import 'recent_order.dart';

/// The result of reconciling one page of authoritative snapshots.
class PosReconcileResult {
  const PosReconcileResult({
    required this.orders,
    required this.applied,
    required this.ignored,
  });

  /// The full, merged order list — build-in-memory-then-commit. The caller
  /// persists this as ONE write; nothing is mutated in place.
  final List<PosRecentOrder> orders;

  /// How many snapshots actually changed something (drives "was this a no-op?").
  final int applied;

  /// How many snapshots were deliberately NOT applied (older revision, local
  /// draft, terminal protection). Not an error — a rule doing its job.
  final int ignored;

  bool get changedAnything => applied > 0;
}

/// Merges authoritative server snapshots into the local order list.
///
/// THE RULES, in force order:
///
///   1. A snapshot NEVER creates a local draft and never overwrites one. A draft
///      was never submitted; the server has no opinion about it, and a snapshot
///      that appeared to match one would be a coincidence, not authority.
///
///   2. REVISION FIRST. A higher server revision always wins. At EQUAL revision a
///      newer `sync_at` may still update settlement — a payment bumps `sync_at`
///      WITHOUT bumping the order's revision, so this is the ONLY way a paid order
///      ever becomes "paid" on this device. An OLDER revision never wins.
///
///   3. A pending local operation is NEVER deleted, resolved or marked successful
///      by a snapshot. A snapshot that "looks compatible" with a queued payment is
///      not an acknowledgement of it — only the operation's own result is. The
///      snapshot refreshes AUTHORITATIVE fields and leaves the queue alone.
///
///   4. TERMINAL IS A RATCHET. Once the server says completed/cancelled/voided, an
///      OLDER snapshot can never re-open it. (Rule 2 already forbids this; it is
///      restated because silently re-opening a closed order would put live payment
///      and cancel buttons back on it.)
///
///   5. IDEMPOTENT. Applying the same page twice changes nothing, and a duplicate
///      page cannot duplicate an order — orders are keyed by SERVER order id.
///
///   6. A bounded page missing an order is NOT a deletion. Absence means nothing
///      here; only an explicit server status can retire an order.
///
/// [orders] is not mutated. A new list is returned.
PosReconcileResult reconcileSnapshots(
  List<PosRecentOrder> orders,
  List<PosOrderSnapshot> snapshots,
) {
  if (snapshots.isEmpty) {
    return PosReconcileResult(
      orders: List<PosRecentOrder>.of(orders),
      applied: 0,
      ignored: 0,
    );
  }

  // Index by SERVER order id. Local drafts have none and are therefore
  // structurally unreachable from a snapshot — rule 1 holds by construction, not
  // by a check that could be forgotten.
  final byOrderId = <String, int>{};
  for (var i = 0; i < orders.length; i++) {
    final id = orders[i].orderId;
    if (id != null && id.isNotEmpty) byOrderId[id] = i;
  }

  final next = List<PosRecentOrder>.of(orders);
  var applied = 0;
  var ignored = 0;

  for (final snap in snapshots) {
    final index = byOrderId[snap.orderId];
    if (index == null) {
      // The server knows an order this device does not. That is normal (another
      // till on the same branch took it) and it is NOT a draft. We do not
      // fabricate a local order from a snapshot in Commit 2: the recent-orders
      // surface is still "what THIS device did". Adopting foreign orders is the
      // operational centre's job (Commit 3), and doing it here would silently
      // change what the existing surface means.
      ignored++;
      continue;
    }

    final local = next[index];
    final merged = applySnapshot(local, snap);
    if (identical(merged, local)) {
      ignored++;
    } else {
      next[index] = merged;
      applied++;
    }
  }

  return PosReconcileResult(orders: next, applied: applied, ignored: ignored);
}

/// Applies ONE authoritative snapshot to ONE local order.
///
/// Returns the SAME instance (identical) when the snapshot carries no new
/// authority — that is how idempotency is both implemented and observable.
PosRecentOrder applySnapshot(PosRecentOrder local, PosOrderSnapshot snap) {
  // Rule 1 — a draft has no server identity; nothing to reconcile against.
  if (local.orderId == null || local.orderId != snap.orderId) return local;

  // Rule 2 — revision first, then the payment-aware cursor at equal revision.
  final known = local.snapshot;
  if (known != null && !snap.isNewerThan(known)) return local;

  // Rule 3 — the pending operation SURVIVES. We refresh authoritative fields and
  // deliberately do not touch the queue: a snapshot is not an acknowledgement.
  // The sync state only moves to `terminal` when the SERVER says so; a device
  // still holding a queued op keeps its pendingOperation marker so the UI can
  // keep telling the truth about it.
  final syncState = snap.isTerminal
      ? PosOrderSyncState.terminal
      : (local.syncState.hasPendingWork ||
            local.syncState == PosOrderSyncState.rejected)
      ? local.syncState
      : PosOrderSyncState.synchronized;

  return local.withServerSnapshot(snap, syncState: syncState);
}

/// THE canonical unpaid count (POS-OPERATIONS-SYNC-001).
///
/// This predicate existed in THREE places before, each re-deriving settlement from
/// the STALE submit-time total — which is exactly why a comped order sat in the
/// badge forever. There is now one.
///
/// An order is counted only when it BOTH still owes money AND is still
/// operationally relevant:
///   * `notChargeable` (a comp) owes nothing -> never counted.
///   * `paid` owes nothing -> never counted.
///   * a TERMINAL order (completed / cancelled / voided) is finished work, whatever
///     it owes -> never counted. A cancelled order is not a debt.
///   * a local DRAFT was never submitted -> never counted.
int unpaidOrderCount(Iterable<PosRecentOrder> orders) =>
    orders.where(isCountedUnpaid).length;

/// Whether [order] belongs in the cashier's unpaid badge. Exposed so the count,
/// the filters and (in Commit 3) the sections all ask the SAME question.
bool isCountedUnpaid(PosRecentOrder order) {
  if (order.syncState == PosOrderSyncState.localDraft) return false;
  if (order.isTerminal) return false;
  return order.settlement.owesMoney;
}
