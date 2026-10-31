import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_operations.dart';
import 'package:restoflow_dashboard/src/storefront/seo_consent_repository.dart';

const _scope = SeoConsentOperationScope(
  membershipId: 'actor-membership',
  organizationId: 'org',
  restaurantId: 'restaurant',
);
const _intent = SeoConsentMutation(
  id: '11111111-1111-4111-8111-111111111111',
  expectedRevision: '0',
  consentEnabled: true,
);
const _other = SeoConsentMutation(
  id: '22222222-2222-4222-8222-222222222222',
  expectedRevision: '0',
  consentEnabled: false,
);
const _current = SeoConsentState(
  consentEnabled: true,
  revision: '1',
  canManage: true,
);

String _encode(SeoConsentMutation intent) => jsonEncode({
  'version': 1,
  'id': intent.id,
  'expected_revision': intent.expectedRevision,
  'consent_enabled': intent.consentEnabled,
});

class _Journal implements SeoConsentJournal {
  final records = <String, Map<String, String>>{};
  bool failRead = false,
      failWrite = false,
      loseWrite = false,
      failRemove = false;
  Completer<void>? writeGate;
  @override
  Future<Map<String, String>> read(String scope) async {
    if (failRead) throw StateError('Storage unavailable');
    return Map.of(records[scope] ?? {});
  }

  @override
  Future<void> write(String scope, String requestId, String value) async {
    await writeGate?.future;
    if (failWrite) throw StateError('Storage unavailable');
    if (!loseWrite) records.putIfAbsent(scope, () => {})[requestId] = value;
  }

  @override
  Future<void> remove(String scope, String requestId) async {
    if (failRemove) throw StateError('Storage unavailable');
    records[scope]?.remove(requestId);
  }
}

class _Repo implements SeoConsentRepository {
  final writes = <SeoConsentMutation>[];
  final checks = <SeoConsentMutation>[];
  SeoConsentOutcome outcome = SeoConsentOutcome.unavailable;
  SeoConsentMutationState mutationState = SeoConsentMutationState.notRecorded;
  SeoConsentOutcome reconciliationOutcome = SeoConsentOutcome.ok;
  @override
  Future<SeoConsentResult> read() async =>
      const SeoConsentResult(SeoConsentOutcome.ok, state: _current);
  @override
  Future<SeoConsentResult> save(SeoConsentMutation intent) async {
    writes.add(intent);
    return SeoConsentResult(
      outcome,
      state: outcome == SeoConsentOutcome.ok ? _current : null,
    );
  }

