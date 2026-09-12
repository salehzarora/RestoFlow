// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R2 — the DECODER and QUARANTINE probes.
//
// Adopted verbatim in substance from the external Codex delta review that
// raised S1-F003: the stored-record decoder accepted evidence it could not
// justify (a non-boolean replay flag, negative change, a resolution naming a
// different tender than the frozen one, an unusable or contradictory
// timestamp, an accepted record with no one-time effect claim) and the
// envelope accepted a non-integer schema version.
//
// The contract asserted here is the same one the store already owed: anything
// this build cannot fully read is QUARANTINED, the raw bytes stay
// byte-for-byte intact, and no attempt is loaded from them. The last test is
// the positive control that keeps these rules from passing vacuously.
//
// Synthetic ids and amounts only. No network, no printer, no drawer.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:shared_preferences/shared_preferences.dart';

const _scope = PosSyncScope(
  organizationId: 'org-reviewer',
  restaurantId: 'restaurant-reviewer',
  branchId: 'branch-reviewer',
  deviceId: 'device-reviewer',
);

const _timestamp = '2026-09-09T08:00:00.000Z';

Map<String, Object?> _accepted() => <String, Object?>{
  'local_operation_id': 'op-reviewer',
  'target_id': 'target-reviewer',
  'client_created_at': _timestamp,
  // CHANGED IN S1-R4: `identity_key` is the canonical derivation from the
  // frozen order (`PosOrderIdentity.server` -> `srv:<orderId>`,
  // order_identity.dart:45). The old `server:` spelling is a value this
  // project never produces, which is why the fixture failed to exercise the
  // identity invariant at all.
  'identity_key': 'srv:order-reviewer',
  'order_id': 'order-reviewer',
  'order_number': '#REVIEWER',
  'expected_revision': 7,
  'tender_type': 'cash',
  'amount_minor': 4000,
  'amount_tendered_minor': 5000,
  'currency_code': 'ILS',
  'organization_id': _scope.organizationId,
  'restaurant_id': _scope.restaurantId,
  'branch_id': _scope.branchId,
  'device_id': _scope.deviceId,
  'employee_profile_id': 'employee-reviewer',
  'phase': 'accepted',
  'last_outcome': 'none',
  'sent_at': _timestamp,
  'resolved_at': _timestamp,
  'resolution': <String, Object?>{
    'payment_id': 'payment-reviewer',
    'receipt_number': 'receipt-reviewer',
    'change_due_minor': 1000,
    'method': 'cash',
    'replay': false,
    'order_status': 'completed',
  },
  'refusal': null,
  'refusal_memoized': false,
  'auto_effects_reserved_at': _timestamp,
  'supersedes': null,
};

Future<({PaymentAttemptLoad load, SharedPreferences prefs, String raw})>
_loadEnvelope({
  required Object? version,
  required List<Object?> attempts,
}) async {
  final key = paymentAttemptsStorageKey(_scope.key);
  final raw = jsonEncode(<String, Object?>{
    'version': version,
    'attempts': attempts,
  });
  SharedPreferences.setMockInitialValues(<String, Object>{key: raw});
  final prefs = await SharedPreferences.getInstance();
  final load = await SharedPrefsPaymentAttemptStore(prefs).load(_scope);
  return (load: load, prefs: prefs, raw: raw);
}

Future<void> _expectRecordQuarantined(Map<String, Object?> record) async {
  final result = await _loadEnvelope(version: 1, attempts: <Object?>[record]);
  expect(result.load.attempts, isEmpty);
  expect(result.load.quarantined, hasLength(1));
  expect(result.load.quarantined.single.reason, 'record');
  expect(
    result.prefs.getString(paymentAttemptsStorageKey(_scope.key)),
    result.raw,
    reason: 'unreadable evidence must remain byte-for-byte intact',
  );
}

