import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;

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

  /// Attaches [payment] to a stored unpaid order (no-op if unknown/already paid).
  void recordPayment(String orderNumber, CashPayment payment) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      if (o.orderNumber == orderNumber && o.payment == null) {
        next.add(o.copyWith(payment: payment));
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

  /// Count of currently-unpaid recent orders (drives the app-bar badge).
  int get unpaidCount => state.where((o) => !o.isPaid).length;

  void _syncPayments(PaymentState ps) {
    var changed = false;
    final next = <PosRecentOrder>[];
    for (final o in state) {
      if (o.payment == null) {
        final p = ps.paymentFor(o.orderNumber);
        if (p != null) {
          next.add(o.copyWith(payment: p));
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
      // Prefer the copy that carries a payment (paid state must not be lost).
      byNumber[o.orderNumber] =
          (prev != null && prev.payment != null && o.payment == null)
          ? prev
          : o;
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
