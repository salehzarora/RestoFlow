// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: the provider-card journal — the
// separately versioned sibling record, its total strict codec, the durable
// store, quarantine and retention (execution packet §5).
import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show posCardChargeTimeout;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/provider_card_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosPersistenceException;
import 'package:restoflow_pos/src/format/provider_card_presentation.dart';

import 'support/provider_card_fakes.dart';

ProviderCardAttempt _live({
  int n = 1,
  String order = kCardOrder,
  int amount = 1200,
}) => ProviderCardAttempt.create(
  attemptId: cardV4(n),
  organizationId: kCardScope.organizationId,
  restaurantId: kCardScope.restaurantId,
  branchId: kCardScope.branchId,
  deviceId: kCardScope.deviceId,
  orderId: order,
  orderNumber: '#A1',
  mode: ProviderCardMode.live,
  amountMinor: amount,
  currencyCode: 'ILS',
  expectedRevision: 7,
  employeeProfileId: 'emp-cashier',
  now: kCardNow,
);

ProviderCardAttempt _test({int n = 1}) => ProviderCardAttempt.create(
  attemptId: cardV4(n),
  organizationId: kCardScope.organizationId,
  restaurantId: kCardScope.restaurantId,
  branchId: kCardScope.branchId,
  deviceId: kCardScope.deviceId,
  orderId: kCardOrder,
  orderNumber: '#A1',
  mode: ProviderCardMode.test,
  amountMinor: 100,
  currencyCode: 'ILS',
  expectedRevision: 7,
  employeeProfileId: null,
  now: kCardNow,
);

const _facts = ProviderCardServerFacts(
  state: 'approved',
  classification: 'approved_unrecorded',
  recorded: false,
  refusalCode: null,
  anomalyCode: null,
  resolution: null,
  recoverable: null,
  resumeCount: null,
  paymentId: null,
  serverTs: '2026-10-30T12:00:00Z',
);

ProviderCardAttempt _approvedWithLeg() {
  final at = canonicalInstantForTest();
  return _live().copyWith(
    startMayHaveExecuted: true,
    startLastSentAt: at,
    startOutcome: ProviderCardStartOutcome.answered,
    server: _facts,
    recording: ProviderCardRecordingOperation(
      localOperationId: cardV4(1),
      targetId: cardV4(2),
      clientCreatedAt: at,
      orderId: kCardOrder,
      amountTenderedMinor: 1200,
    ),
    recordingInDoubt: true,
    updatedAt: at,
  );
}

String canonicalInstantForTest() => kCardNow.toUtc().toIso8601String();

Map<String, Object?> _json(ProviderCardAttempt a) =>
    jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>;

/// Creates [a] through the store's admission: the mint callback returns it.
Future<ProviderCardCreate> _create(
  ProviderCardStore store,
  ProviderCardAttempt a,
) => store.createIfAbsent(
  kCardScope,
  identityKey: a.identityKey,
  mode: a.mode,
  mint: () => a,
);

ProviderCardMalformed _malformed(Map<String, Object?> raw) {
  final d = decodeProviderCardAttempt(raw);
  expect(d, isA<ProviderCardMalformed>());
  return d as ProviderCardMalformed;
}

ProviderCardServerFacts _f({
  required String state,
  required String classification,
  bool recorded = false,
  String? resolution,
  String? paymentId,
}) => ProviderCardServerFacts(
  state: state,
  classification: classification,
  recorded: recorded,
  refusalCode: null,
  anomalyCode: null,
  resolution: resolution,
  recoverable: null,
  resumeCount: null,
  paymentId: paymentId,
  serverTs: '2026-10-30T12:00:00Z',
);

ProviderCardAttempt _answered(
  ProviderCardAttempt a,
  ProviderCardServerFacts facts,
) => a.copyWith(
  startMayHaveExecuted: true,
  updatedAt: canonicalInstantForTest(),
  startLastSentAt: canonicalInstantForTest(),
  startOutcome: ProviderCardStartOutcome.answered,
  server: facts,
);

