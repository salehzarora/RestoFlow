import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

class _Transport implements SyncRpcTransport {
  _Transport(this.response);
  Object? response;
  bool throws = false;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (throws) throw StateError('synthetic transport uncertainty');
    return response;
  }
}

Map<String, dynamic> _state({String revision = '9007199254740993'}) => {
  'ok': true,
  'entity': 'storefront_seo_consent',
  'organization_id': 'synthetic-org',
  'restaurant_id': 'synthetic-restaurant',
  'provisioned': true,
  'consent_enabled': false,
  'can_manage': true,
  'indexing_active': false,
  'effective_indexing_eligible': false,
  'revision': revision,
};

const _intent = SeoConsentMutation(
  id: '5301b1aa-344b-44c4-9902-5a47fb39aa8c',
  expectedRevision: '9007199254740993',
  consentEnabled: false,
);

SupabaseSeoConsentRepository _repo(_Transport transport) =>
    SupabaseSeoConsentRepository(
      transport: transport,
      organizationId: 'synthetic-org',
      restaurantId: 'synthetic-restaurant',
    );

void main() {
  for (final field in ['indexing_active', 'effective_indexing_eligible']) {
    for (final value in [true, null, 'false']) {
      test('refuses operational or malformed $field=$value', () async {
        final t = _Transport({..._state(), field: value});
        expect((await _repo(t).read()).outcome, SeoConsentOutcome.unavailable);
      });
    }
  }
  test(
    'server read capability is preserved without inferring an owner role',
    () async {
      final t = _Transport({
        ..._state(),
        'can_manage': false,
        'consent_enabled': true,
      });
      final result = await _repo(t).read();
      expect(result.state!.canManage, false);
      expect(result.state!.consentEnabled, true);
    },
  );
  test('successful receipt must represent the same decision', () async {
    final t = _Transport({
      ..._state(),
      'client_request_id': _intent.id,
      'consent_enabled': true,
    });
    expect(
      (await _repo(t).save(_intent)).outcome,
      SeoConsentOutcome.unavailable,
    );
  });
  test('versioned read pins exact scope and preserves bigint text', () async {
    final t = _Transport(_state());
    final result = await _repo(t).read();
    expect(result.outcome, SeoConsentOutcome.ok);
    expect(result.state!.revision, '9007199254740993');
    expect(t.calls.single.$1, 'get_storefront_seo_consent_v1');
    expect(t.calls.single.$2, {
      'p_organization_id': 'synthetic-org',
      'p_restaurant_id': 'synthetic-restaurant',
    });
  });

  for (final field in ['organization_id', 'restaurant_id']) {
    test('refuses a successful response with another $field', () async {
      final t = _Transport({..._state(), field: 'another-scope'});
      expect((await _repo(t).read()).outcome, SeoConsentOutcome.unavailable);
    });
  }

  for (final bad in <Object?>[
    null,
    42,
    '01',
    '-1',
    '9223372036854775808',
    '1\n',
  ]) {
    test('refuses noncanonical/rounded/overflow revision $bad', () async {
      final t = _Transport({..._state(), 'revision': bad});
      expect((await _repo(t).read()).outcome, SeoConsentOutcome.unavailable);
    });
  }

  test('save uses only versioned CAS intent and keeps id stable', () async {
    final t = _Transport({..._state(), 'client_request_id': _intent.id});
    final repo = _repo(t);
    expect((await repo.save(_intent)).outcome, SeoConsentOutcome.ok);
    expect((await repo.save(_intent)).outcome, SeoConsentOutcome.ok);
    expect(t.calls[0].$1, t.calls[1].$1);
    expect(t.calls[0].$2, t.calls[1].$2);
    expect(t.calls.first.$1, 'set_storefront_seo_consent_v1');
    expect(t.calls.first.$2['p_expected_revision'], '9007199254740993');
    expect(t.calls.first.$2['p_consent_enabled'], false);
    expect(t.calls.first.$2.keys, isNot(contains('p_branch_id')));
    expect(t.calls.first.$2.keys, isNot(contains('p_actor_id')));
  });

  test('a success receipt for another mutation is uncertain', () async {
    final t = _Transport({..._state(), 'client_request_id': 'other'});
    expect(
      (await _repo(t).save(_intent)).outcome,
      SeoConsentOutcome.unavailable,
    );
  });

  test('transport exception is uncertain and never retries', () async {
    final t = _Transport(null)..throws = true;
    expect(
      (await _repo(t).save(_intent)).outcome,
      SeoConsentOutcome.unavailable,
    );
    expect(t.calls, hasLength(1));
  });

  test(
    'reconciliation is separate read contract, retaining full same intent',
    () async {
      final t = _Transport({
        ..._state(),
        'mutation_state': 'committed',
        'result': {..._state(), 'client_request_id': _intent.id},
        'current': _state(revision: '9007199254740994'),
      });
      final result = await _repo(t).reconcile(_intent);
      expect(result.outcome, SeoConsentOutcome.ok);
      expect(result.mutationState, SeoConsentMutationState.committed);
      expect(result.current!.revision, '9007199254740994');
      expect(t.calls.single.$1, 'reconcile_storefront_seo_consent_v1');
      expect(t.calls.single.$2['p_client_request_id'], _intent.id);
      expect(
        t.calls.single.$2['p_expected_revision'],
        _intent.expectedRevision,
      );
    },
  );

  test('not recorded requires authoritative current state', () async {
    final t = _Transport({
      ..._state(),
      'mutation_state': 'not_recorded',
      'result': null,
    });
    expect(
      (await _repo(t).reconcile(_intent)).outcome,
      SeoConsentOutcome.unavailable,
    );
    t.response = {...t.response as Map, 'current': _state()};
    expect(
      (await _repo(t).reconcile(_intent)).mutationState,
      SeoConsentMutationState.notRecorded,
    );
  });

  test(
    'a committed receipt cannot substitute another mutation or scope',
    () async {
      final t = _Transport({
        ..._state(),
        'mutation_state': 'committed',
        'result': {..._state(), 'client_request_id': 'another'},
        'current': _state(),
      });
      expect(
        (await _repo(t).reconcile(_intent)).outcome,
        SeoConsentOutcome.unavailable,
      );
    },
  );

  test(
    'confirmed refusal is not an invitation to resend that identity',
    () async {
      final t = _Transport({
        ..._state(),
        'mutation_state': 'refused',
        'result': {
          'ok': false,
          'error': 'revision_conflict',
          'client_request_id': _intent.id,
        },
        'current': _state(),
      });
      final result = await _repo(t).reconcile(_intent);
      expect(result.outcome, SeoConsentOutcome.revisionConflict);
      expect(result.mutationState, SeoConsentMutationState.refused);
      expect(t.calls, hasLength(1));
    },
  );

  for (final entry in {
    'permission_denied': SeoConsentOutcome.denied,
    'not_found': SeoConsentOutcome.notFound,
    'revision_conflict': SeoConsentOutcome.revisionConflict,
    'request_conflict': SeoConsentOutcome.requestConflict,
    'invalid_request': SeoConsentOutcome.invalidRequest,
  }.entries) {
    test('typed refusal ${entry.key} is preserved', () async {
      final t = _Transport({'ok': false, 'error': entry.key});
      expect((await _repo(t).save(_intent)).outcome, entry.value);
    });
  }

  test('mutation IDs are independent RFC4122 v4 identities', () {
    final ids = List.generate(30, (_) => newSeoConsentMutationId());
    expect(ids.toSet(), hasLength(30));
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });
}
