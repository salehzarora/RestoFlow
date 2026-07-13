import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/void_repository.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

/// MONEY-SETTLEMENT-CONSISTENCY-001 (corrective) — the POS half of the error contract.
///
/// THE BUG. `app.sync_push` rebuilds the envelope from scratch when a dispatched RPC
/// RAISES, collapsing every domain code into a generic `rejected`. Two refusals were on
/// that path, so the POS could not see them:
///   * record_payment's zero-total refusal — the "nothing to pay" explanation was
///     unreachable;
///   * void_order's terminal-order refusal — an already-closed order was indistinguishable
///     from a dropped network, so the POS GUESSED "already closed" from a zero total. That
///     could tell an operator an order was closed when the connection had merely failed.
///
/// Both now RETURN a stable code, which sync_push passes through verbatim. These tests
/// drive the REAL repositories over a fake transport and pin that ONLY the exact code may
/// produce the specific outcome — never a raw message, never a SQLSTATE, never the total.
Future<AppLocalizations> _l(String code) =>
    AppLocalizations.delegate.load(Locale(code));

SubmittedOrderView _view(String n, {int total = 4200}) => SubmittedOrderView(
  orderNumber: n,
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: total,
  orderId: 'oid-$n',
  lines: [
    SubmittedLineView(
      name: 'Burger',
      quantity: 1,
      lineTotalMinor: total,
      currencyCode: 'ILS',
    ),
  ],
);

