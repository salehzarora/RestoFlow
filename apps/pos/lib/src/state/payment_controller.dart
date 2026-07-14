import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/payment.dart';
import '../data/payment_repository.dart';
import 'pos_session.dart';

/// Immutable POS payment state (RF-116): the live shift / cash-drawer context
/// plus the recorded cash payments, keyed by order number.
class PaymentState {
  const PaymentState({required this.shift, required this.payments});

  final ShiftContext shift;
  final Map<String, CashPayment> payments;

  CashPayment? paymentFor(String orderNumber) => payments[orderNumber];
}

/// Records cash payments and exposes the demo shift/cash-drawer context
/// (RF-116). Recording a payment rolls the order amount into the drawer and
/// refreshes the context. In-memory demo only — no backend, no printer.
class PaymentController extends Notifier<PaymentState> {
  late PaymentRepository _repo;

  @override
  PaymentState build() {
    _repo = ref.watch(paymentRepositoryProvider);
    return PaymentState(shift: _repo.shiftContext(), payments: const {});
  }

  /// Records a payment for [orderNumber] (settling the order [orderId] in real
  /// mode; ignored by the demo store). [amountMinor] is the order total and, for
  /// a CASH [method], [tenderedMinor] is the cash received; a NON-CASH tender
  /// (card/bit/external) is externally recorded for the exact total with no
  /// change (RF-117). Throws [PaymentException] if a cash tender does not cover
  /// the total or (real mode) the push fails / is unauthorized. Returns the
  /// recorded [CashPayment].
  Future<CashPayment> payCash({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    final payment = await _repo.recordCashPayment(
      orderId: orderId,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      method: method,
      // POS-OPERATIONS-SYNC-001: the authoritative revision this payment is being
      // made against. It makes the server's conflict path reachable at last.
      expectedRevision: expectedRevision,
    );
    state = PaymentState(
      shift: _repo.shiftContext(),
      payments: {...state.payments, orderNumber: payment},
    );
    return payment;
  }

  CashPayment? paymentFor(String orderNumber) => state.paymentFor(orderNumber);
}

/// The cash-payment repository. Selects by client runtime mode (M7): the
/// in-memory [DemoPaymentStore] in demo mode (the DEFAULT), or the real
/// [RealPaymentRepository] in real mode (RF-130), which posts a `payment.create`
/// op to `public.sync_push` over the shared [posAuthTransportProvider] transport
/// and [posSyncSessionProvider] session (RF-131); with no transport or no session
/// it fails closed. Tests can override this provider, [runtimeConfigProvider],
/// [posAuthTransportProvider], or [posSyncSessionProvider] to force a mode.
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoPaymentStore();
  return RealPaymentRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});

/// The POS payment controller (shift context + recorded payments).
final paymentControllerProvider =
    NotifierProvider<PaymentController, PaymentState>(PaymentController.new);
