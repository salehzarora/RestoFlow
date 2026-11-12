// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: the provider-card controller — start,
// the direct transport kinds, status, release, single flight, adoption,
// quarantine, the settle window, posture gating and the foreground polling
// (execution packet §6, §7, §9, §10). Fake Edge only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/ids.dart' show FixedClientIdGenerator;
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/provider_card_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_capability.dart';
import 'package:restoflow_pos/src/data/provider_card_store.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posAuthTransportProvider, posSyncSessionProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart'
    show posSyncScopeProvider;
import 'package:restoflow_pos/src/state/provider_card_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_card_fakes.dart';

class _World {
  _World(this.c, this.server, this.prefs, this.ids, this.clock);
  final ProviderContainer c;
  final CardServerFake server;
  final SharedPreferences prefs;
  final CountingCardIds ids;
  final CardClock clock;

  ProviderCardController get ctrl =>
      c.read(providerCardControllerProvider.notifier);
  ProviderCardState get state => c.read(providerCardControllerProvider);
  ProviderCardAttempt? attempt([String order = kCardOrder]) =>
      state.currentFor(PosOrderIdentity.server(order), includeTest: true);

  Future<ProviderCardStartRequest> start({
    ProviderCardMode mode = ProviderCardMode.live,
    int? revision = 7,
    String order = kCardOrder,
  }) => ctrl.start(
    identity: PosOrderIdentity.server(order),
    orderId: order,
    orderNumber: '#A1',
    amountMinor: 1200,
    currencyCode: 'ILS',
    expectedRevision: revision,
    mode: mode,
  );

  Future<ProviderCardLoad> journal() =>
      SharedPrefsProviderCardStore(prefs: () async => prefs).load(kCardScope);
}

Future<_World> _world({
  CardServerFake? server,
  SharedPreferences? prefs,
  CardClock? clock,
  ProviderCardPollPolicy? policy,
  bool lab = false,
  Duration Function()? monotonic,
  ProviderCardStore? store,
}) async {
  final s = server ?? CardServerFake();
  final p = prefs ?? await freshCardPrefs();
  final ids = CountingCardIds();
  final k = clock ?? CardClock();
  final c = cardContainer(
    server: s,
    prefs: p,
    ids: ids,
    clock: k,
    policy: policy,
    monotonic: monotonic,
    store: store,
  );
  await c.read(staffCapabilitiesProvider.future);
  if (lab) c.read(providerCardLabEnabledProvider.notifier).state = true;
  await c.read(providerCardControllerProvider.notifier).ensureHydrated();
  return _World(c, s, p, ids, k);
}

