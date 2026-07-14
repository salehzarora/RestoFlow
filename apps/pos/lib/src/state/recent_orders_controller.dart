import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_identity.dart';
import '../data/order_reconciler.dart';
import '../data/order_snapshot.dart';
import '../data/payment.dart';
import '../data/recent_order.dart';
import '../data/recent_orders_store.dart';
import '../data/sync_cursor_store.dart' show PosSyncScope;
import 'payment_controller.dart';
import 'pos_sync_scope_provider.dart';
import 'submitted_order_view.dart';

/// POS-ORDERS-AND-PAYMENT-001: the cashier's recent/unpaid-orders list.
///
/// Populated from what THIS device submits ([recordSubmitted]) and settles
/// (reactively, by watching [paymentControllerProvider]), persisted per device
/// (real mode) so a "today + yesterday" window survives a restart. Honest and
/// fail-closed: it holds only real orders the device created — never fabricated
/// data — and shows paid/unpaid from the recorded payment (the POS does not pull
/// live fulfillment status, so it does not invent Ready/Delivered states). Money
/// is the stored snapshot, never recomputed.
class PosRecentOrdersController extends Notifier<List<PosRecentOrder>> {
  // NOT `late final`: build() re-runs on the SAME instance whenever the watched scope
  // changes, and a `late final` would throw on the second assignment.
  PosRecentOrdersStore _store = InMemoryRecentOrdersStore();

  /// The FULL operational scope key — organization + restaurant + branch + device.
  ///
  /// It used to be the device id ALONE, while the sync cursor already used the full
  /// scope. A till re-paired into another branch therefore kept the same storage key
  /// and was served branch A's orders while sitting in branch B.
  String _scopeKey = '';
  bool _disposed = false;

  /// THE SCOPE GENERATION — which is not the same question as the scope KEY.
  ///
  /// Keying the store correctly was necessary and not sufficient. An asynchronous load
  /// or write STARTED in branch A is still in flight when the till is re-paired into
  /// branch B: it resumes, finds a controller that is now B's, and writes A's orders
  /// into B's state and B's storage. The key was right and the DATA still crossed the
  /// branch boundary, because nothing bound the RESULT to the scope it was fetched FOR.
  ///
  /// Every scope change bumps this counter, which invalidates every operation started
  /// under the previous one. A stale result is DISCARDED — silently. It is not an
  /// error: nothing failed, the question simply stopped being ours to answer, and
  /// showing branch B a red banner about branch A's fetch would be a lie about B.
  int _generation = 0;

  /// True when work begun at [gen], for the scope [scopeKey], may no longer touch state
  /// or storage.
  ///
  /// A PLAIN FIELD COMPARISON, deliberately: Riverpod forbids any `ref` access between a
  /// dependency changing and the provider rebuilding, which is exactly the window a
  /// stale response lands in. The generation is advanced EAGERLY by the scope listener
  /// in [build] instead, so it is already correct when an awaited continuation resumes.
  bool _isStale(int gen, String scopeKey) =>
      _disposed || gen != _generation || scopeKey != _scopeKey;

  /// Only today + yesterday are surfaced (a lightweight cashier window, not a
  /// heavy history); older orders are pruned on load/update. Capped to bound the
  /// persisted size on a very busy day.
  static const int _maxOrders = 200;

  @override
  List<PosRecentOrder> build() {
    _store = ref.watch(posRecentOrdersStoreProvider);
    // WATCHED, not read. When the branch/device/session changes this provider
    // rebuilds, state resets to empty, and _recover() loads THAT scope's cache — so
    // the previous branch's orders cannot linger on screen. `ref.read` here (the old
    // behaviour) froze the scope at first build and never looked again.
    // LISTENED as well as watched: the listener fires the moment the scope changes, so
    // the generation has already advanced by the time an in-flight load or persist
    // resumes — without this controller touching `ref` in the window where Riverpod
    // forbids it.
    ref.listen<PosSyncScope?>(
      posSyncScopeProvider,
      (previous, next) => _onScopeChanged(next?.key ?? ''),
    );
    _onScopeChanged(ref.watch(posSyncScopeProvider)?.key ?? '');
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // Reactively attach a payment to its recent order the moment it is recorded
    // (covers the current-order pay-now path AND pay-later from this surface).
    ref.listen<PaymentState>(
      paymentControllerProvider,
      (previous, next) => _syncPayments(next),
    );
    _recover();
    return const <PosRecentOrder>[];
  }

