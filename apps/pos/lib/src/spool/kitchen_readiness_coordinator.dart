import 'dart:async';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'kitchen_readiness_evidence.dart';
import 'kitchen_spool_readiness_probe.dart';
import 'pos_kitchen_spool_hooks.dart' show PosKitchenReadinessLifecycle;

/// KITCHEN-MODE-001C3A — the READINESS-ONLY foreground heartbeat.
///
/// The server readiness row expires ten minutes after acceptance, so
/// startup/resume-only reporting goes stale on an idle POS. This coordinator
/// re-files the report every [kKitchenReadinessHeartbeatInterval] while the
/// app is FOREGROUNDED, plus immediately on startup/resume and on demand
/// (printer/scope/spool-state changes are wired to [requestImmediate]).
///
/// HARD BOUNDARY — this timer is readiness-only. It never invokes the print
/// worker, the dispatch drain, any transport send, key provisioning, or
/// database creation: its only dependencies are the pure evidence builder,
/// the NON-MUTATING spool probe, the mode fetch, and the readiness report
/// call. Pausing/backgrounding cancels the timer; logout/unpair/scope change
/// disposes the whole coordinator (the provider rebuilds a fresh one for the
/// new scope); one report is in flight at a time (concurrent callers JOIN
/// the in-flight run).
const Duration kKitchenReadinessHeartbeatInterval = Duration(minutes: 5);

/// Outer bound on one report round-trip (the transport has its own timeouts;
/// this is the belt-and-suspenders cap so a hung call can never wedge the
/// single-flight slot).
const Duration kKitchenReadinessCallTimeout = Duration(seconds: 20);

/// Short build identifier filed with the report (server CHECK 1..64 chars).
/// Compile-time injectable; NEVER an endpoint or device identifier.
const String kPosKitchenReadinessAppBuild = String.fromEnvironment(
  'RESTOFLOW_POS_BUILD',
  defaultValue: 'pos-dev',
);

enum KitchenReadinessRunOutcome {
  /// The server accepted the report (activationReady mirrors qualifying).
  reported,

  /// A stale revision was recovered: cache invalidated, mode refetched,
  /// report re-filed ONCE and accepted.
  staleRecovered,

  /// The stale-revision recovery did not converge in this run (no loop —
  /// the next lifecycle trigger starts fresh).
  staleUnrecovered,

  /// Typed skips: no report was attempted.
  skippedNoScope,
  skippedModeUnavailable,
  skippedRevisionUnavailable,
  skippedIneligibleOldServer,
  skippedEvidenceBlocked,

  /// Typed failures from the report call.
  rejected,
  invalidSession,
  transientFailure,
  serverFailure,
  malformed,

  /// The coordinator was disposed before/while running.
  disposed,
}

final class KitchenReadinessRunReport {
  const KitchenReadinessRunReport({
    required this.trigger,
    required this.outcome,
    this.activationReady,
    this.detail,
    this.statusReported = false,
  });

  final String trigger;

  /// The READINESS-leg outcome (the run's headline). When no printer evidence
  /// exists this is [KitchenReadinessRunOutcome.skippedEvidenceBlocked] while
  /// [statusReported] can still be true.
  final KitchenReadinessRunOutcome outcome;

  /// Server qualifying evaluation, present only when a report was accepted.
  final bool? activationReady;

  /// Safe typed code (blocker/rejection reason) — never raw text, never an
  /// endpoint.
  final String? detail;

  /// KITCHEN-MODE-001C3B1A: whether the configuration-INDEPENDENT POS status
  /// report was accepted this run (it is sent BEFORE readiness and does not
  /// require a printer, so it can be true even when readiness was skipped).
  final bool statusReported;
}

final class KitchenReadinessHeartbeat implements PosKitchenReadinessLifecycle {
  KitchenReadinessHeartbeat({
    required DeviceContext? Function() deviceContext,
    required Future<KitchenModeResult> Function() fetchMode,
    required Future<KitchenReadinessPrinterEvidence> Function() printerEvidence,
    required Future<KitchenSpoolReadinessProbeResult> Function({
      required String deviceId,
      required String branchId,
    })
    probeSpool,
    required Future<KitchenPosStatusResult> Function(KitchenPosStatusReport)
    sendStatus,
    required Future<KitchenReadinessResult> Function(KitchenReadinessReport)
    sendReport,
    required Future<void> Function() invalidateModeCache,
    String appBuild = kPosKitchenReadinessAppBuild,
    Duration interval = kKitchenReadinessHeartbeatInterval,
    Duration callTimeout = kKitchenReadinessCallTimeout,
    Timer Function(Duration, void Function())? periodicTimerFactory,
  }) : _deviceContext = deviceContext,
       _fetchMode = fetchMode,
       _printerEvidence = printerEvidence,
       _sendStatus = sendStatus,
       _probeSpool = probeSpool,
       _sendReport = sendReport,
       _invalidateModeCache = invalidateModeCache,
       _appBuild = appBuild,
       _interval = interval,
       _callTimeout = callTimeout,
       _periodicTimerFactory =
           periodicTimerFactory ??
           ((duration, tick) => Timer.periodic(duration, (_) => tick()));

