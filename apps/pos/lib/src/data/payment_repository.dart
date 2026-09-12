import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';

import 'ids.dart';
import 'order_identity.dart';
import 'payment.dart';
import 'payment_attempt.dart';

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
    this.shiftRequired = false,
    this.unconfirmed = false,
    this.notApplied = false,
    this.authRequired = false,
    this.saveBlocked = false,
    this.settledElsewhere = false,
    this.inFlight = false,
    this.unresolvedAttempt = false,
    this.otherActor = false,
    this.quarantined = false,
    this.revisionRequired = false,
    this.actorRequired = false,
    this.attempt,
  });
  final String message;

  /// STALE-TABLE-ORDER-RECOVERY-001: the server's `record_payment` precondition
  /// "no open shift for this branch/device" (or no active drawer). The order is
  /// fine; the PAYING device must open a shift first. Never a generic failure.
  final bool shiftRequired;

  /// The server's EXACT `order_not_chargeable`. Terminal for this sheet: the order
  /// owes nothing, and no tender, amount or retry can change that.
  final bool notChargeable;

  /// POS-OPERATIONS-SYNC-001: an optimistic-concurrency conflict — the order moved
  /// under us (another till, the kitchen, an auto-completion). NEVER auto-retried:
  /// re-sending the same payment against a state we now know is wrong is exactly how
  /// a double charge happens. The row is refreshed and the cashier decides.
  final bool conflict;

  /// PAYMENT-ATTEMPT-RECOVERY-001: the outcome of THIS attempt is UNKNOWN — the
  /// server may have committed. The attempt stays durable and must be RESUMED
  /// under the same identity; never re-tendered.
  final bool unconfirmed;

  /// The transport proved the request did not commit (rolled back / refused at
  /// the gateway). Same attempt, resumable.
  final bool notApplied;

  /// The session was refused; sign in again, then resume the SAME attempt.
  final bool authRequired;

  /// The attempt could not be durably saved, so NOTHING was sent.
  final bool saveBlocked;

  /// THIS attempt was refused and the order is settled by another
  /// attempt/device. Not our payment.
  final bool settledElsewhere;

  /// A send for this order is already in flight on this controller.
  final bool inFlight;

  /// An earlier UNRESOLVED attempt with different inputs exists; nothing sent.
  final bool unresolvedAttempt;

  /// The unresolved attempt belongs to another cashier; nothing sent.
  final bool otherActor;

  /// A stored attempt for this scope/order cannot be read; nothing sent.
  final bool quarantined;

  /// PDR-003: no authoritative order revision, so nothing was minted or sent.
  final bool revisionRequired;

  /// PDR-007: no identifiable cashier, so nothing was minted or sent.
  final bool actorRequired;

  /// The attempt concerned, when one exists.
  final PaymentAttemptSummary? attempt;

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
  /// Records a completed payment for the order [orderId] (the server order id a real
  /// `payment.create` references). [orderNumber] is the DISPLAY code — printed and read
  /// out, never an identity. [method] is the tender (RF-117): CASH requires
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

  /// The recorded payment for the order with [identity], or null if it is unpaid.
  ///
  /// BY IDENTITY, never by display code: two orders can share a `#XXXXXX`, and a lookup
  /// keyed on it would hand back the OTHER order's payment — which, here, is the very
  /// check that decides whether a payment is a duplicate.
  CashPayment? paymentFor(PosOrderIdentity identity);
}

/// PAYMENT-ATTEMPT-RECOVERY-001 — what the server said about ONE send of ONE
/// durable attempt. Exactly one of the five shapes; nothing here is a guess.
sealed class PaymentSendResult {
  const PaymentSendResult();
}

/// `applied` (first application OR a verified same-key replay of it).
class PaymentSendAccepted extends PaymentSendResult {
  const PaymentSendAccepted(this.resolution);
  final PaymentAttemptResolution resolution;
}

/// A DEFINITIVE refusal of this attempt. [memoized] means the server's ledger
/// holds it and will replay it for this key forever; false means it was
/// rolled back (an older server raising the precondition at batch level).
class PaymentSendRefused extends PaymentSendResult {
  const PaymentSendRefused(this.code, {required this.memoized});
  final PaymentRefusalCode code;
  final bool memoized;
}

/// The reply was lost or unreadable; the server MAY have committed.
class PaymentSendUnconfirmed extends PaymentSendResult {
  const PaymentSendUnconfirmed(this.reason);
  final PaymentUnconfirmedReason reason;
}

/// The transport proved the request did NOT commit (a raised server error =
/// rolled-back transaction; a 4xx gateway refusal before execution). The
/// identity is still free; resuming under the same key is safe.
class PaymentSendNotApplied extends PaymentSendResult {
  const PaymentSendNotApplied(this.code);
  final String code;
}

/// A session-class refusal (rolled back). Sign in again, then resume.
class PaymentSendAuthRequired extends PaymentSendResult {
  const PaymentSendAuthRequired();
}

/// The READ-ONLY answer to "what became of attempt X?" — from the server's own
/// per-device operation ledger via `sync_pull` (`operation_statuses`), which
/// executes nothing.
sealed class PaymentAttemptStatusLookup {
  const PaymentAttemptStatusLookup();
}

class PaymentAttemptStatusApplied extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusApplied(this.resolution);
  final PaymentAttemptResolution resolution;
}

class PaymentAttemptStatusRefused extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusRefused(this.code);
  final PaymentRefusalCode code;
}

/// The ledger holds our key but its stored outcome is unusable (or it is a
/// different operation) — cannot be resolved automatically.
class PaymentAttemptStatusCollision extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusCollision();
}

