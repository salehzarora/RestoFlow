// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F: the provider recording leg and the D-054
// Resume (execution packet §8): the canonical payment.create without
// expected_revision, persisted before its first send and reused byte for byte;
// one internal recording; cashier resend; the refusal report; the manager
// Resume with its count, denials and limit; resume_authority_required; TEST
// never records. Fake Edge and fake sync_push only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/payment_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_attempt.dart';
import 'package:restoflow_pos/src/data/provider_card_recording.dart';
import 'package:restoflow_pos/src/data/provider_card_store.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/provider_card_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_card_fakes.dart';

class _W {
  _W(this.c, this.server, this.prefs, this.ids);
  final ProviderContainer c;
  final CardServerFake server;
  final SharedPreferences prefs;
  final CountingCardIds ids;

  ProviderCardController get ctrl =>
      c.read(providerCardControllerProvider.notifier);
  ProviderCardState get state => c.read(providerCardControllerProvider);
  ProviderCardAttempt get a =>
      state.currentFor(PosOrderIdentity.server(kCardOrder), includeTest: true)!;
  String get id => a.attemptId;

  Future<void> start() => ctrl.start(
    identity: PosOrderIdentity.server(kCardOrder),
    orderId: kCardOrder,
    orderNumber: '#A1',
    amountMinor: 1200,
    currencyCode: 'ILS',
    expectedRevision: 7,
    mode: ProviderCardMode.live,
  );

  /// Start, then the provider approves and a status check learns it.
  Future<void> approveAndCheck() async {
    await start();
    server.approve(id);
    await ctrl.checkStatus(id);
  }

  Future<ProviderCardLoad> journal() =>
      SharedPrefsProviderCardStore(prefs: () async => prefs).load(kCardScope);
}

Future<_W> _w({
  CardServerFake? server,
  SharedPreferences? prefs,
  ProviderCardStore? store,
}) async {
  final s = server ?? CardServerFake();
  final p = prefs ?? await freshCardPrefs();
  final ids = CountingCardIds();
  final c = cardContainer(server: s, prefs: p, ids: ids, store: store);
  await c.read(staffCapabilitiesProvider.future);
  await c.read(providerCardControllerProvider.notifier).ensureHydrated();
  return _W(c, s, p, ids);
}

