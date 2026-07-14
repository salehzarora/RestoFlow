import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/order_identity.dart';
import '../data/payment.dart';
import '../data/payment_repository.dart';
import 'pos_session.dart';
import 'pos_sync_scope_provider.dart';

/// Immutable POS payment state (RF-116): the live shift / cash-drawer context plus
/// the recorded cash payments, keyed by ORDER IDENTITY.
///
/// POS-OPERATIONS-SYNC-001 (second review correction): this map was keyed by the
/// DISPLAY code. Two orders sharing a `#XXXXXX` therefore shared one entry, so paying
/// one of them marked BOTH paid — the second order's payment button disappeared, its
/// receipt showed the other order's money, and the till's takings were wrong by a whole
/// order. The key is now [PosOrderIdentity]: the server's order id where it exists,
/// this device's own operation id before that, and never the code.
class PaymentState {
  const PaymentState({required this.shift, required this.payments});

  final ShiftContext shift;

  /// Keyed by [PosOrderIdentity.key] — NEVER by `orderNumber`.
  final Map<String, CashPayment> payments;

  /// The payment recorded for [identity] this session, or null.
  CashPayment? paymentFor(PosOrderIdentity identity) => payments[identity.key];
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

  /// Records a payment against [identity] — THE order's identity, not its display
  /// code (settling the order [orderId] in real mode; ignored by the demo store).
  /// [amountMinor] is the order total and, for a CASH [method], [tenderedMinor] is the
  /// cash received; a NON-CASH tender (card/bit/external) is externally recorded for
  /// the exact total with no change (RF-117). Throws [PaymentException] if a cash
  /// tender does not cover the total or (real mode) the push fails / is unauthorized.
  /// Returns the recorded [CashPayment].
  Future<CashPayment> payCash({
    required PosOrderIdentity identity,
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    // The scope this payment is being taken IN. A payment belongs to the branch whose
    // drawer it went into, and to no other.
    final scopeKey = ref.read(posSyncScopeProvider)?.key;

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

    // STALE SCOPE. The till was re-paired into another branch while this payment was in
    // flight. The payment itself is REAL — the server took it, and it is returned to
    // the caller so the receipt and the change due are still correct — but it must not
    // be merged into the NEW branch's session state, where it would roll a different
    // branch's cash into this one's drawer figure. It stays on the server, and the
    // branch it belongs to reads it back authoritatively on its next reconciliation.
    if (ref.read(posSyncScopeProvider)?.key != scopeKey) return payment;

    state = PaymentState(
      shift: _repo.shiftContext(),
      // Keyed by IDENTITY. Keying by the display code is what attached one payment to
      // two different orders.
      payments: {...state.payments, identity.key: payment},
    );
    return payment;
  }

  /// The payment recorded for [identity] this session, or null.
  CashPayment? paymentFor(PosOrderIdentity identity) =>
      state.paymentFor(identity);
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
