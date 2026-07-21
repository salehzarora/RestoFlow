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
  transportKind: KitchenReadinessTransportKind.network,
  paperWidth: KitchenReadinessPaperWidth.mm80,
  printerFingerprint:
      'aaaabbbbccccddddeeeeffff00001111aaaabbbbccccddddeeeeffff00001111',
);

const _spoolResult = KitchenSpoolReadinessProbeResult(
  secureSpoolAvailable: true,
  unresolvedLocalJobs: 2,
);

void main() {
  late List<KitchenReadinessReport> sent;
  late List<Object? Function()> sendScript;
  late List<KitchenModeResult Function()> modeScript;
  late int invalidations;
  late List<_ManualTimer> timers;
  late List<Duration> timerIntervals;
  DeviceContext? context;
  KitchenReadinessPrinterEvidence evidence = _readyEvidence;
  Future<KitchenReadinessResult> Function(KitchenReadinessReport)? sendOverride;

  setUp(() {
    sent = [];
    sendScript = [];
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
    final wire = sent.single;
    expect(wire.modeRevision, 3);
    expect(wire.appBuild, 'pos-test');
    expect(wire.secureSpoolAvailable, isTrue);
    expect(wire.unresolvedLocalJobs, 2);
    expect(wire.printerFingerprint, _readyEvidence.printerFingerprint);
    hb.dispose();
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