  /// A DIFFERENT SCOPE IS A DIFFERENT WORLD. Everything begun for the previous one is
  /// obsolete: the counter moves, and every in-flight load or persist started under it
  /// discards itself when it resumes.
  void _onScopeChanged(String key) {
    if (key == _scopeKey) return;
    _generation++;
    _scopeKey = key;
    // _owedWrites is deliberately NOT touched: each scope's debt is keyed by that
    // scope and waits for its owner to return. Forgetting it here is exactly how
    // A's unsaved day used to vanish across A -> B -> A.
  }

  /// Loads any persisted recent orders (real mode) and merges them under the
  /// in-session state, then applies the current payments. Never throws.
  ///
  /// BOUND TO THE SCOPE IT STARTED FOR. A load begun in branch A that completes after
  /// the till has been re-paired into branch B is DISCARDED: branch A's day must not
  /// appear on branch B's till, and it must not overwrite the recovery B has already
  /// begun for itself.
  Future<void> _recover() async {
    final gen = _generation;
    final scopeKey = _scopeKey;
    // NO SCOPE, NO BUCKET. An unpaired/restoring till has no branch, and `''` is not a
    // branch — it is a REAL, SHARED storage key that every scopeless moment writes to
    // and reads from. Unpair a till from branch A (scope goes null), re-pair it into
    // branch B, and the load during that window would hand branch A's orders straight to
    // branch B, with no race required at all. A till that does not know where it is
    // loads nothing and stores nothing.
    if (scopeKey.isEmpty) return;
    List<PosRecentOrder> loaded;
    try {
      loaded = await _store.load(scopeKey);
    } catch (_) {
      return;
    }
    if (_isStale(gen, scopeKey)) return; // the till moved on; this is not ours

    // KEYED BY IDENTITY, NOT BY DISPLAY CODE. Two persisted orders that happen to share
    // a `#XXXXXX` are two orders: keying this map on the code silently collapsed them
    // into one on every restart, and one of the cashier's real orders vanished.
    final byIdentity = <String, PosRecentOrder>{
      for (final o in loaded) o.identity.key: o,
    };
    // THE OWED SNAPSHOT PARTICIPATES IN RECOVERY. If this scope still owes the disk
    // a write, the owed rows are NEWER than anything the store returned — they are
    // the very rows the store refused. They carry the order-time lines, payment
    // markers and void reasons a server re-fetch cannot reconstruct, so they win
    // over the loaded (stale) copies here; the debt itself stays booked until a
    // write actually lands.
    final owed = _owedWrites[scopeKey];
    if (owed != null) {
      for (final o in owed) {
        byIdentity[o.identity.key] = o;
      }
    }
    // In-session state (if any) wins over the persisted copy — with ONE exception.
    // If the first pull raced this recovery and landed BEFORE the load completed, it
    // reconciled against an EMPTY list and adopted this device's own orders as
    // BRANCH-DISCOVERED: lineless shells with no receipt, no payment marker, no void
    // reason. Letting such a shell overwrite the loaded device-owned row would
    // permanently strip the day of its receipts. Where that happened, the loaded row
    // is kept and the shell's SNAPSHOT is merged into it through the ONE reconciler
    // rule — exactly what would have happened had recovery won the race.
    for (final o in state) {
      final key = o.identity.key;
      final recovered = byIdentity[key];
      final shellSnap = o.snapshot;
      if (recovered != null &&
          o.origin == PosOrderOrigin.branchDiscovered &&
          recovered.order != null &&
          shellSnap != null) {
        byIdentity[key] = applySnapshot(recovered, shellSnap);
      } else {
        byIdentity[key] = o;
      }
    }
    _apply(byIdentity.values.toList(), persist: false);
    _syncPayments(ref.read(paymentControllerProvider));
  }