  final DeviceContext? Function() _deviceContext;
  final Future<KitchenModeResult> Function() _fetchMode;
  final Future<KitchenReadinessPrinterEvidence> Function() _printerEvidence;
  final Future<KitchenSpoolReadinessProbeResult> Function({
    required String deviceId,
    required String branchId,
  })
  _probeSpool;
  final Future<KitchenPosStatusResult> Function(KitchenPosStatusReport)
  _sendStatus;
  final Future<KitchenReadinessResult> Function(KitchenReadinessReport)
  _sendReport;
  final Future<void> Function() _invalidateModeCache;
  final String _appBuild;
  final Duration _interval;
  final Duration _callTimeout;
  final Timer Function(Duration, void Function()) _periodicTimerFactory;

  Timer? _timer;
  bool _disposed = false;
  Future<KitchenReadinessRunReport>? _inFlight;

  /// Startup: arm the periodic timer and file immediately.
  void onStartup() {
    _armTimer();
    requestImmediate('startup');
  }

  /// Resume: re-arm (paused cancels) and file immediately.
  void onResume() {
    _armTimer();
    requestImmediate('resume');
  }

  /// Background/hidden: STOP the periodic timer (a heartbeat against an
  /// invisible surface is pure waste; the server row simply expires).
  void onPaused() {
    _timer?.cancel();
    _timer = null;
  }