void main() {
  // ===== 27. PaymentRepository maps the EXACT order_not_chargeable code ========
  test(
    '27 the payment path maps the exact order_not_chargeable code',
    () async {
      final e = await _payment(
        _reply(<String, Object?>{
          'ok': false,
          'error': 'order_not_chargeable',
          'status': 'rejected',
        }),
      );

      expect(e, isA<PaymentException>());
      expect(
        e!.notChargeable,
        isTrue,
        reason: 'the typed flag is what drives the localized explanation',
      );
    },
  );

  // ===== 29. a generic/other rejection must NOT read as non-chargeable ========
  test('29 a generic rejection is NOT order_not_chargeable', () async {
    for (final error in <String>[
      'rejected', // the OLD collapsed code — must NEVER become the domain refusal
      'conflict',
      'permission_denied',
    ]) {
      final e = await _payment(
        _reply(<String, Object?>{
          'ok': false,
          'error': error,
          'sqlstate': '42501',
          'status': 'rejected',
        }),
      );
      expect(e, isA<PaymentException>(), reason: error);
      expect(
        e!.notChargeable,
        isFalse,
        reason: '$error must stay a plain, retryable failure',
      );
    }
  });

  test('29b a TRANSPORT failure is NOT order_not_chargeable', () async {
    final e = await _payment(null); // the transport throws before any verdict
    expect(e, isA<PaymentException>());
    expect(
      e!.notChargeable,
      isFalse,
      reason: 'a dropped network says NOTHING about the order',
    );
  });

  // ===== 30. a MALFORMED payment envelope stays generic =======================
  test('30 a MALFORMED payment envelope is NOT order_not_chargeable', () async {
    for (final raw in <Object?>[
      'nonsense',
      <String, Object?>{}, // no results
      <String, Object?>{'results': <Object?>[]}, // empty
      <String, Object?>{
        'results': <Object?>[
          <String, Object?>{'local_operation_id': 'someone-else'},
        ],
      },
    ]) {
      final e = await _payment(_raw(raw));
      expect(e, isA<PaymentException>(), reason: '$raw');
      expect(
        e!.notChargeable,
        isFalse,
        reason: 'a malformed envelope tells us NOTHING about the order',
      );
    }
  });

  // ===== 31. only the EXACT terminal code may claim "already closed" ==========
  test(
    '31 the EXACT terminal code produces the not-voidable refusal',
    () async {
      final e = await _void(
        _reply(<String, Object?>{
          'ok': false,
          'error': 'invalid_transition',
          'detail': 'order_not_voidable',
          'order_status': 'completed',
          'status': 'rejected',
        }),
      );

      expect(e!.notVoidable, isTrue);
      expect(e.alreadyPaid, isFalse);
      expect(e.permissionDenied, isFalse);
      expect(e.transport, isFalse);
      expect(e.conflict, isFalse);
    },
  );

  // ===== 34. the completed-payment block keeps its OWN typed refusal ==========
  test('34 the completed-payment block stays distinguishable', () async {
    final e = await _void(
      _reply(<String, Object?>{
        'ok': false,
        'error': 'permission_denied',
        'detail': 'order_has_completed_payment',
        'status': 'rejected',
      }),
    );

    expect(e!.alreadyPaid, isTrue);
    expect(
      e.notVoidable,
      isFalse,
      reason: 'a PAID order is not an ALREADY-CLOSED order',
    );
  });

  // ===== 35. an authorization denial keeps its OWN typed refusal ==============
  test('35 an authorization denial stays distinguishable', () async {
    final e = await _void(
      _reply(<String, Object?>{
        'ok': false,
        'error': 'permission_denied',
        'status': 'rejected',
      }),
    );

    expect(e!.permissionDenied, isTrue);
    expect(e.notVoidable, isFalse);
    expect(e.alreadyPaid, isFalse);
  });

  // ===== 36. a GENERIC rejection is NEVER converted into "already closed" =====
  test('36 a GENERIC rejection is NEVER converted into terminal', () async {
    // THE regression that mattered: `rejected` is EXACTLY what sync_push used to return
    // for a terminal order, which is why the POS started guessing. It must stay unknown.
    for (final op in <Map<String, Object?>>[
      <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'sqlstate': '42501',
        'status': 'rejected',
      },
      <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'detail': 'revoked_employee',
        'status': 'rejected',
      },
      <String, Object?>{'status': 'pending'},
    ]) {
      final e = await _void(_reply(op));
      expect(e, isA<VoidException>(), reason: '$op');
      expect(
        e!.notVoidable,
        isFalse,
        reason: 'a generic rejection must NEVER claim the order is closed',
      );
      expect(e.conflict, isFalse);
      expect(e.alreadyPaid, isFalse);
      expect(e.permissionDenied, isFalse);
    }
  });

  // ===== 32. a network void failure stays retryable/generic ===================
  test('32 a TRANSPORT void failure is retryable and NEVER terminal', () async {
    final e = await _void(null);

    expect(e!.transport, isTrue);
    expect(
      e.notVoidable,
      isFalse,
      reason:
          'the request never got a verdict — the order state is UNKNOWN, and claiming '
          '"already closed" would state a fact we do not have',
    );
  });

  // ===== 33. a malformed void response stays generic ==========================
  test('33 a MALFORMED void envelope stays generic (never terminal)', () async {
    for (final raw in <Object?>[
      'nonsense',
      <String, Object?>{},
      <String, Object?>{'results': <Object?>[]},
    ]) {
      final e = await _void(_raw(raw));
      expect(e, isA<VoidException>(), reason: '$raw');
      expect(e!.notVoidable, isFalse);
      expect(e.conflict, isFalse);
      expect(e.permissionDenied, isFalse);
    }
  });

  test('a CONFLICT (stale revision) is its own typed outcome', () async {
    final e = await _void(
      _reply(<String, Object?>{
        'ok': false,
        'error': 'conflict',
        'status': 'conflict',
      }),
    );
    expect(e!.conflict, isTrue);
    expect(e.notVoidable, isFalse);
  });

  // ===== each typed outcome maps to a DISTINCT localized message (ar/he/en) ===
  test('each typed void outcome renders a DISTINCT localized message', () async {
    for (final code in ['ar', 'he', 'en']) {
      final l10n = await _l(code);
      final messages = <String>{
        l10n.posCancelPaidOrderError,
        l10n.posCancelPermissionDenied,
        l10n.posCancelOrderClosed,
        l10n.posCancelOrderConflict,
        l10n.posCancelOrderFailed, // transport / malformed / unknown
      };
      expect(
        messages.length,
        5,
        reason:
            '$code: five outcomes, five messages — sharing a string would re-introduce '
            'exactly the ambiguity this ticket removes',
      );
      for (final m in messages) {
        expect(m.trim(), isNotEmpty, reason: code);
      }
    }
  });

  // ===== 39 (P2). non-chargeable is EXACTLY zero, never `<= 0` ================
  test('39 non-chargeable is EXACTLY zero — a negative total is never "No charge"', () {
    // FIRST, the honest fact: a negative total is structurally UNREACHABLE in the POS
    // model. SubmittedOrderView.grandTotalMinor CLAMPS `subtotal - discount + tax` at
    // zero, so a corrupt negative can never surface as a PosRecentOrder total. That is
    // the real defence, and it is worth pinning.
    final clamped = PosRecentOrder(
      order: _view('#NEG', total: -1),
      submittedAt: DateTime.utc(2026, 7, 16),
    );
    expect(
      clamped.grandTotalMinor,
      0,
      reason: 'the POS view clamps a negative total to zero',
    );

    // SECOND, the predicate itself is `== 0`, NOT `<= 0`. The clamp makes the difference
    // unobservable TODAY, but `<= 0` would silently label a negative total "No charge"
    // and hide its payment/cancel controls the moment that clamp changed — hiding a money
    // defect behind a reassuring chip. `== 0` matches the canonical server rule
    // (total < 0 -> FAIL CLOSED), so the two can never drift.
    // (The reachable negative-total case lives on the Dashboard model, which does NOT
    //  clamp: see money_settlement_consistency_test.dart.)
    expect(
      clamped.isNonChargeable,
      isTrue,
      reason: 'the clamped total IS zero',
    );

    final positive = PosRecentOrder(
      order: _view('#P'),
      submittedAt: DateTime.utc(2026, 7, 16),
    );
    expect(positive.isNonChargeable, isFalse);
    expect(positive.isFullySettled, isFalse, reason: 'it owes 42.00');

    final zero = PosRecentOrder(
      order: _view('#Z', total: 0),
      submittedAt: DateTime.utc(2026, 7, 16),
    );
    expect(zero.isNonChargeable, isTrue);
    expect(zero.isFullySettled, isTrue);
    expect(zero.isTerminal, isFalse);
  });
}