void main() {
  setUp(() {
    resetProviderCardStoreChainsForTest();
    installNoNetworkGuard();
  });

  group('the first send (packet §8.1, §8.2)', () {
    test('approved → ONE canonical payment.create, alone, without '
        'expected_revision → recorded; the provider is not called', () async {
      final w = await _w();
      await w.approveAndCheck();
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(w.server.pushCalls, hasLength(1));
      final call = w.server.pushCalls.single;
      expect(call.keys.toSet(), {
        'p_pin_session_id',
        'p_device_id',
        'p_operations',
      });
      expect(call['p_pin_session_id'], kCardPin);
      final ops = call['p_operations'] as List;
      expect(ops, hasLength(1), reason: 'the only operation of its call');
      final op = ops.single as Map<String, dynamic>;
      expect(op.keys.toList(), <String>[
        'local_operation_id',
        'operation_type',
        'target_entity',
        'target_id',
        'client_created_at',
        'payload',
      ]);
      expect(op['local_operation_id'], w.id, reason: 'the SAME identity');
      expect(op['operation_type'], 'payment.create');
      expect(op['payload'], <String, Object?>{
        'order_id': kCardOrder,
        'tender_type': 'card',
        'amount_tendered_minor': 1200,
      });
      expect(jsonEncode(call).contains('expected_revision'), isFalse);
      expect(w.server.paymentsCreated, 1);
      expect(w.a.payment!.receiptNumber, 'R-1');
      expect(w.server.providerCommits, 1);
      expect(w.server.providerLookups, 0);
      expect(w.server.providerReleases, 0);
      expect(
        w.ctrl.consumeReceipt(w.id),
        isTrue,
        reason: 'one automatic receipt',
      );
      expect(w.ctrl.consumeReceipt(w.id), isFalse);
    });

    test(
      'the leg is durably persisted, in doubt, before its first send',
      () async {
        final w = await _w();
        var checked = false;
        w.server.onPush = (_) async {
          final a = (await w.journal()).attempts.single;
          expect(a.recording, isNotNull);
          expect(a.recordingInDoubt, isTrue);
          expect(a.recordingOutcome, isNull);
          checked = true;
        };
        await w.approveAndCheck();
        expect(checked, isTrue);
        final stored = (await w.journal()).attempts.single;
        expect(stored.recording!.toSyncOperation(), w.server.pushedOps.single);
        expect(stored.recordingInDoubt, isFalse);
        expect(stored.recordingOutcome, ProviderCardRecordingOutcome.applied);
      },
    );

    test('a revision move after approval (KDS, fulfilment) never strands the '
        'leg; a stale revision on a leg WOULD be refused', () async {
      final w = await _w();
      await w.start();
      w.server.approve(w.id);
      w.server.orderRevision = 99;
      await w.ctrl.checkStatus(w.id);
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(w.server.legRows[w.id]!.status, 'applied');
    });

    test('ordinary tenders keep PDR-003: the base record still sends '
        'expected_revision; the leg view is never persisted', () async {
      final base = PaymentAttempt.mint(
        ids: FixedClientIdGenerator(<String>[cardV4(80), cardV4(81)]),
        now: kCardNow,
        orderId: kCardOrder,
        orderNumber: '#A1',
        amountMinor: 1200,
        tenderedMinor: 1200,
        currencyCode: 'ILS',
        method: PaymentMethod.card,
        expectedRevision: 7,
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        deviceId: kCardDevice,
        employeeProfileId: 'emp-cashier',
      );
      expect(
        (base.toSyncOperation()['payload'] as Map)['expected_revision'],
        7,
      );
      final w = await _w();
      await w.approveAndCheck();
      expect(
        w.prefs.getKeys().where(
          (k) => k.startsWith('restoflow.pos.payment_attempts'),
        ),
        isEmpty,
      );
    });
  });

  group('resend and restart (packet §8.2)', () {
    test('a lost reply before any commit: the cashier re-sends the SAME leg '
        'after a fresh proof; one payment exists', () async {
      final w = await _w();
      w.server.legFaults.add('lost');
      await w.approveAndCheck();
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
      final statusBefore = w.server.edgeCount('status');
      await w.ctrl.resendRecording(w.id);
      expect(
        w.server.edgeCount('status'),
        statusBefore + 1,
        reason: 'the fresh proof',
      );
      expect(w.server.edgeBodies.last['source'], 'operator');
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(w.server.pushedOps, hasLength(2));
      expect(
        jsonEncode(w.server.pushedOps[0]),
        jsonEncode(w.server.pushedOps[1]),
      );
      expect(w.server.paymentsCreated, 1);
      expect(w.ids.calls, 2, reason: 'the attempt id and the target id, once');
      expect(
        w.ctrl.consumeReceipt(w.id),
        isTrue,
        reason: 'this device received its own applied reply',
      );
    });

    test('a lost reply AFTER the commit: the fresh proof finds it recorded, '
        'nothing is re-sent, and no automatic receipt fires', () async {
      final w = await _w();
      w.server.legFaults.add('drop');
      await w.approveAndCheck();
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
      await w.ctrl.resendRecording(w.id);
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(w.server.pushedOps, hasLength(1));
      expect(w.server.paymentsCreated, 1);
      expect(
        w.ctrl.consumeReceipt(w.id),
        isFalse,
        reason: 'a passive discovery; Reprint stands',
      );
    });

    test(
      'restart before the reply: the stored leg is reused byte for byte',
      () async {
        final w = await _w();
        w.server.legFaults.add('lost');
        await w.approveAndCheck();
        final stored = (await w.journal()).attempts.single;
        final w2 = await _w(server: w.server, prefs: w.prefs);
        expect(w2.a.phase, ProviderCardPhase.recordingUnconfirmed);
        final pushesBefore = w.server.pushedOps.length;
        expect(
          w.server.pushedOps,
          hasLength(pushesBefore),
          reason: 'hydration sends nothing',
        );
        await w2.ctrl.resendRecording(w2.id);
        expect(w.server.pushedOps.last, stored.recording!.toSyncOperation());
        expect(w2.a.phase, ProviderCardPhase.recorded);
        expect(w.server.paymentsCreated, 1);
      },
    );

    test('a failed fresh proof sends no leg', () async {
      final w = await _w();
      w.server.legFaults.add('lost');
      await w.approveAndCheck();
      w.server.edgeScript.add(
        const CardChargeTransportFailure.uncertain(
          CardChargeFailureReason.timeout,
        ),
      );
      final pushes = w.server.pushCalls.length;
      await w.ctrl.resendRecording(w.id);
      expect(w.server.pushCalls, hasLength(pushes));
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
    });

    test('transient_failure, single_operation_required and a whole-call raise '
        'leave the leg resendable', () async {
      for (final fault in <String>['transient', 'single', 'raise42501']) {
        resetProviderCardStoreChainsForTest();
        final w = await _w();
        w.server.legFaults.add(fault);
        await w.approveAndCheck();
        expect(
          w.a.phase,
          ProviderCardPhase.recordingUnconfirmed,
          reason: fault,
        );
        await w.ctrl.resendRecording(w.id);
        expect(w.a.phase, ProviderCardPhase.recorded, reason: fault);
        expect(w.server.paymentsCreated, 1, reason: fault);
      }
    });
  });

  group('refusals and the manager Resume (packet §8.4)', () {
    Future<_W> refused(String kind) async {
      final w = await _w();
      w.server.nextLegRefusal = kind;
      await w.approveAndCheck();
      return w;
    }

    test('a recoverable refusal is reported, then a MANAGER resumes the SAME '
        'leg with recording_resume = the count; no provider call', () async {
      final w = await refused('precondition_failed');
      final report = w.server.edgeBodies.last;
      expect(report['recording_refused'], true);
      expect(report['refusal_code'], 'precondition_failed');
      expect(w.a.refusalReportPending, isNull);
      expect(w.a.server!.recoverable, isTrue);
      expect(w.a.phase, ProviderCardPhase.recordingRefused);
      final commits = w.server.providerCommits;
      final lookups = w.server.providerLookups;

      // A cashier cannot resume.
      await w.ctrl.resumeRecording(w.id);
      expect(w.state.notes[w.id], ProviderCardNote.managerRequired);
      expect(w.server.pushedOps, hasLength(1));

      w.server.role = 'manager';
      await w.ctrl.resumeRecording(w.id);
      expect(w.a.phase, ProviderCardPhase.recorded);
      final first = Map<String, dynamic>.of(w.server.pushedOps[0]);
      final resumed = Map<String, dynamic>.of(w.server.pushedOps[1]);
      expect(resumed.remove('recording_resume'), 0);
      expect(
        resumed,
        first,
        reason: 'same identity, target, timestamp, payload',
      );
      expect(w.server.attempts[w.id]!.resumeCount, 1);
      expect(w.server.paymentsCreated, 1);
      expect(w.server.providerCommits, commits);
      expect(w.server.providerLookups, lookups);
    });

    test('a stale count is refused and consumes nothing; the next Resume uses '
        'the fresh count', () async {
      final w = await refused('precondition_failed');
      w.server.role = 'manager';
      var bumped = false;
      w.server.onPush = (p) {
        final op = (p['p_operations'] as List).single as Map;
        if (op.containsKey('recording_resume') && !bumped) {
          bumped = true;
          // Another device's Resume won meanwhile: it reopened the row, the
          // leg was refused again and that refusal was reported.
          w.server.simulateOtherResume(w.id);
        }
      };
      await w.ctrl.resumeRecording(w.id);
      expect(w.a.phase, ProviderCardPhase.resumeRefused);
      expect(w.a.resumeDenied, 'resume_stale');
      expect(w.server.attempts[w.id]!.resumeCount, 1);
      expect(w.a.server!.resumeCount, 1, reason: 're-read after the denial');
      await w.ctrl.resumeRecording(w.id);
      expect((w.server.pushedOps.last)['recording_resume'], 1);
      expect(w.a.phase, ProviderCardPhase.recorded);
    });

    test('a denial by the server guard never consumes the count', () async {
      final w = await refused('precondition_failed');
      w.server.role = 'manager';
      w.server.onPush = (_) => w.server.role = 'cashier'; // the session changed
      await w.ctrl.resumeRecording(w.id);
      expect(w.a.resumeDenied, 'not_manager');
      expect(w.server.attempts[w.id]!.resumeCount, 0);
      expect(w.server.paymentsCreated, 0);
    });

    test(
      'after three Resumes the attempt needs reconciliation; no fourth',
      () async {
        final w = await refused('precondition_failed');
        w.server.attempts[w.id]!.resumeCount = 3;
        await w.ctrl.checkStatus(w.id);
        expect(w.a.phase, ProviderCardPhase.reconciliation);
        w.server.role = 'manager';
        final pushes = w.server.pushCalls.length;
        await w.ctrl.resumeRecording(w.id);
        expect(w.server.pushCalls, hasLength(pushes));
      },
    );

    test('a row a Resume reopened answers a cashier resume_authority_required; '
        'only a manager sends it', () async {
      final w = await refused('precondition_failed');
      w.server.role = 'manager';
      w.server.legFaults.add('transient');
      await w.ctrl.resumeRecording(w.id);
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
      w.server.role = 'cashier';
      await w.ctrl.resendRecording(w.id);
      expect(w.a.phase, ProviderCardPhase.managerMustSend);
      expect(w.server.paymentsCreated, 0);
      await w.ctrl.managerSend(w.id);
      expect(w.state.notes[w.id], ProviderCardNote.managerRequired);
      w.server.role = 'manager';
      await w.ctrl.managerSend(w.id);
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(w.server.pushedOps.last.containsKey('recording_resume'), isFalse);
      expect(
        w.server.attempts[w.id]!.resumeCount,
        1,
        reason: 'no second Resume consumed',
      );
    });

    test('revoked_device is never recoverable', () async {
      final w = await refused('revoked_device');
      expect(w.a.recordingRefusal, 'revoked_device');
      expect(w.a.phase, ProviderCardPhase.reconciliation);
    });
  });

  group('an owed refusal report (packet §8.4)', () {
    const lost = CardChargeTransportFailure.uncertain(
      CardChargeFailureReason.transport,
    );

    /// The leg is refused [kind]; the automatic report that follows is lost.
    Future<_W> reportLost(String kind) async {
      final w = await _w();
      w.server.nextLegRefusal = kind;
      w.server.onPush = (_) => w.server.edgeScript.add(lost);
      await w.approveAndCheck();
      w.server.onPush = null;
      return w;
    }

    int reports(_W w) =>
        w.server.edgeBodies.where((b) => b['recording_refused'] == true).length;

    Future<_W> refused(String kind) async {
      final w = await _w();
      w.server.nextLegRefusal = kind;
      await w.approveAndCheck();
      return w;
    }

    for (final (kind, note) in <(String, ProviderCardNote)>[
      ('revoked_employee', ProviderCardNote.signInAgain),
      ('permission_denied', ProviderCardNote.roleCannot),
    ]) {
      test(
        '$kind: the server refuses the report from that same session, so '
        'it stays owed (reconciliation, no Resume); another person signs '
        'in, Check status delivers it, then a manager Resume records',
        () async {
          final w = await refused(kind);
          expect(w.a.refusalReportPending, kind);
          expect(w.a.phase, ProviderCardPhase.reconciliation);
          expect(w.state.notes[w.id], note);
          expect(w.server.edgeBodies.last['recording_refused'], true);
          expect(w.server.edgeBodies.last['pin_session_id'], kCardPin);
          w.server.role = 'manager';
          final pushes = w.server.pushCalls.length;
          await w.ctrl.resumeRecording(w.id);
          expect(
            w.server.pushCalls,
            hasLength(pushes),
            reason: 'no Resume yet',
          );

          w.c.read(cardSessionProvider.notifier).state = const SyncSession(
            pinSessionId: kCardPin2,
            deviceId: kCardDevice,
          );
          expect(w.state.hydrated, isFalse);
          await w.ctrl.ensureHydrated();
          expect(w.a.refusalReportPending, kind, reason: 'the journal kept it');
          await w.ctrl.checkStatus(w.id);
          final delivered = w.server.edgeBodies.last;
          expect(delivered['recording_refused'], true);
          expect(delivered['refusal_code'], kind);
          expect(delivered['source'], 'operator');
          expect(delivered['pin_session_id'], kCardPin2);
          expect(w.a.refusalReportPending, isNull);
          expect(w.a.server!.recoverable, isTrue);
          expect(w.a.phase, ProviderCardPhase.recordingRefused);

          final commits = w.server.providerCommits;
          await w.ctrl.resumeRecording(w.id);
          expect(w.a.phase, ProviderCardPhase.recorded);
          expect(w.server.pushedOps.last['recording_resume'], 0);
          expect(w.server.paymentsCreated, 1);
          expect(w.server.providerCommits, commits, reason: 'no provider call');
        },
      );
    }

    test('a report lost in transit stays owed; the next Check status '
        'delivers it with the stored hint', () async {
      final w = await reportLost('precondition_failed');
      expect(w.a.refusalReportPending, 'precondition_failed');
      expect(w.a.phase, ProviderCardPhase.reconciliation);
      expect(w.state.notes[w.id], ProviderCardNote.unavailable);
      expect(reports(w), 1);
      await w.ctrl.checkStatus(w.id);
      expect(reports(w), 2);
      expect(w.server.edgeBodies.last['refusal_code'], 'precondition_failed');
      expect(w.a.refusalReportPending, isNull);
      expect(w.a.phase, ProviderCardPhase.recordingRefused);
    });

    test('a restart keeps the owed report; Check status after it delivers '
        'it', () async {
      final w = await reportLost('precondition_failed');
      final restarted = await _w(server: w.server, prefs: w.prefs);
      expect(restarted.a.refusalReportPending, 'precondition_failed');
      await restarted.ctrl.checkStatus(restarted.id);
      expect(restarted.a.refusalReportPending, isNull);
      expect(restarted.a.phase, ProviderCardPhase.recordingRefused);
    });

    test('a non-recoverable refusal delivered later stays in reconciliation '
        'and never offers a Resume', () async {
      final w = await reportLost('revoked_device');
      await w.ctrl.checkStatus(w.id);
      expect(w.a.refusalReportPending, isNull);
      expect(w.a.server!.classification, 'orphan_approved');
      expect(w.a.phase, ProviderCardPhase.reconciliation);
      w.server.role = 'manager';
      final pushes = w.server.pushCalls.length;
      await w.ctrl.resumeRecording(w.id);
      expect(w.server.pushCalls, hasLength(pushes));
    });

    test('an owed report goes once: a second Check status joins the one in '
        'flight', () async {
      final w = await reportLost('precondition_failed');
      final hold = Completer<void>();
      w.server.holdEdge = hold;
      final first = w.ctrl.checkStatus(w.id);
      final second = w.ctrl.checkStatus(w.id);
      await pumpEventQueue();
      hold.complete();
      await Future.wait([first, second]);
      expect(reports(w), 2, reason: 'the lost one, then one delivery');
    });
  });

  group('the leg is proven on the stored record (packet §8.2)', () {
    test('a leg whose write returns into another PIN session is not sent; it '
        'reads "may have been sent" there', () async {
      final prefs = await freshCardPrefs();
      final store = HookedCardStore(
        SharedPrefsProviderCardStore(prefs: () async => prefs),
      );
      final w = await _w(prefs: prefs, store: store);
      await w.start();
      final id = w.id;
      w.server.approve(id);
      final hold = Completer<void>();
      store.holdLegWrite = hold;
      final run = w.ctrl.checkStatus(id);
      await pumpEventQueue();
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      expect(w.state.hydrated, isFalse);
      hold.complete();
      await run;
      await w.ctrl.ensureHydrated();
      expect(w.server.pushCalls, isEmpty, reason: 'nothing under the new one');
      expect(w.a.recording, isNotNull);
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
    });

    test('a leg on the wire across a PIN switch: the new session shows it '
        'being recorded, then what it stored, and arms no receipt', () async {
      final w = await _w();
      await w.start();
      final id = w.id;
      w.server.approve(id);
      final hold = Completer<void>();
      w.server.onPush = (_) => hold.future;
      final run = w.ctrl.checkStatus(id);
      await pumpEventQueue();
      expect(w.server.pushCalls, hasLength(1), reason: 'the leg is on its way');
      w.c.read(cardSessionProvider.notifier).state = const SyncSession(
        pinSessionId: kCardPin2,
        deviceId: kCardDevice,
      );
      expect(w.state.hydrated, isFalse);
      await w.ctrl.ensureHydrated();
      expect(w.state.busy[id], ProviderCardBusy.recording);
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
      hold.complete();
      await run;
      await pumpEventQueue();
      expect(w.state.busy[id], isNull);
      expect(w.a.phase, ProviderCardPhase.recorded);
      expect(
        w.state.receiptArmed,
        isEmpty,
        reason: 'armed only in the session that received the reply',
      );
      expect(w.server.pushCalls, hasLength(1));
    });

    test('a status refused for this session\'s role is no context proof: an '
        'explicit resend sends nothing', () async {
      final w = await _w();
      w.server.legFaults.add('lost');
      await w.approveAndCheck();
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
      final pushes = w.server.pushCalls.length;
      w.server.deniedPins.add(kCardPin);
      await w.ctrl.resendRecording(w.id);
      expect(w.server.pushCalls, hasLength(pushes));
      expect(w.state.notes[w.id], ProviderCardNote.roleCannot);
      expect(w.a.phase, ProviderCardPhase.recordingUnconfirmed);
    });

    test('an approval whose write failed sends no leg; the next status that '
        'stores it does', () async {
      final prefs = await freshCardPrefs();
      final store = HookedCardStore(
        SharedPrefsProviderCardStore(prefs: () async => prefs),
      );
      final w = await _w(prefs: prefs, store: store);
      await w.start();
      w.server.approve(w.id);
      store.failUpdates = 1;
      await w.ctrl.checkStatus(w.id);
      expect(w.server.pushCalls, isEmpty);
      expect(w.a.recording, isNull);
      await w.ctrl.checkStatus(w.id);
      expect(w.server.pushCalls, hasLength(1));
      expect(w.a.phase, ProviderCardPhase.recorded);
    });
  });

  group('TEST never records (packet §8.3)', () {
    test('test_attempt_not_recordable is a safety stop: never retried, never '
        'reported', () async {
      final w = await _w();
      await w.start();
      // The ledger holds a TEST attempt under this identity, while a status
      // answer claims a LIVE approval: the POS sends its leg once and stops.
      final live = w.server.attempts[w.id]!;
      w.server.attempts[w.id] = FakeCardAttempt(
        id: live.id,
        mode: 'test',
        amountMinor: 1200,
        currencyCode: 'ILS',
        orderId: null,
        expectedRevision: null,
      )..state = 'approved';
      w.server.edgeScript.add((
        200,
        <String, Object?>{
          'ok': true,
          'attempt_id': w.id,
          'state': 'approved',
          'classification': 'approved_unrecorded',
          'recorded': false,
          'amount_minor': 1200,
          'currency_code': 'ILS',
          'server_ts': '2026-10-30T12:00:00Z',
        },
      ));
      await w.ctrl.checkStatus(w.id);
      expect(w.a.safetyStop, ProviderCardSafetyStop.testAttemptNotRecordable);
      expect(w.a.phase, ProviderCardPhase.reconciliation);
      final edge = w.server.edgeBodies.length;
      await w.ctrl.resendRecording(w.id);
      expect(w.server.pushCalls, hasLength(1));
      expect(w.server.edgeBodies, hasLength(edge), reason: 'no report');
    });
  });

  group('the leg answers, read exactly (packet §8.3)', () {
    final attempt =
        ProviderCardAttempt.create(
          attemptId: cardV4(1),
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          deviceId: kCardDevice,
          orderId: kCardOrder,
          orderNumber: '#A1',
          mode: ProviderCardMode.live,
          amountMinor: 1200,
          currencyCode: 'ILS',
          expectedRevision: 7,
          employeeProfileId: null,
          now: kCardNow,
        ).copyWith(
          startMayHaveExecuted: true,
          startLastSentAt: kCardNow.toUtc().toIso8601String(),
          recording: ProviderCardRecordingOperation(
            localOperationId: cardV4(1),
            targetId: cardV4(2),
            clientCreatedAt: kCardNow.toUtc().toIso8601String(),
            orderId: kCardOrder,
            amountTenderedMinor: 1200,
          ),
          updatedAt: kCardNow.toUtc().toIso8601String(),
        );

    Map<String, Object?> reply(Map<String, Object?> row) => <String, Object?>{
      'ok': true,
      'server_ts': '2026-10-30T12:00:00Z',
      'results': <Object?>[
        <String, Object?>{
          'local_operation_id': cardV4(1),
          'operation_type': 'payment.create',
          ...row,
        },
      ],
    };

    ProviderCardRecordingResult read(
      Map<String, Object?> row, {
      bool resumed = false,
    }) => classifyProviderRecordingReply(reply(row), attempt, resumed: resumed);

    const guard = <String, Object?>{
      'ok': false,
      'status': 'rejected',
      'idempotency_replay': false,
      'server_ts': '2026-10-30T12:00:01Z',
      'order_id': kCardOrder,
    };

    test('each provider tuple maps to its hint', () {
      expect(
        (read({
                  ...guard,
                  'error': 'provider_recording_refused',
                  'detail': 'payment_exists',
                })
                as ProviderCardRecordingRefused)
            .hint,
        'provider_recording_refused',
      );
      expect(
        (read({...guard, 'error': 'amount_mismatch'})
                as ProviderCardRecordingRefused)
            .hint,
        'amount_mismatch',
      );
      expect(
        (read({...guard, 'error': 'card_context_lost'})
                as ProviderCardRecordingRefused)
            .hint,
        'card_context_lost',
      );
      expect(
        read({...guard, 'error': 'test_attempt_not_recordable'}),
        isA<ProviderCardRecordingSafetyStop>(),
      );
      expect(
        (read({
                  'ok': false,
                  'error': 'rejected',
                  'detail': 'revoked_device',
                  'status': 'rejected',
                  'idempotency_replay': false,
                })
                as ProviderCardRecordingRefused)
            .hint,
        'revoked_device',
      );
      expect(
        read({
          'ok': false,
          'error': 'invalid_payload',
          'detail': 'recording_resume',
          'status': 'rejected',
          'idempotency_replay': false,
        }),
        isA<ProviderCardRecordingSafetyStop>(),
      );
    });

    test('the base tuples go through the unchanged base classifier', () {
      expect(
        (read({
                  'ok': false,
                  'error': 'rejected',
                  'sqlstate': 'P0001',
                  'detail': 'precondition_failed',
                  'status': 'rejected',
                  'idempotency_replay': false,
                })
                as ProviderCardRecordingRefused)
            .hint,
        'precondition_failed',
      );
      expect(
        (read({
                  'ok': false,
                  'error': 'rejected',
                  'sqlstate': 'P0001',
                  'detail': null,
                  'status': 'rejected',
                  'idempotency_replay': false,
                })
                as ProviderCardRecordingRefused)
            .hint,
        'nonrecoverable_refusal',
      );
      expect(
        read({
          'ok': false,
          'error': 'conflict',
          'detail':
              'idempotency key already used for a different operation/payload',
          'status': 'conflict',
          'idempotency_replay': false,
        }),
        isA<ProviderCardRecordingCollision>(),
      );
      expect(
        (read({
                  'ok': false,
                  'error': 'conflict',
                  'sqlstate': '40001',
                  'status': 'conflict',
                  'idempotency_replay': false,
                })
                as ProviderCardRecordingRefused)
            .hint,
        'conflict',
      );
      // An applied tuple with the WRONG method is never a card payment.
      final applied = <String, Object?>{
        'ok': true,
        'payment_id': 'p-1',
        'order_id': kCardOrder,
        'method': 'cash',
        'receipt_number': 'R-1',
        'change_due_minor': 0,
        'shift_id': 's',
        'cash_drawer_session_id': 'd',
        'payment_revision': 1,
        'order_revision': 7,
        'auto_completed': false,
        'order_status': 'served',
        'server_ts': '2026-10-30T12:00:00Z',
        'status': 'applied',
        'idempotency_replay': false,
      };
      expect(read(applied), isA<ProviderCardRecordingUnconfirmed>());
      expect(
        read({...applied, 'method': 'card'}),
        isA<ProviderCardRecordingApplied>(),
      );
    });

    test('pending answers and resume_denied, exactly', () {
      const pending = <String, Object?>{
        'ok': false,
        'retryable': true,
        'status': 'pending',
        'idempotency_replay': false,
      };
      expect(
        read({...pending, 'error': 'resume_authority_required'}),
        isA<ProviderCardRecordingResumeAuthorityRequired>(),
      );
      for (final code in <String>[
        'transient_failure',
        'dependency_not_ready',
        'single_operation_required',
      ]) {
        expect(
          (read({...pending, 'error': code}) as ProviderCardRecordingPending)
              .code,
          code,
        );
      }
      expect(
        read({...pending, 'error': 'mystery'}),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
      final denied = <String, Object?>{
        'ok': false,
        'error': 'rejected',
        'sqlstate': 'P0001',
        'detail': 'precondition_failed',
        'status': 'rejected',
        'idempotency_replay': true,
        'resume_denied': 'resume_stale',
      };
      expect(
        (read(denied, resumed: true) as ProviderCardRecordingResumeDenied)
            .token,
        'resume_stale',
      );
      expect(
        read(denied),
        isA<ProviderCardRecordingUnconfirmed>(),
        reason: 'no Resume was sent',
      );
      expect(
        read({...denied, 'resume_denied': 'made_up'}, resumed: true),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
    });

    test('malformed envelopes are unconfirmed, never a refusal', () {
      expect(
        classifyProviderRecordingReply(null, attempt, resumed: false),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
      expect(
        classifyProviderRecordingReply(
          {'ok': true, 'results': <Object?>[]},
          attempt,
          resumed: false,
        ),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
      expect(
        classifyProviderRecordingReply(
          {
            ...reply({...guard, 'error': 'amount_mismatch'}),
            'server_ts': null,
          },
          attempt,
          resumed: false,
        ),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
      expect(
        read({...guard, 'error': 'amount_mismatch', 'order_id': kCardOrder2}),
        isA<ProviderCardRecordingUnconfirmed>(),
      );
    });

    test('transport failures are mapped explicitly', () {
      expect(
        mapProviderRecordingTransportFailure(
          const SyncTransportException(SyncTransportErrorKind.auth),
        ),
        isA<ProviderCardRecordingAuthRequired>(),
      );
      expect(
        mapProviderRecordingTransportFailure(
          const SyncTransportException(
            SyncTransportErrorKind.transient,
            code: 'device_session_unverified',
          ),
        ),
        isA<ProviderCardRecordingNotSent>(),
      );
      expect(
        mapProviderRecordingTransportFailure(
          const SyncTransportException(
            SyncTransportErrorKind.server,
            code: '42501',
          ),
        ),
        isA<ProviderCardRecordingNotApplied>(),
      );
      for (final code in <String?>['409', '422', '504', null]) {
        expect(
          mapProviderRecordingTransportFailure(
            SyncTransportException(SyncTransportErrorKind.server, code: code),
          ),
          isA<ProviderCardRecordingUnconfirmed>(),
          reason: '$code',
        );
      }
    });
  });
}