  /// Records a freshly-submitted order as UNPAID (idempotent per order number).
  /// Best-effort: a persistence failure never surfaces into the submit path.
  void recordSubmitted(SubmittedOrderView view) {
    // Replace by IDENTITY, not by display code. `orderNumber` is a shortened human
    // reference and is NOT unique: keying on it here meant a second, genuinely
    // different order with the same code silently EVICTED the first from the till.
    final incoming = PosRecentOrder(order: view, submittedAt: DateTime.now());
    final key = incoming.identity.key;
    final existing = <PosRecentOrder>[
      for (final o in state)
        if (o.identity.key != key) o,
    ];
    final payment = ref
        .read(paymentControllerProvider)
        .paymentFor(view.identity);
    final order = PosRecentOrder(
      order: view,
      submittedAt: incoming.submittedAt,
      payment: payment,
    );
    _apply(<PosRecentOrder>[order, ...existing]);
  }

  /// Attaches [payment] to a stored unpaid order (no-op if unknown/already paid,
  /// or MONEY-VOID-001 already cancelled — a voided order is terminal and can
  /// never be marked paid).
  /// [orderStatus] is the order's CANONICAL status as the server reported it in the
  /// payment envelope (`record_payment` returns `order_status`, which is `completed`
  /// when the served + fully-settled rule auto-closed the order). Storing it is how this
  /// device learns an order became terminal, so it stops offering Cancel on it.
  /// Attaches [payment] to the order identified by [identity] — NOT by display code.
  /// Money is filed against the order it was taken for, and against no other.
  void recordPayment(
    PosOrderIdentity identity,
    CashPayment payment, {
    String? orderStatus,
  }) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      if (o.identity == identity && o.payment == null && !o.isVoided) {
        next.add(o.copyWith(payment: payment, status: orderStatus));
        changed = true;
      } else {
        next.add(o);
      }
    }
    if (!changed) return;
    _apply(next);
  }

  /// MONEY-VOID-001: marks a stored order CANCELLED (voided) after the server
  /// confirms the void. No-op if the order is unknown, already paid, or already
  /// voided (a paid order cannot be voided in the MVP — the server rejects it,
  /// so this never runs for one). The order stays in the list under a
  /// "Cancelled" pill (auditable) but drops out of the unpaid count and can no
  /// longer be paid or reprinted as a receipt.
  void markVoided(PosOrderIdentity identity, String reason) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      // The SERVER already decided (this only runs after it confirmed the void), so this
      // guard must not re-derive policy — it only stops a double write. It checks the
      // PAYMENT MARKER, not settlement, because a live completed payment is exactly what
      // the server's void guard blocks on; a NON-CHARGEABLE order carries none and is
      // genuinely voidable while it is still active.
      //
      // Matched by IDENTITY: voiding an order must never cancel a DIFFERENT order that
      // merely shares its printed code.
      if (o.identity == identity && !o.isVoided && o.payment == null) {
        next.add(
          o.copyWith(
            voidedAt: DateTime.now(),
            voidReason: reason,
            status: 'voided',
          ),
        );
        changed = true;
      } else {
        next.add(o);
      }
    }
    if (!changed) return;
    _apply(next);
  }

  /// The current recent order with [identity], or null.
  PosRecentOrder? orderFor(PosOrderIdentity identity) {
    for (final o in state) {
      if (o.identity == identity) return o;
    }
    return null;
  }

  /// THE unpaid count (drives the app-bar badge).
  ///
  /// POS-OPERATIONS-SYNC-001: delegates to the ONE canonical predicate in
  /// `order_reconciler.dart`. This logic previously existed in three places, each
  /// re-deriving settlement from the STALE submit-time total — which is exactly how
  /// a comped order stayed in the badge forever. There is now one, and it is
  /// SERVER-authoritative.
  int get unpaidCount => unpaidOrderCount(state);

  /// POS-OPERATIONS-SYNC-001 — applies AUTHORITATIVE server snapshots.
  ///
  /// Build-in-memory, validate, then commit as ONE persistence write. Returns false
  /// if persistence failed, which is the caller's signal NOT to advance the pull
  /// cursor: the cursor only moves forward, so advancing past data we failed to
  /// store would lose it permanently.
  ///
  /// A queued operation is NEVER deleted or resolved here — a snapshot is not an
  /// acknowledgement (see order_reconciler.dart, rule 3).
  Future<bool> applySnapshots(List<PosOrderSnapshot> snapshots) async {
    // NOTHING WAS STORED, so the caller must NOT advance its cursor past these rows.
    // Returning `true` here (the old behaviour) told the coordinator the page was
    // durable when the controller was gone and nothing had been written at all.
    if (_disposed) return false;

    // The scope these rows are being applied INTO, captured before anything can move.
    final gen = _generation;
    final scopeKey = _scopeKey;
    final store = _store;

    // A SCOPELESS TILL HAS NOWHERE TO PUT THESE. `''` is a shared bucket, not a branch;
    // writing a branch's authoritative orders into it is how they resurface on the NEXT
    // branch this device is paired to.
    if (scopeKey.isEmpty) return false;

    if (snapshots.isEmpty) {
      // AN EMPTY PAGE IS ONLY A SUCCESS IF WE OWE THE DISK NOTHING. "Nothing changed"
      // is a statement about the SERVER; if a previous durable write failed, memory
      // and disk still disagree, and reporting success here let a quiet server clear
      // the persistence error while the cashier's day remained unstored. If a write
      // is owed, this is the retry.
      final owed = _owedWrites[scopeKey];
      if (owed == null) return true;
      // Persist the UNION of the owed snapshot and the current state, keyed by
      // identity with the CURRENT state winning where both hold a row. The owed
      // rows alone could miss local writes made since the failure; the state alone
      // could be EMPTY if this retry races startup recovery — and writing [] over
      // the stored day while clearing the debt would be the exact loss this map
      // exists to prevent.
      final byIdentity = <String, PosRecentOrder>{
        for (final o in owed) o.identity.key: o,
        for (final o in state) o.identity.key: o,
      };
      final rows = _sortedPruned(byIdentity.values.toList());
      try {
        await store.persist(scopeKey, rows);
        // Clear the debt ONLY if it is still the exact snapshot this write
        // incorporated. A NEWER debt booked while the write was in flight (a
        // local write the disk refused a moment ago) is not paid off by the
        // completion of an OLDER one — object identity is the version token.
        if (identical(_owedWrites[scopeKey], owed)) {
          _owedWrites.remove(scopeKey);
        }
        return true;
      } catch (_) {
        return _isStale(gen, scopeKey);
      }
    }

    // THE MERGE BASIS IS EVERYTHING THIS SCOPE KNOWS LOCALLY — the live state AND
    // any owed unsaved rows. Reconciling against the state alone lost data in one
    // exact window: back in a scope whose recovery load was still pending, the
    // state was momentarily EMPTY while the owed map held the scope's rich
    // deviceOwned rows (order-time lines, payment/receipt truth, local operation
    // identity — everything a server page cannot carry). A NON-EMPTY page landing
    // in that window was adopted as a lineless branchDiscovered SHELL, the shell
    // was persisted, and the debt was cleared — the known rich truth discarded
    // within the same process lifetime. With the owed rows in the basis, the
    // canonical reconciler does what it always does for a deviceOwned row: keeps
    // the local structure and applies the server's authoritative fields on top.
    // Matching is by AUTHORITATIVE SERVER ORDER ID (the reconciler's only key) —
    // never the display code.
    final owedAtMerge = _owedWrites[scopeKey];
    final List<PosRecentOrder> base;
    if (owedAtMerge == null) {
      base = state;
    } else {
      final byIdentity = <String, PosRecentOrder>{
        for (final o in owedAtMerge) o.identity.key: o,
        // The live state wins where both hold a row: it is the same lineage,
        // strictly newer.
        for (final o in state) o.identity.key: o,
      };
      base = byIdentity.values.toList();
    }

    final result = reconcileSnapshots(base, snapshots);
    if (!result.changedAnything && owedAtMerge == null) {
      // IDEMPOTENT: re-applying the same page is a genuine no-op — no state
      // churn, no rewrite, no rebuild.
      return true;
    }
    // ...UNLESS THE LAST DURABLE WRITE FAILED. Then "nothing changed" is true only of
    // MEMORY: the disk still does not have these rows. Returning success here is how a
    // retry after a persistence failure quietly re-reported success, cleared the error,
    // stamped a fresh sync time — and lost the rows anyway at the next restart. If we
    // owe the disk a write, we attempt it, whatever reconciliation thinks.
    final merged = result.changedAnything
        ? _sortedPruned(result.orders)
        : _sortedPruned(base);
    if (_disposed) return false;
    state = merged;
    try {
      // PERSIST UNDER THE CAPTURED KEY, never under whatever `_scopeKey` happens to say
      // by the time the write runs. Reading the field here would let a branch switch
      // mid-write file branch A's orders under branch B's key — the very leak the
      // scoped key exists to prevent, reintroduced one await later.
      await store.persist(scopeKey, merged);
      // The debt is paid ONLY if this write actually incorporated it — i.e. the
      // owed snapshot is still the one that entered the merge basis above. A
      // NEWER debt booked while this write was in flight survives it.
      if (identical(_owedWrites[scopeKey], owedAtMerge)) {
        _owedWrites.remove(scopeKey);
      }
      return true;
    } catch (_) {
      // BOOK THE DEBT UNDER THE CAPTURED KEY — even when the scope has since moved
      // on. These rows are the captured scope's newest unsaved truth, and they are
      // what recovery merges back when that scope returns.
      _owedWrites[scopeKey] = merged;
      // The in-memory state is still correct and usable; only durability failed.
      // Report it so the cursor stays put and the same page is re-delivered next
      // time, rather than being silently skipped.
      //
      // UNLESS the scope moved on: then this write was for a branch we have left, its
      // failure says nothing about the branch we are now in, and reporting it would
      // raise a persistence alarm on a till that is perfectly healthy.
      return _isStale(gen, scopeKey);
    }
  }

  /// Records a SAFE, typed server refusal against an order (e.g.
  /// `order_not_chargeable`), so the UI can explain it instead of silently
  /// re-submitting a request the server has already refused.
  void recordSyncRefusal(PosOrderIdentity identity, String reason) {
    var changed = false;
    final next = <PosRecentOrder>[
      for (final o in state)
        if (o.identity == identity && !changed)
          () {
            changed = true;
            return o.copyWith(
              syncState: PosOrderSyncState.rejected,
              lastSyncError: reason,
            );
          }()
        else
          o,
    ];
    if (changed) _apply(next);
  }

  void _syncPayments(PaymentState ps) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      // MONEY-VOID-001: never reactively attach a payment to a cancelled order.
      if (o.payment == null && !o.isVoided) {
        // BY IDENTITY. This lookup used the display code, so a payment taken for one
        // order was reactively stamped onto EVERY row sharing that code — the clearest
        // possible way to mark an unpaid order paid without anyone paying for it.
        final p = ps.paymentFor(o.identity);
        if (p != null) {
          // Learn the order's CANONICAL status from the server's payment envelope, so a
          // payment that auto-closed the order stops this device offering Cancel on it.
          next.add(o.copyWith(payment: p, status: p.orderStatus));
          changed = true;
          continue;
        }
      }
      next.add(o);
    }
    if (changed) _apply(next);
  }

  void _apply(List<PosRecentOrder> orders, {bool persist = true}) {
    final result = _sortedPruned(orders);
    if (_disposed) return;
    state = result;
    if (persist) {
      // Fire-and-forget for the LOCAL-WRITE paths (submit / payment / void), where the
      // in-memory state is already correct and a durability wobble must not break the
      // till mid-service. It is recorded so the surface can be honest about it.
      //
      // The RECONCILIATION path does NOT come through here -- applySnapshots awaits the
      // write and REPORTS failure, because that is the path whose success decides
      // whether the sync cursor may advance.
      final scopeKey = _scopeKey;
      if (scopeKey.isEmpty) return; // no branch, no bucket (see applySnapshots)
      unawaited(
        _store.persist(scopeKey, result).catchError((Object _) {
          // BOOKED UNDER THE CAPTURED KEY, whatever the active scope is by now:
          // these rows are that scope's newest unsaved truth, and its recovery
          // merges them back. (Only an awaited applySnapshots success clears the
          // debt — a racing fire-and-forget success must not.)
          _owedWrites[scopeKey] = result;
        }),
      );
    }
  }

  /// THE OWED DURABLE WRITES, PER SCOPE: scope key -> the exact rows whose write
  /// failed. This is the newest unsaved truth for that scope — order-time lines,
  /// payment markers, void reasons — everything a re-fetch from the server can NOT
  /// reconstruct (the branch feed returns lineless snapshots).
  ///
  /// It used to be one controller-level boolean, RESET on scope change. That lost
  /// the debt across A -> B -> A: back in A, the persisted store held only the
  /// stale pre-failure rows, the in-memory rich state was gone with the rebuild,
  /// and an empty/no-change page then reported success over a disk that silently
  /// disagreed — receipts and D-008 order-time truth lost. Now the debt is keyed by
  /// the exact scope that earned it: B never inherits it, B's successes never
  /// clear it, and returning to A merges the owed rows back through recovery and
  /// retries the write.
  ///
  /// IN-MEMORY, honestly: if the process dies while a write is owed, the unsaved
  /// delta is gone — the write itself was the thing that failed, so there is
  /// nowhere durable it could have been kept. Within a live run, however, no scope
  /// transition ever discards it.
  final Map<String, List<PosRecentOrder>> _owedWrites =
      <String, List<PosRecentOrder>>{};

  /// True when the ACTIVE scope still owes the disk a write — the in-memory state
  /// and the stored state disagree. Surfaced so the UI can say so rather than
  /// silently pretending the day is saved.
  bool get lastPersistFailed => _owedWrites.containsKey(_scopeKey);

  /// THE DEDUPE KEY IS THE ORDER'S IDENTITY — never the display code.
  ///
  /// `orderNumber` is a SHORTENED, human-facing reference (`#XXXXXX`, the last six hex
  /// characters of the order UUID). It is not unique and was never promised to be: two
  /// genuinely different server orders can share one, and this map used to key on it —
  /// so the second order silently REPLACED the first and one of them vanished from the
  /// till. A display string is for reading, not for identity. See [PosOrderIdentity].
  List<PosRecentOrder> _sortedPruned(List<PosRecentOrder> orders) {
    final byId = <String, PosRecentOrder>{};
    for (final o in orders) {
      final key = o.identity.key;
      final prev = byId[key];
      if (prev == null) {
        byId[key] = o;
        continue;
      }
      // A TERMINAL marker (paid OR MONEY-VOID-001 voided) must never be lost to a
      // plain copy on a merge (e.g. a payment-less voided copy meeting an older
      // non-voided copy on reload).
      final prevTerminal = prev.payment != null || prev.isVoided;
      final oTerminal = o.payment != null || o.isVoided;
      byId[key] = (prevTerminal && !oTerminal) ? prev : o;
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.sortAt.compareTo(a.sortAt));
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final windowed = <PosRecentOrder>[
      for (final o in list)
        if (!o.sortAt.isBefore(cutoff)) o,
    ];
    return windowed.length > _maxOrders
        ? windowed.sublist(0, _maxOrders)
        : windowed;
  }
}

/// The recent-orders persistence seam. Default: in-memory (demo mode / tests —
/// session only). The real app overrides this in `main.dart` with a
/// [SharedPrefsRecentOrdersStore] so the list + paid/unpaid state survive a
/// refresh / restart. Kept a singleton so the in-memory data survives controller
/// rebuilds within a session.
final posRecentOrdersStoreProvider = Provider<PosRecentOrdersStore>(
  (ref) => InMemoryRecentOrdersStore(),
);

/// The POS recent/unpaid-orders controller (newest first, today + yesterday).
final posRecentOrdersControllerProvider =
    NotifierProvider<PosRecentOrdersController, List<PosRecentOrder>>(
      PosRecentOrdersController.new,
    );