void main() {
  setUp(() {
    resetProviderCardStoreChainsForTest();
    installNoNetworkGuard();
  });

  group('start (packet §5.4, §6)', () {
    test(
      'the attempt is durably "may have been sent" BEFORE the handoff',
      () async {
        final w = await _world();
        var checked = false;
        w.server.onEdge = (body) async {
          final load = await w.journal();
          final a = load.attempts.single;
          expect(a.startInDoubt, isTrue);
          expect(a.startLastSentAt, isNotNull);
          expect(a.attemptId, body['attempt_id']);
          checked = true;
        };
        expect(await w.start(), ProviderCardStartRequest.started);
        expect(checked, isTrue);
        final a = w.attempt()!;
        expect(a.phase, ProviderCardPhase.waiting);
        expect(a.startInDoubt, isFalse);
        expect(a.startOutcome, ProviderCardStartOutcome.answered);
        expect(
          (await w.journal()).attempts.single.phase,
          ProviderCardPhase.waiting,
        );
      },
    );

    test('notSent: the SAME request may be re-sent explicitly; nothing is '
        'minted', () async {
      final w = await _world();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
      expect(w.attempt()!.startHasNoPossibleEffect, isTrue);
      await w.ctrl.retryStart(w.attempt()!.attemptId);
      expect(w.server.edgeCount('start'), 2);
      expect(w.server.edgeBytes[0], w.server.edgeBytes[1]);
      expect(w.ids.calls, 1);
      expect(w.attempt()!.phase, ProviderCardPhase.waiting);
    });

    test('each send of an attempt is stamped later than the one before it, '
        'even on a wall clock that stands still or steps back', () async {
      final clock = CardClock();
      final w = await _world(clock: clock);
      const notSent = CardChargeTransportFailure.notSent(
        CardChargeFailureReason.handoffRefused,
      );
      w.server.edgeScript.addAll(<Object>[notSent, notSent, notSent, notSent]);
      await w.start();
      final id = w.attempt()!.attemptId;
      final stamps = <String>[w.attempt()!.startLastSentAt!];
      await w.ctrl.retryStart(id);
      stamps.add(w.attempt()!.startLastSentAt!);
      clock.advance(const Duration(minutes: -5));
      await w.ctrl.retryStart(id);
      stamps.add(w.attempt()!.startLastSentAt!);
      // Once the clock has moved on past the last stamp, a send is stamped
      // with the clock again.
      clock.advance(const Duration(minutes: 10));
      await w.ctrl.retryStart(id);
      stamps.add(w.attempt()!.startLastSentAt!);
      expect(w.server.edgeCount('start'), 4);
      expect(stamps.first, canonicalInstantOf(kCardNow));
      expect(stamps.last, canonicalInstantOf(clock.now));
      for (var i = 1; i < stamps.length; i++) {
        expect(
          DateTime.parse(stamps[i]).isAfter(DateTime.parse(stamps[i - 1])),
          isTrue,
          reason: 'send ${i + 1}: ${stamps[i]} after ${stamps[i - 1]}',
        );
      }
      expect((await w.journal()).attempts.single.startLastSentAt, stamps.last);
    });

    test('a resend is stamped from the stored record, never from a stale copy '
        'another controller holds', () async {
      final clock = CardClock();
      final prefs = await freshCardPrefs();
      const notSent = CardChargeTransportFailure.notSent(
        CardChargeFailureReason.handoffRefused,
      );
      final w = await _world(clock: clock, prefs: prefs);
      w.server.edgeScript.addAll(<Object>[notSent, notSent, notSent]);
      await w.start();
      final id = w.attempt()!.attemptId;
      // A second controller reads the journal now and keeps that copy.
      final other = await _world(server: w.server, clock: clock, prefs: prefs);
      await w.ctrl.retryStart(id);
      final second = (await w.journal()).attempts.single.startLastSentAt!;
      expect(other.attempt()!.startLastSentAt, isNot(second));
      await other.ctrl.retryStart(id);
      final third = (await w.journal()).attempts.single.startLastSentAt!;
      expect(w.server.edgeCount('start'), 3);
      expect(
        DateTime.parse(third).isAfter(DateTime.parse(second)),
        isTrue,
        reason: '$third after $second',
      );
    });

    test('unauthenticated: the attempt is preserved; the explicit resend uses '
        'the same identity', () async {
      final w = await _world();
      w.server.edgeScript.add((
        401,
        <String, Object?>{'ok': false, 'error': 'invalid_session'},
      ));
      await w.start();
      expect(w.attempt()!.phase, ProviderCardPhase.authRequired);
      await w.ctrl.retryStart(w.attempt()!.attemptId);
      expect(w.server.edgeBytes[0], w.server.edgeBytes[1]);
      expect(w.ids.calls, 1);
      expect(w.attempt()!.phase, ProviderCardPhase.waiting);
    });

    test('notApplied (400 / 403 / 404 / 405): a refusal, never a decline; no '
        'retry', () async {
      for (final status in <int>[400, 403, 404, 405]) {
        final w = await _world();
        w.server.edgeScript.add((
          status,
          <String, Object?>{'ok': false, 'error': 'invalid_request'},
        ));
        await w.start();
        final a = w.attempt()!;
        expect(a.phase, ProviderCardPhase.notApplied, reason: '$status');
        expect(a.isOpen, isFalse);
        await w.ctrl.retryStart(a.attemptId);
        await w.ctrl.checkStatus(a.attemptId);
        expect(
          w.server.edgeBodies,
          hasLength(1),
          reason: 'no automatic or explicit retry',
        );
      }
    });

    test('uncertain: start is NEVER sent again — not by retry, not by a new '
        'start, not after a restart; only status resolves it', () async {
      final w = await _world();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.timeout,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      expect(w.attempt()!.phase, ProviderCardPhase.uncertain);
      await w.ctrl.retryStart(id);
      expect(await w.start(), ProviderCardStartRequest.adopted);
      await w.ctrl.checkStatus(id);
      expect(w.server.edgeCount('start'), 1);
      expect(w.server.edgeCount('status'), 1);
      // Restart: a new provider graph over the same journal.
      final w2 = await _world(server: w.server, prefs: w.prefs);
      expect(w2.attempt()!.attemptId, id);
      expect(w2.attempt()!.phase, ProviderCardPhase.uncertain);
      expect(
        w.server.edgeBodies,
        hasLength(2),
        reason: 'hydration sends nothing',
      );
      await w2.ctrl.retryStart(id);
      expect(await w2.start(), ProviderCardStartRequest.adopted);
      expect(w.server.edgeCount('start'), 1);
    });

    test(
      '409 / 413 / 415 / 422 answers stay uncertain: zero later starts',
      () async {
        for (final status in <int>[409, 413, 415, 422]) {
          final w = await _world();
          w.server.edgeScript.add((
            status,
            <String, Object?>{'ok': false, 'error': 'invalid_request'},
          ));
          await w.start();
          expect(
            w.attempt()!.phase,
            ProviderCardPhase.uncertain,
            reason: '$status',
          );
          await w.ctrl.retryStart(w.attempt()!.attemptId);
          expect(w.server.edgeCount('start'), 1, reason: '$status');
        }
      },
    );

    test('a competing start on the same order is refused typed; no second '
        'provider send', () async {
      final server = CardServerFake();
      server.attempts[cardV4(500)] = FakeCardAttempt(
        id: cardV4(500),
        mode: 'live',
        amountMinor: 1200,
        currencyCode: 'ILS',
        orderId: kCardOrder,
        expectedRevision: 7,
      );
      final w = await _world(server: server);
      await w.start();
      final a = w.attempt()!;
      expect(a.phase, ProviderCardPhase.refused);
      expect(a.startRefusal!.error, 'payment_in_progress');
      expect(server.providerCommits, 0);
      expect(server.edgeCount('start'), 1);
    });

    test(
      'a start refusal with attempt facts (same identity, other fields) is a '
      'safety stop',
      () async {
        final w = await _world();
        w.server.edgeScript.add((
          200,
          <String, Object?>{
            'ok': false,
            'error': 'conflict',
            'attempt_id': cardV4(1),
            'attempt_state': 'sent',
            'server_ts': '2026-10-30T12:00:00Z',
          },
        ));
        await w.start();
        expect(w.attempt()!.safetyStop, ProviderCardSafetyStop.attemptConflict);
        expect(w.attempt()!.phase, ProviderCardPhase.reconciliation);
      },
    );

    test('two UI instances: concurrent starts create ONE attempt and send ONE '
        'start', () async {
      final w = await _world();
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final first = w.start();
      final second = await w.start();
      expect(second, ProviderCardStartRequest.busy);
      hold.complete();
      expect(await first, ProviderCardStartRequest.started);
      expect(w.server.edgeCount('start'), 1);
      expect((await w.journal()).attempts, hasLength(1));
    });

    test('two provider graphs over one journal: the second adopts the open '
        'attempt and sends nothing', () async {
      final w = await _world();
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final first = w.start();
      await pumpEventQueue();
      final w2 = await _world(server: w.server, prefs: w.prefs);
      expect(await w2.start(), ProviderCardStartRequest.adopted);
      hold.complete();
      await first;
      expect(w.server.edgeCount('start'), 1);
    });

    test(
      'an unreadable stored record blocks new starts (quarantine)',
      () async {
        final key = 'restoflow.pos.provider_card_attempts.v1.${kCardScope.key}';
        final prefs = await freshCardPrefs(<String, Object>{
          key: jsonEncode({
            'version': 1,
            'attempts': [
              {'schema_version': 9},
            ],
          }),
        });
        final w = await _world(prefs: prefs);
        expect(w.state.quarantined, isTrue);
        expect(await w.start(), ProviderCardStartRequest.quarantined);
        expect(w.server.edgeBodies, isEmpty);
      },
    );

    test('a save that does not hold sends nothing', () async {
      final w = await _world();
      final failing = _FailingStore();
      final c2 = cardContainer(
        server: w.server,
        prefs: w.prefs,
        extra: [providerCardStoreProvider.overrideWithValue(failing)],
      );
      await c2.read(staffCapabilitiesProvider.future);
      final ctrl = c2.read(providerCardControllerProvider.notifier);
      await ctrl.ensureHydrated();
      final r = await ctrl.start(
        identity: PosOrderIdentity.server(kCardOrder),
        orderId: kCardOrder,
        orderNumber: '#A1',
        amountMinor: 1200,
        currencyCode: 'ILS',
        expectedRevision: 7,
        mode: ProviderCardMode.live,
      );
      expect(r, ProviderCardStartRequest.saveBlocked);
      expect(w.server.edgeBodies, isEmpty);
    });
  });

  group('status, settle window and release (packet §6, §7.3, §10)', () {
    test('one status in flight per attempt: a second check joins it', () async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final a = w.ctrl.checkStatus(id);
      final b = w.ctrl.checkStatus(id);
      await pumpEventQueue();
      hold.complete();
      await Future.wait([a, b]);
      expect(w.server.edgeCount('status'), 1);
    });

    test('attempt_not_found is inconclusive inside the 200 s settle window '
        '(30 s, 170 s, 199 s) and conclusive at 200 s; a set-aside attempt '
        'frees a NEW explicit start', () async {
      final clock = CardClock();
      final w = await _world(clock: clock);
      w.server.edgeScript.add(
        const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.transport,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      for (final at in const <int>[30, 170, 199]) {
        clock.now = kCardNow.add(Duration(seconds: at));
        await w.ctrl.checkStatus(id);
        expect(
          w.attempt()!.phase,
          ProviderCardPhase.uncertain,
          reason: '$at s',
        );
        expect(w.attempt()!.mayBeSetAside, isFalse, reason: '$at s');
      }
      clock.now = kCardNow.add(const Duration(seconds: 200));
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.notFound);
      expect(w.attempt()!.mayBeSetAside, isTrue);
      expect(await w.ctrl.setAside(id), isTrue);
      expect(
        (await w.journal()).attempts.single.closed,
        ProviderCardClosure.setAside,
      );
      expect(await w.start(), ProviderCardStartRequest.started);
      expect(w.ids.calls, 2, reason: 'a new identity, explicitly');
      expect(w.server.edgeCount('start'), 2);
    });

    test(
      'declined is terminal; nothing is retried; a new start is explicit',
      () async {
        final w = await _world();
        await w.start();
        final id = w.attempt()!.attemptId;
        w.server.nextLookupState[id] = 'declined';
        await w.ctrl.checkStatus(id);
        expect(w.attempt()!.phase, ProviderCardPhase.declined);
        expect(w.attempt()!.isOpen, isFalse);
        expect(w.server.edgeCount('start'), 1);
        expect(w.server.pushCalls, isEmpty);
      },
    );

    test('release is advisory: one request per tap, "released" keeps the same '
        'attempt and Check status', () async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      await w.ctrl.release(id);
      expect(w.server.providerReleases, 1);
      expect(w.attempt()!.phase, ProviderCardPhase.released);
      expect(w.attempt()!.isOpen, isTrue);
      await w.ctrl.release(id);
      expect(
        w.server.edgeCount('release'),
        1,
        reason: 'not releasable any more',
      );
      w.server.nextLookupState[id] = 'approved';
      w.server.approve(id);
      await w.ctrl.checkStatus(id);
      expect(
        w.attempt()!.server!.state,
        'approved',
        reason: 'released never proved no charge',
      );
    });

    test('a release the provider does not confirm says so', () async {
      final w = await _world();
      w.server.releaseConfirms = false;
      await w.start();
      final id = w.attempt()!.attemptId;
      await w.ctrl.release(id);
      expect(w.state.notes[id], ProviderCardNote.releaseNotConfirmed);
      expect(w.attempt()!.phase, ProviderCardPhase.waiting);
    });

    test('status failures never change the attempt', () async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      final before = jsonEncode(w.attempt()!.toJson());
      w.server.edgeScript
        ..add(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.timeout,
          ),
        )
        ..add((
          503,
          <String, Object?>{'ok': false, 'error': 'provider_unavailable'},
        ))
        ..add((401, <String, Object?>{'ok': false, 'error': 'invalid_session'}))
        ..add((200, <String, Object?>{'ok': true, 'attempt_id': cardV4(1)}));
      for (final note in <ProviderCardNote>[
        ProviderCardNote.unavailable,
        ProviderCardNote.unavailable,
        ProviderCardNote.signInAgain,
        ProviderCardNote.unavailable,
      ]) {
        await w.ctrl.checkStatus(id);
        expect(w.state.notes[id], note);
        expect(jsonEncode(w.attempt()!.toJson()), before);
      }
    });
  });

  group('posture gating (packet §9)', () {
    test('no binding, starts stopped, or the wrong mode: no start', () async {
      final absent = await _world(server: CardServerFake(terminalMode: null));
      expect(await absent.start(), ProviderCardStartRequest.notPermitted);
      final stopped = await _world(
        server: CardServerFake(terminalEnabled: false),
      );
      expect(await stopped.start(), ProviderCardStartRequest.notPermitted);
      final test = await _world(server: CardServerFake(terminalMode: 'test'));
      expect(await test.start(), ProviderCardStartRequest.notPermitted);
      expect(
        await test.start(mode: ProviderCardMode.test),
        ProviderCardStartRequest.notPermitted,
        reason: 'the lab toggle is off by default',
      );
      for (final w in [absent, stopped, test]) {
        expect(w.server.edgeBodies, isEmpty);
      }
    });

    test('a LIVE start needs an authoritative revision', () async {
      final w = await _world();
      expect(await w.start(revision: null), ProviderCardStartRequest.invalid);
      expect(w.server.edgeBodies, isEmpty);
    });

    test(
      'TEST: the lab starts an order-less test attempt that never records',
      () async {
        final w = await _world(
          server: CardServerFake(terminalMode: 'test'),
          lab: true,
        );
        expect(
          await w.start(mode: ProviderCardMode.test),
          ProviderCardStartRequest.started,
        );
        final id = w.attempt()!.attemptId;
        final body = w.server.edgeBodies.single;
        expect(body['mode'], 'test');
        expect(body.containsKey('order_id'), isFalse);
        w.server.nextLookupState[id] = 'approved';
        await w.ctrl.checkStatus(id);
        expect(w.attempt()!.phase, ProviderCardPhase.testApproved);
        expect(w.attempt()!.recording, isNull);
        expect(
          w.server.pushCalls,
          isEmpty,
          reason: 'no payment.create for TEST',
        );
      },
    );
  });

  group('foreground polling (packet §10)', () {
    testWidgets(
      'automatic checks run only while a lease is held; closing stops '
      'them and keeps the attempt',
      (tester) async {
        final w = await _world();
        await w.start();
        final id = w.attempt()!.attemptId;
        final lease = w.ctrl.attachForeground(id);
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(w.server.edgeCount('status'), 1);
        expect(w.server.edgeBodies.last['source'], 'auto');
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(w.server.edgeCount('status'), 2);
        lease.release();
        await tester.pump(const Duration(seconds: 60));
        expect(w.server.edgeCount('status'), 2);
        expect(w.attempt(), isNotNull);
      },
    );

    testWidgets('an automatic and a manual check collide into ONE request', (
      tester,
    ) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final lease = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      final manual = w.ctrl.checkStatus(id);
      await tester.pump();
      hold.complete();
      await tester.pump();
      await manual;
      expect(w.server.edgeCount('status'), 1);
      lease.release();
    });

    testWidgets('unreadable answers back off 8 / 16 / 30 s', (tester) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      for (var i = 0; i < 3; i++) {
        w.server.edgeScript.add(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.transport,
          ),
        );
      }
      final lease = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1);
      await tester.pump(const Duration(seconds: 7));
      expect(w.server.edgeCount('status'), 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(w.server.edgeCount('status'), 2);
      await tester.pump(const Duration(seconds: 15));
      expect(w.server.edgeCount('status'), 2);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(w.server.edgeCount('status'), 3);
      await tester.pump(const Duration(seconds: 29));
      expect(w.server.edgeCount('status'), 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(w.server.edgeCount('status'), 4);
      lease.release();
    });

    testWidgets('the lease budget and poll_limit stop automatic checks; Check '
        'status still works', (tester) async {
      final w = await _world(policy: const ProviderCardPollPolicy(budget: 2));
      await w.start();
      final id = w.attempt()!.attemptId;
      final lease = w.ctrl.attachForeground(id);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
      }
      expect(w.server.edgeCount('status'), 2);
      expect(w.state.notes[id], ProviderCardNote.autoChecksPaused);
      lease.release();
      // poll_limit from the server.
      w.server.autoPollCap = 0;
      final lease2 = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.state.notes[id], ProviderCardNote.pollLimit);
      final before = w.server.edgeCount('status');
      await tester.pump(const Duration(seconds: 30));
      expect(w.server.edgeCount('status'), before);
      // While another request is under way, Check status checks nothing, so
      // the note stays.
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final releasing = w.ctrl.release(id);
      await tester.pump();
      await w.ctrl.checkStatus(id);
      expect(w.state.notes[id], ProviderCardNote.pollLimit);
      expect(w.server.edgeCount('status'), before);
      hold.complete();
      await tester.pump();
      await releasing;
      await w.ctrl.checkStatus(id);
      expect(w.server.edgeBodies.last['source'], 'operator');
      expect(w.server.edgeCount('status'), before + 1);
      lease2.release();
    });

    testWidgets('an empty back-off list falls back to the interval', (
      tester,
    ) async {
      final w = await _world(
        policy: const ProviderCardPollPolicy(backoff: <Duration>[]),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      for (var i = 0; i < 2; i++) {
        w.server.edgeScript.add(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.transport,
          ),
        );
      }
      final lease = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(w.server.edgeCount('status'), 2);
      lease.release();
    });

    testWidgets('a session that may not act makes the automatic checks back '
        'off', (tester) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      w.server.deniedPins.add(kCardPin);
      final lease = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1);
      expect(w.state.notes[id], ProviderCardNote.roleCannot);
      await tester.pump(const Duration(seconds: 7));
      expect(
        w.server.edgeCount('status'),
        1,
        reason: 'backing off: 8 s, not the 4 s interval',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(w.server.edgeCount('status'), 2);
      lease.release();
    });

    testWidgets('a rebuild (another PIN session) keeps a visible view\'s '
        'lease: its checks resume once the journal is read again', (
      tester,
    ) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      final lease = w.ctrl.attachForeground(id);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1);
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      expect(w.state.hydrated, isFalse, reason: 'a new world reads again');
      await w.ctrl.ensureHydrated();
      expect(w.attempt(), isNotNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(w.server.edgeCount('status'), 2);
      expect(w.server.edgeBodies.last['pin_session_id'], kCardPin2);
      lease.release();
      await tester.pump(const Duration(seconds: 30));
      expect(w.server.edgeCount('status'), 2);
    });
  });

  group('the settle window on the monotonic clock (packet §7.3)', () {
    const uncertain = CardChargeTransportFailure.uncertain(
      CardChargeFailureReason.transport,
    );

    test('a forward wall-clock step never settles it early: the same span '
        'must pass on the monotonic clock', () async {
      final clock = CardClock();
      var mono = Duration.zero;
      final w = await _world(clock: clock, monotonic: () => mono);
      w.server.edgeScript.add(uncertain);
      await w.start();
      final id = w.attempt()!.attemptId;
      // The wall clock jumps ten minutes; thirty seconds really passed.
      clock.advance(const Duration(minutes: 10));
      mono = const Duration(seconds: 30);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.uncertain);
      expect(
        w.attempt()!.serverNotFoundAt,
        isNull,
        reason: 'an inconclusive answer is not recorded',
      );
      mono = const Duration(seconds: 200);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.notFound);
    });

    test('the window runs from the END of a start exchange: a slow handoff '
        'does not shorten it', () async {
      final clock = CardClock();
      var mono = Duration.zero;
      final w = await _world(clock: clock, monotonic: () => mono);
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      w.server.edgeScript.add(uncertain);
      final started = w.start();
      await pumpEventQueue();
      // The exchange takes 35 s (a slow access-token step, a late handoff).
      mono = const Duration(seconds: 35);
      clock.advance(const Duration(seconds: 35));
      hold.complete();
      await started;
      final id = w.attempt()!.attemptId;
      mono = const Duration(seconds: 200);
      clock.advance(const Duration(seconds: 165));
      await w.ctrl.checkStatus(id);
      expect(
        w.attempt()!.phase,
        ProviderCardPhase.uncertain,
        reason: '200 s after the stamp, 165 s after the exchange ended',
      );
      mono = const Duration(seconds: 235);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.notFound);
    });

    test('a wall clock stepped back never delays it: the recorded decision '
        'is the monotonic one', () async {
      final clock = CardClock();
      var mono = Duration.zero;
      final w = await _world(clock: clock, monotonic: () => mono);
      w.server.edgeScript.add(uncertain);
      await w.start();
      final id = w.attempt()!.attemptId;
      clock.advance(const Duration(hours: -1));
      mono = const Duration(seconds: 200);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.notFound);
    });

    test('a new process measures it again from the hydration', () async {
      final clock = CardClock();
      final prefs = await freshCardPrefs();
      final w = await _world(
        clock: clock,
        prefs: prefs,
        monotonic: () => Duration.zero,
      );
      w.server.edgeScript.add(uncertain);
      await w.start();
      final id = w.attempt()!.attemptId;
      clock.advance(const Duration(seconds: 250));
      var mono = Duration.zero;
      final restarted = await _world(
        server: w.server,
        clock: clock,
        prefs: prefs,
        monotonic: () => mono,
      );
      await restarted.ctrl.checkStatus(id);
      expect(
        restarted.attempt()!.phase,
        ProviderCardPhase.uncertain,
        reason: 'the wall clock alone does not settle it',
      );
      mono = const Duration(seconds: 200);
      await restarted.ctrl.checkStatus(id);
      expect(restarted.attempt()!.phase, ProviderCardPhase.notFound);
      expect(w.server.edgeCount('start'), 1);
    });

    test('a resend that may have executed is waited on from the end of its '
        'own exchange, under its own stamp', () async {
      // The wall clock stands still: the resend is stamped one millisecond
      // after the first send, and its wait is bound to that stamp.
      final clock = CardClock();
      var mono = Duration.zero;
      final w = await _world(clock: clock, monotonic: () => mono);
      w.server.edgeScript.addAll(<Object>[
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
        uncertain,
      ]);
      await w.start();
      final id = w.attempt()!.attemptId;
      mono = const Duration(seconds: 30);
      await w.ctrl.retryStart(id);
      expect(w.attempt()!.phase, ProviderCardPhase.uncertain);
      mono = const Duration(seconds: 229);
      await w.ctrl.checkStatus(id);
      expect(
        w.attempt()!.phase,
        ProviderCardPhase.uncertain,
        reason: '199 s after the resend ended',
      );
      mono = const Duration(seconds: 230);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.notFound);
      expect(w.server.edgeCount('start'), 2);
    });

    test('a stale view\'s resend is refused on the stored record, and a '
        'not-found while another controller\'s resend is on its way records '
        'nothing', () async {
      // The wall clock stands still: the two sends are told apart by their
      // stamps alone (the resend's is one millisecond later). Were the stamps
      // equal, only the dropped wait of the first start, which could have had
      // no effect, would keep the not-found from being recorded.
      final clock = CardClock();
      final prefs = await freshCardPrefs();
      var mono = Duration.zero;
      final w = await _world(clock: clock, prefs: prefs, monotonic: () => mono);
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
      // Minutes on, a second controller over the same journal sends the SAME
      // start again; it is still on its way to the Edge.
      mono = const Duration(minutes: 5);
      final other = await _world(
        server: w.server,
        clock: clock,
        prefs: prefs,
        monotonic: () => mono,
      );
      expect(await other.start(), ProviderCardStartRequest.adopted);
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final resent = other.ctrl.retryStart(id);
      await pumpEventQueue();
      expect(w.server.edgeCount('start'), 2);
      // The first controller's stale view sends again: refused on the stored
      // record, which it shows from then on.
      await w.ctrl.retryStart(id);
      expect(w.server.edgeCount('start'), 2);
      expect(w.attempt()!.phase, ProviderCardPhase.uncertain);
      await w.ctrl.checkStatus(id);
      expect(
        w.attempt()!.phase,
        ProviderCardPhase.uncertain,
        reason: 'the resend is still on its way: not found proves nothing',
      );
      expect((await w.journal()).attempts.single.serverNotFoundAt, isNull);
      hold.complete();
      await resent;
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.waiting);
    });

    test('a wait on an earlier send never measures a later one, even on a '
        'wall clock that stands still', () async {
      // The wall clock stands still: the sends are told apart by their stamps
      // alone, each later than the one before it.
      final clock = CardClock();
      final prefs = await freshCardPrefs();
      var mono = Duration.zero;
      const notSent = CardChargeTransportFailure.notSent(
        CardChargeFailureReason.handoffRefused,
      );
      final w = await _world(clock: clock, prefs: prefs, monotonic: () => mono);
      w.server.edgeScript.add(notSent);
      await w.start();
      final id = w.attempt()!.attemptId;
      // The SAME start goes again and is held on its way out; meanwhile a
      // second controller reads the journal and begins to wait on that send.
      final first = Completer<void>();
      w.server.holdEdge = first;
      w.server.edgeScript.add(notSent);
      final again = w.ctrl.retryStart(id);
      await pumpEventQueue();
      final second = (await w.journal()).attempts.single.startLastSentAt;
      mono = const Duration(seconds: 10);
      final other = await _world(
        server: w.server,
        clock: clock,
        prefs: prefs,
        monotonic: () => mono,
      );
      expect(other.attempt()!.phase, ProviderCardPhase.uncertain);
      // That send never left. Minutes later the start goes once more, and it
      // is still on its way when the second controller checks.
      first.complete();
      await again;
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
      mono = const Duration(minutes: 5);
      final last = Completer<void>();
      w.server.holdEdge = last;
      final third = w.ctrl.retryStart(id);
      await pumpEventQueue();
      expect(w.server.edgeCount('start'), 3);
      expect(
        (await w.journal()).attempts.single.startLastSentAt,
        isNot(second),
        reason: 'the later send carries a stamp of its own',
      );
      for (var i = 1; i <= 2; i++) {
        await other.ctrl.checkStatus(id);
        expect(
          other.attempt()!.phase,
          ProviderCardPhase.uncertain,
          reason: 'check $i: the wait began on another send',
        );
      }
      expect((await w.journal()).attempts.single.serverNotFoundAt, isNull);
      last.complete();
      await third;
    });
  });

  group('one request per attempt across worlds (packet §10)', () {
    testWidgets('a rebuild while a status is on the wire: the new world sends '
        'nothing for that attempt until it returns', (tester) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      final lease = w.ctrl.attachForeground(id);
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1, reason: 'held on the wire');
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      expect(w.state.hydrated, isFalse);
      await w.ctrl.ensureHydrated();
      expect(
        w.state.busy[id],
        ProviderCardBusy.checking,
        reason: 'the new world shows the request under way',
      );
      await w.ctrl.checkStatus(id);
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(
        w.server.edgeCount('status'),
        1,
        reason: 'no second request while the first is on the wire',
      );
      hold.complete();
      await tester.pump();
      expect(w.state.busy[id], isNull, reason: 'it returned');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(w.server.edgeCount('status'), 2);
      expect(w.server.edgeBodies.last['pin_session_id'], kCardPin2);
      lease.release();
    });

    testWidgets('a late answer after the container is disposed re-arms '
        'nothing', (tester) async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      w.ctrl.attachForeground(id);
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(w.server.edgeCount('status'), 1);
      w.c.dispose();
      hold.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(w.server.edgeCount('status'), 1);
    });

    test('an answer that returns into another PIN session writes nothing '
        'into it', () async {
      final w = await _world();
      await w.start();
      final id = w.attempt()!.attemptId;
      w.server.deniedPins.add(kCardPin);
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final run = w.ctrl.checkStatus(id);
      await pumpEventQueue();
      // The PIN session changes while the answer is on its way, and nothing
      // reads the controller until it arrives.
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      hold.complete();
      await run;
      await w.ctrl.ensureHydrated();
      await pumpEventQueue();
      expect(
        w.state.notes[id],
        isNull,
        reason: 'the refusal was for the session signed in before',
      );
      expect(w.state.busy[id], isNull);
    });
  });

  group('journal reach, retry gate and set-aside (packet §5, §6, §7.3)', () {
    test('no RPC transport, or demo mode: the journal is never read and '
        'hydration is immediate (no card call is possible there)', () async {
      for (final demo in <bool>[false, true]) {
        final store = _CountingStore();
        final c = ProviderContainer(
          overrides: <Override>[
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: demo),
            ),
            posAuthTransportProvider.overrideWithValue(null),
            posSyncSessionProvider.overrideWithValue(kCardSession),
            posSyncScopeProvider.overrideWithValue(kCardScope),
            providerCardStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(c.dispose);
        await c.read(providerCardControllerProvider.notifier).ensureHydrated();
        expect(c.read(providerCardControllerProvider).hydrated, isTrue);
        expect(store.loads, 0, reason: 'demo: $demo');
      }
    });

    test('retrying a never-sent start needs the posture to still permit a '
        'start; otherwise nothing is sent', () async {
      final w = await _world();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
      w.server.terminalEnabled = false;
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      await w.ctrl.retryStart(id);
      expect(w.server.edgeCount('start'), 1);
      expect(w.state.notes[id], ProviderCardNote.terminalUnavailable);
      w.server.terminalEnabled = true;
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      await w.ctrl.retryStart(id);
      expect(w.server.edgeCount('start'), 2);
      expect(w.server.edgeBytes[0], w.server.edgeBytes[1]);
      expect(w.ids.calls, 1);
    });

    test('a retry reads a posture that is not known yet before deciding; one '
        'still unreadable sends nothing and says so', () async {
      final w = await _world();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      w.server.capabilitiesThrow = true;
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      await w.ctrl.retryStart(id);
      expect(w.server.edgeCount('start'), 1);
      expect(w.state.notes[id], ProviderCardNote.postureUnknown);
      // The probe answers again: the retry its card view asks for reads it
      // and goes out.
      w.server.capabilitiesThrow = false;
      final lease = w.ctrl.attachForeground(id);
      await w.ctrl.retryStart(id);
      expect(w.server.edgeCount('start'), 2);
      expect(w.server.edgeBytes[0], w.server.edgeBytes[1]);
      lease.release();
    });

    test('a retry shows the attempt being prepared while it reads the '
        'posture; a card view gone by then sends nothing', () async {
      final w = await _world();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      w.server.capabilitiesThrow = true;
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      w.server.capabilitiesThrow = false;
      final lease = w.ctrl.attachForeground(id);
      final hold = Completer<void>();
      w.server.capabilitiesHold = hold;
      final retried = w.ctrl.retryStart(id);
      await pumpEventQueue();
      expect(w.state.busy[id], ProviderCardBusy.starting);
      lease.release();
      hold.complete();
      await retried;
      expect(w.server.edgeCount('start'), 1, reason: 'nobody watches it');
      expect(w.state.busy[id], isNull);
      expect(w.state.notes[id], ProviderCardNote.notSent);
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
    });

    test('a fresh posture read is shared while under way; one that fails '
        'leaves the PIN session\'s capabilities as they were, and one that '
        'succeeds publishes only the card posture', () async {
      final w = await _world(server: CardServerFake(terminalMode: null));
      final caps = w.c.read(staffCapabilitiesProvider).valueOrNull;
      expect(caps, isNotNull);
      final probes = w.server.capabilitiesCalls;
      w.server.capabilitiesThrow = true;
      final reads = await Future.wait(<Future<ProviderCardPosture>>[
        w.ctrl.readPosture(),
        w.ctrl.readPosture(),
      ]);
      expect(reads, everyElement(isA<ProviderCardPostureUnknown>()));
      expect(w.server.capabilitiesCalls, probes + 1, reason: 'one read');
      expect(w.c.read(staffCapabilitiesProvider).valueOrNull, same(caps));
      expect(
        w.c.read(providerCardPostureProvider).posture,
        isA<ProviderCardPostureAbsent>(),
      );
      w.server.capabilitiesThrow = false;
      w.server.terminalMode = 'live';
      final read = await w.ctrl.readPosture();
      expect(read, isA<ProviderCardPosturePresent>());
      expect(w.c.read(providerCardPostureProvider).posture, same(read));
      expect(w.c.read(staffCapabilitiesProvider).valueOrNull, same(caps));
      // The probe answers again: its newer answer stands.
      w.server.terminalMode = null;
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      expect(
        w.c.read(providerCardPostureProvider).posture,
        isA<ProviderCardPostureAbsent>(),
      );
    });

    test('a fresh posture belongs to its PIN session: it lapses when the '
        'session changes, and a read answered after a change publishes '
        'nothing', () async {
      final w = await _world(server: CardServerFake(terminalMode: null));
      w.server.terminalMode = 'live';
      expect(await w.ctrl.readPosture(), isA<ProviderCardPosturePresent>());
      expect(
        w.c.read(providerCardPostureProvider).posture,
        isA<ProviderCardPosturePresent>(),
      );
      // Another person signs in; the probe for that session is still on its
      // way, and the earlier session's posture is no longer shown.
      final probe = Completer<void>();
      w.server.capabilitiesHold = probe;
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      expect(
        w.c.read(providerCardPostureProvider).posture,
        isA<ProviderCardPostureUnknown>(),
      );
      probe.complete();
      await w.c.read(staffCapabilitiesProvider.future);
      // A read still under way when the session changes again publishes
      // nothing: its answer was for the session signed in before.
      final read = Completer<void>();
      w.server.capabilitiesHold = read;
      final pending = w.ctrl.readPosture();
      await pumpEventQueue();
      w.c.read(cardSessionProvider.notifier).state = kCardSession;
      read.complete();
      expect(await pending, isA<ProviderCardPostureUnknown>());
      expect(w.c.read(providerCardFreshPostureProvider), isNull);
    });

    test('set-aside answers whether the record is closed: a refused write '
        'keeps it open', () async {
      final prefs = await freshCardPrefs();
      final store = HookedCardStore(
        SharedPrefsProviderCardStore(prefs: () async => prefs),
      );
      final w = await _world(prefs: prefs, store: store);
      w.server.edgeScript.add(
        const CardChargeTransportFailure.notSent(
          CardChargeFailureReason.handoffRefused,
        ),
      );
      await w.start();
      final id = w.attempt()!.attemptId;
      store.failUpdates = 1;
      expect(await w.ctrl.setAside(id), isFalse);
      expect(w.attempt()!.phase, ProviderCardPhase.notSent);
      expect(w.attempt()!.isOpen, isTrue);
      expect(w.state.notes[id], ProviderCardNote.saveFailed);
      expect(await w.ctrl.setAside(id), isTrue);
      expect(
        (await w.journal()).attempts.single.closed,
        ProviderCardClosure.abandoned,
      );
    });
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001.
  group(
    'an unresolved TEST attempt stays recoverable (correction packet §4)',
    () {
      final key = providerCardAttemptsStorageKey(kCardScope.key);
      ProviderCardAttempt? labOff(_World w, [String order = kCardOrder]) => w
          .state
          .currentFor(PosOrderIdentity.server(order), includeTest: false);

      Future<void> signIn(_World w, String pin) async {
        w.c.read(cardSessionProvider.notifier).state = SyncSession(
          pinSessionId: pin,
          deviceId: kCardDevice,
        );
        expect(w.state.hydrated, isFalse, reason: 'the journal is read again');
        await w.ctrl.ensureHydrated();
        await w.c.read(staffCapabilitiesProvider.future);
      }

      test('it stays the attempt shown with the lab off — after a PIN switch '
          'and a restart, with the same identity; Check status asks about it, '
          'nothing starts again, and the lab adopts it', () async {
        final prefs = await freshCardPrefs();
        final w = await _world(
          server: CardServerFake(terminalMode: 'test'),
          prefs: prefs,
          lab: true,
        );
        expect(
          await w.start(mode: ProviderCardMode.test),
          ProviderCardStartRequest.started,
        );
        final id = w.attempt()!.attemptId;
        expect(w.attempt()!.phase, ProviderCardPhase.testWaiting);

        await signIn(w, kCardPin2);
        expect(w.c.read(providerCardLabEnabledProvider), isFalse);
        expect(labOff(w)?.attemptId, id, reason: 'the lab does not hide it');
        await w.ctrl.checkStatus(id);
        expect(w.server.edgeCount('status'), 1);
        expect(w.server.edgeBodies.last['attempt_id'], id);
        expect(
          await w.start(mode: ProviderCardMode.test),
          ProviderCardStartRequest.notPermitted,
          reason: 'the lab off starts no TEST attempt',
        );
        w.c.read(providerCardLabEnabledProvider.notifier).state = true;
        expect(
          await w.start(mode: ProviderCardMode.test),
          ProviderCardStartRequest.adopted,
          reason: 'the lab on adopts the open one',
        );
        expect(w.ids.calls, 1);

        final restarted = await _world(server: w.server, prefs: prefs);
        expect(restarted.c.read(providerCardLabEnabledProvider), isFalse);
        expect(labOff(restarted)?.attemptId, id);
        expect(labOff(restarted)!.phase, ProviderCardPhase.testWaiting);
        await restarted.ctrl.checkStatus(id);
        expect(w.server.edgeCount('status'), 2);
        expect(w.server.edgeBodies.last['attempt_id'], id);
        expect(w.server.edgeCount('start'), 1, reason: 'never started again');
        expect(restarted.ids.calls, 0, reason: 'one identity');
        expect(
          w.server.pushCalls,
          isEmpty,
          reason: 'a TEST attempt never builds payment.create',
        );
        expect((await w.journal()).attempts.single.attemptId, id);
        expect((await w.journal()).attempts.single.closed, isNull);
      });

      test('a TEST attempt waiting, cancel-confirmed or not confirmed is never '
          'set aside; the journal is left as it was', () async {
        Future<void> refused(_World w, ProviderCardPhase phase) async {
          final a = w.attempt()!;
          expect(a.phase, phase);
          expect(a.mayBeSetAside, isFalse, reason: '$phase');
          final before = w.prefs.getString(key);
          expect(await w.ctrl.setAside(a.attemptId), isFalse, reason: '$phase');
          expect(w.prefs.getString(key), before, reason: '$phase');
          expect(w.attempt()!.closed, isNull, reason: '$phase');
          expect(w.attempt()!.isOpen, isTrue, reason: '$phase');
        }

        final w = await _world(
          server: CardServerFake(terminalMode: 'test'),
          lab: true,
        );
        await w.start(mode: ProviderCardMode.test);
        await refused(w, ProviderCardPhase.testWaiting);
        await w.ctrl.release(w.attempt()!.attemptId);
        expect(w.server.edgeCount('release'), 1);
        await refused(w, ProviderCardPhase.testReleased);

        final u = await _world(
          server: CardServerFake(terminalMode: 'test'),
          lab: true,
        );
        u.server.edgeScript.add(
          const CardChargeTransportFailure.uncertain(
            CardChargeFailureReason.transport,
          ),
        );
        await u.start(mode: ProviderCardMode.test);
        await refused(u, ProviderCardPhase.uncertain);
        expect(u.server.edgeCount('start'), 1);
      });

      test('a final TEST result — approved, declined or closed — is out of '
          'sight with the lab off and shown in the lab', () async {
        final w = await _world(
          server: CardServerFake(terminalMode: 'test'),
          lab: true,
        );
        final finals = <String, ProviderCardPhase>{
          kCardOrder: ProviderCardPhase.testApproved,
          kCardOrder2: ProviderCardPhase.testDeclined,
          cardOrderN(3): ProviderCardPhase.testClosed,
        };
        for (final e in finals.entries) {
          expect(
            await w.start(mode: ProviderCardMode.test, order: e.key),
            ProviderCardStartRequest.started,
          );
          final identity = PosOrderIdentity.server(e.key);
          final id = w.state.currentFor(identity, includeTest: true)!.attemptId;
          switch (e.value) {
            case ProviderCardPhase.testApproved:
              w.server.nextLookupState[id] = 'approved';
            case ProviderCardPhase.testDeclined:
              w.server.nextLookupState[id] = 'declined';
            default:
              w.server.attempts[id]!.resolution = 'test_closed';
          }
          expect(labOff(w, e.key)?.attemptId, id, reason: 'open: in sight');
          await w.ctrl.checkStatus(id);
          expect(
            w.state.currentFor(identity, includeTest: true)!.phase,
            e.value,
          );
          expect(labOff(w, e.key), isNull, reason: '${e.value}');
        }
        expect(w.server.pushCalls, isEmpty);
      });
    },
  );

  group('the journal admission bound (correction packet §5)', () {
    final key = providerCardAttemptsStorageKey(kCardScope.key);
    List<ProviderCardAttempt> openFill(int count) => [
      for (var i = 0; i < count; i++)
        cardInDoubt(cardStoredAttempt(100 + i, order: cardOrderN(i))),
    ];

    test('at the bound a start is refused typed — nothing minted, written or '
        'sent, no quarantine — and every stored attempt stays usable: a '
        'status check, its recording leg, and the room a recorded one '
        'makes', () async {
      final stored = cardJournalEnvelope(openFill(kProviderCardJournalCap));
      final prefs = await freshCardPrefs(<String, Object>{key: stored});
      final w = await _world(prefs: prefs);
      expect(w.state.byIdentity, hasLength(kProviderCardJournalCap));
      expect(await w.start(), ProviderCardStartRequest.journalFull);
      expect(w.ids.calls, 0, reason: 'no identity minted');
      expect(w.server.edgeBodies, isEmpty, reason: 'no Edge request');
      expect(prefs.getString(key), stored, reason: 'no journal append');
      expect(w.state.quarantined, isFalse, reason: 'not corruption');

      final first = cardV4(100);
      w.server.attempts[first] = FakeCardAttempt(
        id: first,
        mode: 'live',
        amountMinor: 1200,
        currencyCode: 'ILS',
        orderId: cardOrderN(0),
        expectedRevision: 7,
      );
      await w.ctrl.checkStatus(first);
      expect(w.server.edgeCount('status'), 1);
      expect(w.state.byId(first)!.phase, ProviderCardPhase.waiting);
      expect(
        (await w.journal()).attempts.first.phase,
        ProviderCardPhase.waiting,
      );
      expect(await w.start(), ProviderCardStartRequest.journalFull);

      w.server.approve(first);
      await w.ctrl.checkStatus(first);
      expect(w.state.byId(first)!.phase, ProviderCardPhase.recorded);
      expect(w.server.pushCalls, hasLength(1));
      expect(w.server.edgeCount('start'), 0);
      expect(w.ids.calls, 1, reason: 'the leg target id only');

      expect(await w.start(), ProviderCardStartRequest.started);
      expect(w.ids.calls, 2, reason: 'one attempt id, once admitted');
      expect(w.server.edgeCount('start'), 1);
      final load = await w.journal();
      expect(load.attempts, hasLength(kProviderCardJournalCap));
      expect(load.attempts.map((a) => a.attemptId), isNot(contains(first)));
    });

    test('at the bound an open attempt of the same order is adopted: no '
        'second identity, nothing sent', () async {
      final fill = openFill(kProviderCardJournalCap - 1);
      final mine = cardInDoubt(cardStoredAttempt(99, order: kCardOrder));
      final stored = cardJournalEnvelope([...fill, mine]);
      final prefs = await freshCardPrefs(<String, Object>{key: stored});
      final w = await _world(prefs: prefs);
      expect(await w.start(), ProviderCardStartRequest.adopted);
      expect(w.attempt()!.attemptId, mine.attemptId);
      expect(w.ids.calls, 0);
      expect(w.server.edgeBodies, isEmpty);
      expect(prefs.getString(key), stored);
    });

    test('199 open records and one safe final record: the final one makes '
        'room and the start goes ahead', () async {
      final at = kCardNow.toUtc().toIso8601String();
      final fill = openFill(kProviderCardJournalCap - 1);
      final finalOne = cardStoredAttempt(
        98,
        order: cardOrderN(500),
      ).copyWith(closed: ProviderCardClosure.abandoned, updatedAt: at);
      final prefs = await freshCardPrefs(<String, Object>{
        key: cardJournalEnvelope([
          ...fill.take(10),
          finalOne,
          ...fill.skip(10),
        ]),
      });
      final w = await _world(prefs: prefs);
      expect(await w.start(), ProviderCardStartRequest.started);
      expect(w.ids.calls, 1);
      expect(w.server.edgeCount('start'), 1);
      final ids = (await w.journal()).attempts.map((a) => a.attemptId).toList();
      expect(ids, hasLength(kProviderCardJournalCap));
      expect(ids, isNot(contains(cardV4(98))));
      for (final a in fill) {
        expect(ids, contains(a.attemptId));
      }
    });

    test('at the bound the manager Resume of a refused recording still runs — '
        'its proof, its leg and its recorded answer are all stored — and the '
        'recorded attempt then makes room', () async {
      final w = await _world();
      w.server.nextLegRefusal = 'precondition_failed';
      await w.start();
      final id = w.attempt()!.attemptId;
      w.server.approve(id);
      await w.ctrl.checkStatus(id);
      expect(w.attempt()!.phase, ProviderCardPhase.recordingRefused);
      expect(w.ids.calls, 2, reason: 'the attempt id and the leg target id');
      // Other attempts of this till fill the journal to the bound meanwhile.
      final env = jsonDecode(w.prefs.getString(key)!) as Map<String, Object?>;
      final filled = jsonEncode(<String, Object?>{
        'version': 1,
        'attempts': <Object?>[
          ...env['attempts']! as List<Object?>,
          for (final a in openFill(kProviderCardJournalCap - 1)) a.toJson(),
        ],
      });
      await w.prefs.setString(key, filled);
      expect(
        await w.start(order: kCardOrder2),
        ProviderCardStartRequest.journalFull,
      );
      expect(w.ids.calls, 2, reason: 'nothing minted at the bound');

      w.server.role = 'manager';
      await w.ctrl.resumeRecording(id);
      expect(w.attempt()!.phase, ProviderCardPhase.recorded);
      expect(w.server.pushedOps, hasLength(2));
      expect(w.server.pushedOps.last['recording_resume'], 0);
      expect(w.server.attempts[id]!.resumeCount, 1);
      final stored = (await w.journal()).attempts;
      expect(stored, hasLength(kProviderCardJournalCap));
      expect(stored.first.phase, ProviderCardPhase.recorded);

      expect(
        await w.start(order: kCardOrder2),
        ProviderCardStartRequest.started,
        reason: 'the recorded attempt is safe and final',
      );
      expect(w.ids.calls, 3);
      final after = (await w.journal()).attempts.map((a) => a.attemptId);
      expect(after, hasLength(kProviderCardJournalCap));
      expect(after, isNot(contains(id)));
    });

    test('an id source that gives no lowercase UUID v4 starts nothing: the '
        'answer is invalid, and nothing is written or sent', () async {
      final prefs = await freshCardPrefs();
      final server = CardServerFake();
      final c = cardContainer(
        server: server,
        prefs: prefs,
        ids: FixedClientIdGenerator(<String>['not-a-uuid-v4']),
      );
      await c.read(staffCapabilitiesProvider.future);
      final ctrl = c.read(providerCardControllerProvider.notifier);
      await ctrl.ensureHydrated();
      expect(
        await ctrl.start(
          identity: PosOrderIdentity.server(kCardOrder),
          orderId: kCardOrder,
          orderNumber: '#A1',
          amountMinor: 1200,
          currencyCode: 'ILS',
          expectedRevision: 7,
          mode: ProviderCardMode.live,
        ),
        ProviderCardStartRequest.invalid,
      );
      expect(server.edgeBodies, isEmpty);
      expect(prefs.containsKey(key), isFalse, reason: 'nothing written');
      expect(c.read(providerCardControllerProvider).byIdentity, isEmpty);
    });
  });

  group('envelope uniqueness (correction packet §6)', () {
    test('a journal holding one attempt twice, or two open attempts of one '
        'order and mode, is quarantined whole: nothing is shown, started, '
        'sent or rewritten', () async {
      final key = providerCardAttemptsStorageKey(kCardScope.key);
      final a = cardInDoubt(cardStoredAttempt(5, order: kCardOrder));
      final b = cardInDoubt(cardStoredAttempt(6, order: kCardOrder));
      for (final raw in <String>[
        cardJournalEnvelope([a, a]),
        cardJournalEnvelope([a, b]),
      ]) {
        resetProviderCardStoreChainsForTest();
        final prefs = await freshCardPrefs(<String, Object>{key: raw});
        final w = await _world(prefs: prefs);
        expect(w.state.quarantined, isTrue);
        expect(w.state.byIdentity, isEmpty, reason: 'no copy is chosen');
        expect(w.attempt(), isNull);
        expect(await w.start(), ProviderCardStartRequest.quarantined);
        await w.ctrl.checkStatus(a.attemptId);
        expect(await w.ctrl.setAside(a.attemptId), isFalse);
        expect(w.server.edgeBodies, isEmpty);
        expect(w.ids.calls, 0);
        expect(prefs.getString(key), raw, reason: 'kept as support evidence');
      }
    });
  });

  // BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001, the
  // fix-delta review (FR-3): open TEST attempts now always compete for the
  // form, and an open LIVE attempt of the order still comes first.
  group('an open LIVE attempt comes before an open TEST one '
      '(correction packet §4.2)', () {
    final identity = PosOrderIdentity.server(kCardOrder);

    test('currentFor picks an open LIVE attempt over a newer open TEST '
        'attempt of the order, with the lab on or off', () {
      final live = cardInDoubt(cardStoredAttempt(7, order: kCardOrder));
      final trial = cardInDoubt(
        cardStoredAttempt(8, order: kCardOrder, mode: ProviderCardMode.test),
      );
      expect(live.isOpen && trial.isOpen, isTrue);
      final s = ProviderCardState(
        hydrated: true,
        quarantined: false,
        byIdentity: <String, List<ProviderCardAttempt>>{
          identity.key: <ProviderCardAttempt>[live, trial],
        },
      );
      for (final lab in <bool>[false, true]) {
        expect(
          s.currentFor(identity, includeTest: lab)!.attemptId,
          cardV4(7),
          reason: 'lab $lab',
        );
      }
    });

    test('a LIVE attempt kept in doubt beside a newer TEST attempt of the '
        'order is the one shown after a PIN switch', () async {
      final prefs = await freshCardPrefs();
      final store = HookedCardStore(
        SharedPrefsProviderCardStore(prefs: () async => prefs),
      );
      final w = await _world(prefs: prefs, store: store);
      // A LIVE start the server refuses, whose answer could not be saved: in
      // memory it is refused, in the journal it may have been sent.
      w.server.startsDisabled = true;
      w.server.onEdge = (body) {
        if (body['action'] == 'start') store.failUpdates = 1;
      };
      expect(await w.start(), ProviderCardStartRequest.started);
      w.server
        ..onEdge = null
        ..startsDisabled = false;
      final liveId = cardV4(1);
      expect(w.state.byId(liveId)!.isOpen, isFalse);
      expect(
        (await w.journal()).attempts.single.phase,
        ProviderCardPhase.uncertain,
      );
      // The till is read again as a TEST till; in the lab a TEST start for
      // the same order is admitted (another mode).
      w.server.terminalMode = 'test';
      w.c.invalidate(staffCapabilitiesProvider);
      await w.c.read(staffCapabilitiesProvider.future);
      w.c.read(providerCardLabEnabledProvider.notifier).state = true;
      expect(
        await w.start(mode: ProviderCardMode.test),
        ProviderCardStartRequest.started,
      );
      expect(
        [
          for (final a in (await w.journal()).attempts)
            '${a.mode.wire}:${a.phase.name}',
        ],
        ['live:uncertain', 'test:testWaiting'],
      );
      // A PIN switch reads the journal again: both are open, the LIVE first.
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      await w.ctrl.ensureHydrated();
      expect(w.c.read(providerCardLabEnabledProvider), isFalse);
      expect(w.state.byId(liveId)!.isOpen, isTrue);
      for (final lab in <bool>[false, true]) {
        expect(
          w.state.currentFor(identity, includeTest: lab)!.attemptId,
          liveId,
          reason: 'lab $lab',
        );
      }
    });
  });
}

class _CountingStore implements ProviderCardStore {
  int loads = 0;

  @override
  Future<ProviderCardCreate> createIfAbsent(
    scope, {
    required identityKey,
    required mode,
    required mint,
  }) async => throw StateError('not expected');

  @override
  Future<ProviderCardLoad> load(scope) async {
    loads++;
    return ProviderCardLoad.empty;
  }

  @override
  Future<ProviderCardAttempt> update(scope, attemptId, transform) async =>
      throw StateError('not expected');
}

class _FailingStore implements ProviderCardStore {
  @override
  Future<ProviderCardCreate> createIfAbsent(
    scope, {
    required identityKey,
    required mode,
    required mint,
  }) async => throw StateError('storage refused');

  @override
  Future<ProviderCardLoad> load(scope) async => ProviderCardLoad.empty;

  @override
  Future<ProviderCardAttempt> update(scope, attemptId, transform) async =>
      throw StateError('storage refused');
}
