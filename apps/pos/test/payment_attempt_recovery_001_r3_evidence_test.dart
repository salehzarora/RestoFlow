// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R3 — the EVIDENCE regressions (F002/F003).
//
// Adopted UNCHANGED in substance from Codex's external harness
// `reviewer_s1_r2_f002_f003_gap_test.dart` (SHA-256
// 6F8DED73001BC962F430A3E150A553C4668CF02E29F3C7C472961DE640F5A128). Every one
// of its 23 tests already asserted SAFE behaviour; at 5159338a the 6 positive
// controls passed and the 17 adversarial assertions failed, twice. Not one
// assertion, input or fixture below was altered — only this header, and the
// per-test reset of the isolate-wide physical-key boundary that the F001
// correction introduces.
//
// F002 covers the direct source-shaped tuples (replay boolean, authoritative
// order status, exact conflict and rejection tuples) and the passive scan
// (cross-page duplicates, cursor field types, non-boolean has_more, malformed
// stored replay), each with its positive control. F003 covers the envelope key
// allowlist, whitespace identities, the stored order-status vocabulary, the
// two timestamp orderings, the required memoized flag, quarantine preservation
// through update, and a same-order quarantine blocking direct creation.
//
// Synthetic data and fake transports only. No endpoint, SQL, device, or effect I/O.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        SyncRpcTransport,
        SyncSession,
        SyncTransportErrorKind,
        SyncTransportException;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException, PosSyncScope;
import 'package:shared_preferences/shared_preferences.dart';

const scope = PosSyncScope(
  organizationId: 'org-review',
  restaurantId: 'restaurant-review',
  branchId: 'branch-review',
  deviceId: 'device-review',
);

final now = DateTime.utc(2026, 9, 9, 8);

PaymentAttempt attempt({String op = 'op-review'}) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator(<String>[op, '$op-target']),
  now: now,
  orderId: 'order-review',
  orderNumber: '#REVIEW',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: 7,
  organizationId: scope.organizationId,
  restaurantId: scope.restaurantId,
  branchId: scope.branchId,
  deviceId: scope.deviceId,
  employeeProfileId: 'employee-review',
);

Map<String, dynamic> sourceApplied({bool includeReplay = true}) =>
    <String, dynamic>{
      'local_operation_id': 'op-review',
      'operation_type': 'payment.create',
      'status': 'applied',
      'ok': true,
      'payment_id': 'payment-server',
      'order_id': 'order-review',
      'method': 'cash',
      'receipt_number': '77',
      'change_due_minor': 1000,
      'shift_id': 'shift-server',
      'cash_drawer_session_id': 'drawer-server',
      'payment_revision': 1,
      'order_revision': 8,
      'auto_completed': false,
      'order_status': 'served',
      'server_ts': '2026-09-09T08:00:01.000Z',
      if (includeReplay) 'idempotency_replay': false,
    };

Map<String, dynamic> envelope(Map<String, dynamic> row) => <String, dynamic>{
  'ok': true,
  'results': <Object?>[row],
  'server_ts': '2026-09-09T08:00:02.000Z',
};

Map<String, Object?> acceptedRecord({String op = 'op-record'}) =>
    <String, Object?>{
      'local_operation_id': op,
      'target_id': '$op-target',
      'client_created_at': '2026-09-09T08:00:00.000Z',
      'identity_key': 'srv:order-record',
      'order_id': 'order-record',
      'order_number': '#RECORD',
      'expected_revision': 7,
      'tender_type': 'cash',
      'amount_minor': 4000,
      'amount_tendered_minor': 5000,
      'currency_code': 'ILS',
      'organization_id': scope.organizationId,
      'restaurant_id': scope.restaurantId,
      'branch_id': scope.branchId,
      'device_id': scope.deviceId,
      'employee_profile_id': 'employee-review',
      'phase': 'accepted',
      'last_outcome': 'none',
      'sent_at': '2026-09-09T08:00:00.000Z',
      'resolved_at': '2026-09-09T08:00:01.000Z',
      'resolution': <String, Object?>{
        'payment_id': 'payment-server',
        'receipt_number': '77',
        'change_due_minor': 1000,
        'method': 'cash',
        'replay': false,
        'order_status': 'served',
      },
      'refusal': null,
      'refusal_memoized': false,
      'auto_effects_reserved_at': '2026-09-09T08:00:01.000Z',
      'supersedes': null,
    };