  @override
  Future<SeoConsentReconciliation> reconcile(SeoConsentMutation intent) async {
    checks.add(intent);
    return SeoConsentReconciliation(
      reconciliationOutcome,
      mutationState: mutationState,
      current: _current,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('durable journal and readback precede the first POST', () async {
    final gate = Completer<void>();
    final journal = _Journal()..writeGate = gate;
    final operations = SeoConsentOperations(journal);
    final repo = _Repo();
    final saving = operations.save(_scope, repo, _intent);
    await Future<void>.delayed(Duration.zero);
    expect(repo.writes, isEmpty);
    gate.complete();
    await saving;
    expect(journal.records[_scope.key]![_intent.id], _encode(_intent));
    expect(repo.writes.single, same(_intent));
  });

  for (final failure in ['read', 'write', 'readback']) {
    test('$failure storage failure prevents POST', () async {
      final journal = _Journal()
        ..failRead = failure == 'read'
        ..failWrite = failure == 'write'
        ..loseWrite = failure == 'readback';
      final repo = _Repo();
      expect(
        (await SeoConsentOperations(
          journal,
        ).save(_scope, repo, _intent)).outcome,
        SeoConsentOutcome.unavailable,
      );
      expect(repo.writes, isEmpty);
    });
  }

  test(
    'new app/session restores exact UUID/CAS/decision before allowing another intent',
    () async {
      final journal = SharedPreferencesSeoConsentJournal();
      final first = SeoConsentOperations(journal);
      final repo = _Repo();
      await first.save(_scope, repo, _intent);
      final reloaded = SeoConsentOperations(
        SharedPreferencesSeoConsentJournal(),
      );
      await reloaded.restore(_scope);
      expect(reloaded.pending(_scope)!.id, _intent.id);
      expect(reloaded.pending(_scope)!.expectedRevision, '0');
      expect(reloaded.pending(_scope)!.consentEnabled, true);
      await reloaded.save(_scope, repo, _other);
      expect(repo.writes, hasLength(1));
      expect((await journal.read(_scope.key)).keys, [_intent.id]);
    },
  );

  test(
    'different actor/restaurant scope cannot consume or inherit the pending intent',
    () async {
      final operations = SeoConsentOperations(_Journal());
      final repo = _Repo();
      await operations.save(_scope, repo, _intent);
      for (final scope in [
        const SeoConsentOperationScope(
          membershipId: 'other-actor',
          organizationId: 'org',
          restaurantId: 'restaurant',
        ),
        const SeoConsentOperationScope(
          membershipId: 'actor-membership',
          organizationId: 'org',
          restaurantId: 'other-restaurant',
        ),
      ]) {
        await operations.restore(scope);
        expect(operations.pending(scope), isNull);
      }
      expect(operations.pending(_scope)!.id, _intent.id);
    },
  );

  test(
    'not-recorded and denied resend never release an earlier ambiguous operation',
    () async {
      final journal = _Journal();
      final operations = SeoConsentOperations(journal);
      final repo = _Repo();
      await operations.save(_scope, repo, _intent);
      await operations.reconcile(_scope, repo, _intent);
      repo.outcome = SeoConsentOutcome.denied;
      await operations.save(_scope, repo, _intent);
      expect(operations.pending(_scope)!.id, _intent.id);
      expect(journal.records[_scope.key]!.keys, [_intent.id]);
      expect(repo.writes.every((value) => identical(value, _intent)), true);
      repo.mutationState = SeoConsentMutationState.committed;
      await operations.reconcile(_scope, repo, _intent);
      expect(operations.pending(_scope), isNull);
      expect(journal.records[_scope.key], isEmpty);
    },
  );

  test(
    'existing different durable intent survives and prevents a new POST',
    () async {
      final journal = SharedPreferencesSeoConsentJournal();
      await journal.write(_scope.key, _intent.id, _encode(_intent));
      final repo = _Repo();
      final operations = SeoConsentOperations(journal);
      await operations.save(_scope, repo, _other);
      expect(repo.writes, isEmpty);
      expect((await journal.read(_scope.key)).keys, [_intent.id]);
      expect(operations.pending(_scope)!.id, _intent.id);
    },
  );

  test(
    'two UUID keys survive reload and resolve in order without unlocking between receipts',
    () async {
      final journal = SharedPreferencesSeoConsentJournal();
      // Two racing tabs keep separate immutable records; neither overwrites the other.
      await journal.write(_scope.key, _other.id, _encode(_other));
      await journal.write(_scope.key, _intent.id, _encode(_intent));
      final operations = SeoConsentOperations(
        SharedPreferencesSeoConsentJournal(),
      );
      await operations.restore(_scope);
      expect(operations.pendingCount(_scope), 2);
      expect(operations.pending(_scope)!.id, _intent.id);
      final repo = _Repo()..mutationState = SeoConsentMutationState.committed;
      await operations.reconcile(_scope, repo, operations.pending(_scope)!);
      expect(operations.pendingCount(_scope), 1);
      expect(operations.pending(_scope)!.id, _other.id);
      expect((await journal.read(_scope.key)).keys, [_other.id]);
      expect(repo.writes, isEmpty);
      await operations.reconcile(_scope, repo, operations.pending(_scope)!);
      expect(operations.pending(_scope), isNull);
      expect(await journal.read(_scope.key), isEmpty);
      expect(repo.checks.map((intent) => intent.id), [_intent.id, _other.id]);
    },
  );

  test(
    'same UUID with changed payload is rejected without replacing the immutable record',
    () async {
      final journal = SharedPreferencesSeoConsentJournal();
      await journal.write(_scope.key, _intent.id, _encode(_intent));
      await expectLater(
        journal.write(
          _scope.key,
          _intent.id,
          _encode(
            SeoConsentMutation(
              id: _intent.id,
              expectedRevision: '1',
              consentEnabled: false,
            ),
          ),
        ),
        throwsStateError,
      );
      expect((await journal.read(_scope.key))[_intent.id], _encode(_intent));
    },
  );

  test(
    'journal removal failure keeps the operation frozen for a further exact receipt check',
    () async {
      final journal = _Journal();
      final operations = SeoConsentOperations(journal);
      final repo = _Repo();
      await operations.save(_scope, repo, _intent);
      journal.failRemove = true;
      repo.mutationState = SeoConsentMutationState.committed;
      expect(
        (await operations.reconcile(_scope, repo, _intent)).outcome,
        SeoConsentOutcome.unavailable,
      );
      expect(operations.pending(_scope)!.id, _intent.id);
      journal.failRemove = false;
      await operations.reconcile(_scope, repo, _intent);
      expect(operations.pending(_scope), isNull);
    },
  );

  test(
    'request identity conflict never releases the unknown decision',
    () async {
      final journal = _Journal();
      final operations = SeoConsentOperations(journal);
      final repo = _Repo();
      await operations.save(_scope, repo, _intent);
      repo.reconciliationOutcome = SeoConsentOutcome.requestConflict;
      repo.mutationState = SeoConsentMutationState.refused;
      final result = await operations.reconcile(_scope, repo, _intent);
      expect(result.mutationState, isNull);
      expect(operations.pending(_scope)!.id, _intent.id);
      expect(journal.records[_scope.key]!.keys, [_intent.id]);
    },
  );
}
