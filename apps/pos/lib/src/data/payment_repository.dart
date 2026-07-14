import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

import 'ids.dart';
import 'payment.dart';

const String _demoOrgId = 'demo-org';
const String _demoRestaurantId = 'demo-restaurant';
const String _demoBranchId = 'demo-branch';
const String _demoDeviceId = 'demo-device';

/// Thrown when a cash payment cannot be recorded (e.g. the tendered amount does
/// not cover the order total). Messages carry only domain values — never secrets.
///
/// [notChargeable] is set ONLY for the server's exact stable domain code
/// `order_not_chargeable` (MONEY-SETTLEMENT-CONSISTENCY-001): the order is zero-total, so
/// it owes nothing and the server refuses to mint a 0-amount payment or burn a receipt
/// number. It is a TYPED flag on purpose — a transport failure, a malformed envelope or
/// any other rejection must NEVER be mistaken for it, because the UI tells the cashier
/// something categorically different in each case.
class PaymentException implements Exception {
  const PaymentException(
    this.message, {
    this.notChargeable = false,
    this.conflict = false,
  });
  final String message;

  /// The server's EXACT `order_not_chargeable`. Terminal for this sheet: the order
  /// owes nothing, and no tender, amount or retry can change that.
  final bool notChargeable;

  /// POS-OPERATIONS-SYNC-001: an optimistic-concurrency conflict — the order moved
  /// under us (another till, the kitchen, an auto-completion). NEVER auto-retried:
  /// re-sending the same payment against a state we now know is wrong is exactly how
  /// a double charge happens. The row is refreshed and the cashier decides.
  final bool conflict;

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
  /// Records a completed payment for the order [orderId] (the server order id a
  /// real `payment.create` references; ignored by the demo store which keys on
  /// [orderNumber]). [method] is the tender (RF-117): CASH requires
  /// [tenderedMinor] >= [amountMinor] and yields change; a NON-CASH tender
  /// (card/bit/external) is externally recorded with change 0 and
  /// tendered = [amountMinor] (the order total). Throws [PaymentException] if a
  /// cash tender does not cover the total (demo) or the real push fails / is
  /// unauthorized (fail-closed).
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
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
    required String
    orderId, // demo keys on orderNumber; orderId is ignored here
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision, // demo has no server revision to conflict against
  }) async {
    if (amountMinor < 0 || tenderedMinor < 0) {
      throw const PaymentException('amounts must not be negative');
    }
    // RF-117: only CASH must physically cover the total (change is drawer cash).
    // A NON-CASH tender is externally recorded for the exact order total with no
    // change and no drawer movement (mirrors app.record_payment).
    if (method.isCash && tenderedMinor < amountMinor) {
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
    // NON-CASH: record amount = tendered = order total, change = 0 (no float).
    final effectiveTendered = method.isCash ? tenderedMinor : amountMinor;
    final changeMinor = method.isCash ? tenderedMinor - amountMinor : 0;
    final payment = CashPayment(
      paymentId: 'demo-payment-$n',
      orderNumber: orderNumber,
      deviceId: _demoDeviceId,
      localOperationId: 'demo-pay-op-$n',
      method: method,
      status: PaymentStatus.completed,
      amountMinor: amountMinor,
      tenderedMinor: effectiveTendered,
      changeMinor: changeMinor,
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
    // RF-117: only CASH rolls into the drawer (non-cash tenders never move
    // drawer cash — mirrors close_shift summing method='cash' only, MONEY §14).
    final sales = _payments.fold<int>(
      0,
      (sum, p) => p.method.isCash ? sum + p.amountMinor : sum,
    );
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

/// REAL cash-payment repository (M7 / RF-130). Selected by
/// `runtimeConfigProvider` in real mode. It delivers a `payment.create` op to the
/// RF-126 `public.sync_push` wrapper (dispatched server-side to
/// `app.record_payment`, RF-054/RF-055), reusing the same shared public-schema
/// [SyncRpcTransport] + [SyncSession] as the real outbox (RF-129; anon key + the
/// signed-in JWT, never the `app` schema, never a service-role key). The server
/// is the authority for the per-branch receipt number (D-021) and the change due
/// (D-007); the client sends ONLY the tendered amount + the order id and reads
/// the receipt/change/payment id back from the per-op result.
///
/// FAIL-CLOSED: with no [SyncSession]/[SyncRpcTransport] (sign-in not wired) or no
/// [orderId], every call throws [PaymentException] - no backend contact, no false
/// "live" payment. A non-`applied` result (wrong PIN/role, NO OPEN SHIFT
/// precondition (RF-055), conflict, or a malformed envelope) also throws
/// [PaymentException]; nothing is ever invented.
///
/// SCOPE (RF-130): this wires `payment.create` only. The server hard-requires an
/// OPEN shift + active cash drawer (resolved from the session/device, RF-055);
/// the client `shift.open` flow is a SEPARATE ticket, so until a shift is open
/// server-side a real payment is honestly REJECTED (precondition). Client-side
/// shift/drawer display is likewise deferred (no `sync_pull` here), so
/// [shiftContext] returns a neutral placeholder. Money is integer minor units
/// (D-007) - the tendered amount is passed through verbatim, the change is read
/// back from the server, no float is introduced.
class RealPaymentRepository implements PaymentRepository {
  const RealPaymentRepository(
    this._transport,
    this._session,
    this._idGenerator,
  );

  /// The shared public-schema RPC transport, or null when real mode was selected
  /// but the Supabase config was missing/invalid (fail-closed).
  final SyncRpcTransport? _transport;

  /// The authenticated PIN/device session, or null until the sign-in flow wires
  /// one (fail-closed: no session => no real payment).
  final SyncSession? _session;

  /// Mints the payment's `local_operation_id` (idempotency key, D-022) and a
  /// client provisional id for the op `target_id`. The RECORDED payment id is
  /// always the server-authoritative `payment_id` from the result, never this.
  final ClientIdGenerator _idGenerator;

  @override
  Future<CashPayment> recordCashPayment({
    required String orderId,
    required String orderNumber,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    PaymentMethod method = PaymentMethod.cash,
    int? expectedRevision,
  }) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      throw const PaymentException(
        'real payment unavailable: an authenticated PIN session on a paired, '
        'active device is required (sign-in flow not wired yet) - failing '
        'closed, no payment is recorded.',
      );
    }
    if (orderId.trim().isEmpty) {
      throw const PaymentException(
        'real payment unavailable: the submitted order id is missing - failing '
        'closed, no payment is recorded.',
      );
    }

    final localOperationId = _idGenerator.newId();
    final clientPaymentId = _idGenerator.newId();
    final createdAt = DateTime.now();
    // The op `payload` is the server-accepted subset (RF-056): order_id + the
    // tender (RF-117: cash|card|bit|external). The server reads the order total,
    // computes change, allocates the receipt, and resolves the open shift/drawer
    // from the session/device - none of which the client sends. A NON-CASH tender
    // has amount_tendered = the order total (the server forces it anyway; for
    // cash the physical tender is passed through). Integer minor units (no float).
    final op = <String, dynamic>{
      'local_operation_id': localOperationId,
      'operation_type': 'payment.create',
      'target_entity': 'payment',
      'target_id': clientPaymentId,
      'client_created_at': createdAt.toIso8601String(),
      'payload': <String, dynamic>{
        'order_id': orderId,
        'tender_type': method.wire, // 'cash' | 'card' | 'bit' | 'external'
        'amount_tendered_minor': tenderedMinor,
        // POS-OPERATIONS-SYNC-001: OPTIMISTIC CONCURRENCY, finally switched on.
        // sync_push forwards this to app.record_payment, which refuses (SQLSTATE
        // 40001 -> the typed `conflict`) when the order has moved since we read it.
        // The POS stored NO revision before this phase and sent none, so the
        // server's conflict branch was UNREACHABLE: two tills could each pay an
        // order they both believed was unpaid. Omitted when we genuinely do not
        // know one -- sending a guess would be worse than sending nothing.
        if (expectedRevision != null) 'expected_revision': expectedRevision,
      },
    };

    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[op],
      });
    } on SyncTransportException catch (e) {
      // A whole-batch failure (e.g. 42501 - revoked device / expired PIN
      // session). Carry only the error code, never raw backend text.
      throw PaymentException('payment failed: ${e.code ?? e.kind.name}');
    }

    return _applyPaymentResult(
      raw: raw,
      localOperationId: localOperationId,
      orderNumber: orderNumber,
      deviceId: session.deviceId,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      requestedMethod: method,
      paidAt: createdAt,
    );
  }

  /// Maps a `public.sync_push` envelope to a completed [CashPayment], FAIL-CLOSED.
  ///
  /// Only an `applied` per-op result carrying the server-authoritative
  /// `payment_id` + `receipt_number` + integer `change_due_minor` yields a
  /// payment; anything we cannot positively parse - a malformed envelope, a
  /// missing/empty `results`, no result matching this op's `local_operation_id`,
  /// a missing/unknown/non-`applied` status (rejected / conflict / the RF-055
  /// no-open-shift precondition), an `applied` contradicted by `ok: false`, a
  /// missing/blank/wrong-type `payment_id`, or a missing/non-integer money value
  /// - throws [PaymentException] (never a fabricated payment, never a
  /// client-generated id, never raw backend JSON).
  CashPayment _applyPaymentResult({
    required Object? raw,
    required String localOperationId,
    required String orderNumber,
    required String deviceId,
    required int amountMinor,
    required int tenderedMinor,
    required String currencyCode,
    required PaymentMethod requestedMethod,
    required DateTime paidAt,
  }) {
    Never reject(String code) =>
        throw PaymentException('payment rejected: $code');

    if (raw is! Map) reject('malformed_response');
    final results = raw['results'];
    if (results is! List) reject('missing_results');
    if (results.isEmpty) reject('empty_results');

    Map<String, dynamic>? op;
    for (final r in results) {
      if (r is Map && r['local_operation_id'] == localOperationId) {
        op = r.cast<String, dynamic>();
        break;
      }
    }
    if (op == null) reject('no_matching_operation');

    final status = op['status'];
    if (status is! String) reject('missing_status');
    if (status != 'applied') {
      final error = op['error'];
      // MONEY-SETTLEMENT-CONSISTENCY-001: the ONE typed refusal. Matched on the EXACT
      // stable domain code the server returns — never on a raw database message, never on
      // a SQLSTATE, and never inferred from the order's total. Every other rejection
      // (including the generic `rejected`) stays a plain, retryable failure.
      if (error == 'order_not_chargeable') {
        throw const PaymentException(
          'order_not_chargeable',
          notChargeable: true,
        );
      }
      // POS-OPERATIONS-SYNC-001: the optimistic-concurrency refusal. `sync_push`
      // classifies SQLSTATE 40001 as the stable token `conflict`, so this is a typed
      // domain code — not a SQLSTATE we sniffed and not a raw message we parsed.
      //
      // Now that the POS actually SENDS expected_revision, this path is reachable for
      // the first time. It is NEVER auto-retried: re-sending the same payment against
      // a state we now know is wrong is precisely how an order gets charged twice.
      if (error == 'conflict') {
        throw const PaymentException('conflict', conflict: true);
      }
      reject(error is String ? error : status);
    }
    if (op['ok'] == false) reject('applied_not_ok');

    final receiptNumber = op['receipt_number'];
    if (receiptNumber is! String || receiptNumber.isEmpty) {
      reject('missing_receipt_number');
    }
    // The payment id is SERVER-AUTHORITATIVE (RF-054): a missing / null / blank /
    // wrong-type id fails closed and is NEVER replaced by a client-generated id.
    final paymentId = op['payment_id'];
    if (paymentId is! String || paymentId.isEmpty) reject('missing_payment_id');
    // Integer minor units only - a float/absent change is a contract violation.
    final changeMinor = op['change_due_minor'];
    if (changeMinor is! int) reject('invalid_change_due_minor');
    // RF-117: the server ECHOES the recorded tender method; trust it, falling
    // back to the requested tender only if the field is absent (older server).
    final recordedMethod =
        PaymentMethod.fromWire(op['method']) ?? requestedMethod;

    // MONEY-SETTLEMENT-CONSISTENCY-001 / ORDER-AUTO-COMPLETION-001: the server reports the
    // order's FINAL status here — `completed` when this payment auto-closed a served
    // order. Absent on an older server: null means "not told", never "not terminal".
    final orderStatus = op['order_status'];

    return CashPayment(
      paymentId: paymentId,
      orderNumber: orderNumber,
      deviceId: deviceId,
      localOperationId: localOperationId,
      method: recordedMethod,
      status: PaymentStatus.completed,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      changeMinor: changeMinor,
      currencyCode: currencyCode,
      receiptNumber: receiptNumber,
      paidAt: paidAt,
      orderStatus: orderStatus is String && orderStatus.isNotEmpty
          ? orderStatus
          : null,
    );
  }

  /// Real shift/drawer state is server-managed and not pulled client-side in
  /// RF-130 (no `sync_pull` here) - return a neutral placeholder so the payment
  /// UI composes without crashing; the server enforces the open-shift
  /// precondition (RF-055) on the actual payment. Honest: no demo cash is shown.
  @override
  ShiftContext shiftContext() => const ShiftContext(
    shiftOpen: false,
    drawerOpen: false,
    openingFloatMinor: 0,
    cashInDrawerMinor: 0,
    lastPaymentMinor: null,
    currencyCode: 'ILS',
  );

  /// No client-side payment cache in real mode (the controller holds recorded
  /// payments in its state); a real lookup would be a `sync_pull` (deferred).
  @override
  CashPayment? paymentFor(String orderNumber) => null;
}