Map<String, Object?> refusedRecord({String op = 'op-record'}) {
  final record = acceptedRecord(op: op);
  record
    ..['phase'] = 'refused'
    ..['resolution'] = null
    ..['refusal'] = 'precondition_failed'
    ..['refusal_memoized'] = true
    ..['auto_effects_reserved_at'] = null;
  return record;
}

class PagedTransport implements SyncRpcTransport {
  PagedTransport(this.pages);
  final List<Object?> pages;
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final index = calls++;
    final page = pages[index < pages.length ? index : pages.length - 1];
    if (page is SyncTransportException) throw page;
    return page;
  }
}

Map<String, Object?> page({
  required List<Object?> rows,
  required Object? hasMore,
  Object? nextCursor,
}) => <String, Object?>{
  'ok': true,
  'operation_statuses': <String, Object?>{
    'rows': rows,
    'has_more': hasMore,
    'next_cursor': nextCursor,
  },
};

Map<String, Object?> passiveRow({Object? result}) => <String, Object?>{
  'local_operation_id': 'op-review',
  'operation_type': 'payment.create',
  'target_entity': 'payment',
  'target_id': 'op-review-target',
  'status': 'applied',
  'result': result ?? sourceApplied(),
  // CHANGED IN S1-R4: the feed projects its own identity fields on EVERY row
  // (20260729090000_...sql:1334-1348); a row without them is not a shape the
  // tracked projection produces.
  'id': 'so-00000001',
  'updated_at': '2026-09-09T08:00:01.000Z',
  // CHANGED IN S1-R5: and the REMAINING projected keys. The tracked projection
  // builds all fifteen for every row it emits, with null for a SQL NULL, so a
  // fixture carrying a subset is a shape the source never produces. Nullability
  // follows 20260622110000_rf056_sync_operations_push.sql.
  'last_error_code': null,
  'last_error_class': null,
  'conflict_info': null,
  'rejection_reason': null,
  'retry_count': 0,
  'applied_at': '2026-09-09T08:00:01.000Z',
  'server_received_at': '2026-09-09T08:00:01.000Z',
};

Future<PaymentAttemptStatusLookup> lookup(PagedTransport transport) =>
    RealPaymentRepository(
      transport,
      const SyncSession(pinSessionId: 'pin-review', deviceId: 'device-review'),
      FixedClientIdGenerator(const <String>['unused-a', 'unused-b']),
      clock: () => now,
    ).lookupAttemptStatus(attempt());

Future<PaymentAttemptLoad> loadRaw(String raw) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    paymentAttemptsStorageKey(scope.key): raw,
  });
  final prefs = await SharedPreferences.getInstance();
  return SharedPrefsPaymentAttemptStore(prefs).load(scope);
}