void main() {
  setUp(resetProviderCardStoreChainsForTest);

  group('round 1: family, stops and the settle window (packet §5.2, §7)', () {
    test('a record whose server facts belong to the other mode is '
        'quarantined (R5d), never repaired', () {
      for (final facts in <ProviderCardServerFacts>[
        _f(state: 'approved', classification: 'test_approved'),
        _f(
          state: 'approved',
          classification: 'test_approved',
          resolution: 'test_closed',
        ),
      ]) {
        expect(
          _malformed(_json(_answered(_live(), facts))).rule,
          'R5d',
          reason: facts.classification,
        );
      }
      expect(
        _malformed(
          _json(
            _answered(
              _test(),
              _f(state: 'sent', classification: 'in_progress'),
            ),
          ),
        ).rule,
        'R5d',
      );
      // Same family on both sides still decodes.
      expect(
        decodeProviderCardAttempt(
          _json(
            _answered(
              _live(),
              _f(state: 'sent', classification: 'in_progress'),
            ),
          ),
        ),
        isA<ProviderCardDecoded>(),
      );
    });

    test('a stop raised on the attempt\'s own LIVE approval yields to the '
        'server\'s final word; a stop about another attempt never does', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final voided = _f(
        state: 'approved',
        classification: 'resolved',
        resolution: 'provider_voided',
      );
      final recorded = _f(
        state: 'approved',
        classification: 'recorded',
        recorded: true,
        paymentId: cardV4(90),
      );
      for (final stop in <ProviderCardSafetyStop>[
        ProviderCardSafetyStop.recordingContract,
      ]) {
        final a = _approvedWithLeg().copyWith(
          safetyStop: stop,
          updatedAt: canonicalInstantForTest(),
        );
        expect(a.phase, ProviderCardPhase.reconciliation, reason: '$stop');
        final closed = a.copyWith(
          server: voided,
          updatedAt: canonicalInstantForTest(),
        );
        expect(closed.phase, ProviderCardPhase.resolved, reason: '$stop');
        expect(
          presentProviderCardAttempt(en, closed).title,
          isNot(en.posCardReconcileTitle),
          reason: 'the stop text is for reconciliation only',
        );
        expect(
          a
              .copyWith(server: recorded, updatedAt: canonicalInstantForTest())
              .phase,
          ProviderCardPhase.recorded,
          reason: '$stop',
        );
      }
      for (final stop in <ProviderCardSafetyStop>[
        ProviderCardSafetyStop.attemptConflict,
        ProviderCardSafetyStop.modeMismatch,
        ProviderCardSafetyStop.amountMismatch,
        // A TEST identity answered the LIVE leg: the server's facts are
        // another attempt's.
        ProviderCardSafetyStop.testAttemptNotRecordable,
      ]) {
        final a = _approvedWithLeg().copyWith(
          safetyStop: stop,
          updatedAt: canonicalInstantForTest(),
        );
        expect(
          a
              .copyWith(server: voided, updatedAt: canonicalInstantForTest())
              .phase,
          ProviderCardPhase.reconciliation,
          reason: '$stop',
        );
        expect(
          a
              .copyWith(server: recorded, updatedAt: canonicalInstantForTest())
              .phase,
          ProviderCardPhase.reconciliation,
          reason: '$stop',
        );
      }
    });

    test('the settle window is 150 s idle + the 40 s exchange deadline + '
        '10 s; a recorded not-found carries the decision, no wall clock', () {
      expect(
        kProviderCardStartSettleWindow,
        const Duration(seconds: 150) +
            posCardChargeTimeout +
            const Duration(seconds: 10),
      );
      final uncertain = _live().copyWith(
        startMayHaveExecuted: true,
        updatedAt: canonicalInstantForTest(),
        startLastSentAt: canonicalInstantForTest(),
        startOutcome: ProviderCardStartOutcome.uncertain,
      );
      expect(uncertain.notFoundSettled, isFalse);
      expect(uncertain.phase, ProviderCardPhase.uncertain);
      // Even an instant that reads as earlier than the send (a wall clock
      // stepped back) is the decision the controller recorded.
      for (final d in const <Duration>[
        Duration(seconds: -5),
        Duration(seconds: 1),
        Duration(seconds: 200),
      ]) {
        final settled = uncertain.copyWith(
          serverNotFoundAt: kCardNow.add(d).toUtc().toIso8601String(),
          updatedAt: canonicalInstantForTest(),
        );
        expect(settled.notFoundSettled, isTrue, reason: '$d');
        expect(settled.phase, ProviderCardPhase.notFound, reason: '$d');
      }
    });

    test('a recorded not-found needs a start that may have executed and no '
        'server answer (R5e)', () {
      final at = canonicalInstantForTest();
      final noEffect = _live().copyWith(
        startLastSentAt: at,
        startOutcome: ProviderCardStartOutcome.notSent,
        serverNotFoundAt: at,
        updatedAt: at,
      );
      expect(_malformed(_json(noEffect)).rule, 'R5e');
      final answered = _answered(
        _live(),
        _f(state: 'sent', classification: 'in_progress'),
      ).copyWith(serverNotFoundAt: at, updatedAt: at);
      expect(_malformed(_json(answered)).rule, 'R5e');
      final inDoubt = _live().copyWith(
        startInDoubt: true,
        startLastSentAt: at,
        serverNotFoundAt: at,
        updatedAt: at,
      );
      expect(
        decodeProviderCardAttempt(_json(inDoubt)),
        isA<ProviderCardDecoded>(),
      );
    });

    test('every recording value needs the leg, the refusal hint included '
        '(R6e)', () {
      final at = canonicalInstantForTest();
      final hintOnly = _live().copyWith(
        recordingRefusal: 'conflict',
        updatedAt: at,
      );
      expect(_malformed(_json(hintOnly)).rule, 'R6e');
      final outcomeOnly = _live().copyWith(
        recordingOutcome: ProviderCardRecordingOutcome.unconfirmed,
        updatedAt: at,
      );
      expect(_malformed(_json(outcomeOnly)).rule, 'R6e');
    });

    test('the store never writes a record it could not read back', () async {
      final prefs = await freshCardPrefs();
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      await _create(store, _live());
      final key = providerCardAttemptsStorageKey(kCardScope.key);
      final before = prefs.getString(key);
      final at = canonicalInstantForTest();
      await expectLater(
        store.update(
          kCardScope,
          cardV4(1),
          (c) => c.copyWith(serverNotFoundAt: at, updatedAt: at),
        ),
        throwsA(isA<PosPersistenceException>()),
      );
      expect(prefs.getString(key), before);
      expect((await store.load(kCardScope)).quarantined, isEmpty);
    });
  });

  group('the sibling record (packet §5.2)', () {
    test('round trip: every key always present, schema version 1', () {
      final a = _approvedWithLeg();
      final raw = _json(a);
      expect(raw.keys.toSet(), ProviderCardAttempt.keys);
      expect(raw, hasLength(34));
      expect(raw['schema_version'], 1);
      final d = decodeProviderCardAttempt(raw);
      expect(d, isA<ProviderCardDecoded>());
      expect((d as ProviderCardDecoded).attempt, equals(a));
      expect(jsonEncode(d.attempt.toJson()), jsonEncode(a.toJson()));
    });

    test('a TEST record carries no revision, leg, payment or receipt', () {
      final t = _test();
      expect(t.expectedRevision, isNull);
      final raw = _json(t);
      expect(raw['expected_revision'], isNull);
      expect(raw['recording'], isNull);
      expect(decodeProviderCardAttempt(raw), isA<ProviderCardDecoded>());
    });

    test('strict: unknown key, missing key, unknown version', () {
      final raw = _json(_live());
      expect(_malformed({...raw, 'pan': 'x'}).rule, 'R2');
      expect(_malformed(Map.of(raw)..remove('closed')).rule, 'R2');
      expect(_malformed({...raw, 'schema_version': 2}).rule, 'R1');
      expect(_malformed({...raw, 'schema_version': '1'}).rule, 'R1');
    });

    test('strict: identity, money and mode rules', () {
      final raw = _json(_live());
      expect(
        _malformed({
          ...raw,
          'attempt_id': 'C0000001-0000-4000-8000-000000000001',
        }).rule,
        'R3a',
      );
      expect(
        _malformed({
          ...raw,
          'attempt_id': 'c0000001-0000-1000-8000-000000000001',
        }).rule,
        'R3a',
      );
      expect(_malformed({...raw, 'identity_key': 'srv:other'}).rule, 'R3d');
      expect(_malformed({...raw, 'amount_minor': 0}).rule, 'R3g');
      expect(_malformed({...raw, 'amount_minor': 12.5}).rule, 'R3g');
      expect(_malformed({...raw, 'currency_code': 'ils'}).rule, 'R3h');
      expect(
        _malformed({
          ...raw,
          'order_id': 'not-a-uuid',
          'identity_key': 'srv:not-a-uuid',
        }).rule,
        'R3i',
      );
      expect(_malformed({...raw, 'expected_revision': null}).rule, 'R3j');
      final t = _json(_test());
      expect(_malformed({...t, 'expected_revision': 7}).rule, 'R3k');
      expect(
        _malformed({
          ...raw,
          'client_created_at': '2026-10-30T12:00:00+00:00',
        }).rule,
        'R3m',
      );
    });

    test('strict: start, server, leg and closure cross-field rules', () {
      final raw = _json(_live());
      expect(_malformed({...raw, 'start_in_doubt': true}).rule, 'R4d');
      expect(_malformed({...raw, 'start_outcome': 'maybe'}).rule, 'R4c');
      final sent = {...raw, 'start_last_sent_at': raw['client_created_at']};
      expect(_malformed({...sent, 'start_outcome': 'refused'}).rule, 'R4f');
      expect(_malformed({...raw, 'server': _facts.toJson()}).rule, 'R5b');
      final leg = _json(_approvedWithLeg());
      final badPayload =
          jsonDecode(jsonEncode(leg['recording'])) as Map<String, Object?>;
      (badPayload['payload']! as Map<String, Object?>)['expected_revision'] = 7;
      expect(_malformed({...leg, 'recording': badPayload}).rule, 'R6a');
      final otherAmount =
          jsonDecode(jsonEncode(leg['recording'])) as Map<String, Object?>;
      (otherAmount['payload']!
              as Map<String, Object?>)['amount_tendered_minor'] =
          1;
      expect(_malformed({...leg, 'recording': otherAmount}).rule, 'R6a');
      expect(
        _malformed({
          ...leg,
          'payment': {
            'payment_id': 'p',
            'receipt_number': 'r',
            'order_status': null,
          },
        }).rule,
        'R6l',
      );
      expect(
        _malformed({...leg, 'refusal_report_pending': 'conflict'}).rule,
        'R6h',
      );
      expect(_malformed({...leg, 'resume_denied': 'resume_stale'}).rule, 'R6j');
      expect(
        _malformed({
          ...sent,
          'start_may_have_executed': true,
          'closed': 'abandoned',
        }).rule,
        'R7c',
      );
      final t = _json(_test());
      expect(
        _malformed({
          ...t,
          'start_may_have_executed': true,
          'start_last_sent_at': t['client_created_at'],
          'server': const ProviderCardServerFacts(
            state: 'approved',
            classification: 'test_approved',
            recorded: false,
            refusalCode: null,
            anomalyCode: null,
            resolution: null,
            recoverable: null,
            resumeCount: null,
            paymentId: null,
            serverTs: '2026-10-30T12:00:00Z',
          ).toJson(),
          // A leg canonical for THIS record: only the mode forbids it.
          'recording': ProviderCardRecordingOperation(
            localOperationId: cardV4(1),
            targetId: cardV4(2),
            clientCreatedAt: canonicalInstantForTest(),
            orderId: kCardOrder,
            amountTenderedMinor: 100,
          ).toJson(),
        }).rule,
        'R6b',
      );
    });

    test('server facts must be a shape the server can produce', () {
      expect(
        const ProviderCardServerFacts(
          state: 'sent',
          classification: 'recorded',
          recorded: true,
          refusalCode: null,
          anomalyCode: null,
          resolution: null,
          recoverable: null,
          resumeCount: null,
          paymentId: null,
          serverTs: '2026-10-30T12:00:00Z',
        ).consistencyProblem(),
        isNotNull,
      );
      expect(
        const ProviderCardServerFacts(
          state: 'approved',
          classification: 'test_sent',
          recorded: false,
          refusalCode: null,
          anomalyCode: null,
          resolution: null,
          recoverable: null,
          resumeCount: null,
          paymentId: null,
          serverTs: '2026-10-30T12:00:00Z',
        ).consistencyProblem(),
        isNotNull,
      );
      expect(_facts.consistencyProblem(), isNull);
    });

    test('the record never holds a credential, a session, a terminal or a '
        'provider value', () {
      final a = _approvedWithLeg();
      final text = jsonEncode(a.toJson());
      for (final forbidden in <String>[
        kCardToken,
        kCardPin,
        'device_session_token',
        'pin_session_id',
        'provider_return_code',
        'terminal',
        'credential',
        'pan',
      ]) {
        expect(text.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the canonical leg: exact keys, no expected_revision, and a Resume '
        'adds only recording_resume beside the payload', () {
      final leg = _approvedWithLeg().recording!;
      final op = leg.toSyncOperation();
      expect(op.keys.toList(), <String>[
        'local_operation_id',
        'operation_type',
        'target_entity',
        'target_id',
        'client_created_at',
        'payload',
      ]);
      expect(op['payload'], <String, Object?>{
        'order_id': kCardOrder,
        'tender_type': 'card',
        'amount_tendered_minor': 1200,
      });
      expect(jsonEncode(op).contains('expected_revision'), isFalse);
      final resumed = leg.toSyncOperation(recordingResume: 2);
      expect(Map.of(resumed)..remove('recording_resume'), op);
      expect(resumed['recording_resume'], 2);
      expect(
        (resumed['payload'] as Map).containsKey('recording_resume'),
        isFalse,
      );
    });
  });

  group('the store (packet §5.1, §5.3, §5.4)', () {
    test(
      'its own key family; the base payment envelope is never touched',
      () async {
        final prefs = await freshCardPrefs();
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final created = await _create(store, _live());
        expect(created, isA<ProviderCardCreated>());
        expect(prefs.getKeys(), <String>{
          'restoflow.pos.provider_card_attempts.v1.${kCardScope.key}',
        });
        final env = jsonDecode(prefs.getString(prefs.getKeys().single)!) as Map;
        expect(env.keys.toSet(), <String>{'version', 'attempts'});
        expect(env['version'], 1);
      },
    );

    test(
      'createIfAbsent adopts an open attempt of the same order and mode',
      () async {
        final prefs = await freshCardPrefs();
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final results = await Future.wait([
          _create(store, _live(n: 1)),
          _create(store, _live(n: 2)),
        ]);
        expect(results.whereType<ProviderCardCreated>(), hasLength(1));
        expect(results.whereType<ProviderCardAdopted>(), hasLength(1));
        final load = await store.load(kCardScope);
        expect(load.attempts, hasLength(1));
        // Another order is independent.
        expect(
          await _create(store, _live(n: 3, order: kCardOrder2)),
          isA<ProviderCardCreated>(),
        );
      },
    );

    test('update applies the transition to the FRESHEST stored record', () async {
      final prefs = await freshCardPrefs();
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      final a = _live();
      await _create(store, a);
      final at = canonicalInstantForTest();
      await store.update(
        kCardScope,
        a.attemptId,
        (c) =>
            c.copyWith(startInDoubt: true, startLastSentAt: at, updatedAt: at),
      );
      // A stale copy's writer only flips its own field: the in-doubt fact stays.
      final written = await store.update(
        kCardScope,
        a.attemptId,
        (c) => c.copyWith(startMayHaveExecuted: true, updatedAt: at),
      );
      expect(written.startInDoubt, isTrue);
      expect(written.startMayHaveExecuted, isTrue);
      await expectLater(
        store.update(kCardScope, cardV4(99), (c) => c),
        throwsA(isA<PosPersistenceException>()),
      );
    });

    test(
      'an unreadable entry is kept, reported and blocks new starts',
      () async {
        final key = 'restoflow.pos.provider_card_attempts.v1.${kCardScope.key}';
        final good = _live(n: 1, order: kCardOrder2).toJson();
        final bad = {..._json(_live(n: 2)), 'future_field': true};
        final prefs = await freshCardPrefs(<String, Object>{
          key: jsonEncode({
            'version': 1,
            'attempts': [good, bad],
          }),
        });
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final load = await store.load(kCardScope);
        expect(load.attempts, hasLength(1));
        expect(load.quarantined.single.reason, 'record');
        expect(load.blocksNewStarts, isTrue);
        expect(
          await _create(store, _live(n: 3)),
          isA<ProviderCardCreateQuarantined>(),
        );
        // A transition of the readable record re-emits the unreadable one.
        final at = canonicalInstantForTest();
        await store.update(
          kCardScope,
          cardV4(1),
          (c) => c.copyWith(
            startInDoubt: true,
            startLastSentAt: at,
            updatedAt: at,
          ),
        );
        final env = jsonDecode(prefs.getString(key)!) as Map;
        expect((env['attempts'] as List)[1], bad);
      },
    );

    test(
      'an unknown envelope version quarantines the family and refuses writes',
      () async {
        final key = 'restoflow.pos.provider_card_attempts.v1.${kCardScope.key}';
        final prefs = await freshCardPrefs(<String, Object>{
          key: jsonEncode({'version': 2, 'attempts': <Object>[]}),
        });
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final load = await store.load(kCardScope);
        expect(load.envelopeUnreadable, isTrue);
        expect(load.blocksNewStarts, isTrue);
        expect(
          await _create(store, _live()),
          isA<ProviderCardCreateQuarantined>(),
        );
        await expectLater(
          store.update(kCardScope, cardV4(1), (c) => c),
          throwsA(isA<PosPersistenceException>()),
        );
        expect(
          prefs.getString(key),
          jsonEncode({'version': 2, 'attempts': <Object>[]}),
        );
      },
    );

    test(
      'retention drops only old terminal entries, never an open one',
      () async {
        final prefs = await freshCardPrefs();
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final at = canonicalInstantForTest();
        // One OPEN attempt first, then 205 set-aside (terminal) ones.
        final open = _live(
          n: 1,
        ).copyWith(startInDoubt: true, startLastSentAt: at, updatedAt: at);
        await _create(store, open);
        for (var i = 0; i < 205; i++) {
          final order =
              '0b0b0b0b-0000-4000-8000-${(i + 10).toString().padLeft(12, '0')}';
          await _create(
            store,
            _live(
              n: 100 + i,
              order: order,
            ).copyWith(closed: ProviderCardClosure.abandoned, updatedAt: at),
          );
        }
        final load = await store.load(kCardScope);
        expect(load.attempts, hasLength(kProviderCardJournalCap));
        expect(
          load.attempts.first.attemptId,
          cardV4(1),
          reason: 'the open one stays',
        );
      },
    );
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001.
  group('correction A: set-aside only where no charge can exist '
      '(correction packet §4)', () {
    test('one set-aside rule for both modes: an unresolved TEST attempt is '
        'never set aside, a final one needs none', () {
      for (final kind in _unresolvedKinds) {
        final a = _kind(kind, 1);
        expect(a.isOpen, isTrue, reason: kind);
        final expected = const <String>{
          'live not sent',
          'live sign in again',
          'live not found',
          'test not sent',
          'test sign in again',
          'test not found',
        }.contains(kind);
        expect(a.mayBeSetAside, expected, reason: kind);
      }
      for (final kind in _finalKinds) {
        final a = _kind(kind, 1);
        expect(a.mayBeSetAside, isFalse, reason: kind);
        expect(a.isRetentionPrunable, isTrue, reason: kind);
      }
      expect(_kind('test waiting', 1).phase, ProviderCardPhase.testWaiting);
      expect(
        _kind('test cancel confirmed', 1).phase,
        ProviderCardPhase.testReleased,
      );
      expect(_kind('test not confirmed', 1).phase, ProviderCardPhase.uncertain);
    });

    test('R7d: a stored closure of an unresolved attempt is quarantined, never '
        'honoured as closed; one of a final or set-asidable record reads', () {
      final at = canonicalInstantForTest();
      for (final kind in <String>[..._unresolvedKinds, ..._finalKinds]) {
        final a = _kind(kind, 1);
        if (a.closed != null) continue;
        final closure = kind.endsWith('not sent')
            ? ProviderCardClosure.abandoned
            : ProviderCardClosure.setAside;
        final decoded = decodeProviderCardAttempt(
          _json(a.copyWith(closed: closure, updatedAt: at)),
        );
        // Unresolved: open and not set-asidable (recorded is open too, and
        // no build ever closes it).
        if (a.isOpen && !a.mayBeSetAside) {
          expect(decoded, isA<ProviderCardMalformed>(), reason: kind);
          expect((decoded as ProviderCardMalformed).rule, 'R7d', reason: kind);
        } else {
          expect(decoded, isA<ProviderCardDecoded>(), reason: kind);
          expect(
            (decoded as ProviderCardDecoded).attempt.phase,
            ProviderCardPhase.closed,
            reason: kind,
          );
        }
      }
      // The two cases that matter most: the 001F build set aside a waiting
      // TEST attempt (refused) and a final TEST approval (still readable).
      ProviderCardDecode closedAs(String kind) => decodeProviderCardAttempt(
        _json(
          _kind(
            kind,
            1,
          ).copyWith(closed: ProviderCardClosure.setAside, updatedAt: at),
        ),
      );
      expect(closedAs('test waiting'), isA<ProviderCardMalformed>());
      expect(closedAs('test approved'), isA<ProviderCardDecoded>());
    });

    test(
      'a TEST attempt the 001F build set aside while it was waiting is kept '
      'and reported, blocks new starts and is never shown as closed',
      () async {
        final key = providerCardAttemptsStorageKey(kCardScope.key);
        final at = canonicalInstantForTest();
        final setAside = _json(
          _kind(
            'test waiting',
            1,
          ).copyWith(closed: ProviderCardClosure.setAside, updatedAt: at),
        );
        final other = _kind('live not confirmed', 2);
        final prefs = await freshCardPrefs(<String, Object>{
          key: jsonEncode({
            'version': 1,
            'attempts': [setAside, other.toJson()],
          }),
        });
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final load = await store.load(kCardScope);
        expect(load.attempts.map((a) => a.attemptId), [other.attemptId]);
        expect(load.quarantined.single.reason, 'record');
        expect(load.quarantined.single.rule, 'R7d');
        expect(load.blocksNewStarts, isTrue);
        expect(
          await _create(store, _live()),
          isA<ProviderCardCreateQuarantined>(),
        );
        await store.update(
          kCardScope,
          other.attemptId,
          (c) => c.copyWith(updatedAt: '2026-10-30T12:05:00.000Z'),
        );
        final env = jsonDecode(prefs.getString(key)!) as Map;
        expect(
          (env['attempts'] as List).first,
          setAside,
          reason: 'kept as read',
        );
      },
    );
  });

  group('correction B: the 200-record admission bound '
      '(correction packet §5)', () {
    final key = providerCardAttemptsStorageKey(kCardScope.key);
    List<ProviderCardAttempt> openFill(int count, {int from = 0}) => [
      for (var i = 0; i < count; i++)
        cardInDoubt(cardStoredAttempt(100 + from + i, order: cardOrderN(i))),
    ];

    test('200 open records: a new start is refused typed — nothing minted, '
        'nothing written — and an open attempt of the same order is still '
        'adopted, minting nothing', () async {
      final stored = cardJournalEnvelope(openFill(kProviderCardJournalCap));
      final prefs = await freshCardPrefs(<String, Object>{key: stored});
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      var mints = 0;
      final refused = await store.createIfAbsent(
        kCardScope,
        identityKey: _live().identityKey,
        mode: ProviderCardMode.live,
        mint: () {
          mints++;
          return _live();
        },
      );
      expect(refused, isA<ProviderCardCreateFull>());
      expect(mints, 0, reason: 'no identity minted');
      expect(prefs.getString(key), stored, reason: 'nothing written');
      final load = await store.load(kCardScope);
      expect(load.blocksNewStarts, isFalse, reason: 'not a quarantine');
      expect(load.envelopeUnreadable, isFalse);
      expect(load.attempts, hasLength(kProviderCardJournalCap));
      final sameOrder = cardStoredAttempt(999, order: cardOrderN(0));
      final adopted = await store.createIfAbsent(
        kCardScope,
        identityKey: sameOrder.identityKey,
        mode: ProviderCardMode.live,
        mint: () {
          mints++;
          return sameOrder;
        },
      );
      expect(adopted, isA<ProviderCardAdopted>());
      expect((adopted as ProviderCardAdopted).attempt.attemptId, cardV4(100));
      expect(mints, 0);
      expect(prefs.getString(key), stored);
    });

    test('199 open records and one safe final record: the final one makes '
        'room — not the oldest — and the new attempt is admitted', () async {
      final at = canonicalInstantForTest();
      final open = openFill(kProviderCardJournalCap - 1);
      final finalOne = cardStoredAttempt(
        98,
        order: cardOrderN(500),
      ).copyWith(closed: ProviderCardClosure.abandoned, updatedAt: at);
      final prefs = await freshCardPrefs(<String, Object>{
        key: cardJournalEnvelope([
          ...open.take(50),
          finalOne,
          ...open.skip(50),
        ]),
      });
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      expect(await _create(store, _live()), isA<ProviderCardCreated>());
      final load = await store.load(kCardScope);
      expect(load.attempts, hasLength(kProviderCardJournalCap));
      final ids = load.attempts.map((a) => a.attemptId).toList();
      expect(ids, isNot(contains(cardV4(98))));
      expect(
        ids.take(kProviderCardJournalCap - 1),
        [for (final a in open) a.attemptId],
        reason: 'every open record stays, in order',
      );
      expect(ids.last, _live().attemptId);
    });

    test('each safe final kind makes room; no other kind is ever dropped and '
        'the start is refused instead', () async {
      for (final kind in _finalKinds) {
        resetProviderCardStoreChainsForTest();
        final prefs = await freshCardPrefs(<String, Object>{
          key: cardJournalEnvelope([
            _kind(kind, 1),
            ...openFill(kProviderCardJournalCap - 1),
          ]),
        });
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        expect(
          await _create(store, _live(n: 900)),
          isA<ProviderCardCreated>(),
          reason: kind,
        );
        final ids = (await store.load(
          kCardScope,
        )).attempts.map((a) => a.attemptId);
        expect(ids, isNot(contains(cardV4(1))), reason: kind);
        expect(ids, contains(cardV4(900)), reason: kind);
      }
      for (final kind in _unresolvedKinds) {
        resetProviderCardStoreChainsForTest();
        final stored = cardJournalEnvelope([
          _kind(kind, 1),
          ...openFill(kProviderCardJournalCap - 1),
        ]);
        final prefs = await freshCardPrefs(<String, Object>{key: stored});
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        expect(
          await _create(store, _live(n: 900)),
          isA<ProviderCardCreateFull>(),
          reason: kind,
        );
        expect(prefs.getString(key), stored, reason: kind);
      }
    });

    test('at the bound every stored attempt still takes its transitions '
        '(status, the recording leg, a final resolution)', () async {
      final waiting = _kind('live waiting', 1);
      final stored = cardJournalEnvelope([
        waiting,
        ...openFill(kProviderCardJournalCap - 1),
      ]);
      final prefs = await freshCardPrefs(<String, Object>{key: stored});
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      final at = canonicalInstantForTest();
      final approved = await store.update(
        kCardScope,
        waiting.attemptId,
        (c) => c.copyWith(server: _facts, updatedAt: at),
      );
      expect(approved.phase, ProviderCardPhase.approvedRecording);
      final leg = await store.update(
        kCardScope,
        waiting.attemptId,
        (c) => c.copyWith(
          recording: _leg(1, c.orderId),
          recordingInDoubt: true,
          updatedAt: at,
        ),
      );
      expect(leg.phase, ProviderCardPhase.recordingUnconfirmed);
      final resolved = await store.update(
        kCardScope,
        waiting.attemptId,
        (c) => c.copyWith(
          server: _f(
            state: 'approved',
            classification: 'resolved',
            resolution: 'provider_voided',
          ),
          updatedAt: at,
        ),
      );
      expect(resolved.phase, ProviderCardPhase.resolved);
      final load = await store.load(kCardScope);
      expect(load.attempts, hasLength(kProviderCardJournalCap));
      expect(load.attempts.first.phase, ProviderCardPhase.resolved);
    });
  });

  group('correction C: envelope-level uniqueness (correction packet §6)', () {
    final key = providerCardAttemptsStorageKey(kCardScope.key);
    final at = canonicalInstantForTest();

    Future<void> expectQuarantinedWhole(String raw, String rule) async {
      resetProviderCardStoreChainsForTest();
      final prefs = await freshCardPrefs(<String, Object>{key: raw});
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      final load = await store.load(kCardScope);
      expect(load.envelopeUnreadable, isTrue, reason: rule);
      expect(load.attempts, isEmpty, reason: 'no record is exposed');
      expect(load.quarantined.single.reason, 'envelope');
      expect(load.quarantined.single.rule, rule);
      expect(load.blocksNewStarts, isTrue);
      expect(
        await _create(store, _live(n: 99, order: kCardOrder2)),
        isA<ProviderCardCreateQuarantined>(),
      );
      for (final entry in jsonDecode(raw)['attempts'] as List) {
        final id = (entry as Map)['attempt_id'] as String;
        await expectLater(
          store.update(
            kCardScope,
            id,
            (c) => c.copyWith(serverNotFoundAt: at, updatedAt: at),
          ),
          throwsA(isA<PosPersistenceException>()),
          reason: 'no copy is updated',
        );
      }
      expect(prefs.getString(key), raw, reason: 'the stored bytes stay');
    }

    test('one attempt id twice — an exact copy, or a copy under another order '
        '— quarantines the whole envelope', () async {
      final a = _kind('live not confirmed', 5);
      final other = _kind('live waiting', 6);
      final copyOtherOrder = cardInDoubt(
        cardStoredAttempt(5, order: cardOrderN(77)),
      );
      await expectQuarantinedWhole(
        cardJournalEnvelope([a, other, a]),
        'duplicate attempt_id',
      );
      await expectQuarantinedWhole(
        cardJournalEnvelope([a, copyOtherOrder]),
        'duplicate attempt_id',
      );
      // A copy that this build cannot read still carries the stored id.
      await expectQuarantinedWhole(
        jsonEncode({
          'version': 1,
          'attempts': [
            a.toJson(),
            {..._json(a), 'future_field': true},
          ],
        }),
        'duplicate attempt_id',
      );
    });

    test('two open records of one order and mode quarantine the whole '
        'envelope, LIVE or TEST', () async {
      final notConfirmed = cardInDoubt(cardStoredAttempt(5, order: kCardOrder));
      final waiting = _answeredAs(
        cardStoredAttempt(6, order: kCardOrder),
        _f(state: 'sent', classification: 'in_progress'),
      );
      await expectQuarantinedWhole(
        cardJournalEnvelope([notConfirmed, waiting]),
        'duplicate open attempt',
      );
      final testOpen = cardInDoubt(
        cardStoredAttempt(7, order: kCardOrder, mode: ProviderCardMode.test),
      );
      final testWaiting = _answeredAs(
        cardStoredAttempt(8, order: kCardOrder, mode: ProviderCardMode.test),
        _f(state: 'sent', classification: 'test_sent'),
      );
      await expectQuarantinedWhole(
        cardJournalEnvelope([testOpen, testWaiting]),
        'duplicate open attempt',
      );
    });

    test('terminal rows may share an order and an amount, and an open LIVE and '
        'an open TEST attempt of one order stand together', () async {
      final declinedA = _answeredAs(
        cardStoredAttempt(5, order: kCardOrder),
        _f(state: 'declined', classification: 'declined'),
      );
      final declinedB = _answeredAs(
        cardStoredAttempt(6, order: kCardOrder),
        _f(state: 'declined', classification: 'declined'),
      );
      final openLive = cardInDoubt(cardStoredAttempt(7, order: kCardOrder));
      final openTest = cardInDoubt(
        cardStoredAttempt(8, order: kCardOrder, mode: ProviderCardMode.test),
      );
      final raw = cardJournalEnvelope([
        declinedA,
        declinedB,
        openLive,
        openTest,
      ]);
      final prefs = await freshCardPrefs(<String, Object>{key: raw});
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      final load = await store.load(kCardScope);
      expect(load.quarantined, isEmpty);
      expect(load.attempts, [declinedA, declinedB, openLive, openTest]);
      final live = await _create(store, _live(n: 50));
      expect((live as ProviderCardAdopted).attempt.attemptId, cardV4(7));
      final test = await _create(store, _test(n: 51));
      expect((test as ProviderCardAdopted).attempt.attemptId, cardV4(8));
      expect(prefs.getString(key), raw);
    });

    test(
      'the store never writes an envelope it would refuse to read',
      () async {
        // A minted id that is already stored.
        final a = _kind('live not confirmed', 5);
        final stored = cardJournalEnvelope([a]);
        final prefs = await freshCardPrefs(<String, Object>{key: stored});
        final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
        final clash = cardStoredAttempt(5, order: kCardOrder2);
        await expectLater(
          store.createIfAbsent(
            kCardScope,
            identityKey: clash.identityKey,
            mode: clash.mode,
            mint: () => clash,
          ),
          throwsA(isA<PosPersistenceException>()),
        );
        expect(prefs.getString(key), stored);
        // A transition that would leave two open records of one order and
        // mode, of a kind the server can produce: a late approval after a
        // manager freed the attempt (freed -> orphan_approved, reconciliation)
        // while a newer attempt of the order is open. No card view reaches a
        // freed attempt today (no Check status, never polled); the store
        // refuses the write and keeps the stored bytes.
        resetProviderCardStoreChainsForTest();
        final freed = _answeredAs(
          cardStoredAttempt(6, order: kCardOrder),
          _f(state: 'unknown', classification: 'freed'),
        );
        final waiting = _answeredAs(
          cardStoredAttempt(7, order: kCardOrder),
          _f(state: 'sent', classification: 'in_progress'),
        );
        final two = cardJournalEnvelope([freed, waiting]);
        final prefs2 = await freshCardPrefs(<String, Object>{key: two});
        final store2 = SharedPrefsProviderCardStore(prefs: () async => prefs2);
        await expectLater(
          store2.update(
            kCardScope,
            freed.attemptId,
            (c) => c.copyWith(
              server: _f(state: 'approved', classification: 'orphan_approved'),
              updatedAt: at,
            ),
          ),
          throwsA(isA<PosPersistenceException>()),
        );
        expect(prefs2.getString(key), two);
      },
    );

    test('a new record must match its admission: another order, mode or '
        'scope from the mint is refused and nothing is written', () async {
      final prefs = await freshCardPrefs();
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      final asked = _live(n: 5);
      final wrong = <ProviderCardAttempt>[
        _live(n: 6, order: kCardOrder2),
        _test(n: 7),
        ProviderCardAttempt.create(
          attemptId: cardV4(8),
          organizationId: kCardScope.organizationId,
          restaurantId: kCardScope.restaurantId,
          branchId: kCardScope.branchId,
          deviceId: 'another-device',
          orderId: kCardOrder,
          orderNumber: '#A1',
          mode: ProviderCardMode.live,
          amountMinor: 1200,
          currencyCode: 'ILS',
          expectedRevision: 7,
          employeeProfileId: null,
          now: kCardNow,
        ),
      ];
      for (final minted in wrong) {
        await expectLater(
          store.createIfAbsent(
            kCardScope,
            identityKey: asked.identityKey,
            mode: asked.mode,
            mint: () => minted,
          ),
          throwsA(isA<PosPersistenceException>()),
          reason: minted.attemptId,
        );
      }
      expect(prefs.containsKey(key), isFalse);
      expect(await _create(store, asked), isA<ProviderCardCreated>());
    });

    test('a valid envelope is byte-compatible with 001F: written and '
        're-emitted exactly as before', () async {
      final prefs = await freshCardPrefs();
      final store = SharedPrefsProviderCardStore(prefs: () async => prefs);
      await _create(store, _live());
      expect(prefs.getString(key), cardJournalEnvelope([_live()]));
      resetProviderCardStoreChainsForTest();
      final x = _answeredAs(
        cardStoredAttempt(5, order: kCardOrder),
        _f(state: 'declined', classification: 'declined'),
      );
      final y = _answeredAs(
        cardStoredAttempt(6, order: kCardOrder),
        _f(state: 'declined', classification: 'declined'),
      );
      final z = cardInDoubt(cardStoredAttempt(7, order: kCardOrder2));
      final prefs2 = await freshCardPrefs(<String, Object>{
        key: cardJournalEnvelope([x, y, z]),
      });
      final store2 = SharedPrefsProviderCardStore(prefs: () async => prefs2);
      expect((await store2.load(kCardScope)).attempts, [x, y, z]);
      const later = '2026-10-30T12:05:00.000Z';
      await store2.update(
        kCardScope,
        z.attemptId,
        (c) => c.copyWith(updatedAt: later),
      );
      expect(
        prefs2.getString(key),
        cardJournalEnvelope([x, y, z.copyWith(updatedAt: later)]),
      );
    });
  });
}

/// The unresolved kinds of record (each open; never dropped to make room;
/// set aside only where no charge can exist).
const List<String> _unresolvedKinds = <String>[
  'live not sent',
  'live sign in again',
  'live not found',
  'live not confirmed',
  'live waiting',
  'live cancel requested',
  'live approved',
  'live recording not confirmed',
  'live recording refused',
  'live anomaly',
  'live safety stop',
  'test not sent',
  'test sign in again',
  'test not found',
  'test not confirmed',
  'test waiting',
  'test cancel confirmed',
  'test safety stop',
];

/// The safe and final kinds (terminal or recorded): the only ones dropped.
const List<String> _finalKinds = <String>[
  'live not applied',
  'live refused',
  'live declined',
  'live freed',
  'live resolved',
  'live recorded',
  'live closed',
  'test not applied',
  'test refused',
  'test approved',
  'test declined',
  'test closed',
  'test set aside',
];

ProviderCardAttempt _answeredAs(
  ProviderCardAttempt a,
  ProviderCardServerFacts facts,
) => a.copyWith(
  startMayHaveExecuted: true,
  startLastSentAt: canonicalInstantForTest(),
  startOutcome: ProviderCardStartOutcome.answered,
  server: facts,
  updatedAt: canonicalInstantForTest(),
);

ProviderCardRecordingOperation _leg(int n, String order) =>
    ProviderCardRecordingOperation(
      localOperationId: cardV4(n),
      targetId: cardV4(5000 + n),
      clientCreatedAt: canonicalInstantForTest(),
      orderId: order,
      amountTenderedMinor: 1200,
    );

/// A record of [kind] with identity [n], for an order of its own.
ProviderCardAttempt _kind(String kind, int n) {
  final at = canonicalInstantForTest();
  final test = kind.startsWith('test ');
  final a = cardStoredAttempt(
    n,
    order: cardOrderN(1000 + n),
    mode: test ? ProviderCardMode.test : ProviderCardMode.live,
    amount: test ? 100 : 1200,
  );
  ProviderCardAttempt facts(String state, String classification) =>
      _answeredAs(a, _f(state: state, classification: classification));
  final recoverable = ProviderCardServerFacts(
    state: 'approved',
    classification: 'approved_unrecorded',
    recorded: false,
    refusalCode: 'precondition_failed',
    anomalyCode: null,
    resolution: null,
    recoverable: true,
    resumeCount: 0,
    paymentId: null,
    serverTs: '2026-10-30T12:00:00Z',
  );
  const anomaly = ProviderCardServerFacts(
    state: 'unknown',
    classification: 'provider_anomaly',
    recorded: false,
    refusalCode: null,
    anomalyCode: 'out_of_contract',
    resolution: null,
    recoverable: null,
    resumeCount: null,
    paymentId: null,
    serverTs: '2026-10-30T12:00:00Z',
  );
  return switch (kind.substring(5)) {
    'not sent' => a,
    'sign in again' => a.copyWith(
      startLastSentAt: at,
      startOutcome: ProviderCardStartOutcome.authRequired,
      updatedAt: at,
    ),
    'not found' => cardInDoubt(a).copyWith(serverNotFoundAt: at, updatedAt: at),
    'not confirmed' => cardInDoubt(a),
    'safety stop' => cardInDoubt(a).copyWith(
      safetyStop: ProviderCardSafetyStop.attemptConflict,
      updatedAt: at,
    ),
    'waiting' when !test => facts('sent', 'in_progress'),
    'cancel requested' => facts('released', 'in_progress'),
    'approved' when !test => facts('approved', 'approved_unrecorded'),
    'recording not confirmed' =>
      facts('approved', 'approved_unrecorded').copyWith(
        recording: _leg(n, a.orderId),
        recordingInDoubt: true,
        updatedAt: at,
      ),
    'recording refused' => _answeredAs(a, recoverable).copyWith(
      recording: _leg(n, a.orderId),
      recordingMayHaveExecuted: true,
      recordingOutcome: ProviderCardRecordingOutcome.refused,
      recordingRefusal: 'precondition_failed',
      updatedAt: at,
    ),
    'anomaly' => _answeredAs(a, anomaly),
    'not applied' => a.copyWith(
      startLastSentAt: at,
      startOutcome: ProviderCardStartOutcome.notApplied,
      updatedAt: at,
    ),
    'refused' => a.copyWith(
      startMayHaveExecuted: true,
      startLastSentAt: at,
      startOutcome: ProviderCardStartOutcome.refused,
      startRefusal: const ProviderCardStartRefusal(
        'card_payments_disabled',
        null,
      ),
      updatedAt: at,
    ),
    'declined' when !test => facts('declined', 'declined'),
    'freed' => facts('unknown', 'freed'),
    'resolved' => _answeredAs(
      a,
      _f(
        state: 'approved',
        classification: 'resolved',
        resolution: 'provider_voided',
      ),
    ),
    'recorded' => _answeredAs(
      a,
      _f(
        state: 'approved',
        classification: 'recorded',
        recorded: true,
        paymentId: cardV4(7000 + n),
      ),
    ),
    'closed' when !test => a.copyWith(
      closed: ProviderCardClosure.abandoned,
      updatedAt: at,
    ),
    'waiting' => facts('sent', 'test_sent'),
    'cancel confirmed' => facts('released', 'test_released'),
    'approved' => facts('approved', 'test_approved'),
    'declined' => facts('declined', 'test_declined'),
    'closed' => _answeredAs(
      a,
      _f(state: 'sent', classification: 'test_sent', resolution: 'test_closed'),
    ),
    'set aside' => cardInDoubt(a).copyWith(
      serverNotFoundAt: at,
      closed: ProviderCardClosure.setAside,
      updatedAt: at,
    ),
    _ => throw ArgumentError(kind),
  };
}