Future<void> _expectEnvelopeQuarantined(Object? version) async {
  final result = await _loadEnvelope(
    version: version,
    attempts: <Object?>[_accepted()],
  );
  expect(result.load.attempts, isEmpty);
  expect(result.load.quarantined, hasLength(1));
  expect(result.load.quarantined.single.reason, 'envelope');
  expect(
    result.prefs.getString(paymentAttemptsStorageKey(_scope.key)),
    result.raw,
    reason: 'unknown envelope bytes must remain intact',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is deliberately isolate-wide
  // and impossible to clear at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  test(
    'REVIEWER-DECODER-001 resolution replay wrong type is quarantined without throwing',
    () async {
      final record = _accepted();
      (record['resolution']! as Map<String, Object?>)['replay'] = 'false';
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-002 negative change is quarantined without throwing',
    () async {
      final record = _accepted();
      (record['resolution']! as Map<String, Object?>)['change_due_minor'] = -1;
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-003 resolution method and frozen tender mismatch is quarantined',
    () async {
      final record = _accepted();
      (record['resolution']! as Map<String, Object?>)['method'] = 'card';
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-004 blank resolved timestamp is quarantined without throwing',
    () async {
      final record = _accepted()..['resolved_at'] = '   ';
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-005 malformed resolved timestamp is quarantined without throwing',
    () async {
      final record = _accepted()..['resolved_at'] = 'not-a-timestamp';
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-006 accepted missing auto effects reservation is quarantined',
    () async {
      final record = _accepted()..remove('auto_effects_reserved_at');
      await _expectRecordQuarantined(record);
    },
  );

  test(
    'REVIEWER-DECODER-007 fractional envelope version is quarantined without throwing',
    () async => _expectEnvelopeQuarantined(1.5),
  );

  test(
    'REVIEWER-DECODER-008 string envelope version is quarantined without throwing',
    () async => _expectEnvelopeQuarantined('1'),
  );

  test(
    'REVIEWER-DECODER-009 valid accepted record loads as positive control',
    () async {
      final result = await _loadEnvelope(
        version: 1,
        attempts: <Object?>[_accepted()],
      );
      expect(result.load.quarantined, isEmpty);
      expect(result.load.attempts, hasLength(1));
      final attempt = result.load.attempts.single;
      expect(attempt.phase, PaymentAttemptPhase.accepted);
      expect(attempt.resolution?.changeDueMinor, 1000);
      expect(attempt.resolution?.method.wire, 'cash');
      expect(attempt.autoEffectsReservedAt, _timestamp);
    },
  );

  // =========================================================================
  // S1-R2 / F003 — the WRITER-STATE controls.
  //
  // Strictness is only safe if it accepts everything the PRODUCTION WRITER
  // actually emits. Each state below is produced by the model's own
  // transitions — the same calls the store makes — and must survive the
  // decoder unchanged, with no quarantine. Without these, tightening the
  // decoder could quietly quarantine real money records.
  group('S1R2-F003 — every state the writer produces still round-trips', () {
    PaymentAttempt minted() => PaymentAttempt.mint(
      ids: FixedClientIdGenerator(const ['op-writer', 'op-writer-target']),
      now: DateTime.parse(_timestamp),
      orderId: 'order-reviewer',
      orderNumber: '#REVIEWER',
      amountMinor: 4000,
      tenderedMinor: 5000,
      currencyCode: 'ILS',
      method: PaymentMethod.cash,
      expectedRevision: 7,
      organizationId: _scope.organizationId,
      restaurantId: _scope.restaurantId,
      branchId: _scope.branchId,
      deviceId: _scope.deviceId,
      employeeProfileId: 'employee-reviewer',
    );

    const resolution = PaymentAttemptResolution(
      paymentId: 'payment-reviewer',
      receiptNumber: 'receipt-reviewer',
      changeDueMinor: 1000,
      method: PaymentMethod.cash,
      replay: false,
      orderStatus: 'completed',
    );

    Future<PaymentAttempt> roundTrip(PaymentAttempt attempt) async {
      final result = await _loadEnvelope(
        version: PaymentAttempt.schemaVersion,
        attempts: <Object?>[attempt.toJson()],
      );
      expect(
        result.load.quarantined,
        isEmpty,
        reason: 'a record this build WROTE must stay readable',
      );
      return result.load.attempts.single;
    }

    test('S1R2-F003w1 a freshly minted pending record round-trips', () async {
      final back = await roundTrip(minted());
      expect(back.phase, PaymentAttemptPhase.pending);
      expect(back.lastOutcome, PaymentAttemptLastOutcome.none);
      expect(back.sentAt, isNull);
      expect(back.localOperationId, 'op-writer');
    });

    test('S1R2-F003w2 a SENT pending record round-trips', () async {
      final back = await roundTrip(minted().markSent(_timestamp));
      expect(back.phase, PaymentAttemptPhase.pending);
      expect(back.sentAt, _timestamp);
    });

    test(
      'S1R2-F003w3 every in-flight note the writer can store round-trips',
      () async {
        final observed = <String, String>{};
        for (final outcome in PaymentAttemptLastOutcome.values) {
          final back = await roundTrip(
            minted().markSent(_timestamp).withLastOutcome(outcome),
          );
          observed[outcome.wire] = back.lastOutcome.wire;
        }
        expect(observed, <String, String>{
          for (final o in PaymentAttemptLastOutcome.values) o.wire: o.wire,
        });
      },
    );

    test(
      'S1R2-F003w4 an ACCEPTED record with its effect claim round-trips',
      () async {
        final back = await roundTrip(
          minted()
              .markSent(_timestamp)
              .accepted(resolution, at: _timestamp, reserveEffects: true),
        );
        expect(back.phase, PaymentAttemptPhase.accepted);
        expect(back.autoEffectsReservedAt, _timestamp);
        expect(back.resolution?.paymentId, 'payment-reviewer');
        expect(back.resolution?.changeDueMinor, 1000);
        expect(back.resolution?.orderStatus, 'completed');
      },
    );

    test(
      'S1R2-F003w5 a REFUSED record round-trips, memoized and not',
      () async {
        final observed = <bool, String>{};
        for (final memoized in const <bool>[true, false]) {
          final back = await roundTrip(
            minted()
                .markSent(_timestamp)
                .refused(
                  PaymentRefusalCode.shiftRequired,
                  at: _timestamp,
                  memoized: memoized,
                ),
          );
          observed[memoized] = '${back.phase.wire}/${back.refusalMemoized}';
        }
        expect(observed, <bool, String>{
          true: 'refused/true',
          false: 'refused/false',
        });
      },
    );

    test('S1R2-F003w7 a record resolved on the PASSIVE path round-trips, and '
        'still holds the one-time effect claim', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final claim = await store.createIfAbsent(_scope, minted());

      // `armCaller: false` is boot / hydration / Check Status: the claim is
      // CONSUMED so nothing can arm it later, but the caller is never told it
      // may fire a receipt or a drawer kick.
      final acceptance = await store.resolveAccepted(
        _scope,
        claim.attempt,
        resolution,
        at: _timestamp,
        armCaller: false,
      );
      expect(acceptance.armed, isFalse);

      // A fresh store over the same preferences reads it back intact.
      final reread = await SharedPrefsPaymentAttemptStore(prefs).load(_scope);
      expect(reread.quarantined, isEmpty);
      final back = reread.attempts.single;
      expect(back.phase, PaymentAttemptPhase.accepted);
      expect(
        back.autoEffectsReservedAt,
        isNotNull,
        reason: 'the claim was consumed by the passive resolution',
      );
      expect(back.resolution?.receiptNumber, 'receipt-reviewer');
    });

    test('S1R2-F003w6 a SETTLED-ELSEWHERE record round-trips', () async {
      final back = await roundTrip(
        minted()
            .markSent(_timestamp)
            .refused(PaymentRefusalCode.generic, at: _timestamp, memoized: true)
            .settledElsewhere(at: _timestamp),
      );
      expect(back.phase, PaymentAttemptPhase.settledElsewhere);
      expect(back.refusal, isNotNull);
    });
  });
}
