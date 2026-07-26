import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;

import '../data/order_submission.dart' show OutboxEntry, OutboxSyncState;
import '../data/demo_tables.dart';
import '../data/draft_recovery_store.dart';
import '../data/recent_order.dart' show PosRecentOrder;
import 'cart_controller.dart';
import 'outbox_controller.dart';
import 'pos_session.dart' show posSignedInEmployeeProfileIdProvider;
import 'pos_sync_scope_provider.dart';
import 'recent_orders_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 (A2) — the exact operational context a draft
/// recovery belongs to. A recovery is offered ONLY when the CURRENT context matches
/// its binding, so a different employee (a new PIN session), a re-pair into another
/// branch, or a different device can NEVER see or restore someone else's draft, its
/// customer name, or its notes.
///
/// [scopeKey] is the full operational scope (organization + restaurant + branch +
/// device) — all durably persisted, so it is IDENTICAL before and after a restart.
/// [employeeProfileId] (Codex #1) is the STABLE authenticated worker id (the server
/// device-staff roster id), which is the SAME for a worker across every PIN login —
/// so the SAME worker can reclaim their recovery after an app restart + re-login,
/// while a different worker (different employeeProfileId) or a different till/branch
/// (different scopeKey) cannot. The ephemeral pinSessionId is deliberately NOT part
/// of the durable ownership (a new one is minted per login, which is exactly why the
/// prior binding was unreclaimable after restart). Both are null in demo / unpaired
/// mode — a demo recovery matches only another demo context, never a real paired one.
class PosRecoveryBinding {
  const PosRecoveryBinding({this.scopeKey, this.employeeProfileId});

  final String? scopeKey;
  final String? employeeProfileId;

  /// EXACT match on both stable components — a recovery is never restored across a
  /// scope (org/restaurant/branch/device) or worker boundary.
  bool matches(PosRecoveryBinding other) =>
      other.scopeKey == scopeKey &&
      other.employeeProfileId == employeeProfileId;

  @override
  bool operator ==(Object other) =>
      other is PosRecoveryBinding &&
      other.scopeKey == scopeKey &&
      other.employeeProfileId == employeeProfileId;

  @override
  int get hashCode => Object.hash(scopeKey, employeeProfileId);

  /// MENU-ORDER-001 (Codex #1/#8/#9): durable serialization so the recovery's
  /// STABLE ownership survives a restart — gated to its scope + worker id (a
  /// different operator never sees it). No PIN / hash / token / JWT is persisted.
  Map<String, Object?> toJson() => <String, Object?>{
    if (scopeKey != null) 'scope_key': scopeKey,
    if (employeeProfileId != null) 'employee_profile_id': employeeProfileId,
  };

  /// Decode only the STABLE fields. A legacy record that carried the ephemeral
  /// `pin_session_id` decodes with a null worker id (it is NOT re-attributed) — it
  /// simply becomes unavailable and is cleaned by existing retention (Codex #2).
  static PosRecoveryBinding fromJson(Map<String, Object?> json) =>
      PosRecoveryBinding(
        scopeKey: json['scope_key']?.toString(),
        employeeProfileId: json['employee_profile_id']?.toString(),
      );
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
    this.correctionOutboxEntryId,
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

  /// MENU-ORDER-001 (Codex, correction-window durability): the outbox entry id of the
  /// CORRECTED resubmit this recovery is now the source of — set when the operator
  /// restores this rejected draft (Back to cart) and re-Sends it. It durably LINKS the
  /// source recovery to the corrected order so the recovery is cleared when that
  /// corrected order is authoritatively ACCEPTED — even across a crash between
  /// acceptance and local cleanup (the authoritative snapshot/outbox-applied signal
  /// keys on THIS corrected id, and the reconcile clears the source recovery through
  /// it). Null until a corrected resubmit; Back to cart alone never clears the record.
  final String? correctionOutboxEntryId;

