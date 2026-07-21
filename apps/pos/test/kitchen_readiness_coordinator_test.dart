import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/spool/kitchen_readiness_coordinator.dart';
import 'package:restoflow_pos/src/spool/kitchen_readiness_evidence.dart';
import 'package:restoflow_pos/src/spool/kitchen_spool_readiness_probe.dart';

/// KITCHEN-MODE-001C3A — the readiness-only foreground heartbeat: immediate
/// lifecycle reporting, 5-minute cadence, single-flight, pause/dispose
/// cancellation, and bounded stale-revision recovery. Deterministic manual
/// ticker — no arbitrary sleeps.
class _ManualTimer implements Timer {
  _ManualTimer(this.onTick);

  final void Function() onTick;
  bool cancelled = false;
  int ticks = 0;

  void fire() {
    if (cancelled) return;
    ticks++;
    onTick();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => ticks;
}

const _context = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
);

const _readyEvidence = ReadyKitchenPrinterEvidence(
  printerAssignmentId: 'assign-1',
  transportKind: KitchenReadinessTransportKind.network,
  paperWidth: KitchenReadinessPaperWidth.mm80,
  printerFingerprint:
      'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
);

/// F1: a truthful 58mm diagnostic — Ready (not Blocked), so readiness is still
/// sent, but with a NULL assignment id and a non-qualifying width.
const _diag58Evidence = ReadyKitchenPrinterEvidence(
  printerAssignmentId: null,
  transportKind: KitchenReadinessTransportKind.network,
  paperWidth: KitchenReadinessPaperWidth.mm58,
  printerFingerprint:
      'ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000',
);

const _spoolResult = KitchenSpoolReadinessProbeResult(
  secureSpoolAvailable: true,
  unresolvedLocalJobs: 2,
  spoolCountState: KitchenSpoolCountState.counted,
);

