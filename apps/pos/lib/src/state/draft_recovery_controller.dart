import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import '../data/order_submission.dart' show OutboxEntry, OutboxSyncState;
import '../data/demo_tables.dart';
import 'cart_controller.dart';
import 'outbox_controller.dart';
import 'pos_session.dart' show posSyncSessionProvider;
import 'pos_sync_scope_provider.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 (A2) — the exact operational context a draft
/// recovery belongs to. A recovery is offered ONLY when the CURRENT context matches
/// its binding, so a different employee (a new PIN session), a re-pair into another
/// branch, or a different device can NEVER see or restore someone else's draft, its
/// customer name, or its notes.
///
/// [scopeKey] is the full operational scope (organization + restaurant + branch +
/// device); [pinSessionId] is the human PIN session — a new employee login mints a new
/// PIN session against the current device session, so it distinguishes the operator
/// (and the device-session/pairing) even on the same device. Both are null in demo /
/// unpaired mode, where there is a single implicit operator — a demo recovery therefore
/// matches only another demo context, never a real paired one.
class PosRecoveryBinding {
  const PosRecoveryBinding({this.scopeKey, this.pinSessionId});

  final String? scopeKey;
  final String? pinSessionId;

  /// EXACT match on every component — a recovery is never restored across a scope or
  /// PIN-session boundary.
  bool matches(PosRecoveryBinding other) =>
      other.scopeKey == scopeKey && other.pinSessionId == pinSessionId;

  @override
  bool operator ==(Object other) =>
      other is PosRecoveryBinding &&
      other.scopeKey == scopeKey &&
      other.pinSessionId == pinSessionId;

  @override
  int get hashCode => Object.hash(scopeKey, pinSessionId);
}

/// PILOT-OPERATIONS-CORRECTIONS-001 — a recoverable snapshot of ONE submit attempt,
/// kept until the server authoritatively ACCEPTS the order or the cashier deliberately
/// discards it. It exists so a permanently-rejected NEW order (item_unavailable) is not
/// a dead-end: the cashier can restore the exact draft (products, quantities, modifiers,
/// notes, order type, table, customer name) into the cart, correct it, and send a NEW
/// deliberate submit — never a retry of the same (server-ledgered, replay-only) rejected
/// operation identity.
///
/// Keyed by [outboxEntryId] in a MAP (not a single slot), so more than one pending
/// submit can each keep its own record: rejection A restores A and accepting/discarding
/// A clears only A — a later submit B never erases A.
class PosDraftRecovery {
  const PosDraftRecovery({
    required this.draft,
    required this.orderType,
    required this.outboxEntryId,
    required this.binding,
    this.table,
    this.customerName,
  });

  final CartDraftSnapshot draft;
  final OrderType orderType;

  /// The outbox entry id of the submit this draft belongs to — the record's key AND the
  /// exact identity used to locate a rejected shell in Recent Orders.
  final String outboxEntryId;

  /// The exact scope + PIN session this recovery may be restored in (A2).
  final PosRecoveryBinding binding;

  final DemoTable? table;
  final String? customerName;
}

/// The recovery store: a map of outbox-entry-id -> [PosDraftRecovery]. Multi-slot and
/// scope-bound — see [PosDraftRecovery].
class PosDraftRecoveryController
    extends Notifier<Map<String, PosDraftRecovery>> {
  @override
  Map<String, PosDraftRecovery> build() {
    // PILOT-OPERATIONS-CORRECTIONS-001 (Finding 3): CONTROLLER-SEAM cleanup of accepted
    // recoveries. Watching the outbox here — not a widget listener — means an order that
    // becomes APPLIED clears its recovery even if its confirmation was never opened, is
    // unmounted, or the app navigated away. This covers the "capture then applied" order
    // (a recovery stored while pending, later applied); the "applied before capture"
    // order is handled in [capture] below.
    ref.listen(outboxControllerProvider, (previous, next) {
      _clearApplied(next);
    });
    return const <String, PosDraftRecovery>{};
  }

  /// Capture the draft of a just-started submit under its own key. NEVER overwrites a
  /// different attempt — two pending submits keep independent records.
  ///
  /// Finding 3: if the submit is ALREADY applied by the time we capture (real-mode
  /// auto-push returned after the entry transitioned to applied), there is nothing to
  /// recover — do NOT store it. This closes the "applied before capture" race the
  /// outbox listener alone cannot see.
  void capture(PosDraftRecovery recovery) {
    final entry = ref
        .read(outboxControllerProvider.notifier)
        .entryById(recovery.outboxEntryId);
    if (entry != null && entry.syncState == OutboxSyncState.applied) return;
    state = <String, PosDraftRecovery>{
      ...state,
      recovery.outboxEntryId: recovery,
    };
  }

  /// Clear ONLY the record for [outboxEntryId] (after its restore, discard, or an
  /// accepted order). Other attempts' records are untouched.
  void clear(String outboxEntryId) {
    if (!state.containsKey(outboxEntryId)) return;
    state = <String, PosDraftRecovery>{
      for (final e in state.entries)
        if (e.key != outboxEntryId) e.key: e.value,
    };
  }

  /// Clear only if a record is held for [outboxEntryId] (used when that entry is
  /// ACCEPTED — a newer attempt's recovery must not be wiped). Same as [clear]; kept
  /// as a named alias for the acceptance call site's intent.
  void clearIfFor(String outboxEntryId) => clear(outboxEntryId);

  /// The recovery for [outboxEntryId] IF one is held AND it belongs to the [current]
  /// operational context — else null. This is the ONLY read path a restore may use, so
  /// employee B can never restore employee A's draft, nor see its customer name/notes.
  PosDraftRecovery? recoverable(
    String? outboxEntryId,
    PosRecoveryBinding current,
  ) {
    if (outboxEntryId == null) return null;
    final r = state[outboxEntryId];
    if (r == null) return null;
    return r.binding.matches(current) ? r : null;
  }

  /// Finding 3: clear the recovery of every APPLIED submit. Idempotent — a duplicate
  /// applied delivery finds nothing to clear. NEVER touches a pending, retryable-failed,
  /// or permanently-rejected (item_unavailable) entry, whose recovery must be retained.
  void _clearApplied(List<OutboxEntry> entries) {
    final applied = <String>{
      for (final e in entries)
        if (e.syncState == OutboxSyncState.applied) e.id,
    };
    if (applied.isEmpty) return;
    final next = <String, PosDraftRecovery>{
      for (final e in state.entries)
        if (!applied.contains(e.key)) e.key: e.value,
    };
    if (next.length != state.length) state = next;
  }
}

final posDraftRecoveryProvider =
    NotifierProvider<PosDraftRecoveryController, Map<String, PosDraftRecovery>>(
      PosDraftRecoveryController.new,
    );

/// The CURRENT operational binding — the scope + PIN session a recovery may be
/// captured against and restored in. Watched by the confirmation and the recent-orders
/// surface so that a PIN switch or branch/device re-pair immediately makes a prior
/// employee's recovery inaccessible (its binding no longer matches). Null components in
/// demo / unpaired mode.
final posRecoveryBindingProvider = Provider<PosRecoveryBinding>((ref) {
  final scopeKey = ref.watch(posSyncScopeProvider)?.key;
  final pinSessionId = ref.watch(posSyncSessionProvider)?.pinSessionId;
  return PosRecoveryBinding(scopeKey: scopeKey, pinSessionId: pinSessionId);
});
