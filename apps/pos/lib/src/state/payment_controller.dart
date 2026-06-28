import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/payment.dart';
import '../data/payment_repository.dart';

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

  /// Takes a cash payment for [orderNumber]. [amountMinor] is the order total
  /// and [tenderedMinor] is the cash received; throws [PaymentException] if the
  /// tender does not cover the total. Returns the recorded [CashPayment].
  Future<CashPayment> payCash({
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
  }) async {
    final payment = await _repo.recordCashPayment(
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
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
/// in-memory [DemoPaymentStore] in demo mode (the DEFAULT), or the
/// [RealPaymentRepository] skeleton in real mode. Tests can override either this
/// provider or [runtimeConfigProvider] to force a mode.
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return DemoPaymentStore();
  return RealPaymentRepository(cfg.supabase);
});

/// The POS payment controller (shift context + recorded payments).
final paymentControllerProvider =
    NotifierProvider<PaymentController, PaymentState>(PaymentController.new);
