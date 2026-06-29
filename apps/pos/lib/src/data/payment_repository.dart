import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'payment.dart';

const String _demoOrgId = 'demo-org';
const String _demoRestaurantId = 'demo-restaurant';
const String _demoBranchId = 'demo-branch';
const String _demoDeviceId = 'demo-device';

/// Thrown when a cash payment cannot be recorded (e.g. the tendered amount does
/// not cover the order total). Messages carry only domain values — never secrets.
class PaymentException implements Exception {
  const PaymentException(this.message);
  final String message;
  @override
  String toString() => 'PaymentException: $message';
}

/// The cash-payment seam (RF-116). [recordCashPayment] maps 1:1 to the
/// `app.record_payment` RPC (RF-054): validate the tender covers the total,
/// allocate a receipt number, compute change, mark the payment completed, and
/// roll the cash into the drawer. [shiftContext] / [paymentFor] are local reads.
///
/// Implemented here ONLY by the in-memory [DemoPaymentStore]; the real
/// Supabase-backed implementation lands with the device/PIN-session auth bridge.
/// Nothing here contacts a backend or a printer.
abstract class PaymentRepository {
  /// Records a completed cash payment for [orderNumber]. Throws
  /// [PaymentException] if [tenderedMinor] is less than [amountMinor].
  Future<CashPayment> recordCashPayment({
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
  });

  /// The current demo shift / cash-drawer context.
  ShiftContext shiftContext();

  /// The recorded payment for [orderNumber], or null if it is unpaid.
  CashPayment? paymentFor(String orderNumber);
}

/// In-memory, clearly-labelled DEMO cash-payment + shift store (RF-116).
///
/// Backs the shift/drawer context with the real domain [Shift] +
/// [CashDrawerSession] (RF-037) for status + opening float, and derives the
/// running cash as `openingFloat + sum(completed cash payments.amountMinor)`
/// (MONEY_AND_TAX_SPEC §14). Receipt numbers are PROVISIONAL demo ids
/// (DECISION D-021). All money is integer minor units (DECISION D-007). NO
/// backend, NO persistence, NO printer.
class DemoPaymentStore implements PaymentRepository {
  DemoPaymentStore({DateTime Function()? clock, int openingFloatMinor = 20000})
    : _clock = clock ?? DateTime.now,
      _shift = Shift(
        shiftId: 'demo-shift',
        organizationId: _demoOrgId,
        restaurantId: _demoRestaurantId,
        branchId: _demoBranchId,
        openedByEmployeeId: 'demo-cashier',
      )..open(),
      _drawer = CashDrawerSession(
        cashDrawerSessionId: 'demo-drawer',
        shiftId: 'demo-shift',
        organizationId: _demoOrgId,
        restaurantId: _demoRestaurantId,
        branchId: _demoBranchId,
        openingFloatMinor: openingFloatMinor,
        deviceId: _demoDeviceId,
      )..activate();

  final DateTime Function() _clock;
  final Shift _shift;
  final CashDrawerSession _drawer;

  final List<CashPayment> _payments = <CashPayment>[];
  int _seq = 0;

  @override
  Future<CashPayment> recordCashPayment({
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
  }) async {
    if (amountMinor < 0 || tenderedMinor < 0) {
      throw const PaymentException('amounts must not be negative');
    }
    if (tenderedMinor < amountMinor) {
      throw const PaymentException(
        'tendered amount must cover the order total',
      );
    }

    // Idempotency: a duplicate pay for an already-paid order returns the
    // existing payment (mirrors the per-order single-completed-payment rule).
    final existing = paymentFor(orderNumber);
    if (existing != null) return existing;

    _seq++;
    final n = _seq.toString().padLeft(4, '0');
    final payment = CashPayment(
      paymentId: 'demo-payment-$n',
      orderNumber: orderNumber,
      deviceId: _demoDeviceId,
      localOperationId: 'demo-pay-op-$n',
      method: PaymentMethod.cash,
      status: PaymentStatus.completed,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      changeMinor: tenderedMinor - amountMinor,
      currencyCode: currencyCode,
      receiptNumber: 'PROV-$n',
      paidAt: _clock(),
    );
    _payments.add(payment);
    return payment;
  }

  @override
  CashPayment? paymentFor(String orderNumber) {
    for (final p in _payments) {
      if (p.orderNumber == orderNumber) return p;
    }
    return null;
  }

  @override
  ShiftContext shiftContext() {
    final sales = _payments.fold<int>(0, (sum, p) => sum + p.amountMinor);
    return ShiftContext(
      shiftOpen: _shift.status == ShiftStatus.open,
      drawerOpen: _drawer.status == CashDrawerSessionStatus.active,
      openingFloatMinor: _drawer.openingFloatMinor,
      cashInDrawerMinor: _drawer.openingFloatMinor + sales,
      lastPaymentMinor: _payments.isEmpty ? null : _payments.last.amountMinor,
      currencyCode: 'ILS',
    );
  }
}

/// REAL cash-payment repository (M7). Selected by `runtimeConfigProvider` in
/// real mode. The production path delivers a `payment.create` op to the RF-126
/// `public.sync_push` wrapper (dispatched server-side to `app.record_payment`,
/// RF-054), where the server allocates the authoritative per-branch receipt
/// number and computes change (D-021 / D-007).
///
/// STILL FAIL-CLOSED: unlike `order.submit` (wired in RF-129), a `payment.create`
/// op needs the server `order_id` of an already-submitted order PLUS an open
/// shift + active cash drawer (RF-062), AND the PIN/device session that
/// authorizes the push. The current `recordCashPayment(orderNumber, ...)` seam
/// carries only the provisional order NUMBER - not the server order_id / shift
/// context - and the sign-in/shift flow is not wired yet. So every method throws
/// [RealRepoNotWiredError]: no surface claims live data and no backend is
/// contacted. Wiring it is a follow-up (thread the submit result's order_id + the
/// open-shift context through the seam). Money stays integer minor units (D-007).
class RealPaymentRepository implements PaymentRepository {
  const RealPaymentRepository(this.config);

  /// The validated anon-key Supabase config (or null when real mode was selected
  /// but config was missing/invalid - fail-closed). Held for the future
  /// authenticated transport; no client is constructed yet.
  final SupabaseBootstrapConfig? config;

  static const String _reason =
      'payment: sync_push -> app.record_payment needs the server order_id + an '
      'open shift/drawer threaded from the submit/shift flow - not wired yet';

  @override
  Future<CashPayment> recordCashPayment({
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
  }) async => throw const RealRepoNotWiredError(_reason);

  @override
  ShiftContext shiftContext() => throw const RealRepoNotWiredError(_reason);

  @override
  CashPayment? paymentFor(String orderNumber) =>
      throw const RealRepoNotWiredError(_reason);
}