// --- harness: drive the REAL repositories end-to-end ------------------------
// No private helper is reached into. Each test pushes through the repository's real public
// entry point over a fake transport returning a crafted `sync_push` envelope, echoing back
// whatever `local_operation_id` the repository actually minted — so op-matching, the status
// check and the error mapping are all genuinely exercised.

/// Builds the envelope from the op the repository sent (splicing in its real op id).
typedef _Build = Object? Function(Map<String, Object?> sentOp);

class _StubTransport implements SyncRpcTransport {
  const _StubTransport(this.build);
  final _Build? build;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    // A null builder models a wire failure: the request never reaches a verdict.
    if (build == null) {
      throw const SyncTransportException(SyncTransportErrorKind.transient);
    }
    final ops = p['p_operations'] as List<dynamic>;
    return build!((ops.first as Map).cast<String, Object?>());
  }
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'device-1');

/// A well-formed one-op envelope carrying [op], with the repository's own op id spliced in.
_Build _reply(Map<String, Object?> op) =>
    (sent) => <String, Object?>{
      'ok': true,
      'results': <Object?>[
        <String, Object?>{
          ...op,
          'local_operation_id': sent['local_operation_id'],
        },
      ],
    };

/// A raw, possibly-malformed response, returned verbatim.
_Build _raw(Object? raw) =>
    (_) => raw;

Future<PaymentException?> _payment(_Build? build) async {
  final repo = RealPaymentRepository(
    _StubTransport(build),
    _session,
    RandomClientIdGenerator(),
  );
  try {
    await repo.recordCashPayment(
      orderId: 'oid-1',
      orderNumber: '#1',
      amountMinor: 0,
      tenderedMinor: 0,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
    );
    return null;
  } on PaymentException catch (e) {
    return e;
  }
}

Future<VoidException?> _void(_Build? build) async {
  final repo = RealVoidRepository(
    _StubTransport(build),
    _session,
    RandomClientIdGenerator(),
  );
  try {
    await repo.voidOrder(orderId: 'oid-1', reason: 'wrong order');
    return null;
  } on VoidException catch (e) {
    return e;
  }
}
