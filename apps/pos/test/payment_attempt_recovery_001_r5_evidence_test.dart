// PAYMENT-ATTEMPT-RECOVERY-001 / S1-R5 — the EXACT-SOURCE evidence
// regressions (F002) and scope-aware retention (F003).
//
// Adopted from two retained Codex harnesses, which share one base:
//   * `reviewer_s1_r4_f002_source_contract_variations_test.dart` (SHA-256
//     AF502DC4D3A42BC6A857F1F0A01886DFAF9B9AB19424B5C7FEE6470948007C81) —
//     the 25 R4 cases this file supersedes plus the nine-case residual group
//     (one positive control and eight negatives); that group ran
//     1 pass / 8 fail at 8d6b804f, twice.
//   * `reviewer_s1_r4_f003_retention_variation_test.dart` (SHA-256
//     5CEC9918F106002E5BA6DB94ED42DD0D2433393F11E6841D0C71E32B01BD6760) —
//     the same base plus the foreign-scope retention case, which is the only
//     case carried across from it; it ran 0/1 at 8d6b804f, twice.
//
// Every case asserts the REQUIRED SAFE outcome, so none needed a twin. TWO
// corrections were made and each is documented where it stands: the feed-row
// FIXTURES are completed to the tracked 15-key projection, and the retention
// case's `contains(<Map>)` matchers are wrapped in `equals(...)` because as
// written they compared map IDENTITY and could not discriminate. No assertion's
// meaning was weakened; the rules they test were not relaxed.
//
// F002 covers the complete tracked applied tuple, the required order binding
// AND source timestamp on both RETURNED refusals, a real five-character
// SQLSTATE on a caught refusal, the outer reply stamp, the replay boolean, the
// impossible stored replay of true, and a feed scan that validates every row
// against the full generic projection before any terminal or absence decision.
// F003 covers the execution-history invariants, the authoritative identity-key
// derivation, scope-aware quarantine preservation through update, and now
// scope-aware retention.
//
// Synthetic data and fake transports only. No endpoint, SQL, device, or effect I/O.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport, SyncSession;
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/payment_attempt_store.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/payment_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const scope = PosSyncScope(
  organizationId: 'org-review-r3',
  restaurantId: 'restaurant-review-r3',
  branchId: 'branch-review-r3',
  deviceId: 'device-review-r3',
);

final now = DateTime.utc(2026, 9, 9, 14);

PaymentAttempt attempt({
  String op = 'op-review-r3',
  String orderId = 'order-review-r3',
  PosSyncScope inScope = scope,
}) => PaymentAttempt.mint(
  ids: FixedClientIdGenerator(<String>[op, '$op-target']),
  now: now,
  orderId: orderId,
  orderNumber: '#R3',
  amountMinor: 4000,
  tenderedMinor: 5000,
  currencyCode: 'ILS',
  method: PaymentMethod.cash,
  expectedRevision: 7,
  organizationId: inScope.organizationId,
  restaurantId: inScope.restaurantId,
  branchId: inScope.branchId,
  deviceId: inScope.deviceId,
  employeeProfileId: 'employee-review-r3',
);

Map<String, dynamic> sourceApplied() => <String, dynamic>{
  'local_operation_id': 'op-review-r3',
  'operation_type': 'payment.create',
  'status': 'applied',
  'ok': true,
  'payment_id': 'payment-server-r3',
  'order_id': 'order-review-r3',
  'method': 'cash',
  'receipt_number': '77',
  'change_due_minor': 1000,
  'shift_id': 'shift-server-r3',
  'cash_drawer_session_id': 'drawer-server-r3',
  'payment_revision': 1,
  'order_revision': 8,
  'auto_completed': false,
  'order_status': 'served',
  'server_ts': '2026-09-09T14:00:01.000Z',
  'idempotency_replay': false,
};

Map<String, dynamic> envelope(Map<String, dynamic> row) => <String, dynamic>{
  'ok': true,
  'results': <Object?>[row],
  'server_ts': '2026-09-09T14:00:02.000Z',
};

PaymentSendResult classify(Map<String, dynamic> row) =>
    RealPaymentRepository.classifyEnvelope(envelope(row), attempt());

class PagedTransport implements SyncRpcTransport {
  PagedTransport(this.pages);
  final List<Object?> pages;
  int calls = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    final index = calls++;
    return pages[index < pages.length ? index : pages.length - 1];
  }
}