  /// Returns a copy carrying the corrected resubmit's [correctedEntryId] link (D-008
  /// snapshots + stable line ids are untouched — only the correction pointer changes).
  PosDraftRecovery withCorrection(String correctedEntryId) => PosDraftRecovery(
    draft: draft,
    orderType: orderType,
    outboxEntryId: outboxEntryId,
    binding: binding,
    table: table,
    customerName: customerName,
    correctionOutboxEntryId: correctedEntryId,
  );

  /// MENU-ORDER-001 (Codex #8/#9): durable serialization so a permanently-
  /// rejected order's recovery — its draft (products, quantities, modifiers,
  /// notes, AND the Dashboard menu ranks), order type, table and customer name —
  /// survives an app restart. Restored under its [binding], so a different
  /// operator can never see it.
  Map<String, Object?> toJson() => <String, Object?>{
    'draft': draft.toJson(),
    'order_type': orderType.name,
    'outbox_entry_id': outboxEntryId,
    'binding': binding.toJson(),
    if (table != null) 'table': table!.toJson(),
    if (customerName != null) 'customer_name': customerName,
    if (correctionOutboxEntryId != null)
      'correction_outbox_entry_id': correctionOutboxEntryId,
  };

  static PosDraftRecovery fromJson(Map<String, Object?> json) {
    final rawTable = json['table'];
    final orderTypeName = (json['order_type'] ?? OrderType.takeaway.name)
        .toString();
    return PosDraftRecovery(
      draft: CartDraftSnapshot.fromJson(
        (json['draft'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      orderType: OrderType.values.firstWhere(
        (t) => t.name == orderTypeName,
        orElse: () => OrderType.takeaway,
      ),
      outboxEntryId: (json['outbox_entry_id'] ?? '').toString(),
      binding: PosRecoveryBinding.fromJson(
        (json['binding'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      table: rawTable is Map
          ? DemoTable.fromJson(rawTable.cast<String, Object?>())
          : null,
      customerName: json['customer_name']?.toString(),
      // Backward-compatible: a record written before the correction-window fix has
      // no link (null) and decodes as a plain, fully-recoverable rejected draft.
      correctionOutboxEntryId: json['correction_outbox_entry_id']?.toString(),
    );
  }
}

/// The recovery store: a map of outbox-entry-id -> [PosDraftRecovery]. Multi-slot and
/// scope-bound — see [PosDraftRecovery].
class PosDraftRecoveryController
    extends Notifier<Map<String, PosDraftRecovery>> {
  // MENU-ORDER-001 (Codex #8/#9): the durable store (default in-memory; real app
  // overrides with a SharedPrefs store). NOT `late final` — build() re-runs on
  // the same instance.
  PosDraftRecoveryStore _store = InMemoryDraftRecoveryStore();
  bool _disposed = false;

  @override
  Map<String, PosDraftRecovery> build() {
    _store = ref.watch(posDraftRecoveryStoreProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // PILOT-OPERATIONS-CORRECTIONS-001 (Finding 3): CONTROLLER-SEAM cleanup of accepted
    // recoveries. Watching the outbox here — not a widget listener — means an order that
    // becomes APPLIED clears its recovery even if its confirmation was never opened, is
    // unmounted, or the app navigated away. This covers the "capture then applied" order
    // (a recovery stored while pending, later applied); the "applied before capture"
    // order is handled in [capture] below.
    ref.listen(outboxControllerProvider, (previous, next) {
      _clearApplied(next);
    });
    // Finding 4: an AUTHORITATIVE server snapshot for a device-owned order proves the
    // order exists (was accepted) — clear its recovery even when the local outbox entry
    // never reached `applied` (e.g. a lost submit response). A second controller-seam
    // listener, so no widget is required and the two acceptance signals (outbox-applied
    // AND server-snapshot) are both honoured.
    ref.listen(posRecentOrdersControllerProvider, (previous, next) {
      _clearAcceptedBySnapshot(next);
    });
    // MENU-ORDER-001 (Codex #8/#9): rehydrate any persisted recoveries so a
    // permanently-rejected order (item_unavailable) survives a restart — Back to
    // cart restores the exact draft, IN Dashboard menu order.
    _load();
    return const <String, PosDraftRecovery>{};
  }

  /// MENU-ORDER-001 (Codex #8/#9): load the durable recoveries UNDER the current
  /// in-session state (in-session wins), so a restart rehydrates the map while a
  /// recovery captured this session is never clobbered. Never throws.
  Future<void> _load() async {
    Map<String, PosDraftRecovery> loaded;
    try {
      loaded = await _store.load();
    } catch (_) {
      return;
    }
    if (_disposed || loaded.isEmpty) return;
    state = <String, PosDraftRecovery>{...loaded, ...state};
  }

  /// MENU-ORDER-001 (Codex #8/#9): persist the current map (fire-and-forget; a
  /// durability wobble must never break the till). A CLEARED recovery is also
  /// persisted, so an accepted/discarded order does not resurrect on restart.
  void _persist() {
    if (_disposed) return;
    unawaited(_store.persist(state).catchError((Object _) {}));
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
    _persist();
  }

  /// Clear ONLY the record for [outboxEntryId] (after its restore, discard, or an
  /// accepted order). Other attempts' records are untouched.
  void clear(String outboxEntryId) {
    if (!state.containsKey(outboxEntryId)) return;
    state = <String, PosDraftRecovery>{
      for (final e in state.entries)
        if (e.key != outboxEntryId) e.key: e.value,
    };
    _persist();
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

  /// Finding 2: whether a recovery record exists for [outboxEntryId] under ANY binding
  /// (not only the current one). This distinguishes a TRUE orphan shell — no recovery
  /// held anywhere, e.g. after a restart cleared the in-memory map — from a shell whose
  /// recovery belongs to ANOTHER session (a different PIN/scope). Only the former may be
  /// locally dismissed; the latter must stay intact so its owner can still recover it.
  bool hasRecoveryFor(String? outboxEntryId) =>
      outboxEntryId != null && state.containsKey(outboxEntryId);

  /// MENU-ORDER-001 (correction-window durability): durably LINK the source recovery
  /// [sourceOutboxEntryId] to its corrected resubmit [correctedOutboxEntryId] BEFORE the
  /// source can be cleared. If a crash lands between the corrected order's server
  /// acceptance and local cleanup, the authoritative snapshot / outbox-applied signal
  /// for [correctedOutboxEntryId] still clears the source THROUGH this link on the next
  /// startup (see [_clearForAccepted]). No-op when the source is already gone.
  void markCorrectedSubmit(
    String sourceOutboxEntryId,
    String correctedOutboxEntryId,
  ) {
    final source = state[sourceOutboxEntryId];
    if (source == null || sourceOutboxEntryId == correctedOutboxEntryId) return;
    state = <String, PosDraftRecovery>{
      ...state,
      sourceOutboxEntryId: source.withCorrection(correctedOutboxEntryId),
    };
    _persist();
  }

  /// MENU-ORDER-001 (correction-window durability): the source recovery has been
  /// RESOLVED by its corrected resubmit (accepted, or superseded by a fresh rejected
  /// attempt) — clear its record AND retire its Recent-Orders rejected shell. Only the
  /// exact source is touched; idempotent. Back to cart itself never calls this — only a
  /// resubmit or an authoritative acceptance does.
  void resolveCorrectedSource(String sourceOutboxEntryId) {
    clear(sourceOutboxEntryId);
    _retireShell(sourceOutboxEntryId);
  }

  /// Retire the rejected shell for [outboxEntryId], deferred to a microtask so it is
  /// safe to call from WITHIN the recent-orders listener (never mutate a provider during
  /// its own notification). Swallows a disposed-container race.
  void _retireShell(String outboxEntryId) {
    Future<void>.microtask(() {
      if (_disposed) return;
      try {
        ref
            .read(posRecentOrdersControllerProvider.notifier)
            .retireLocalRejectedByOutboxEntry(outboxEntryId);
      } catch (_) {}
    });
  }

  /// Finding 3: clear the recovery of every APPLIED submit. Idempotent — a duplicate
  /// applied delivery finds nothing to clear. NEVER touches a pending, retryable-failed,
  /// or permanently-rejected (item_unavailable) entry whose recovery must be retained —
  /// UNLESS that recovery is the SOURCE of a corrected resubmit that just applied (its
  /// correctionOutboxEntryId link, so the accepted correction clears its source).
  void _clearApplied(List<OutboxEntry> entries) {
    final applied = <String>{
      for (final e in entries)
        if (e.syncState == OutboxSyncState.applied) e.id,
    };
    if (applied.isEmpty) return;
    _clearForAccepted(applied);
  }

  /// Finding 4: clear the recovery of every order the SERVER has authoritatively
  /// snapshotted (the order exists → it was accepted), keyed by the EXACT outbox entry
  /// the submit view carries. A permanently-rejected shell has NO snapshot (the order
  /// was never created), so its OWN recovery is never cleared here — but a source
  /// recovery WHOSE corrected resubmit was accepted IS cleared through its link (the
  /// accepted-then-crash reconcile). Idempotent; touches only matching entries.
  void _clearAcceptedBySnapshot(List<PosRecentOrder> orders) {
    final accepted = <String>{
      for (final o in orders)
        if (o.snapshot != null && o.order?.outboxEntryId != null)
          o.order!.outboxEntryId!,
    };
    if (accepted.isEmpty) return;
    _clearForAccepted(accepted);
  }

  /// Shared acceptance cleanup: clear every recovery whose OWN key OR whose
  /// correctionOutboxEntryId LINK is in [acceptedEntryIds] (its corrected order was
  /// authoritatively accepted), and retire each cleared recovery's rejected shell.
  /// Idempotent — nothing matched leaves the map untouched.
  void _clearForAccepted(Set<String> acceptedEntryIds) {
    final removed = <String>[];
    final next = <String, PosDraftRecovery>{};
    for (final e in state.entries) {
      final rec = e.value;
      final correctionId = rec.correctionOutboxEntryId;
      final isAccepted =
          acceptedEntryIds.contains(e.key) ||
          (correctionId != null && acceptedEntryIds.contains(correctionId));
      if (isAccepted) {
        removed.add(e.key);
      } else {
        next[e.key] = rec;
      }
    }
    if (removed.isEmpty) return;
    state = next;
    _persist();
    for (final key in removed) {
      _retireShell(key);
    }
  }
}

/// MENU-ORDER-001 (Codex #8/#9): the draft-recovery persistence seam. Default:
/// in-memory (demo mode / tests — session only). The real app overrides this in
/// `main.dart` with a [SharedPrefsDraftRecoveryStore] so a rejected order's
/// recovery (and its Dashboard menu ranks) survives a refresh / restart. Kept a
/// singleton so the in-memory data survives controller rebuilds within a session.
final posDraftRecoveryStoreProvider = Provider<PosDraftRecoveryStore>(
  (ref) => InMemoryDraftRecoveryStore(),
);

final posDraftRecoveryProvider =
    NotifierProvider<PosDraftRecoveryController, Map<String, PosDraftRecovery>>(
      PosDraftRecoveryController.new,
    );

/// The CURRENT operational binding — the STABLE scope (org/restaurant/branch/device)
/// + STABLE worker id (employeeProfileId) a recovery may be captured against and
/// restored in. Watched by the confirmation and the recent-orders surface so that a
/// DIFFERENT worker signing in, or a branch/device re-pair, immediately makes a prior
/// employee's recovery inaccessible (its binding no longer matches) — while the SAME
/// worker re-signing-in (even with a fresh pinSessionId, e.g. after a restart) still
/// matches and can reclaim it. Null components in demo / unpaired mode.
final posRecoveryBindingProvider = Provider<PosRecoveryBinding>((ref) {
  final scopeKey = ref.watch(posSyncScopeProvider)?.key;
  final employeeProfileId = ref.watch(posSignedInEmployeeProfileIdProvider);
  return PosRecoveryBinding(
    scopeKey: scopeKey,
    employeeProfileId: employeeProfileId,
  );
});
