import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

import '../data/order_reconciler.dart';
import '../data/order_snapshot.dart';
import '../data/payment.dart';
import '../data/recent_order.dart';
import '../data/recent_orders_store.dart';
import 'outbox_controller.dart' show kDemoDeviceId;
import 'payment_controller.dart';
import 'pos_device_context.dart';
import 'pos_session.dart';
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
  late final PosRecentOrdersStore _store;
  late final String _scopeKey;
  bool _disposed = false;

  /// Only today + yesterday are surfaced (a lightweight cashier window, not a
  /// heavy history); older orders are pruned on load/update. Capped to bound the
  /// persisted size on a very busy day.
  static const int _maxOrders = 200;

  @override
  List<PosRecentOrder> build() {
    _store = ref.watch(posRecentOrdersStoreProvider);
    _scopeKey = _resolveScopeKey();
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

  String _resolveScopeKey() {
    final isDemo = ref.read(runtimeConfigProvider).isDemoMode;
    if (isDemo) return kDemoDeviceId;
    final session = ref.read(posSyncSessionProvider);
    final ctx = ref.read(posDeviceContextProvider);
    return session?.deviceId ?? ctx?.deviceId ?? kDemoDeviceId;
  }

  /// Loads any persisted recent orders (real mode) and merges them under the
  /// in-session state, then applies the current payments. Never throws.
  Future<void> _recover() async {
    List<PosRecentOrder> loaded;
    try {
      loaded = await _store.load(_scopeKey);
    } catch (_) {
      return;
    }
    if (_disposed) return;
    final byNumber = <String, PosRecentOrder>{
      for (final o in loaded) o.orderNumber: o,
    };
    // In-session state (if any) wins over the persisted copy.
    for (final o in state) {
      byNumber[o.orderNumber] = o;
    }
    _apply(byNumber.values.toList(), persist: false);
    _syncPayments(ref.read(paymentControllerProvider));
  }

  /// Records a freshly-submitted order as UNPAID (idempotent per order number).
  /// Best-effort: a persistence failure never surfaces into the submit path.
  void recordSubmitted(SubmittedOrderView view) {
    final existing = <PosRecentOrder>[
      for (final o in state)
        if (o.orderNumber != view.orderNumber) o,
    ];
    final payment = ref
        .read(paymentControllerProvider)
        .paymentFor(view.orderNumber);
    final order = PosRecentOrder(
      order: view,
      submittedAt: DateTime.now(),
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
  void recordPayment(
    String orderNumber,
    CashPayment payment, {
    String? orderStatus,
  }) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      if (o.orderNumber == orderNumber && o.payment == null && !o.isVoided) {
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
  void markVoided(String orderNumber, String reason) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      // The SERVER already decided (this only runs after it confirmed the void), so this
      // guard must not re-derive policy — it only stops a double write. It checks the
      // PAYMENT MARKER, not settlement, because a live completed payment is exactly what
      // the server's void guard blocks on; a NON-CHARGEABLE order carries none and is
      // genuinely voidable while it is still active.
      if (o.orderNumber == orderNumber && !o.isVoided && o.payment == null) {
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

  /// The current recent order for [orderNumber], or null.
  PosRecentOrder? orderFor(String orderNumber) {
    for (final o in state) {
      if (o.orderNumber == orderNumber) return o;
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
    if (_disposed) return true;
    if (snapshots.isEmpty) return true;

    final result = reconcileSnapshots(state, snapshots);
    if (!result.changedAnything) {
      // IDEMPOTENT: re-applying the same page is a genuine no-op — no state
      // churn, no rewrite, no rebuild.
      return true;
    }

    final merged = _sortedPruned(result.orders);
    if (_disposed) return true;
    state = merged;
    try {
      await _store.persist(_scopeKey, merged);
      return true;
    } catch (_) {
      // The in-memory state is still correct and usable; only durability failed.
      // Report it so the cursor stays put and the same page is re-delivered next
      // time, rather than being silently skipped.
      return false;
    }
  }

  /// Records a SAFE, typed server refusal against an order (e.g.
  /// `order_not_chargeable`), so the UI can explain it instead of silently
  /// re-submitting a request the server has already refused.
  void recordSyncRefusal(String orderNumber, String reason) {
    var changed = false;
    final next = <PosRecentOrder>[
      for (final o in state)
        if (o.orderNumber == orderNumber && !changed)
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
        final p = ps.paymentFor(o.orderNumber);
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
      // Fire-and-forget; a persistence failure must never break the POS.
      unawaited(_store.persist(_scopeKey, result).catchError((Object _) {}));
    }
  }

  List<PosRecentOrder> _sortedPruned(List<PosRecentOrder> orders) {
    final byNumber = <String, PosRecentOrder>{};
    for (final o in orders) {
      final prev = byNumber[o.orderNumber];
      if (prev == null) {
        byNumber[o.orderNumber] = o;
        continue;
      }
      // A TERMINAL marker (paid OR MONEY-VOID-001 voided) must never be lost to
      // a plain copy on an orderNumber collision (e.g. a payment-less voided
      // copy meeting an older non-voided copy on reload/merge).
      final prevTerminal = prev.payment != null || prev.isVoided;
      final oTerminal = o.payment != null || o.isVoided;
      byNumber[o.orderNumber] = (prevTerminal && !oTerminal) ? prev : o;
    }
    final list = byNumber.values.toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final now = DateTime.now();
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    final windowed = <PosRecentOrder>[
      for (final o in list)
        if (!o.submittedAt.isBefore(cutoff)) o,
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