void main() {
  late List<KitchenReadinessReport> sent;
  late List<KitchenPosStatusReport> statusSent;
  late List<Object? Function()> sendScript;
  late List<Object? Function()> statusScript;
  late List<KitchenModeResult Function()> modeScript;
  late int invalidations;
  late List<_ManualTimer> timers;
  late List<Duration> timerIntervals;
  DeviceContext? context;
  KitchenReadinessPrinterEvidence evidence = _readyEvidence;
  Future<KitchenReadinessResult> Function(KitchenReadinessReport)? sendOverride;

  setUp(() {
    sent = [];
    statusSent = [];
    sendScript = [];
    statusScript = [];
    modeScript = [];
    invalidations = 0;
    timers = [];
    timerIntervals = [];
    context = _context;
    evidence = _readyEvidence;
    sendOverride = null;
  });

  KitchenReadinessHeartbeat heartbeat({
    Duration callTimeout = const Duration(seconds: 5),
  }) => KitchenReadinessHeartbeat(
    deviceContext: () => context,
    fetchMode: () async {
      if (modeScript.isEmpty) {
        return KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 3,
        );
      }
      return modeScript.removeAt(0)();
    },
    printerEvidence: () async => evidence,
    probeSpool: ({required deviceId, required branchId}) async {
      expect(deviceId, 'dev-1');
      expect(branchId, 'branch-1');
      return _spoolResult;
    },
    sendStatus: (status) async {
      statusSent.add(status);
      if (statusScript.isEmpty) return const KitchenPosStatusAccepted();
      final next = statusScript.removeAt(0)();
      if (next is KitchenPosStatusResult) return next;
      throw next as Object;
    },
    sendReport: (report) async {
      sent.add(report);
      if (sendOverride != null) return sendOverride!(report);
      if (sendScript.isEmpty) {
        return const KitchenReadinessAccepted(activationReady: true);
      }
      final next = sendScript.removeAt(0)();
      if (next is KitchenReadinessResult) return next;
      throw next as Object;
    },
    invalidateModeCache: () async => invalidations++,
    appBuild: 'pos-test',
    callTimeout: callTimeout,
    periodicTimerFactory: (duration, tick) {
      timerIntervals.add(duration);
      final timer = _ManualTimer(tick);
      timers.add(timer);
      return timer;
    },
  );

  test('startup: arms the 5-minute foreground timer and reports IMMEDIATELY '
      'with the full typed evidence', () async {
    final hb = heartbeat();
    hb.onStartup();
    final report = await hb.reportNow(trigger: 'join');
    expect(sent, hasLength(1));
    expect(timerIntervals, [kKitchenReadinessHeartbeatInterval]);
    expect(report.outcome, KitchenReadinessRunOutcome.reported);
    expect(report.activationReady, isTrue);
    expect(report.statusReported, isTrue);
    final wire = sent.single;
    expect(wire.modeRevision, 3);
    expect(wire.appBuild, 'pos-test');
    expect(wire.secureSpoolAvailable, isTrue);
    expect(wire.unresolvedLocalJobs, 2);
    expect(wire.printerFingerprint, _readyEvidence.printerFingerprint);
    // 001C3B1A: the readiness report carries the STABLE assignment id, and the
    // config-independent status was filed FIRST from the SAME snapshot.
    expect(wire.printerAssignmentId, 'assign-1');
    expect(statusSent, hasLength(1));
    expect(statusSent.single.modeRevision, 3);
    expect(statusSent.single.unresolvedLocalJobs, 2);
    // 001C3B1A2: the status carries the probe's count-certainty verbatim.
    expect(statusSent.single.spoolCountState, KitchenSpoolCountState.counted);
    hb.dispose();
  });

  group('001C3B1A coherent status+readiness pipeline', () {
    test(
      'no printer evidence: status is RETAINED, readiness is SKIPPED',
      () async {
        evidence = const BlockedKitchenPrinterEvidence(
          'kitchen_printer_assignment_missing',
        );
        final hb = heartbeat();
        final report = await hb.reportNow(trigger: 't');
        expect(
          report.outcome,
          KitchenReadinessRunOutcome.skippedEvidenceBlocked,
        );
        expect(report.detail, 'kitchen_printer_assignment_missing');
        expect(report.statusReported, isTrue, reason: 'status stands alone');
        expect(statusSent, hasLength(1));
        expect(sent, isEmpty, reason: 'readiness needs a printer');
        hb.dispose();
      },
    );

    test('F1: a 58mm-only printer still files STATUS first and a DIAGNOSTIC '
        'readiness (paper_width=58mm, assignment id=null, not '
        'activation-ready) — no worker/drain/transport reached', () async {
      evidence = _diag58Evidence;
      // The server records the diagnostic report and returns not-ready.
      sendScript.add(
        () => const KitchenReadinessAccepted(activationReady: false),
      );
      final hb = heartbeat();
      final report = await hb.reportNow(trigger: 't');
      expect(report.statusReported, isTrue);
      expect(report.outcome, KitchenReadinessRunOutcome.reported);
      expect(report.activationReady, isFalse, reason: '58mm never activates');
      // Status is filed BEFORE the readiness, from the same snapshot.
      expect(statusSent, hasLength(1));
      // The readiness IS sent (diagnostic), carrying the honest 58mm width and
      // a NULL assignment id.
      expect(sent, hasLength(1));
      expect(sent.single.paperWidth, KitchenReadinessPaperWidth.mm58);
      expect(sent.single.printerAssignmentId, isNull);
      expect(
        sent.single.printerFingerprint,
        _diag58Evidence.printerFingerprint,
      );
      hb.dispose();
    });

    test('status is sent BEFORE readiness (deterministic order)', () async {
      final order = <String>[];
      final hb = KitchenReadinessHeartbeat(
        deviceContext: () => context,
        fetchMode: () async => KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 3,
        ),
        printerEvidence: () async => _readyEvidence,
        probeSpool: ({required deviceId, required branchId}) async =>
            _spoolResult,
        sendStatus: (status) async {
          order.add('status');
          return const KitchenPosStatusAccepted();
        },
        sendReport: (report) async {
          order.add('readiness');
          return const KitchenReadinessAccepted(activationReady: true);
        },
        invalidateModeCache: () async {},
        periodicTimerFactory: (d, t) => _ManualTimer(t),
      );
      await hb.reportNow(trigger: 't');
      expect(order, ['status', 'readiness']);
      hb.dispose();
    });

    test('001C3B1A2: the status count-state comes from the probe snapshot '
        '(a proven-empty absent spool is filed verbatim, never faked to '
        'counted)', () async {
      final hb = KitchenReadinessHeartbeat(
        deviceContext: () => context,
        fetchMode: () async => KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 3,
        ),
        printerEvidence: () async => const BlockedKitchenPrinterEvidence(
          'kitchen_printer_assignment_missing',
        ),
        probeSpool: ({required deviceId, required branchId}) async =>
            const KitchenSpoolReadinessProbeResult(
              secureSpoolAvailable: false,
              unresolvedLocalJobs: 0,
              spoolCountState: KitchenSpoolCountState.absent,
            ),
        sendStatus: (status) async {
          statusSent.add(status);
          return const KitchenPosStatusAccepted();
        },
        sendReport: (report) async =>
            const KitchenReadinessAccepted(activationReady: true),
        invalidateModeCache: () async {},
        periodicTimerFactory: (d, t) => _ManualTimer(t),
      );
      await hb.reportNow(trigger: 't');
      expect(statusSent, hasLength(1));
      expect(statusSent.single.spoolCountState, KitchenSpoolCountState.absent);
      expect(statusSent.single.unresolvedLocalJobs, 0);
      hb.dispose();
    });

    test('001C3B1A2 (F1-E): an UNKNOWN-presence probe (e.g. a documents-'
        'directory failure) sends p_spool_count_state=unknown, NEVER absent, '
        'and its 0 is not interpreted as proven-empty; status stays first with '
        'no readiness/worker/drain/transport side effect', () async {
      final hb = KitchenReadinessHeartbeat(
        deviceContext: () => context,
        fetchMode: () async => KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 3,
        ),
        printerEvidence: () async => const BlockedKitchenPrinterEvidence(
          'kitchen_printer_assignment_missing',
        ),
        probeSpool: ({required deviceId, required branchId}) async =>
            const KitchenSpoolReadinessProbeResult(
              secureSpoolAvailable: false,
              unresolvedLocalJobs: 0,
              spoolCountState: KitchenSpoolCountState.unknown,
              blockerCode: 'spool_presence_unknown',
            ),
        sendStatus: (status) async {
          statusSent.add(status);
          return const KitchenPosStatusAccepted();
        },
        sendReport: (report) async {
          sent.add(report);
          return const KitchenReadinessAccepted(activationReady: true);
        },
        invalidateModeCache: () async {},
        periodicTimerFactory: (d, t) => _ManualTimer(t),
      );
      final report = await hb.reportNow(trigger: 't');
      expect(statusSent, hasLength(1));
      expect(
        statusSent.single.spoolCountState,
        KitchenSpoolCountState.unknown,
        reason: 'a provider failure is filed as unknown, never absent',
      );
      expect(
        statusSent.single.spoolCountState,
        isNot(KitchenSpoolCountState.absent),
      );
      expect(statusSent.single.unresolvedLocalJobs, 0);
      // Status is first; readiness is skipped (no printer) — no readiness send,
      // and the heartbeat structurally has no worker/drain/transport to reach.
      expect(report.statusReported, isTrue);
      expect(report.outcome, KitchenReadinessRunOutcome.skippedEvidenceBlocked);
      expect(sent, isEmpty);
      hb.dispose();
    });

    test('a STALE status revision recovers the WHOLE pipeline once (status + '
        'readiness re-sent with the fresh revision)', () async {
      modeScript
        ..add(
          () => KitchenModeVerifiedKds(
            verifiedAt: DateTime.utc(2026, 7, 21),
            revision: 3,
          ),
        )
        ..add(
          () => KitchenModeVerifiedKds(
            verifiedAt: DateTime.utc(2026, 7, 21),
            revision: 7,
          ),
        );
      statusScript.add(
        () => const KitchenPosStatusStaleModeRevision(serverRevision: 7),
      );
      final hb = heartbeat();
      final report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.staleRecovered);
      expect(invalidations, 1);
      expect(statusSent, hasLength(2), reason: 'status re-sent on retry');
      expect(statusSent.last.modeRevision, 7);
      expect(sent, hasLength(1), reason: 'readiness only on the fresh pass');
      expect(sent.single.modeRevision, 7);
      hb.dispose();
    });

    test('REPEATED stale status does NOT loop (one retry, typed '
        'unrecovered, no readiness)', () async {
      statusScript
        ..add(() => const KitchenPosStatusStaleModeRevision(serverRevision: 7))
        ..add(() => const KitchenPosStatusStaleModeRevision(serverRevision: 8));
      final hb = heartbeat();
      final report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.staleUnrecovered);
      expect(statusSent, hasLength(2));
      expect(
        sent,
        isEmpty,
        reason: 'readiness never reached under stale status',
      );
      hb.dispose();
    });

    test(
      'a status leg failure short-circuits the run WITHOUT readiness',
      () async {
        statusScript.add(() => const KitchenPosStatusInvalidSession());
        final hb = heartbeat();
        final report = await hb.reportNow(trigger: 't');
        expect(report.outcome, KitchenReadinessRunOutcome.invalidSession);
        expect(sent, isEmpty);
        hb.dispose();
      },
    );
  });

  test(
    'no report happens WITHOUT a trigger; each manual tick files one',
    () async {
      final hb = heartbeat();
      hb.onStartup();
      await hb.reportNow(trigger: 'drain-startup');
      expect(sent, hasLength(1));
      timers.single.fire();
      await hb.reportNow(trigger: 'drain-tick');
      expect(sent, hasLength(2));
      hb.dispose();
    },
  );

  test('SINGLE-FLIGHT: concurrent callers join the ONE in-flight run '
      '(exactly one transport call)', () async {
    final gate = Completer<void>();
    sendOverride = (report) async {
      await gate.future;
      return const KitchenReadinessAccepted(activationReady: false);
    };
    final hb = heartbeat();
    final first = hb.reportNow(trigger: 'a');
    final second = hb.reportNow(trigger: 'b');
    final third = hb.reportNow(trigger: 'c');
    gate.complete();
    final results = await Future.wait([first, second, third]);
    expect(sent, hasLength(1), reason: 'joiners must not send again');
    expect(results.map((r) => r.trigger).toSet(), {'a'});
    hb.dispose();
  });

  test('paused: the periodic timer is cancelled; resume re-arms and reports '
      'immediately', () async {
    final hb = heartbeat();
    hb.onStartup();
    await hb.reportNow(trigger: 'drain');
    expect(sent, hasLength(1));
    hb.onPaused();
    expect(timers.single.cancelled, isTrue);
    timers.single.fire();
    await hb.reportNow(trigger: 'drain2');
    expect(sent, hasLength(2), reason: 'cancelled timers never tick');
    hb.onResume();
    await hb.reportNow(trigger: 'drain3');
    expect(sent.length, 3, reason: 'resume filed immediately');
    expect(timers, hasLength(2), reason: 'resume re-armed a fresh timer');
    hb.dispose();
    expect(timers.last.cancelled, isTrue);
  });

  test('disposal mid-run: the run ends typed-disposed WITHOUT reaching the '
      'transport; later triggers are inert', () async {
    final gate = Completer<KitchenModeResult>();
    modeScript.add(() => throw StateError('unused'));
    final hb = KitchenReadinessHeartbeat(
      deviceContext: () => context,
      fetchMode: () => gate.future,
      printerEvidence: () async => evidence,
      probeSpool: ({required deviceId, required branchId}) async =>
          _spoolResult,
      sendStatus: (status) async {
        statusSent.add(status);
        return const KitchenPosStatusAccepted();
      },
      sendReport: (report) async {
        sent.add(report);
        return const KitchenReadinessAccepted(activationReady: true);
      },
      invalidateModeCache: () async => invalidations++,
      periodicTimerFactory: (duration, tick) {
        final timer = _ManualTimer(tick);
        timers.add(timer);
        return timer;
      },
    );
    final run = hb.reportNow(trigger: 'startup');
    hb.dispose();
    gate.complete(
      KitchenModePrinterOnlyWithRevision(
        revision: 4,
        verifiedAt: DateTime.utc(2026, 7, 21),
      ),
    );
    final report = await run;
    expect(report.outcome, KitchenReadinessRunOutcome.disposed);
    expect(sent, isEmpty, reason: 'a disposed run must never report');
    final after = await hb.reportNow(trigger: 'late');
    expect(after.outcome, KitchenReadinessRunOutcome.disposed);
    expect(sent, isEmpty);
  });

  test(
    'typed skips: no scope / printer_only without revision / kds without '
    'revision (old server) / mode fetch failure — ZERO transport calls',
    () async {
      final hb = heartbeat();
      context = null;
      var report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.skippedNoScope);
      context = _context;
      modeScript.add(() => const KitchenModeRevisionUnavailable());
      report = await hb.reportNow(trigger: 't');
      expect(
        report.outcome,
        KitchenReadinessRunOutcome.skippedRevisionUnavailable,
      );
      modeScript.add(
        () => KitchenModeVerifiedKds(verifiedAt: DateTime.utc(2026, 7, 21)),
      );
      report = await hb.reportNow(trigger: 't');
      expect(
        report.outcome,
        KitchenReadinessRunOutcome.skippedIneligibleOldServer,
      );
      modeScript.add(() => const KitchenModeTransientFailure());
      report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.skippedModeUnavailable);
      modeScript.add(() => const KitchenModeInvalidSession());
      report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.invalidSession);
      expect(sent, isEmpty);
      hb.dispose();
    },
  );

  test('a TRUSTED printer_only revision reports with that revision', () async {
    modeScript.add(
      () => KitchenModePrinterOnlyWithRevision(
        revision: 9,
        verifiedAt: DateTime.utc(2026, 7, 21),
      ),
    );
    final hb = heartbeat();
    final report = await hb.reportNow(trigger: 't');
    expect(report.outcome, KitchenReadinessRunOutcome.reported);
    expect(sent.single.modeRevision, 9);
    hb.dispose();
  });

  test(
    'blocked evidence: typed skip carrying the safe reason, zero sends',
    () async {
      evidence = const BlockedKitchenPrinterEvidence(
        'kitchen_printer_assignment_missing',
      );
      final hb = heartbeat();
      final report = await hb.reportNow(trigger: 't');
      expect(report.outcome, KitchenReadinessRunOutcome.skippedEvidenceBlocked);
      expect(report.detail, 'kitchen_printer_assignment_missing');
      expect(sent, isEmpty);
      hb.dispose();
    },
  );

  test('STALE-REVISION RECOVERY: invalidate cache -> refetch -> rebuild -> '
      'retry ONCE -> accepted', () async {
    modeScript
      ..add(
        () => KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 3,
        ),
      )
      ..add(
        () => KitchenModeVerifiedKds(
          verifiedAt: DateTime.utc(2026, 7, 21),
          revision: 7,
        ),
      );
    sendScript.add(
      () => const KitchenReadinessStaleModeRevision(serverRevision: 7),
    );
    final hb = heartbeat();
    final report = await hb.reportNow(trigger: 't');
    expect(report.outcome, KitchenReadinessRunOutcome.staleRecovered);
    expect(invalidations, 1);
    expect(sent, hasLength(2));
    expect(sent.first.modeRevision, 3);
    expect(sent.last.modeRevision, 7, reason: 'rebuilt with the fresh mode');
    hb.dispose();
  });

  test('REPEATED stale revision does NOT loop: at most one retry per '
      'trigger, typed unrecovered', () async {
    sendScript
      ..add(() => const KitchenReadinessStaleModeRevision(serverRevision: 7))
      ..add(() => const KitchenReadinessStaleModeRevision(serverRevision: 8));
    final hb = heartbeat();
    final report = await hb.reportNow(trigger: 't');
    expect(report.outcome, KitchenReadinessRunOutcome.staleUnrecovered);
    expect(sent, hasLength(2), reason: 'exactly one recovery attempt');
    expect(invalidations, 1);
    hb.dispose();
  });

  test('failure taxonomy: rejection reason / invalid session / hung call '
      'bounded by the timeout / thrown evidence never escapes', () async {
    sendScript.add(
      () => const KitchenReadinessRejected(
        KitchenReadinessRejectionReason.invalidFingerprint,
      ),
    );
    final hb = heartbeat(callTimeout: const Duration(milliseconds: 80));
    var report = await hb.reportNow(trigger: 't');
    expect(report.outcome, KitchenReadinessRunOutcome.rejected);
    expect(report.detail, 'invalid_fingerprint');

    sendScript.add(() => const KitchenReadinessInvalidSession());
    report = await hb.reportNow(trigger: 't');
    expect(report.outcome, KitchenReadinessRunOutcome.invalidSession);

    sendOverride = (_) => Completer<KitchenReadinessResult>().future;
    report = await hb.reportNow(trigger: 't');
    expect(
      report.outcome,
      KitchenReadinessRunOutcome.transientFailure,
      reason: 'a hung report call must be bounded by the outer timeout',
    );
    sendOverride = null;

    evidence = _readyEvidence;
    final throwing = KitchenReadinessHeartbeat(
      deviceContext: () => context,
      fetchMode: () async => KitchenModeVerifiedKds(
        verifiedAt: DateTime.utc(2026, 7, 21),
        revision: 3,
      ),
      printerEvidence: () => throw StateError('boom'),
      probeSpool: ({required deviceId, required branchId}) async =>
          _spoolResult,
      sendStatus: (status) async => const KitchenPosStatusAccepted(),
      sendReport: (report) async =>
          const KitchenReadinessAccepted(activationReady: true),
      invalidateModeCache: () async {},
      periodicTimerFactory: (duration, tick) {
        final timer = _ManualTimer(tick);
        timers.add(timer);
        return timer;
      },
    );
    throwing.requestImmediate('fire-and-forget');
    final typed = await throwing.reportNow(trigger: 't');
    expect(typed.outcome, KitchenReadinessRunOutcome.malformed);
    expect(typed.detail, 'unexpected_failure');
    throwing.dispose();
    hb.dispose();
  });
}