/// The ledger has no row for this attempt: it never reached the server, or is
/// still executing. NOT proof that it cannot still commit.
class PaymentAttemptStatusNotFound extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusNotFound();
}

/// The ledger holds our row in a NON-terminal status (`created`, `pending`,
/// `in_flight`, `resolved`): the server has not decided; a same-key re-push
/// ADOPTS and re-dispatches it. Still pending — never a refusal.
class PaymentAttemptStatusInProgress extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusInProgress();
}

class PaymentAttemptStatusUnavailable extends PaymentAttemptStatusLookup {
  const PaymentAttemptStatusUnavailable(this.reason);
  final String reason;
}

/// The seam a durable-attempt-aware repository implements: send EXACTLY the
/// frozen attempt (never minting anything) and read its status without
/// executing it. The controller uses it in real mode; the demo store and
/// hand-written test fakes that implement only [PaymentRepository] keep the
/// legacy direct path.
abstract interface class PaymentAttemptSender {
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt);
  Future<PaymentAttemptStatusLookup> lookupAttemptStatus(
    PaymentAttempt attempt,
  );
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
    // The AUTHORITATIVE order. The demo store used to ignore it and key on the display
    // code — which is how paying one order could return another's payment.
    required String orderId,
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
    // Keyed on the ORDER, so a different order that happens to share this one's printed
    // code is not mistaken for a duplicate — and silently handed a payment it never had.
    final existing = paymentFor(
      PosOrderIdentity.of(orderId: orderId, orderNumber: orderNumber),
    );
    if (existing != null) return existing;

    _seq++;
    final n = _seq.toString().padLeft(4, '0');
    // NON-CASH: record amount = tendered = order total, change = 0 (no float).
    final effectiveTendered = method.isCash ? tenderedMinor : amountMinor;
    final changeMinor = method.isCash ? tenderedMinor - amountMinor : 0;
    final payment = CashPayment(
      paymentId: 'demo-payment-$n',
      // Recorded even in demo when the caller knows it: the payment must carry the
      // AUTHORITATIVE order it settles, not just the code printed on the ticket.
      orderId: orderId.isEmpty ? null : orderId,
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
  CashPayment? paymentFor(PosOrderIdentity identity) {
    for (final p in _payments) {
      final id = PosOrderIdentity.of(
        orderId: p.orderId,
        orderNumber: p.orderNumber,
      );
      if (id == identity) return p;
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
/// PAYMENT-ATTEMPT-RECOVERY-001: the repository no longer OWNS a payment's
/// identity. [sendAttempt] transmits a frozen, already-durable [PaymentAttempt]
/// byte-for-byte (the same `local_operation_id`, `target_id`,
/// `client_created_at` and payload on every send) and classifies the answer
/// into a [PaymentSendResult] — accepted / definitively refused / UNCONFIRMED /
/// not applied / sign-in required — so the controller can resume exactly the
/// same attempt after a lost reply, a sheet reopen or a restart, and the
/// server's same-key ledger replays the original outcome. [recordCashPayment]
/// remains for callers that hold no durable record (it mints a fresh attempt
/// and sends it once). Money is integer minor units (D-007) throughout.
class RealPaymentRepository implements PaymentRepository, PaymentAttemptSender {
  const RealPaymentRepository(
    this._transport,
    this._session,
    this._idGenerator, {
    DateTime Function()? clock,
  }) : _clock = clock;

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

  final DateTime Function()? _clock;

  DateTime _now() => (_clock ?? DateTime.now)();

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
    // A caller with no durable record: mint ONCE, send ONCE. (The controller
    // owns the durable path and never calls this for a resume.)
    final attempt = PaymentAttempt.mint(
      ids: _idGenerator,
      now: _now(),
      orderId: orderId,
      orderNumber: orderNumber,
      amountMinor: amountMinor,
      tenderedMinor: tenderedMinor,
      currencyCode: currencyCode,
      method: method,
      expectedRevision: expectedRevision,
      organizationId: '',
      restaurantId: '',
      branchId: '',
      deviceId: session.deviceId,
      employeeProfileId: null,
    );
    final result = await sendAttempt(attempt);
    return switch (result) {
      PaymentSendAccepted(:final resolution) =>
        attempt
            .accepted(
              resolution,
              at: _now().toUtc().toIso8601String(),
              reserveEffects: false,
            )
            .payment!,
      PaymentSendRefused(:final code) => throw exceptionForRefusal(code),
      PaymentSendUnconfirmed(:final reason) => throw PaymentException(
        'payment unconfirmed: ${reason.name}',
        unconfirmed: true,
        attempt: PaymentAttemptSummary.of(attempt),
      ),
      PaymentSendNotApplied(:final code) => throw PaymentException(
        'payment failed: $code',
        notApplied: true,
        attempt: PaymentAttemptSummary.of(attempt),
      ),
      PaymentSendAuthRequired() => throw PaymentException(
        'payment failed: auth',
        authRequired: true,
        attempt: PaymentAttemptSummary.of(attempt),
      ),
    };
  }

  /// The typed [PaymentException] for a definitive refusal — the SAME codes and
  /// flags the sheet has always keyed its banners on.
  static PaymentException exceptionForRefusal(PaymentRefusalCode code) =>
      switch (code) {
        PaymentRefusalCode.notChargeable => const PaymentException(
          'order_not_chargeable',
          notChargeable: true,
        ),
        PaymentRefusalCode.revisionConflict => const PaymentException(
          'conflict',
          conflict: true,
        ),
        PaymentRefusalCode.shiftRequired => const PaymentException(
          'payment refused: no open shift on this device',
          shiftRequired: true,
        ),
        PaymentRefusalCode.permissionDenied => const PaymentException(
          'payment rejected: permission_denied',
        ),
        PaymentRefusalCode.revokedEmployee => const PaymentException(
          'payment rejected: revoked_employee',
        ),
        PaymentRefusalCode.generic => const PaymentException(
          'payment rejected: rejected',
        ),
      };

  @override
  Future<PaymentSendResult> sendAttempt(PaymentAttempt attempt) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      return const PaymentSendNotApplied('unavailable');
    }
    // NEVER transmit another device's attempt: the key is (device, op) on the
    // server, and a record from another till is not ours to replay.
    if (attempt.deviceId != session.deviceId) {
      return const PaymentSendNotApplied('device_mismatch');
    }
    final Object? raw;
    try {
      raw = await transport.invoke('sync_push', <String, dynamic>{
        'p_pin_session_id': session.pinSessionId,
        'p_device_id': session.deviceId,
        'p_operations': <dynamic>[attempt.toSyncOperation()],
      });
    } on SyncTransportException catch (e) {
      return classifyTransportFailure(e);
    }
    return classifyEnvelope(raw, attempt);
  }

  /// A transport-level failure, classified by what it PROVES about the commit:
  ///
  ///   * `auth` — the session-class preamble refusal; the whole batch rolled
  ///     back. Sign in again, then resume.
  ///   * a SQLSTATE-shaped code (`42501`, `P0001`, …) — a raised server error,
  ///     i.e. a rolled-back transaction: NOT applied, key still free. The one
  ///     precondition an older server may raise at batch level (no open
  ///     shift) keeps its typed refusal.
  ///   * a 4xx gateway status — refused before execution: NOT applied.
  ///   * everything else (timeout, socket, 5xx, 429, unknown) — the request
  ///     MAY have committed: UNCONFIRMED.
  static PaymentSendResult classifyTransportFailure(SyncTransportException e) {
    if (e.kind == SyncTransportErrorKind.auth) {
      return const PaymentSendAuthRequired();
    }
    final code = e.code;
    if (e.kind == SyncTransportErrorKind.server && code != null) {
      if (isNoOpenShiftRefusal(e)) {
        return const PaymentSendRefused(
          PaymentRefusalCode.shiftRequired,
          memoized: false,
        );
      }
      if (_isSqlState(code)) return PaymentSendNotApplied(code);
      // PostgREST's own errors (`PGRST202` function not found, …) are
      // answered before any SQL runs.
      if (RegExp(r'^PGRST\d{3}$').hasMatch(code)) {
        return PaymentSendNotApplied(code);
      }
      final http = int.tryParse(code);
      if (http != null && http >= 400 && http < 500 && !_ambiguous4xx(http)) {
        return PaymentSendNotApplied(code);
      }
    }
    return const PaymentSendUnconfirmed(PaymentUnconfirmedReason.transport);
  }

  /// SQLSTATEs are exactly five alphanumerics (`42501`, `P0001`, `22P02`);
  /// an HTTP status is three digits and never matches.
  static bool _isSqlState(String code) =>
      RegExp(r'^[0-9A-Z]{5}$').hasMatch(code);

  /// 408 (request timeout), 425 (too early) and 429 (throttled) do not prove
  /// the request never executed.
  static bool _ambiguous4xx(int status) =>
      status == 408 || status == 425 || status == 429;

  /// Classifies a `public.sync_push` envelope for [attempt], FAIL-CLOSED and
  /// HONEST: only a positively parsed `applied` result is an acceptance; a
  /// definitive server refusal is typed; anything unreadable, missing or
  /// mismatched is UNCONFIRMED — never a failure the cashier is told to retry
  /// with new money, and never a success.
  /// S1-R3 / F002: every result `sync_push` emits carries an explicit
  /// `idempotency_replay` boolean — false when it decided now, true when it
  /// replayed a stored terminal row. A missing or wrongly typed value means
  /// this is not a result that function produced.
  static bool _replayIsSourceShaped(Map<Object?, Object?> op) =>
      op['idempotency_replay'] is bool;

  static PaymentSendResult classifyEnvelope(
    Object? raw,
    PaymentAttempt attempt, {

    /// S1-R5 / F002 — whether [raw] is a LIVE `sync_push` reply.
    ///
    /// False for exactly one caller: [_classifyLedgerRow], which wraps a
    /// stored `sync_operations.result` — projected by the operation-status
    /// feed, not returned by `sync_push` — in a one-result envelope so the
    /// same result grammar decides it. There is no outer reply there, so no
    /// outer reply stamp exists to require; that row's own shape has already
    /// been validated against the complete tracked feed projection by
    /// [_isFeedRowShaped] before this is reached.
    bool fromLiveReply = true,
  }) {
    if (raw is! Map) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.malformedResponse,
      );
    }
    // S1-F002: the OUTER envelope must itself say the call succeeded. The
    // final `sync_push` returns `ok: true` on its normal path
    // (20260905090001…sql:876), so an envelope that says otherwise while
    // carrying a healthy-looking row is contradictory evidence, not a payment.
    if (raw['ok'] != true) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.malformedResponse,
      );
    }
    // S1-R5 / F002: the final `sync_push` stamps its OWN `server_ts` on the
    // one envelope it returns (`20260905090001_..._002.sql:876`:
    // `jsonb_build_object('ok', true, 'results', v_results, 'server_ts',
    // now())`). R4 validated `ok` and the inner results but not this, so an
    // envelope that function could not have produced was still allowed to
    // settle a payment. A missing or unparseable stamp is unreadable
    // evidence, never an acceptance and never a refusal.
    if (fromLiveReply) {
      final envelopeServerTs = raw['server_ts'];
      if (envelopeServerTs is! String ||
          DateTime.tryParse(envelopeServerTs) == null) {
        return const PaymentSendUnconfirmed(
          PaymentUnconfirmedReason.malformedResponse,
        );
      }
    }
    final results = raw['results'];
    if (results is! List || results.isEmpty) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.malformedResponse,
      );
    }
    // The POS pushes payment.create as a SINGLE-operation batch, so a healthy
    // reply carries exactly one result in total. Extra rows mean this is not
    // the reply we think it is.
    if (results.length != 1) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.mismatchedResult,
      );
    }
    // PDR-002 — EXACTLY ONE result for our operation. The previous build took
    // the first row whose id matched and stopped looking, so a reply carrying
    // two contradictory rows for one operation was resolved from whichever
    // came first. Cardinality is checked before anything is believed.
    final matches = <Map<String, dynamic>>[
      for (final r in results)
        if (r is Map && r['local_operation_id'] == attempt.localOperationId)
          r.cast<String, dynamic>(),
    ];
    if (matches.length != 1) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.mismatchedResult,
      );
    }
    final op = matches.single;
    // The row must be OUR kind of operation. A `payment.create` result is the
    // only shape the fields below mean anything in.
    if (op['operation_type'] != 'payment.create') {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.mismatchedResult,
      );
    }
    // Whenever the server names an order, it must be the frozen one. A result
    // for another order can never settle this attempt.
    final resultOrderId = op['order_id'];
    if (resultOrderId != null && resultOrderId != attempt.orderId) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.mismatchedResult,
      );
    }
    final status = op['status'];
    if (status is! String) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.malformedResponse,
      );
    }
    // Only the words the final `sync_push` contract actually finalizes an
    // operation with are interpreted. `created`, `in_flight`, `resolved` and
    // anything a future server adds mean the operation is NOT decided, and an
    // undecided row must never read as a terminal refusal that frees a new
    // payment identity.
    const known = <String>{
      'applied',
      'rejected',
      'dead',
      'conflict',
      'pending',
    };
    if (!known.contains(status)) {
      return const PaymentSendUnconfirmed(
        PaymentUnconfirmedReason.malformedResponse,
      );
    }
    final error = op['error'];
    final detail = op['detail'];
    switch (status) {
      case 'applied':
        // S1-F002: an applied result must SAY it succeeded. Missing, null or a
        // wrongly typed `ok` is not an older server, it is unreadable evidence.
        if (op['ok'] != true) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        final receiptNumber = op['receipt_number'];
        // The payment id is SERVER-AUTHORITATIVE (RF-054): a missing / null /
        // blank / wrong-type id is never replaced by a client-generated id.
        final paymentId = op['payment_id'];
        // Integer minor units only - a float/absent change is a contract violation.
        final changeMinor = op['change_due_minor'];
        // S1-F002: non-blank identities, and integer minor units that cannot
        // be negative — change due is money handed back, never owed.
        if (receiptNumber is! String ||
            receiptNumber.trim().isEmpty ||
            paymentId is! String ||
            paymentId.trim().isEmpty ||
            changeMinor is! int ||
            changeMinor < 0) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // S1-R4 / F002 — the COMPLETE tracked applied tuple.
        //
        // `app.record_payment` builds one object and sync_push merges it
        // through verbatim (20260716090000_..._contracts.sql:400-411 and
        // 20260905090001_..._002.sql:861-872). Every one of these keys is
        // therefore present on a genuine application, with these types. R3
        // validated only some of them, so a result missing `shift_id`,
        // `cash_drawer_session_id`, `payment_revision`, `order_revision`,
        // `auto_completed` or `server_ts` was still accepted as a payment.
        //
        // NOTE: the shift and drawer ids are validated for SHAPE only. This
        // build deliberately does not compare them to a currently selected
        // shift or drawer — that binding is D2 and is not in this slice.
        final shiftId = op['shift_id'];
        final drawerId = op['cash_drawer_session_id'];
        final paymentRevision = op['payment_revision'];
        final orderRevision = op['order_revision'];
        final autoCompleted = op['auto_completed'];
        final serverTs = op['server_ts'];
        if (shiftId is! String ||
            shiftId.trim().isEmpty ||
            drawerId is! String ||
            drawerId.trim().isEmpty ||
            paymentRevision is! int ||
            paymentRevision < 0 ||
            orderRevision is! int ||
            orderRevision < 0 ||
            autoCompleted is! bool ||
            serverTs is! String ||
            DateTime.tryParse(serverTs) == null) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // S1-R3 / F002: the final `sync_push` stamps `idempotency_replay` on
        // EVERY result it emits — false on a fresh application
        // (`20260905090001_..._002.sql:861-872`) and true when it replays a
        // stored terminal row (`:402-405`). Its ABSENCE therefore means this
        // is not a result that function produced, and defaulting it to false
        // would let a replayed application look like a first one.
        final replayRaw = op['idempotency_replay'];
        if (replayRaw is! bool) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // `order_status` is `record_payment`'s own value: the literal
        // 'completed' when it auto-closed a served order, else the order's
        // current status (`20260716090000_...sql:400-409`), constrained to the
        // D-018 vocabulary. A word outside it is not something this build can
        // show a cashier.
        final orderStatusRaw = op['order_status'];
        if (orderStatusRaw != null &&
            (orderStatusRaw is! String ||
                !kAuthoritativeOrderStatuses.contains(orderStatusRaw))) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // PDR-002: an APPLIED payment must name the order it settled. The
        // final `record_payment` always returns `order_id`, so its absence is
        // an unreadable result rather than an older server.
        if (resultOrderId is! String || resultOrderId.trim().isEmpty) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // RF-117: the server ECHOES the recorded tender method.
        //
        // PDR-002: it is no longer allowed to fall back to the REQUESTED
        // tender. That fallback turned both a missing method and a method the
        // server disagreed with into "whatever we asked for", which is exactly
        // how a card payment could be recorded locally as cash. An applied
        // result must state our tender itself.
        final recordedMethod = PaymentMethod.fromWire(op['method']);
        if (recordedMethod == null || recordedMethod != attempt.method) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.appliedUnparseable,
          );
        }
        // ORDER-AUTO-COMPLETION-001: the server reports the order's FINAL
        // status here — `completed` when this payment auto-closed a served
        // order. Absent means "not told", and is validated above.
        return PaymentSendAccepted(
          PaymentAttemptResolution(
            paymentId: paymentId,
            receiptNumber: receiptNumber,
            changeDueMinor: changeMinor,
            method: recordedMethod,
            replay: replayRaw,
            orderStatus: orderStatusRaw as String?,
          ),
        );
      case 'conflict':
        // S1-F002: every terminal refusal must SAY it failed. A row claiming
        // both a refusal status and success is contradictory evidence.
        if (op['ok'] != false) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.malformedResponse,
          );
        }
        // S1-R3 / F002 — EXACTLY the two tuples the source emits under this
        // status word, matched as complete tuples rather than as a list of
        // independently sufficient clues. The R2 build treated every
        // non-collision conflict as a memoized revision refusal, so an
        // unrelated malformed conflict retired the identity.
        //
        //  * IDENTITY COLLISION (`20260905090001_..._002.sql:398-400`):
        //    error 'conflict' + the exact detail text + no sqlstate.
        //  * REVISION CONFLICT (`:790-800`): error 'conflict' + sqlstate
        //    '40001' + no detail.
        if (!_replayIsSourceShaped(op)) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.malformedResponse,
          );
        }
        const collisionDetail =
            'idempotency key already used for a different operation/payload';
        if (error == 'conflict' &&
            detail == collisionDetail &&
            op['sqlstate'] == null) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.identityCollision,
          );
        }
        if (error == 'conflict' &&
            op['sqlstate'] == '40001' &&
            detail == null) {
          return const PaymentSendRefused(
            PaymentRefusalCode.revisionConflict,
            memoized: true,
          );
        }
        return const PaymentSendUnconfirmed(
          PaymentUnconfirmedReason.malformedResponse,
        );
      case 'pending':
        // `dependency_not_ready`: parked server-side, not executed. S1-R4 /
        // F002: the source stamps the replay boolean here too
        // (20260905090001_..._002.sql:432-436), so a result without it is not
        // a shape that function emits. It stays NON-TERMINAL either way — a
        // parse failure never becomes a refusal.
        if (!_replayIsSourceShaped(op)) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.malformedResponse,
          );
        }
        return PaymentSendNotApplied(error is String ? error : 'pending');
      default:
        // `rejected` and `dead` — the two terminal refusal words the ledger
        // replays forever. Nothing else reaches here: the allowlist above
        // already sent every undecided word to `unconfirmed`.
        if (op['ok'] != false) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.malformedResponse,
          );
        }
        if (!_replayIsSourceShaped(op)) {
          return const PaymentSendUnconfirmed(
            PaymentUnconfirmedReason.malformedResponse,
          );
        }
        // S1-R3 / F002 — the source emits a REJECTED payment result in exactly
        // two shapes, and each is matched as a complete tuple:
        //
        //  A. A caught RAISE, rebuilt by sync_push
        //     (`20260905090001_..._002.sql:834-853`):
        //       error 'rejected' + a `sqlstate` + `detail` that is exactly
        //       null, 'precondition_failed' or 'revoked_employee'.
        //     Plus the dedicated RFDM0 normalisation (`:806-820`):
        //       error 'dispatch_mode_not_allowed' + its fixed detail.
        //
        //  B. A RETURNED domain refusal from `record_payment`, merged through
        //     verbatim (`:866-872`). The only one that function returns rather
        //     than raises is `order_not_chargeable`
        //     (`20260716090000_...sql:256-259`): error + `order_id` +
        //     `server_ts`, and NO `sqlstate` and NO `detail`.
        //
        // Anything else — a returned-shape error carrying a raise-shape
        // `detail`, an unknown token, or a contradictory pair — is evidence
        // this build cannot read, and an unreadable refusal must never retire
        // an identity.
        // S1-R4 / F002: a caught rejection always carries the RAISE's own
        // SQLSTATE (20260905090001_..._002.sql:834-853). An empty string is
        // not a SQLSTATE, and treating one as a valid tuple let a malformed
        // result retire an identity.
        //
        // S1-R5 / F002: and neither is any other non-SQLSTATE text. R4 asked
        // only that the value be non-blank, while this class already owns the
        // exact predicate it needed — a SQLSTATE is exactly five uppercase
        // alphanumerics. `NOT-A-SQLSTATE` therefore terminalized an attempt as
        // a memoized refusal. The existing [_isSqlState] predicate is now the
        // single rule for both the caught-exception path and this one.
        final sqlstate = op['sqlstate'];
        final sqlstateIsReal = sqlstate is String && _isSqlState(sqlstate);
        if (error == 'rejected' && sqlstateIsReal) {
          return switch (detail) {
            null => const PaymentSendRefused(
              PaymentRefusalCode.generic,
              memoized: true,
            ),
            'precondition_failed' => const PaymentSendRefused(
              PaymentRefusalCode.shiftRequired,
              memoized: true,
            ),
            'revoked_employee' => const PaymentSendRefused(
              PaymentRefusalCode.revokedEmployee,
              memoized: true,
            ),
            _ => const PaymentSendUnconfirmed(
              PaymentUnconfirmedReason.malformedResponse,
            ),
          };
        }
        if (error == 'dispatch_mode_not_allowed' &&
            detail == 'direct_print_requires_printer_only_branch' &&
            sqlstate == null) {
          return const PaymentSendRefused(
            PaymentRefusalCode.generic,
            memoized: true,
          );
        }
        if (sqlstate == null && detail == null) {
          // S1-R4 / F002: both RETURNED domain refusals emit `order_id`
          // unconditionally (20260716090000_..._contracts.sql:187-188 and
          // :256-258), so the binding is REQUIRED here rather than checked
          // only when present. A refusal that cannot name the order it refused
          // is not evidence about this attempt.
          final refusalOrderId = op['order_id'];
          final orderBindingHolds =
              refusalOrderId is String && refusalOrderId == attempt.orderId;
          // S1-R5 / F002: `record_payment` returns BOTH of these refusals with
          // its own `server_ts` alongside the order binding
          // (20260716090000_..._contracts.sql:187-188 and :256-258), and
          // sync_push merges the tuple through verbatim. R4 required the
          // binding but not the stamp, so a refusal missing it — or carrying
          // text that is not a timestamp — still retired a payment identity.
          // Both are now required, together, before either word is believed.
          //
          // This is deliberately scoped to the two RETURNED domain refusals.
          // The pre-dispatch validation rejections below are answered by
          // `sync_push` itself without reaching `record_payment`, so they
          // carry no such tuple and none is demanded of them.
          final refusalServerTs = op['server_ts'];
          final serverTsHolds =
              refusalServerTs is String &&
              DateTime.tryParse(refusalServerTs) != null;
          final returnedTupleHolds = orderBindingHolds && serverTsHolds;
          switch (error) {
            case 'order_not_chargeable':
              return returnedTupleHolds
                  ? const PaymentSendRefused(
                      PaymentRefusalCode.notChargeable,
                      memoized: true,
                    )
                  : const PaymentSendUnconfirmed(
                      PaymentUnconfirmedReason.malformedResponse,
                    );
            case 'permission_denied':
              return returnedTupleHolds
                  ? const PaymentSendRefused(
                      PaymentRefusalCode.permissionDenied,
                      memoized: true,
                    )
                  : const PaymentSendUnconfirmed(
                      PaymentUnconfirmedReason.malformedResponse,
                    );
            // Pre-dispatch validation rejections are answered by sync_push
            // WITHOUT claiming a ledger row, so they are not memoized.
            case 'unknown_operation_type':
            case 'invalid_payload':
            case 'invalid_depends_on':
              return const PaymentSendRefused(
                PaymentRefusalCode.generic,
                memoized: false,
              );
          }
        }
        return const PaymentSendUnconfirmed(
          PaymentUnconfirmedReason.malformedResponse,
        );
    }
  }

  /// Whether [row] is shaped like a row this feed actually projects.
  ///
  /// Required of EVERY row, whatever operation it belongs to. Payment-specific
  /// requirements are applied only to the row that claims to be ours, so an
  /// unrelated operation type is skipped rather than rejected.
  ///
  /// S1-R5 / F002 — the COMPLETE tracked projection, not a subset of it.
  ///
  /// `jsonb_build_object` emits all FIFTEEN keys for every row it builds
  /// (`20260729090000_..._direct_print_dispatch.sql:1334-1348`), with `null`
  /// for a SQL NULL, so a genuine row always CARRIES every key. R4 checked
  /// five of them, and Codex proved the two consequences: a row missing
  /// `target_entity` was silently skipped and the page became a definitive
  /// `notFound`, and a row missing `server_received_at` sat beside a real
  /// candidate that was then believed. Presence, type and nullability now all
  /// come from the tracked column definitions
  /// (`20260622110000_rf056_sync_operations_push.sql`).
  static bool _isFeedRowShaped(Object? row) {
    if (row is! Map) return false;
    // NOT NULL columns: always a non-empty projected value.
    for (final key in const <String>[
      'id',
      'local_operation_id',
      'operation_type',
      'status',
      'updated_at',
      'server_received_at',
    ]) {
      final value = row[key];
      if (value is! String || value.isEmpty) return false;
    }
    // NULLABLE text/uuid columns: the key is always projected; the value is
    // either null or a non-empty string.
    for (final key in const <String>[
      'target_entity',
      'target_id',
      'last_error_code',
      'last_error_class',
      'rejection_reason',
      'applied_at',
    ]) {
      if (!row.containsKey(key)) return false;
      final value = row[key];
      if (value != null && (value is! String || value.isEmpty)) return false;
    }
    // NULLABLE jsonb columns. PRESENCE is the generic requirement; the
    // INNER grammar of `result` deliberately is not checked here. That value
    // is the stored decision itself, and [_classifyLedgerRow] already
    // adjudicates it for the row claiming to be ours — giving the more precise
    // collision-class answer for an unreadable stored result rather than the
    // blunt "this whole scan is malformed". Rejecting it at this level would
    // replace a specific, already-proven classification with a weaker one.
    for (final key in const <String>['result', 'conflict_info']) {
      if (!row.containsKey(key)) return false;
    }
    // NOT NULL integer carrying a `>= 0` check constraint.
    final retryCount = row['retry_count'];
    if (retryCount is! int || retryCount < 0) return false;
    return true;
  }

  /// A stable identity for one feed cursor, used to refuse a repeated page.
  static String _cursorFingerprint(Map<String, dynamic> cursor) =>
      '${cursor['updated_at']}|${cursor['id']}';

  /// Whether [next] is strictly after [current] in the feed's own ordering,
  /// `(updated_at asc, id asc)`. Both components are compared as the strings
  /// the source projects; ISO-8601 UTC instants order lexicographically.
  static bool _cursorAdvances(
    Map<String, dynamic> current,
    Map<String, dynamic> next,
  ) {
    final currentAt = current['updated_at'];
    final nextAt = next['updated_at'];
    if (currentAt is! String || nextAt is! String) return false;
    final byTime = nextAt.compareTo(currentAt);
    if (byTime > 0) return true;
    if (byTime < 0) return false;
    final currentId = current['id'];
    final nextId = next['id'];
    if (currentId is! String || nextId is! String) return false;
    return nextId.compareTo(currentId) > 0;
  }

  /// Adjudicates ONE ledger row for [attempt]. Never overwrites the stored
  /// inner evidence: every outer/inner disagreement is a collision-class
  /// answer, never a silently reconciled one.
  static PaymentAttemptStatusLookup _classifyLedgerRow(
    Map<Object?, Object?> r,
    PaymentAttempt attempt,
  ) {
    if (r['operation_type'] != 'payment.create') {
      return const PaymentAttemptStatusCollision();
    }
    // This feed is the ONE read that exposes the outer provisional target and
    // entity, so both are REQUIRED. A row that cannot name our target is not
    // proof about our attempt.
    if (r['target_entity'] != 'payment') {
      return const PaymentAttemptStatusCollision();
    }
    final rowTarget = r['target_id'];
    if (rowTarget is! String || rowTarget != attempt.targetId) {
      return const PaymentAttemptStatusCollision();
    }
    // The ledger's status vocabulary (sync_operations CHECK): the four
    // TERMINAL words replay forever; every other word is a row the server has
    // not decided (a re-push adopts it) — still pending.
    final status = r['status'];
    switch (status) {
      case 'applied':
      case 'rejected':
      case 'conflict':
      case 'dead':
        break;
      default:
        return const PaymentAttemptStatusInProgress();
    }
    // A terminal row whose stored result is absent, null or not an object is
    // UNREADABLE terminal evidence.
    final result = r['result'];
    if (result is! Map) return const PaymentAttemptStatusCollision();
    final Map<String, dynamic> inner;
    try {
      inner = result.cast<String, dynamic>().map(MapEntry.new);
    } catch (_) {
      return const PaymentAttemptStatusCollision();
    }
    // The stored inner identity is VALIDATED against the outer row rather than
    // overwritten by it.
    for (final entry in <String, Object?>{
      'local_operation_id': r['local_operation_id'],
      'operation_type': r['operation_type'],
    }.entries) {
      final innerValue = inner[entry.key];
      if (innerValue != null && innerValue != entry.value) {
        return const PaymentAttemptStatusCollision();
      }
    }
    final innerStatus = inner['status'];
    if (innerStatus != null && innerStatus != status) {
      return const PaymentAttemptStatusCollision();
    }
    // S1-R3 / F002: the STORED result carries its own `idempotency_replay`
    // from when the server decided it. The R2 build stamped `true` over it
    // before classifying, which both hid a malformed stored value and lied
    // about what the ledger actually holds. The replay fact of THIS read — a
    // ledger row is by definition a replay of a stored decision — is kept
    // separate from the stored evidence and is not written into it.
    // S1-R4 / F002: what the LEDGER can hold. `sync_operations.result` is
    // written from `record_payment`'s return (which stamps
    // `idempotency_replay:false`) or from a `jsonb_build_object` that carries
    // no replay key at all (20260905090001_..._002.sql:792-800, 834-853,
    // 861-872). The stamped `true` exists only on the REPLY sync_push builds
    // when it replays a stored row (:402-405) — it is never stored. A stored
    // `true` is therefore evidence this build cannot have come from the
    // tracked writer, and R3 wrongly trusted it by overwriting the field
    // before classifying.
    final storedReplay = inner['idempotency_replay'];
    if (storedReplay != null && storedReplay is! bool) {
      return const PaymentAttemptStatusCollision();
    }
    if (storedReplay == true) return const PaymentAttemptStatusCollision();
    // The REPLAY fact of this read belongs to the read, not to the stored
    // bytes: a ledger row IS a stored decision being replayed, which is
    // exactly what `sync_push` stamps when it replays one
    // (`20260905090001_..._002.sql:402-405`). The stored value is validated
    // above and never rewritten to hide a contradiction; some stored refusal
    // results legitimately carry none at all (`:848-853`).
    final merged = <String, dynamic>{
      ...inner,
      'local_operation_id': r['local_operation_id'],
      'operation_type': r['operation_type'],
      'status': status,
      'idempotency_replay': true,
    };
    return switch (classifyEnvelope(
      <String, dynamic>{
        'ok': true,
        'results': <dynamic>[merged],
      },
      attempt,
      fromLiveReply: false,
    )) {
      PaymentSendAccepted(:final resolution) => PaymentAttemptStatusApplied(
        resolution,
      ),
      PaymentSendRefused(:final code) => PaymentAttemptStatusRefused(code),
      // A terminal row whose stored outcome this build cannot read is a
      // collision-class answer: never success, never a fresh key.
      PaymentSendNotApplied() ||
      PaymentSendUnconfirmed() ||
      PaymentSendAuthRequired() => const PaymentAttemptStatusCollision(),
    };
  }

  /// READ-ONLY status of [attempt] from the server's per-device operation
  /// ledger (`sync_pull` → `operation_statuses`, this org + this device only).
  /// Pages forward from a cursor well before the attempt was created, looking
  /// for its `local_operation_id`. Executes nothing.
  @override
  Future<PaymentAttemptStatusLookup> lookupAttemptStatus(
    PaymentAttempt attempt,
  ) async {
    final transport = _transport;
    final session = _session;
    if (transport == null || session == null) {
      return const PaymentAttemptStatusUnavailable('unavailable');
    }
    if (attempt.deviceId != session.deviceId) {
      return const PaymentAttemptStatusUnavailable('device_mismatch');
    }
    final created =
        DateTime.tryParse(attempt.clientCreatedAt)?.toUtc() ?? _now().toUtc();
    var cursor = <String, dynamic>{
      // Generous slack for client/server clock skew; the ledger row's
      // updated_at is server time.
      'updated_at': created
          .subtract(const Duration(hours: 24))
          .toIso8601String(),
      'id': '00000000-0000-0000-0000-000000000000',
    };
    // S1-R3 / F002 — the scan is COMPLETE within its bound. The R2 build
    // returned as soon as one page carried a matching row, so it could not see
    // the same operation again on a later page. Candidates are now collected
    // across the whole bounded window and only adjudicated once the window has
    // been walked cleanly.
    final candidates = <Map<Object?, Object?>>[];
    final visitedCursors = <String>{_cursorFingerprint(cursor)};
    for (var page = 0; page < 8; page++) {
      final Object? raw;
      try {
        raw = await transport.invoke('sync_pull', <String, dynamic>{
          'p_pin_session_id': session.pinSessionId,
          'p_device_id': session.deviceId,
          'p_entities': <String>['operation_statuses'],
          'p_cursors': <String, dynamic>{'operation_statuses': cursor},
          'p_limit': 500,
        });
      } on SyncTransportException catch (e) {
        // A partial scan is not an absence, whatever earlier pages held.
        return PaymentAttemptStatusUnavailable(e.code ?? e.kind.name);
      }
      if (raw is! Map || raw['ok'] != true) {
        return const PaymentAttemptStatusUnavailable('malformed');
      }
      final ops = raw['operation_statuses'];
      if (ops is! Map) {
        return const PaymentAttemptStatusUnavailable('malformed');
      }
      final rows = ops['rows'];
      if (rows is! List) {
        return const PaymentAttemptStatusUnavailable('malformed');
      }
      for (final r in rows) {
        // S1-R4 / F002 — EVERY row is validated against the GENERIC feed
        // schema before any terminal or absence decision.
        //
        // The tracked projection builds all fifteen keys for every operation
        // type (20260729090000_...sql:1333-1349), so a scalar, or a map
        // missing its own identity, is not a row this feed produces. R3
        // silently skipped both, which let a malformed page become a
        // definitive `notFound` and let a malformed later row sit beside an
        // earlier candidate that was then believed. A row this build cannot
        // read means the scan itself is not trustworthy — never absence.
        if (!_isFeedRowShaped(r)) {
          return const PaymentAttemptStatusUnavailable('malformed_row');
        }
        final row = r as Map;
        // Rows for OTHER operations are perfectly legitimate here; they are
        // simply not ours. Only the generic schema is required of them.
        if (row['local_operation_id'] == attempt.localOperationId) {
          candidates.add(row);
        }
      }
      // More than one row for one operation identity — on this page or across
      // pages — is not evidence this build may act on.
      if (candidates.length > 1) return const PaymentAttemptStatusCollision();

      // `has_more` is a real boolean in the tracked feed
      // (`20260729090000_...sql:1366`: `(v_op_count > v_limit)`). A missing or
      // wrongly typed value is a reply this build cannot read — never a
      // cheerful end-of-feed.
      final hasMore = ops['has_more'];
      if (hasMore is! bool) {
        return const PaymentAttemptStatusUnavailable('malformed_has_more');
      }
      if (!hasMore) {
        // The window was walked cleanly to its end. Only now may absence or a
        // single candidate be believed.
        return candidates.isEmpty
            ? const PaymentAttemptStatusNotFound()
            : _classifyLedgerRow(candidates.single, attempt);
      }
      // The feed says there is more, so the cursor must be exactly the shape
      // the source projects (`:1361`:
      // `jsonb_build_object('updated_at', _uat, 'id', _id)`) and must ADVANCE
      // in the feed's own `(updated_at asc, id asc)` order (`:1352,1359`).
      // Anything else stops the scan instead of issuing another call.
      final next = ops['next_cursor'];
      if (next is! Map) {
        return const PaymentAttemptStatusUnavailable('malformed_cursor');
      }
      final nextUpdatedAt = next['updated_at'];
      final nextId = next['id'];
      if (nextUpdatedAt is! String ||
          nextId is! String ||
          nextUpdatedAt.isEmpty ||
          nextId.isEmpty ||
          next.keys.length != 2) {
        return const PaymentAttemptStatusUnavailable('malformed_cursor');
      }
      final nextCursor = <String, dynamic>{
        'updated_at': nextUpdatedAt,
        'id': nextId,
      };
      if (!_cursorAdvances(cursor, nextCursor)) {
        return const PaymentAttemptStatusUnavailable('cursor_did_not_advance');
      }
      if (!visitedCursors.add(_cursorFingerprint(nextCursor))) {
        return const PaymentAttemptStatusUnavailable('cursor_repeated');
      }
      cursor = nextCursor;
    }
    return const PaymentAttemptStatusUnavailable('too_many_pages');
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
  CashPayment? paymentFor(PosOrderIdentity identity) => null;
}

/// STALE-TABLE-ORDER-RECOVERY-001: recognizes `app.record_payment`'s
/// precondition refusals (raised as 42501 with a "(precondition_failed)"
/// message: no open shift for this branch/device, or no active cash drawer).
bool isNoOpenShiftRefusal(SyncTransportException e) {
  final text = '${e.message ?? ''} ${e.code ?? ''}'.toLowerCase();
  return text.contains('precondition_failed') ||
      text.contains('no open shift') ||
      text.contains('no active cash drawer');
}