  /// Logout/unpair/scope change/provider teardown: permanently stop. A NEW
  /// coordinator is composed for a new scope.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _armTimer() {
    if (_disposed || _timer != null) return;
    _timer = _periodicTimerFactory(_interval, () {
      requestImmediate('heartbeat');
    });
  }

  /// Fire-and-forget trigger (printer config change, spool state change,
  /// lifecycle). [reportNow] never throws, so nothing escapes unawaited.
  void requestImmediate(String trigger) {
    unawaited(reportNow(trigger: trigger));
  }

  /// SINGLE-FLIGHT: a call while a run is in flight JOINS that run.
  Future<KitchenReadinessRunReport> reportNow({required String trigger}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final run = _run(trigger);
    _inFlight = run;
    return run.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<KitchenReadinessRunReport> _run(String trigger) async {
    try {
      return await _runOnce(trigger, isStaleRetry: false);
    } on Object {
      // Typed catch-all: the heartbeat must never surface an unhandled
      // async error through a fire-and-forget trigger.
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.malformed,
        detail: 'unexpected_failure',
      );
    }
  }

  Future<KitchenReadinessRunReport> _runOnce(
    String trigger, {
    required bool isStaleRetry,
  }) async {
    if (_disposed) {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.disposed,
      );
    }
    final context = _deviceContext();
    final deviceId = context?.deviceId;
    final branchId = context?.branchId;
    if (context == null || deviceId == null || branchId == null) {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.skippedNoScope,
      );
    }

    final KitchenModeResult mode;
    try {
      mode = await _fetchMode().timeout(_callTimeout);
    } on Object {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.skippedModeUnavailable,
        detail: 'mode_fetch_failed',
      );
    }
    final int revision;
    switch (mode) {
      case KitchenModePrinterOnlyWithRevision(revision: final r):
        revision = r;
      case KitchenModeVerifiedKds(revision: final r):
        if (r == null) {
          // Old server: normal KDS behavior continues, but WITHOUT a server
          // revision no readiness report may be filed (never fabricated).
          return KitchenReadinessRunReport(
            trigger: trigger,
            outcome: KitchenReadinessRunOutcome.skippedIneligibleOldServer,
          );
        }
        revision = r;
      case KitchenModeRevisionUnavailable():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.skippedRevisionUnavailable,
        );
      case KitchenModeInvalidSession():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.invalidSession,
        );
      case KitchenModeTransientFailure():
      case KitchenModeServerFailure():
      case KitchenModeMalformedResponse():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.skippedModeUnavailable,
          detail: 'mode_fetch_failed',
        );
    }

    // ONE coherent snapshot: the SAME spool probe and the SAME server
    // revision feed both the config-independent status and (when a printer
    // exists) the assignment-aware readiness, so the two can never disagree.
    final spool = await _probeSpool(deviceId: deviceId, branchId: branchId);
    if (_disposed) {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.disposed,
      );
    }

    // (3) Config-independent POS status — filed FIRST and regardless of any
    // printer, so the future printer_only -> kds escape gate always has a
    // fresh authoritative statement of unresolved_local_jobs.
    final KitchenPosStatusResult statusResult;
    try {
      statusResult = await _sendStatus(
        KitchenPosStatusReport(
          appBuild: _appBuild,
          modeRevision: revision,
          secureSpoolAvailable: spool.secureSpoolAvailable,
          unresolvedLocalJobs: spool.unresolvedLocalJobs,
          spoolCountState: spool.spoolCountState,
        ),
      ).timeout(_callTimeout);
    } on Object {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.transientFailure,
      );
    }
    switch (statusResult) {
      case KitchenPosStatusAccepted():
        break; // continue to readiness
      case KitchenPosStatusStaleModeRevision():
        return _recoverStaleOrGiveUp(trigger, isStaleRetry: isStaleRetry);
      case KitchenPosStatusInvalidSession():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.invalidSession,
        );
      case KitchenPosStatusRejected(:final reason):
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.rejected,
          detail: reason.wireName,
        );
      case KitchenPosStatusServerFailure():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.serverFailure,
        );
      case KitchenPosStatusTransientFailure():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.transientFailure,
        );
      case KitchenPosStatusMalformedResponse():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.malformed,
        );
    }
    // From here the status report succeeded.

    if (_disposed) {
      return const KitchenReadinessRunReport(
        trigger: 'disposed',
        outcome: KitchenReadinessRunOutcome.disposed,
        statusReported: true,
      );
    }

    // (4) Printer evidence. No printer -> readiness is SKIPPED but the status
    // above stands (retained), so the escape gate still works.
    final evidence = await _printerEvidence();
    if (evidence is BlockedKitchenPrinterEvidence) {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.skippedEvidenceBlocked,
        detail: evidence.reasonCode,
        statusReported: true,
      );
    }
    final printer = evidence as ReadyKitchenPrinterEvidence;

    if (_disposed) {
      return const KitchenReadinessRunReport(
        trigger: 'disposed',
        outcome: KitchenReadinessRunOutcome.disposed,
        statusReported: true,
      );
    }

    // (5) Assignment-aware readiness, using the SAME spool + revision snapshot.
    final KitchenReadinessResult result;
    try {
      result = await _sendReport(
        KitchenReadinessReport(
          appBuild: _appBuild,
          transportKind: printer.transportKind,
          paperWidth: printer.paperWidth,
          printerFingerprint: printer.printerFingerprint,
          secureSpoolAvailable: spool.secureSpoolAvailable,
          unresolvedLocalJobs: spool.unresolvedLocalJobs,
          modeRevision: revision,
          printerAssignmentId: printer.printerAssignmentId,
        ),
      ).timeout(_callTimeout);
    } on Object {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.transientFailure,
        statusReported: true,
      );
    }

    switch (result) {
      case KitchenReadinessAccepted(:final activationReady):
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: isStaleRetry
              ? KitchenReadinessRunOutcome.staleRecovered
              : KitchenReadinessRunOutcome.reported,
          activationReady: activationReady,
          statusReported: true,
        );
      case KitchenReadinessStaleModeRevision():
        return _recoverStaleOrGiveUp(trigger, isStaleRetry: isStaleRetry);
      case KitchenReadinessRejected(:final reason):
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.rejected,
          detail: reason.wireName,
          statusReported: true,
        );
      case KitchenReadinessInvalidSession():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.invalidSession,
          statusReported: true,
        );
      case KitchenReadinessTransientFailure():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.transientFailure,
          statusReported: true,
        );
      case KitchenReadinessServerFailure():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.serverFailure,
          statusReported: true,
        );
      case KitchenReadinessMalformedResponse():
        return KitchenReadinessRunReport(
          trigger: trigger,
          outcome: KitchenReadinessRunOutcome.malformed,
          statusReported: true,
        );
    }
  }

  /// Stale-revision recovery shared by BOTH the status and readiness legs: the
  /// cached mode is no longer trustworthy for this exact scope/session, so
  /// invalidate it, then re-run the WHOLE coherent pipeline ONCE (never a
  /// mixed old/new snapshot, never a loop).
  Future<KitchenReadinessRunReport> _recoverStaleOrGiveUp(
    String trigger, {
    required bool isStaleRetry,
  }) async {
    if (isStaleRetry) {
      return KitchenReadinessRunReport(
        trigger: trigger,
        outcome: KitchenReadinessRunOutcome.staleUnrecovered,
      );
    }
    try {
      await _invalidateModeCache();
    } on Exception {
      // Best effort; the refetch inside the retried pipeline is authoritative.
    }
    return _runOnce(trigger, isStaleRetry: true);
  }
}