(int, int, String?) loadDisposition(PaymentAttemptLoad load) => (
  load.attempts.length,
  load.quarantined.length,
  load.quarantined.isEmpty ? null : load.quarantined.first.reason,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R3 / F001: the physical-key trust boundary is isolate-wide and cannot be
  // cleared at runtime, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);

  group('F002 direct source-contract negatives', () {
    test('F002-GAP-001 applied requires source-emitted replay boolean', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(sourceApplied(includeReplay: false)),
        attempt(),
      );
      expect(result, isA<PaymentSendUnconfirmed>());
    });

    test('F002-CONTROL-001 complete source-shaped applied row is accepted', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(sourceApplied()),
        attempt(),
      );
      expect(result, isA<PaymentSendAccepted>());
    });

    test('F002-CONTROL-002 exact SQLSTATE conflict tuple is refused', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(<String, dynamic>{
          'local_operation_id': 'op-review',
          'operation_type': 'payment.create',
          'status': 'conflict',
          'ok': false,
          'error': 'conflict',
          'sqlstate': '40001',
          'idempotency_replay': false,
        }),
        attempt(),
      );
      expect(
        (result as PaymentSendRefused).code,
        PaymentRefusalCode.revisionConflict,
      );
    });

    test('F002-CONTROL-003 exact order-not-chargeable tuple is refused', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(<String, dynamic>{
          'local_operation_id': 'op-review',
          'operation_type': 'payment.create',
          'status': 'rejected',
          'ok': false,
          'error': 'order_not_chargeable',
          'order_id': 'order-review',
          'server_ts': '2026-09-09T08:00:01.000Z',
          'idempotency_replay': false,
        }),
        attempt(),
      );
      expect(
        (result as PaymentSendRefused).code,
        PaymentRefusalCode.notChargeable,
      );
    });

    test('F002-GAP-002 contradictory conflict tuple stays unconfirmed', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(<String, dynamic>{
          'local_operation_id': 'op-review',
          'operation_type': 'payment.create',
          'status': 'conflict',
          'ok': false,
          'error': 'permission_denied',
          'sqlstate': '42501',
          'idempotency_replay': false,
        }),
        attempt(),
      );
      expect(result, isA<PaymentSendUnconfirmed>());
    });

    test('F002-GAP-003 contradictory rejection tuple stays unconfirmed', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(<String, dynamic>{
          'local_operation_id': 'op-review',
          'operation_type': 'payment.create',
          'status': 'rejected',
          'ok': false,
          'error': 'order_not_chargeable',
          'detail': 'precondition_failed',
          'idempotency_replay': false,
        }),
        attempt(),
      );
      expect(result, isA<PaymentSendUnconfirmed>());
    });

    test('F002-GAP-004 refusal replay metadata is strict', () {
      final result = RealPaymentRepository.classifyEnvelope(
        envelope(<String, dynamic>{
          'local_operation_id': 'op-review',
          'operation_type': 'payment.create',
          'status': 'conflict',
          'ok': false,
          'error': 'conflict',
          'sqlstate': '40001',
          'idempotency_replay': 'false',
        }),
        attempt(),
      );
      expect(result, isA<PaymentSendUnconfirmed>());
    });

    test('F002-GAP-005 unknown authoritative order status is unconfirmed', () {
      final row = sourceApplied()..['order_status'] = 'teleported';
      expect(
        RealPaymentRepository.classifyEnvelope(envelope(row), attempt()),
        isA<PaymentSendUnconfirmed>(),
      );
    });
  });

  group('F002 passive page/result negatives', () {
    test(
      'F002-CONTROL-004 one source-shaped terminal row is applied',
      () async {
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[passiveRow()], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusApplied>());
      },
    );

    test(
      'F002-GAP-006 duplicate identity across pages is collision-class',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: <Object?>[passiveRow()],
            hasMore: true,
            nextCursor: const <String, Object?>{
              'updated_at': '2026-09-09T08:00:01.000Z',
              'id': '11111111-1111-1111-1111-111111111111',
            },
          ),
          page(rows: <Object?>[passiveRow()], hasMore: false),
        ]);
        final result = await lookup(transport);
        expect(
          (result.runtimeType, transport.calls),
          (PaymentAttemptStatusCollision, 2),
        );
      },
    );

    test(
      'F002-GAP-007 malformed cursor field types fail before another call',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: const <Object?>[],
            hasMore: true,
            nextCursor: const <String, Object?>{
              'updated_at': 7,
              'id': <Object?>[],
            },
          ),
          page(rows: const <Object?>[], hasMore: false),
        ]);
        final result = await lookup(transport);
        expect(
          (result is PaymentAttemptStatusUnavailable, transport.calls),
          (true, 1),
        );
      },
    );

    test(
      'F002-GAP-008 malformed has_more is unavailable, not absence',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: const <Object?>[],
            hasMore: 'true',
            nextCursor: const <String, Object?>{
              'updated_at': '2026-09-09T08:00:01.000Z',
              'id': '11111111-1111-1111-1111-111111111111',
            },
          ),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
      },
    );

    test(
      'F002-GAP-009 malformed inner replay metadata is collision-class',
      () async {
        final inner = sourceApplied()..['idempotency_replay'] = 'false';
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[passiveRow(result: inner)], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusCollision>());
      },
    );

    test(
      'F002-CONTROL-005 partial scan transport failure is unavailable',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: const <Object?>[],
            hasMore: true,
            nextCursor: const <String, Object?>{
              'updated_at': '2026-09-09T08:00:01.000Z',
              'id': '11111111-1111-1111-1111-111111111111',
            },
          ),
          const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: 'offline',
          ),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
      },
    );
  });

  group('F003 decoder/quarantine negatives', () {
    test('F003-GAP-001 envelope rejects non-allowlisted keys', () async {
      final raw = jsonEncode(<String, Object?>{
        'version': 1,
        'attempts': <Object?>[acceptedRecord()],
        'future_authority': true,
      });
      final load = await loadRaw(raw);
      expect(loadDisposition(load), (0, 1, 'envelope'));
    });

    test(
      'F003-GAP-002 whitespace-only required identity quarantines',
      () async {
        final record = acceptedRecord()..['local_operation_id'] = '   ';
        final load = await loadRaw(
          jsonEncode(<String, Object?>{
            'version': 1,
            'attempts': <Object?>[record],
          }),
        );
        expect(loadDisposition(load), (0, 1, 'record'));
      },
    );

    test('F003-GAP-003 unknown stored order status quarantines', () async {
      final record = acceptedRecord();
      (record['resolution']! as Map<String, Object?>)['order_status'] =
          'teleported';
      final load = await loadRaw(
        jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[record],
        }),
      );
      expect(loadDisposition(load), (0, 1, 'record'));
    });

    test('F003-GAP-004 resolved time cannot precede sent time', () async {
      final record = acceptedRecord()
        ..['sent_at'] = '2026-09-09T08:00:03.000Z'
        ..['resolved_at'] = '2026-09-09T08:00:02.000Z'
        ..['auto_effects_reserved_at'] = '2026-09-09T08:00:02.000Z';
      final load = await loadRaw(
        jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[record],
        }),
      );
      expect(loadDisposition(load), (0, 1, 'record'));
    });

    test('F003-GAP-005 effect reservation cannot predate creation', () async {
      final record = acceptedRecord()
        ..['auto_effects_reserved_at'] = '2026-09-09T07:59:59.000Z';
      final load = await loadRaw(
        jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[record],
        }),
      );
      expect(loadDisposition(load), (0, 1, 'record'));
    });

    test(
      'F003-GAP-006 writer-required memoized field cannot disappear',
      () async {
        final record = refusedRecord()..remove('refusal_memoized');
        final load = await loadRaw(
          jsonEncode(<String, Object?>{
            'version': 1,
            'attempts': <Object?>[record],
          }),
        );
        expect(loadDisposition(load), (0, 1, 'record'));
      },
    );

    test(
      'F003-GAP-007 update preserves quarantined duplicate raw verbatim',
      () async {
        final valid = attempt(
          op: 'op-duplicate',
        ).markSent('2026-09-09T08:00:01.000Z');
        final invalid = <String, Object?>{
          ...valid.toJson(),
          'unknown_authority': true,
        };
        final raw = jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[invalid, valid.toJson()],
        });
        SharedPreferences.setMockInitialValues(<String, Object>{
          paymentAttemptsStorageKey(scope.key): raw,
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsPaymentAttemptStore(prefs);
        final before = await store.load(scope);
        expect((before.attempts.length, before.quarantined.length), (1, 1));
        await store.update(
          scope,
          valid.withLastOutcome(PaymentAttemptLastOutcome.unconfirmed),
        );
        final written =
            jsonDecode(prefs.getString(paymentAttemptsStorageKey(scope.key))!)
                as Map<String, dynamic>;
        final entries = written['attempts'] as List<dynamic>;
        expect(entries.first, invalid);
      },
    );

    test('F003-GAP-008 same-order quarantine blocks direct creation', () async {
      final invalid = <String, Object?>{
        'local_operation_id': 'old-op',
        'order_id': 'order-review',
        'phase': 42,
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        paymentAttemptsStorageKey(scope.key): jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[invalid],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      await expectLater(
        store.createIfAbsent(scope, attempt(op: 'new-op')),
        throwsA(isA<PosPersistenceException>()),
      );
    });

    test('F003-CONTROL-001 complete writer record round-trips', () async {
      final original = attempt(
        op: 'op-control',
      ).markSent('2026-09-09T08:00:01.000Z');
      final load = await loadRaw(
        jsonEncode(<String, Object?>{
          'version': 1,
          'attempts': <Object?>[original.toJson()],
        }),
      );
      expect(
        (load.attempts.single.localOperationId, load.quarantined.length),
        ('op-control', 0),
      );
    });
  });
}