Map<String, Object?> page({
  required Object? rows,
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

// CHANGED IN S1-R5 — the COMPLETE tracked feed projection.
//
// The tracked `operation_statuses` projection builds all FIFTEEN keys for
// every row it emits (20260729090000_..._direct_print_dispatch.sql:1334-1348),
// with null for a SQL NULL. This fixture carried eight of them, which was only
// ever accepted because the R4 build validated five. The two R5 negatives
// below prove a row missing ANY projected key cannot become definitive absence
// or sit beside a believed candidate, so the positive fixtures must be
// source-faithful or they would pass for the wrong reason. Nullability follows
// the tracked columns (20260622110000_rf056_sync_operations_push.sql).
Map<String, Object?> passiveRow({Object? result}) => <String, Object?>{
  'id': 'feed-row-r3',
  'local_operation_id': 'op-review-r3',
  'operation_type': 'payment.create',
  'target_entity': 'payment',
  'target_id': 'op-review-r3-target',
  'status': 'applied',
  'result': result ?? sourceApplied(),
  'last_error_code': null,
  'last_error_class': null,
  'conflict_info': null,
  'rejection_reason': null,
  'retry_count': 0,
  'updated_at': '2026-09-09T14:00:01.000Z',
  'applied_at': '2026-09-09T14:00:01.000Z',
  'server_received_at': '2026-09-09T14:00:01.000Z',
};

Future<PaymentAttemptStatusLookup> lookup(PagedTransport transport) =>
    RealPaymentRepository(
      transport,
      const SyncSession(
        pinSessionId: 'pin-review-r3',
        deviceId: 'device-review-r3',
      ),
      FixedClientIdGenerator(const <String>['unused-a', 'unused-b']),
      clock: () => now,
    ).lookupAttemptStatus(attempt());

String envelopeOf(List<Object?> records) => jsonEncode(<String, Object?>{
  'version': PaymentAttempt.schemaVersion,
  'attempts': records,
});

Future<PaymentAttemptLoad> loadRecords(List<Object?> records) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    paymentAttemptsStorageKey(scope.key): envelopeOf(records),
  });
  final prefs = await SharedPreferences.getInstance();
  return SharedPrefsPaymentAttemptStore(prefs).load(scope);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // S1-R4: the physical-key boundary and the in-process disclosure register are
  // both isolate-wide by design, so each test starts from a clean one.
  setUp(resetPaymentAttemptKeyGuardsForTest);
  setUp(resetPaymentDisclosuresForTest);
  setUp(resetPaymentAttemptKeyGuardsForTest);

  group('F002 independent exact-source variations', () {
    test('CONTROL exact tracked applied tuple is accepted', () {
      expect(classify(sourceApplied()), isA<PaymentSendAccepted>());
    });

    for (final field in const <String>[
      'shift_id',
      'cash_drawer_session_id',
      'payment_revision',
      'order_revision',
      'auto_completed',
      'server_ts',
    ]) {
      test('applied tuple missing source field $field is unconfirmed', () {
        final row = sourceApplied()..remove(field);
        expect(classify(row), isA<PaymentSendUnconfirmed>());
      });
    }

    test('returned order_not_chargeable requires its order binding', () {
      final row = <String, dynamic>{
        'local_operation_id': 'op-review-r3',
        'operation_type': 'payment.create',
        'status': 'rejected',
        'ok': false,
        'error': 'order_not_chargeable',
        'server_ts': '2026-09-09T14:00:01.000Z',
        'idempotency_replay': false,
      };
      expect(classify(row), isA<PaymentSendUnconfirmed>());
    });

    test('returned permission_denied requires its order binding', () {
      final row = <String, dynamic>{
        'local_operation_id': 'op-review-r3',
        'operation_type': 'payment.create',
        'status': 'rejected',
        'ok': false,
        'error': 'permission_denied',
        'server_ts': '2026-09-09T14:00:01.000Z',
        'idempotency_replay': false,
      };
      expect(classify(row), isA<PaymentSendUnconfirmed>());
    });

    test('caught refusal requires a real SQLSTATE-shaped value', () {
      final row = <String, dynamic>{
        'local_operation_id': 'op-review-r3',
        'operation_type': 'payment.create',
        'status': 'rejected',
        'ok': false,
        'error': 'rejected',
        'sqlstate': '',
        'detail': null,
        'idempotency_replay': false,
      };
      expect(classify(row), isA<PaymentSendUnconfirmed>());
    });

    test('pending result without source replay metadata is unconfirmed', () {
      final row = <String, dynamic>{
        'local_operation_id': 'op-review-r3',
        'operation_type': 'payment.create',
        'status': 'pending',
        'ok': false,
        'error': 'dependency_not_ready',
        'retryable': true,
      };
      expect(classify(row), isA<PaymentSendUnconfirmed>());
    });

    test(
      'CONTROL passive stored replay=false becomes a replayed acceptance',
      () async {
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[passiveRow()], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusApplied>());
      },
    );

    test('passive stored replay=true is impossible source evidence', () async {
      final inner = sourceApplied()..['idempotency_replay'] = true;
      final transport = PagedTransport(<Object?>[
        page(rows: <Object?>[passiveRow(result: inner)], hasMore: false),
      ]);
      expect(await lookup(transport), isA<PaymentAttemptStatusCollision>());
    });

    test('a scalar feed row cannot become definitive absence', () async {
      final transport = PagedTransport(<Object?>[
        page(rows: <Object?>[7], hasMore: false),
      ]);
      expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
    });

    test('a malformed map row cannot become definitive absence', () async {
      final transport = PagedTransport(<Object?>[
        page(
          rows: <Object?>[
            <String, Object?>{'id': 'malformed-only'},
          ],
          hasMore: false,
        ),
      ]);
      expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
    });

    test(
      'a later malformed row prevents belief in an earlier candidate',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: <Object?>[passiveRow()],
            hasMore: true,
            nextCursor: const <String, Object?>{
              'updated_at': '2026-09-09T14:00:01.000Z',
              'id': '11111111-1111-1111-1111-111111111111',
            },
          ),
          page(rows: <Object?>[7], hasMore: false),
        ]);
        final result = await lookup(transport);
        expect(
          (result.runtimeType, transport.calls),
          (PaymentAttemptStatusUnavailable, 2),
        );
      },
    );

    test(
      'CONTROL valid unrelated later row does not hide the candidate',
      () async {
        final transport = PagedTransport(<Object?>[
          page(
            rows: <Object?>[passiveRow()],
            hasMore: true,
            nextCursor: const <String, Object?>{
              'updated_at': '2026-09-09T14:00:01.000Z',
              'id': '11111111-1111-1111-1111-111111111111',
            },
          ),
          page(
            rows: <Object?>[
              // CHANGED IN S1-R5: completed to the tracked 15-key projection
              // for the same reason as `passiveRow` above.
              <String, Object?>{
                'id': 'feed-row-other',
                'local_operation_id': 'other-op',
                'operation_type': 'payment.create',
                'target_entity': 'payment',
                'target_id': 'other-target',
                'status': 'pending',
                'result': null,
                'last_error_code': null,
                'last_error_class': null,
                'conflict_info': null,
                'rejection_reason': null,
                'retry_count': 0,
                'updated_at': '2026-09-09T14:00:02.000Z',
                'applied_at': null,
                'server_received_at': '2026-09-09T14:00:02.000Z',
              },
            ],
            hasMore: false,
          ),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusApplied>());
      },
    );
  });

  group('F003 independent codec/quarantine variations', () {
    test('CONTROL current writer output round-trips', () async {
      final original = attempt().markSent('2026-09-09T14:00:01.000Z');
      final load = await loadRecords(<Object?>[original.toJson()]);
      expect((load.attempts.length, load.quarantined.length), (1, 0));
    });

    test(
      'sent_at cannot coexist with explicit may_have_executed=false',
      () async {
        final record = attempt().markSent('2026-09-09T14:00:01.000Z').toJson()
          ..['may_have_executed'] = false;
        final load = await loadRecords(<Object?>[record]);
        expect((load.attempts.length, load.quarantined.length), (0, 1));
      },
    );

    test(
      'may_have_executed=true cannot coexist with missing sent_at',
      () async {
        final record = attempt().toJson()..['may_have_executed'] = true;
        final load = await loadRecords(<Object?>[record]);
        expect((load.attempts.length, load.quarantined.length), (0, 1));
      },
    );

    test('pending unconfirmed history requires a started send', () async {
      final record = attempt()
          .withLastOutcome(PaymentAttemptLastOutcome.unconfirmed)
          .toJson();
      final load = await loadRecords(<Object?>[record]);
      expect((load.attempts.length, load.quarantined.length), (0, 1));
    });

    test('identity_key must match the frozen authoritative order id', () async {
      final record = attempt().toJson()..['identity_key'] = 'srv:other-order';
      final load = await loadRecords(<Object?>[record]);
      expect((load.attempts.length, load.quarantined.length), (0, 1));
    });

    test(
      'scope-quarantined same-op raw survives update byte-for-byte',
      () async {
        const foreignScope = PosSyncScope(
          organizationId: 'org-foreign',
          restaurantId: 'restaurant-foreign',
          branchId: 'branch-foreign',
          deviceId: 'device-foreign',
        );
        final foreign = attempt(
          op: 'shared-op',
          orderId: 'foreign-order',
          inScope: foreignScope,
        ).toJson();
        final current = attempt(
          op: 'shared-op',
        ).markSent('2026-09-09T14:00:01.000Z');
        SharedPreferences.setMockInitialValues(<String, Object>{
          paymentAttemptsStorageKey(scope.key): envelopeOf(<Object?>[
            foreign,
            current.toJson(),
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsPaymentAttemptStore(prefs);
        final before = await store.load(scope);
        expect((before.attempts.length, before.quarantined.length), (1, 1));

        await store.update(
          scope,
          current.withLastOutcome(PaymentAttemptLastOutcome.authRequired),
        );
        final raw =
            jsonDecode(prefs.getString(paymentAttemptsStorageKey(scope.key))!)
                as Map<String, dynamic>;
        final entries = raw['attempts'] as List<dynamic>;
        expect(entries.first, foreign);
        expect(
          (entries[1] as Map<String, dynamic>)['last_outcome'],
          PaymentAttemptLastOutcome.authRequired.wire,
        );
      },
    );

    test(
      'CONTROL identifiable unrelated quarantine permits a healthy order',
      () async {
        final corrupt = <String, Object?>{
          'local_operation_id': 'corrupt-op',
          'order_id': 'other-order',
          'future_authority': true,
        };
        SharedPreferences.setMockInitialValues(<String, Object>{
          paymentAttemptsStorageKey(scope.key): envelopeOf(<Object?>[corrupt]),
        });
        final prefs = await SharedPreferences.getInstance();
        final store = SharedPrefsPaymentAttemptStore(prefs);
        final claim = await store.createIfAbsent(scope, attempt());
        expect(
          (claim.created, claim.attempt.localOperationId),
          (true, 'op-review-r3'),
        );
        final raw =
            jsonDecode(prefs.getString(paymentAttemptsStorageKey(scope.key))!)
                as Map<String, dynamic>;
        expect((raw['attempts'] as List<dynamic>).first, corrupt);
      },
    );

    test('CONTROL unidentifiable quarantine blocks every new order', () async {
      final corrupt = <String, Object?>{'future_authority': true};
      SharedPreferences.setMockInitialValues(<String, Object>{
        paymentAttemptsStorageKey(scope.key): envelopeOf(<Object?>[corrupt]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      await expectLater(
        store.createIfAbsent(scope, attempt()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('S1R4 residual source-contract variations', () {
    Map<String, dynamic> returnedRefusal(String error) => <String, dynamic>{
      'local_operation_id': 'op-review-r3',
      'operation_type': 'payment.create',
      'status': 'rejected',
      'ok': false,
      'error': error,
      'order_id': 'order-review-r3',
      'server_ts': '2026-09-09T14:00:01.000Z',
      'idempotency_replay': false,
    };

    Map<String, Object?> completeOtherRow() => <String, Object?>{
      'id': 'feed-row-other-complete',
      'local_operation_id': 'other-op',
      'operation_type': 'order.status',
      'target_entity': 'order',
      'target_id': 'other-order',
      'status': 'pending',
      'result': null,
      'last_error_code': null,
      'last_error_class': null,
      'conflict_info': null,
      'rejection_reason': null,
      'retry_count': 0,
      'updated_at': '2026-09-09T14:00:01.000Z',
      'applied_at': null,
      'server_received_at': '2026-09-09T14:00:01.000Z',
    };

    test(
      'CONTROL complete generic unrelated feed row is safely skipped',
      () async {
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[completeOtherRow()], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusNotFound>());
      },
    );

    test('caught rejection requires a five-character SQLSTATE', () {
      final row = <String, dynamic>{
        'local_operation_id': 'op-review-r3',
        'operation_type': 'payment.create',
        'status': 'rejected',
        'ok': false,
        'error': 'rejected',
        'sqlstate': 'NOT-A-SQLSTATE',
        'detail': null,
        'idempotency_replay': false,
      };
      expect(classify(row), isA<PaymentSendUnconfirmed>());
    });

    for (final error in const <String>[
      'order_not_chargeable',
      'permission_denied',
    ]) {
      test('returned $error requires its source server_ts', () {
        final row = returnedRefusal(error)..remove('server_ts');
        expect(classify(row), isA<PaymentSendUnconfirmed>());
      });

      test('returned $error rejects malformed source server_ts', () {
        final row = returnedRefusal(error)..['server_ts'] = 'not-a-time';
        expect(classify(row), isA<PaymentSendUnconfirmed>());
      });
    }

    test('outer sync_push envelope requires its source server_ts', () {
      final raw = envelope(sourceApplied())..remove('server_ts');
      expect(
        RealPaymentRepository.classifyEnvelope(raw, attempt()),
        isA<PaymentSendUnconfirmed>(),
      );
    });

    test(
      'missing generic projected key cannot become definitive absence',
      () async {
        final row = completeOtherRow()..remove('target_entity');
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[row], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
      },
    );

    test(
      'missing generic projected key cannot coexist with accepted candidate',
      () async {
        final malformed = completeOtherRow()..remove('server_received_at');
        final transport = PagedTransport(<Object?>[
          page(rows: <Object?>[passiveRow(), malformed], hasMore: false),
        ]);
        expect(await lookup(transport), isA<PaymentAttemptStatusUnavailable>());
      },
    );
  });

  test(
    'S1R4 F003 foreign-scope resolved quarantine survives retention pruning',
    () async {
      const foreignScope = PosSyncScope(
        organizationId: 'org-foreign-retention',
        restaurantId: 'restaurant-foreign-retention',
        branchId: 'branch-foreign-retention',
        deviceId: 'device-foreign-retention',
      );
      final foreign =
          attempt(
                op: 'foreign-resolved-op',
                orderId: 'foreign-resolved-order',
                inScope: foreignScope,
              )
              .refused(
                PaymentRefusalCode.generic,
                at: '2026-09-09T14:00:01.000Z',
                memoized: true,
              )
              .toJson();
      final inScopeResolved = <Map<String, Object?>>[
        for (var i = 0; i < kPaymentAttemptsResolvedRetention; i++)
          attempt(op: 'resolved-op-$i', orderId: 'resolved-order-$i')
              .refused(
                PaymentRefusalCode.generic,
                at: '2026-09-09T14:00:01.000Z',
                memoized: true,
              )
              .toJson(),
      ];
      final pending = attempt(
        op: 'current-pending-op',
        orderId: 'current-pending-order',
      ).markSent('2026-09-09T14:00:01.000Z');

      SharedPreferences.setMockInitialValues(<String, Object>{
        paymentAttemptsStorageKey(scope.key): envelopeOf(<Object?>[
          foreign,
          ...inScopeResolved,
          pending.toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsPaymentAttemptStore(prefs);
      final before = await store.load(scope);
      expect(
        (before.attempts.length, before.quarantined.length),
        (kPaymentAttemptsResolvedRetention + 1, 1),
      );

      await store.update(
        scope,
        pending.withLastOutcome(PaymentAttemptLastOutcome.authRequired),
      );
      final raw =
          jsonDecode(prefs.getString(paymentAttemptsStorageKey(scope.key))!)
              as Map<String, dynamic>;
      final entries = raw['attempts'] as List<dynamic>;

      // CHANGED IN S1-R5 — `contains(x)` where x is NOT a Matcher falls back
      // to `Iterable.contains`, i.e. Dart `==`, which for two maps is IDENTITY.
      // The stored entries are decoded from JSON and so are never the same
      // instance as the fixture: as written, the first assertion could not pass
      // under ANY implementation and the second could not fail under any. Both
      // are wrapped in `equals(...)` so they compare by value and actually
      // discriminate. Proven: this corrected pair fails 0/1 at 8d6b804f (the
      // foreign raw is deleted and the in-scope victim survives) and passes 1/1
      // after the correction. Nothing else in the case was touched.
      expect(
        entries,
        contains(equals(foreign)),
        reason: 'a foreign-scope quarantine is never retention-prunable',
      );
      expect(
        entries,
        isNot(contains(equals(inScopeResolved.first))),
        reason: 'the oldest in-scope resolved record is the eligible victim',
      );
      expect(
        entries.where(
          (entry) =>
              entry is Map &&
              entry['local_operation_id'] == 'current-pending-op',
        ),
        hasLength(1),
      );
    },
  );
}
