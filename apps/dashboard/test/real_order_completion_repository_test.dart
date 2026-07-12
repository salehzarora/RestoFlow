import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/data/order_completion_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RealRepoNotWiredError;

/// ORDER-COMPLETION-001 — the REAL repository calls `owner_complete_order`, sends
/// ONLY the organization + order id (never an actor, a timestamp or a next
/// status), maps every STABLE domain error to its own typed outcome, and FAILS
/// CLOSED — it never reports a success it did not receive.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this.response, {this.throwKind});

  final Object? response;
  final SyncTransportErrorKind? throwKind;

  String? lastFunction;
  Map<String, dynamic>? lastArgs;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    lastFunction = function;
    lastArgs = args;
    final kind = throwKind;
    if (kind != null) throw SyncTransportException(kind);
    return response;
  }
}

MembershipContext _scope() => const MembershipContext(
  id: 'm1',
  organizationId: 'org-1',
  organizationName: 'Org 1',
  restaurantId: 'rest-1',
  restaurantName: 'Rest 1',
  branchId: 'branch-1',
  branchName: 'Branch 1',
  role: MembershipRole.manager,
  status: 'active',
);

RealOrderCompletionRepository _repo(_FakeTransport t) =>
    RealOrderCompletionRepository(null, scope: _scope(), transport: t);

void main() {
  test('R1 calls owner_complete_order with ONLY the org + order id', () async {
    final t = _FakeTransport(<String, Object?>{
      'ok': true,
      'entity': 'order',
      'order_id': 'o-1',
      'order_code': '#02A001',
      'status': 'completed',
      'revision': 2,
    });

    final result = await _repo(t).complete('o-1');

    expect(t.lastFunction, 'owner_complete_order');
    expect(t.lastArgs!['p_organization_id'], 'org-1');
    expect(t.lastArgs!['p_order_id'], 'o-1');
    expect(t.lastArgs!['p_expected_revision'], isNull);
    // The client CANNOT supply an actor, a timestamp or a target status.
    expect(t.lastArgs!.containsKey('p_new_status'), isFalse);
    expect(t.lastArgs!.containsKey('p_actor_id'), isFalse);
    expect(t.lastArgs!.containsKey('p_occurred_at'), isFalse);
    expect(t.lastArgs!.length, 3);

    expect(result, isA<OrderCompleted>());
    expect((result as OrderCompleted).alreadyCompleted, isFalse);
    expect(result.revision, 2);
  });

  test(
    'R2 an expected revision is forwarded for stale-client protection',
    () async {
      final t = _FakeTransport(<String, Object?>{'ok': true, 'revision': 5});
      await _repo(t).complete('o-1', expectedRevision: 4);
      expect(t.lastArgs!['p_expected_revision'], 4);
    },
  );

  test(
    'R3 an ALREADY-completed order is a SUCCESS (idempotent retry)',
    () async {
      final t = _FakeTransport(<String, Object?>{
        'ok': true,
        'status': 'completed',
        'already_completed': true,
        'revision': 2,
      });
      final result = await _repo(t).complete('o-1');
      expect(result, isA<OrderCompleted>());
      expect((result as OrderCompleted).alreadyCompleted, isTrue);
    },
  );

  test('R4 every STABLE domain error maps to its own typed outcome', () async {
    const cases = <String, OrderCompletionError>{
      'order_not_paid': OrderCompletionError.notPaid,
      'invalid_transition': OrderCompletionError.invalidState,
      'permission_denied': OrderCompletionError.permissionDenied,
      'revision_mismatch': OrderCompletionError.conflict,
      'not_found': OrderCompletionError.notFound,
    };
    for (final entry in cases.entries) {
      final t = _FakeTransport(<String, Object?>{
        'ok': false,
        'error': entry.key,
      });
      final result = await _repo(t).complete('o-1');
      expect(result, isA<OrderCompletionFailed>(), reason: entry.key);
      final failed = result as OrderCompletionFailed;
      expect(failed.error, entry.value, reason: entry.key);
      // A domain refusal is NEVER blind-retried.
      expect(failed.isRetryable, isFalse, reason: entry.key);
    }
  });

  test('R5 an UNKNOWN error is not treated as retryable', () async {
    final t = _FakeTransport(<String, Object?>{'ok': false, 'error': 'wat'});
    final result = await _repo(t).complete('o-1') as OrderCompletionFailed;
    expect(result.isRetryable, isFalse);
  });

  test('R6 a TRANSPORT failure is the ONLY retryable outcome', () async {
    for (final kind in SyncTransportErrorKind.values) {
      final t = _FakeTransport(null, throwKind: kind);
      final result = await _repo(t).complete('o-1');
      expect(result, isA<OrderCompletionFailed>());
      expect(
        (result as OrderCompletionFailed).error,
        OrderCompletionError.transient,
      );
      expect(result.isRetryable, isTrue);
    }
  });

  test(
    'R7 a MALFORMED body fails CLOSED (never an optimistic success)',
    () async {
      for (final body in <Object?>[null, 'nope', 42, <Object?>[]]) {
        final result = await _repo(_FakeTransport(body)).complete('o-1');
        expect(result, isA<OrderCompletionFailed>(), reason: '$body');
      }
      // An `ok` that is not literally true is NOT a success.
      final sneaky = await _repo(
        _FakeTransport(<String, Object?>{'ok': 'true'}),
      ).complete('o-1');
      expect(sneaky, isA<OrderCompletionFailed>());
    },
  );

  test(
    'R8 FAILS CLOSED with no transport / no scope (never a demo fallback)',
    () {
      expect(
        () => const RealOrderCompletionRepository(
          null,
          scope: null,
          transport: null,
        ).complete('o-1'),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    },
  );
}
