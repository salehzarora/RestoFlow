import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:restoflow_core/restoflow_core.dart' show SecretValue;
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show SupabaseKitchenDispatchAckRepository;
import 'package:restoflow_printing/restoflow_printing.dart'
    show
        KitchenTransportOutcome,
        KitchenTransportOutcomeKind,
        PrinterDestinationSendGate,
        kitchenPrintRetryPolicy;

import 'kitchen_dispatch_import_coordinator.dart'
    show KitchenAckFlushOutcome, KitchenImportScope, flushAck;
import 'kitchen_print_permission.dart';
import 'kitchen_contained_ack.dart';

/// KITCHEN-MODE-001C2C — the crash-safe, bounded kitchen print worker.
///
/// Consumes ONLY jobs that pass the store's runnable ack gate (server
/// acknowledged, no pending ack, no terminal verdict, in scope, due), via
/// the atomic queued claim. Per job:
///
///   claim → decrypt/validate/render OUTSIDE the gate → acquire the SHARED
///   per-printer gate → durable revalidation → markPrinting (queued only)
///   → EXACTLY ONE transport attempt → release gate → atomic local
///   transition + pending ack → acknowledgement flush OUTSIDE the gate.
///
/// The worker reads the destination ONLY from the decrypted durable payload
/// — it has no settings provider, no resolver, no readiness client, no UI,
/// and no session token. Ambiguous/partial/lost outcomes are NEVER retried;
/// only provably-unsent failures schedule the capped indefinite backoff.
enum KitchenWorkerStopReason {
  /// No more runnable jobs (or every remaining job was destination-busy).
  complete,

  /// The bounded per-run job limit was reached with work possibly left.
  runLimitReached,

  /// The runtime disposed mid-run (logout/unpair/scope change) — the loop
  /// stopped before any further send.
  disposed,
}

final class KitchenWorkerRunReport {
  const KitchenWorkerRunReport({
    required this.stoppedReason,
    this.claimed = 0,
    this.accepted = 0,
    this.failedRetryable = 0,
    this.transportUnavailable = 0,
    this.possiblyPrinted = 0,
    this.blockedConfiguration = 0,
    this.revalidationSkips = 0,
    this.acked = 0,
    this.ackRetriesScheduled = 0,
    this.ackTerminal = 0,
  });

  final KitchenWorkerStopReason stoppedReason;
  final int claimed;
  final int accepted;
  final int failedRetryable;

  /// Subset of [failedRetryable] whose cause was a temporarily unavailable
  /// transport medium (radio off / permission) — surfaced separately for
  /// the operational capability state.
  final int transportUnavailable;
  final int possiblyPrinted;
  final int blockedConfiguration;

  /// Gate-critical revalidation refusals (supersession/state change while
  /// waiting) — the row is preserved, nothing was sent.
  final int revalidationSkips;
  final int acked;
  final int ackRetriesScheduled;
  final int ackTerminal;
}

/// One physical network send (the PASS-1 phase-aware sender, pre-bound to
/// its timeout). Exactly one attempt per call.
typedef KitchenNetworkSend =
    Future<KitchenTransportOutcome> Function({
      required String host,
      required int port,
      required Uint8List bytes,
    });

/// One single-attempt Bluetooth send (the PASS-1 no-resend seam).
typedef KitchenBluetoothSend =
    Future<KitchenTransportOutcome> Function({
      required String address,
      required Uint8List bytes,
    });

/// Opaque durable IDs distinguish targeted web jobs from ordinary spool jobs.
/// Every worker, including lifecycle workers without a fence, fails closed.
const webInitialPrintJobPrefix = 'web-initial:';
bool isTargetedWebPrintJob(KitchenSpoolJobRow job) =>
    job.localJobId.startsWith(webInitialPrintJobPrefix);

final class KitchenPrintWorker {
  KitchenPrintWorker({
    required KitchenSpoolStore store,
    required KitchenSpoolCipher cipher,
    required SecretValue key,
    required KitchenDispatchBytesRenderer renderer,
    required KitchenNetworkSend networkSend,
    required KitchenBluetoothSend bluetoothSend,
    required PrinterDestinationSendGate sendGate,
    required SupabaseKitchenDispatchAckRepository ackRepository,
    required KitchenImportScope scope,
    DateTime Function()? now,
    int maxJobsPerRun = 20,
    bool Function()? isDisposed,
    Future<KitchenPrintPermission> Function(KitchenSpoolJobRow)? permission,
    Future<bool> Function(KitchenSpoolJobRow)? mayRun,
    KitchenAckInvoke? acknowledge,
    String? onlyLocalJobId,
    Future<bool> Function(KitchenSpoolJobRow)? beforeTargetSend,
    Future<bool> Function(KitchenSpoolJobRow)? finishTargetSend,
  }) : _store = store,
       _cipher = cipher,
       _key = key,
       _renderer = renderer,
       _networkSend = networkSend,
       _bluetoothSend = bluetoothSend,
       _sendGate = sendGate,
       _ackRepository = ackRepository,
       _scope = scope,
       _now = now ?? DateTime.now,
       _maxJobsPerRun = maxJobsPerRun.clamp(1, 50),
       _permission = permission,
       _mayRun = mayRun,
       _acknowledge = acknowledge,
       _onlyLocalJobId = onlyLocalJobId,
       _beforeTargetSend = beforeTargetSend,
       _finishTargetSend = finishTargetSend,
       _isDisposed = isDisposed ?? (() => false);

  static const Duration _ackBackoffBase = Duration(seconds: 2);
  static const Duration _ackBackoffCap = Duration(minutes: 5);

  final KitchenSpoolStore _store;
  final KitchenSpoolCipher _cipher;
  final SecretValue _key;
  // KIOSK-PRINT-114B.5A: the ONE dispatch bytes seam — production injects the
  // CANONICAL renderer (dispatch -> shared KdsTicketView -> the POS/KDS ticket
  // builder); the legacy KitchenTicketRenderer still satisfies it for tests.
  final KitchenDispatchBytesRenderer _renderer;
  final KitchenNetworkSend _networkSend;
  final KitchenBluetoothSend _bluetoothSend;
  final PrinterDestinationSendGate _sendGate;
  final SupabaseKitchenDispatchAckRepository _ackRepository;
  final KitchenImportScope _scope;
  final DateTime Function() _now;
  final int _maxJobsPerRun;
  final bool Function() _isDisposed;
  final Future<KitchenPrintPermission> Function(KitchenSpoolJobRow)?
  _permission;
  final Future<bool> Function(KitchenSpoolJobRow)? _mayRun;
  final KitchenAckInvoke? _acknowledge;
  final String? _onlyLocalJobId;
  final Future<bool> Function(KitchenSpoolJobRow)? _beforeTargetSend;
  final Future<bool> Function(KitchenSpoolJobRow)? _finishTargetSend;
  final Set<String> _policyDeniedJobs = {};

  Future<KitchenWorkerRunReport> run() async {
    try {
      return await _runOnce();
    } finally {
      final target = _onlyLocalJobId;
      if (target != null) {
        try {
          final row = await _store.getByLocalJobId(target);
          if (row != null) await _retireQueuedTarget(row);
        } catch (_) {
          // Disposal may already have closed the database. The next ordinary
          // worker performs the same conditional recovery before selection.
        }
      }
    }
  }

  Future<KitchenWorkerRunReport> _runOnce() async {
    var claimed = 0, accepted = 0, failed = 0, unavailable = 0;
    var possibly = 0, blocked = 0, skips = 0;
    var acked = 0, ackRetries = 0, ackTerminal = 0;
    var stop = KitchenWorkerStopReason.complete;

    // FIFO snapshot bounded to the run limit; fatal store/DB errors
    // deliberately propagate to the runtime boundary.
    final targetId = _onlyLocalJobId;
    final target = targetId == null
        ? null
        : await _store.getByLocalJobId(targetId);
    final runnable = targetId != null
        ? (target == null ? <KitchenSpoolJobRow>[] : [target])
        : await _ordinaryRunnable();
    var processed = 0;
    for (final candidate in runnable) {
      final targeted = isTargetedWebPrintJob(candidate);
      // No lifecycle drain may pick up a fenced job left by a crash. Only the
      // exact-target path with both callbacks can even queue this durable row.
      if (targeted &&
          (targetId != candidate.localJobId ||
              _beforeTargetSend == null ||
              _finishTargetSend == null))
        continue;
      if (targetId != null && !targeted) continue;
      if (_isDisposed()) {
        stop = KitchenWorkerStopReason.disposed;
        break;
      }
      if (processed >= _maxJobsPerRun) {
        stop = KitchenWorkerStopReason.runLimitReached;
        break;
      }
      // A hold is policy, not a print outcome. Refuse before the durable
      // queued claim, without incrementing the attempt or owing an ACK.
      if (!await _permitted(candidate)) continue;
      processed++;

      final excludedQueued = await _excludedQueuedJobs();
      if (!await _permitted(candidate)) continue;
      final job = await _store.claimRunnableForQueued(
        candidate.localJobId,
        organizationId: _scope.organizationId,
        restaurantId: _scope.restaurantId,
        branchId: _scope.branchId,
        deviceId: _scope.deviceId,
        now: _now(),
        policyExcludedQueuedJobIds: excludedQueued,
      );
      if (job == null) continue; // destination busy / state changed — skip.
      claimed++;

      // Decrypt / validate / render OUTSIDE the gate. A row-local failure
      // becomes blockedConfiguration (queued source, zero paper risk) and
      // never poisons sibling jobs.
      final _Prepared prepared;
      final preparation = await _prepare(job);
      // Policy may change during asynchronous decryption/rendering. Do not
      // turn that change into a configuration failure or transport evidence.
      if (!await _permitted(job)) {
        skips++;
        continue;
      }
      switch (preparation) {
        case _PrepFailure(:final code):
          await _store.markBlockedConfigurationWithAck(
            job.localJobId,
            errorCode: code,
            now: _now(),
          );
          blocked++;
          switch (await _flushJob(job.localJobId)) {
            case KitchenAckFlushOutcome.acked:
              acked++;
            case KitchenAckFlushOutcome.retryScheduled:
              ackRetries++;
            case KitchenAckFlushOutcome.terminal:
              ackTerminal++;
            case KitchenAckFlushOutcome.skipped:
              break;
          }
          continue;
        case final _Prepared ok:
          prepared = ok;
      }

      // GATE-CRITICAL SECTION: durable revalidation + markPrinting + ONE
      // transport attempt — nothing else. No DB claim, no decryption, no
      // rendering, no acknowledgement inside the gate.
      final outcome = await _sendGate.withDestination(
        prepared.gateKey,
        () async {
          if (_isDisposed()) return null;
          final fresh = await _store.getByLocalJobId(job.localJobId);
          if (!_stillSendable(fresh, job)) return null;
          // The shared destination gate may have been occupied by a receipt
          // or another worker. Recheck INSIDE it using current policy, before
          // markPrinting, reservation or either physical transport.
          if (!await _permitted(fresh!)) return null;
          final excludedQueued = await _excludedQueuedJobs();
          if (!await _permitted(fresh)) return null;
          if (_isDisposed()) return null;
          if (!await _store.markPrinting(
            job.localJobId,
            _now(),
            policyExcludedQueuedJobIds: excludedQueued,
          )) {
            return null;
          }
          if (targeted) {
            // Durable local printing precedes the server reservation. A crash
            // on either side is reconciliation, never automatic resend.
            var authorized = false;
            try {
              authorized = await _beforeTargetSend!(job);
            } catch (_) {
              authorized = false;
            }
            if (!authorized || _isDisposed()) {
              return const KitchenTransportOutcome(
                KitchenTransportOutcomeKind.ambiguous,
                'web_print_reconciliation_required',
              );
            }
          }
          return prepared.send();
        },
      );
      if (outcome == null) {
        // Supersession/disposal/state change while waiting: nothing was
        // sent. A targeted queued row must release its destination lock into
        // an honest zero-write operator hold, never back into retryable work.
        if (targeted && await _retireQueuedTarget(job)) blocked++;
        skips++;
        continue;
      }

      // Atomic transition + pending ack OUTSIDE the gate.
      switch (outcome.kind) {
        case KitchenTransportOutcomeKind.accepted:
          await _store.markTransportAcceptedWithAck(job.localJobId, _now());
          accepted++;
        case KitchenTransportOutcomeKind.definitelyNotSent:
        case KitchenTransportOutcomeKind.timeoutBeforeWrite:
        case KitchenTransportOutcomeKind.unavailable:
          if (targeted) {
            // The durable reservation is consumed even for a proven no-write
            // failure. This workstream prioritizes at-most-once transmission.
            await _store.markBlockedConfigurationAfterConfirmedNoWriteWithAck(
              job.localJobId,
              errorCode: outcome.reasonCode,
              now: _now(),
            );
            blocked++;
            break;
          }
          final delay = kitchenPrintRetryPolicy.backoffFor(job.attemptCount);
          await _store.markFailedRetryableWithAck(
            job.localJobId,
            errorCode: outcome.reasonCode,
            nextAttemptAt: _now().add(delay),
            now: _now(),
          );
          failed++;
          if (outcome.kind == KitchenTransportOutcomeKind.unavailable) {
            unavailable++;
          }
        case KitchenTransportOutcomeKind.ambiguous:
        case KitchenTransportOutcomeKind.timeoutAfterPossibleWrite:
          await _store.markPossiblyPrintedWithAck(job.localJobId, _now());
          possibly++;
        case KitchenTransportOutcomeKind.unsupported:
          // Permanent incapability PROVEN zero-write by the classifiers
          // (unbonded target / missing channel / malformed destination all
          // fail before any byte) — the NARROW printing-source transition.
          await _store.markBlockedConfigurationAfterConfirmedNoWriteWithAck(
            job.localJobId,
            errorCode: outcome.reasonCode,
            now: _now(),
          );
          blocked++;
      }
      switch (await _flushJob(job.localJobId)) {
        case KitchenAckFlushOutcome.acked:
          acked++;
        case KitchenAckFlushOutcome.retryScheduled:
          ackRetries++;
        case KitchenAckFlushOutcome.terminal:
          ackTerminal++;
        case KitchenAckFlushOutcome.skipped:
          break;
      }
    }

    return KitchenWorkerRunReport(
      stoppedReason: stop,
      claimed: claimed,
      accepted: accepted,
      failedRetryable: failed,
      transportUnavailable: unavailable,
      possiblyPrinted: possibly,
      blockedConfiguration: blocked,
      revalidationSkips: skips,
      acked: acked,
      ackRetriesScheduled: ackRetries,
      ackTerminal: ackTerminal,
    );
  }

  Future<List<KitchenSpoolJobRow>> _ordinaryRunnable() async {
    // Abandoned fenced imports must not occupy the bounded FIFO snapshot and
    // starve unrelated POS jobs. Count safe metadata only, expand the read by
    // that upper bound, then restore the ordinary bounded FIFO before work.
    final unresolved = await _store.listUnresolved(
      deviceId: _scope.deviceId,
      branchId: _scope.branchId,
    );
    // A process can die during render/gate wait BEFORE markPrinting/begin.
    // Such a queued target otherwise owns the printer forever, because this
    // worker intentionally excludes fenced rows. Retire ONLY queued targets
    // in this exact scope. A late old awaiter cannot markPrinting afterward.
    final retiredTargets = <String>{};
    for (final row in unresolved) {
      if (await _retireQueuedTarget(row)) {
        retiredTargets.add(row.localJobId);
      }
    }
    // A deferred owner also defers its destination's imported siblings. Do
    // this before taking the bounded permitted window: otherwise many such
    // siblings consume every slot and starve independently safe printers.
    // This is only selection; the atomic claim and shared gate still recheck
    // current durable ownership before any state transition or transport.
    final destinationOwners = <String, Set<String>>{};
    for (final row in unresolved) {
      final fingerprint = row.destinationFingerprint;
      if (fingerprint == null ||
          retiredTargets.contains(row.localJobId) ||
          (row.status != KitchenSpoolJobStatus.queued &&
              row.status != KitchenSpoolJobStatus.printing)) {
        continue;
      }
      if (row.status == KitchenSpoolJobStatus.queued &&
          row.organizationId == _scope.organizationId &&
          row.restaurantId == _scope.restaurantId &&
          row.branchId == _scope.branchId &&
          row.deviceId == _scope.deviceId &&
          (await _permissionFor(row)).mayExcludeQueuedOwner) {
        continue;
      }
      destinationOwners.putIfAbsent(fingerprint, () => {}).add(row.localJobId);
    }
    // Held rows must not fill the FIFO window and starve unheld jobs later
    // in it. The existing unresolved metadata supplies a finite upper bound;
    // only the ordinary bounded number of permitted rows proceeds to claims.
    final rows = await _store.listRunnable(
      deviceId: _scope.deviceId,
      branchId: _scope.branchId,
      now: _now(),
      limit: _maxJobsPerRun + 1 + unresolved.length,
    );
    final allowed = <KitchenSpoolJobRow>[];
    for (final row in rows) {
      final owners = destinationOwners[row.destinationFingerprint];
      if (owners != null && owners.any((id) => id != row.localJobId)) {
        continue;
      }
      if (isTargetedWebPrintJob(row) || !await _permitted(row)) continue;
      allowed.add(row);
      if (allowed.length > _maxJobsPerRun) break;
    }
    return allowed;
  }

  /// A failed read can refuse transmission, but it proves no authority to
  /// ignore a queued destination owner. Production uses the typed policy;
  /// the legacy boolean seam deliberately maps false to unknown, never held.
  Future<KitchenPrintPermission> _permissionFor(KitchenSpoolJobRow row) async {
    try {
      final check = _permission;
      final legacy = _mayRun;
      final KitchenPrintPermission result;
      if (check != null) {
        result = await check(row);
      } else if (legacy == null || await legacy(row)) {
        result = KitchenPrintPermission.permitted;
      } else {
        result = KitchenPrintPermission.unknown;
      }
      if (!result.mayTransmit) _policyDeniedJobs.add(row.localJobId);
      return result;
    } on Object {
      _policyDeniedJobs.add(row.localJobId);
      return KitchenPrintPermission.unknown;
    }
  }

  Future<bool> _permitted(KitchenSpoolJobRow row) async =>
      (await _permissionFor(row)).mayTransmit;

  /// A held queued row has never crossed markPrinting, and its policy guard
  /// will refuse it at the shared gate too. It may therefore remain intact
  /// without monopolizing its printer. The store independently requires the
  /// exact scope and queued state; it NEVER ignores a printing row. Only an
  /// immutable exact-dispatch hold permits exclusion. Branch blocking and
  /// unknown/transient reads preserve the queued owner's exclusive claim.
  Future<Set<String>> _excludedQueuedJobs() async {
    if (_permission == null) return const {};
    final unresolved = await _store.listUnresolved(
      deviceId: _scope.deviceId,
      branchId: _scope.branchId,
    );
    final denied = <String>{};
    for (final row in unresolved) {
      if (row.status == KitchenSpoolJobStatus.queued &&
          row.organizationId == _scope.organizationId &&
          row.restaurantId == _scope.restaurantId &&
          row.branchId == _scope.branchId &&
          row.deviceId == _scope.deviceId &&
          (await _permissionFor(row)).mayExcludeQueuedOwner) {
        denied.add(row.localJobId);
      }
    }
    return denied;
  }

  Future<bool> _retireQueuedTarget(KitchenSpoolJobRow row) async {
    if (!isTargetedWebPrintJob(row) ||
        row.status != KitchenSpoolJobStatus.queued ||
        row.organizationId != _scope.organizationId ||
        row.restaurantId != _scope.restaurantId ||
        row.branchId != _scope.branchId ||
        row.deviceId != _scope.deviceId ||
        _policyDeniedJobs.contains(row.localJobId) ||
        !await _permitted(row))
      return false;
    // queued proves the durable markPrinting-before-begin boundary was never
    // crossed. The existing SQL transition is conditional on STILL queued.
    return _store.markBlockedConfigurationWithAck(
      row.localJobId,
      errorCode: 'target_abandoned_before_send',
      now: _now(),
    );
  }

  /// Flushes the job's freshly-written pending acknowledgement OUTSIDE the
  /// gate; the wire status derives ONLY from the durable pending marker.
  Future<KitchenAckFlushOutcome> _flushJob(String localJobId) async {
    final row = await _store.getByLocalJobId(localJobId);
    if (row == null) return KitchenAckFlushOutcome.skipped;
    if (isTargetedWebPrintJob(row)) {
      final finish = _finishTargetSend;
      if (finish == null) return KitchenAckFlushOutcome.skipped;
      try {
        if (await finish(row)) {
          await _store.markServerAcked(localJobId, _now());
          return KitchenAckFlushOutcome.acked;
        }
      } catch (_) {
        // Lost finish reply preserves local truth and the permanent server
        // fence. It is not a reason to call begin or transport again.
      }
      return KitchenAckFlushOutcome.skipped;
    }
    return flushAck(
      _store,
      _ackRepository,
      row,
      _now(),
      backoffBase: _ackBackoffBase,
      backoffCap: _ackBackoffCap,
      acknowledge: _acknowledge,
    );
  }

  /// Whether the durable row is STILL exactly the job we claimed — checked
  /// under the gate, immediately before markPrinting/send. An in-memory
  /// copy from before the gate wait is never trusted.
  bool _stillSendable(KitchenSpoolJobRow? fresh, KitchenSpoolJobRow claimed) =>
      fresh != null &&
      fresh.status == KitchenSpoolJobStatus.queued &&
      fresh.organizationId == _scope.organizationId &&
      fresh.restaurantId == _scope.restaurantId &&
      fresh.branchId == _scope.branchId &&
      fresh.deviceId == _scope.deviceId &&
      fresh.serverAcknowledgedAt != null &&
      fresh.pendingServerAckStatus == null &&
      fresh.serverAckTerminalCode == null &&
      fresh.supersededByDispatchId == null &&
      fresh.destinationFingerprint != null &&
      fresh.destinationFingerprint == claimed.destinationFingerprint &&
      fresh.encryptedPayloadBlob.isNotEmpty;

  Future<_PrepResult> _prepare(KitchenSpoolJobRow job) async {
    // 1–3: decrypt under the canonical AAD reconstructed from DURABLE row
    // metadata (the AAD cryptographically binds dispatch id + full scope).
    final Uint8List clear;
    try {
      clear = await _cipher.decrypt(
        envelope: Uint8List.fromList(job.encryptedPayloadBlob),
        aad: KitchenSpoolAad(
          dispatchId: job.dispatchId,
          organizationId: job.organizationId,
          restaurantId: job.restaurantId,
          branchId: job.branchId,
          deviceId: job.deviceId,
          encryptionVersion: job.encryptionVersion,
        ),
        key: _key,
      );
    } on Object {
      // Wrong key / AAD mismatch / tamper / malformed envelope /
      // unsupported version — one corrupted row, typed and fail-closed.
      return const _PrepFailure('kitchen_payload_undecryptable');
    }

    // 4–5: closed decode + hostile money/privacy re-scan (defence in depth;
    // fromJson re-runs rejectHostileKitchenKeys over the dispatch subtree).
    final KitchenSpoolLocalPayload payload;
    try {
      payload = KitchenSpoolLocalPayload.fromBytes(clear);
    } on Object {
      return const _PrepFailure('kitchen_payload_invalid');
    }

    // 6: identity — the payload must describe THIS durable row.
    final dispatch = payload.dispatch;
    if (dispatch.kind != job.dispatchType) {
      return const _PrepFailure('kitchen_payload_identity_mismatch');
    }
    final payloadRound = dispatch.roundId;
    if (payloadRound != null &&
        job.serviceRoundId != null &&
        payloadRound != job.serviceRoundId) {
      return const _PrepFailure('kitchen_payload_identity_mismatch');
    }

    // 7–8: the pinned destination variant, its fingerprint consistency with
    // the plaintext routing column, and the 80mm-only policy.
    if (payload.paperWidth != '80mm' || job.paperWidth != '80mm') {
      return const _PrepFailure('kitchen_paper_width_not_80mm');
    }
    final String gateKey;
    final Future<KitchenTransportOutcome> Function(Uint8List bytes) sendBytes;
    switch (payload.destination) {
      case NetworkKitchenDestination(:final host, :final port):
        if (job.transportKind != 'network' ||
            job.destinationFingerprint !=
                _fingerprint('network|${host.trim().toLowerCase()}|$port')) {
          return const _PrepFailure('kitchen_destination_invalid');
        }
        gateKey = PrinterDestinationSendGate.networkKey(host, port);
        sendBytes = (bytes) =>
            _networkSend(host: host, port: port, bytes: bytes);
      case BluetoothKitchenDestination(:final address):
        if (job.transportKind != 'bluetooth' ||
            job.destinationFingerprint !=
                _fingerprint('bluetooth|${address.trim().toLowerCase()}')) {
          return const _PrepFailure('kitchen_destination_invalid');
        }
        gateKey = PrinterDestinationSendGate.bluetoothKey(address);
        sendBytes = (bytes) => _bluetoothSend(address: address, bytes: bytes);
      case MissingKitchenDestination():
        // Should be structurally impossible for a runnable job (blocked
        // imports have no fingerprint) — treat as corruption, fail closed.
        return const _PrepFailure('kitchen_destination_invalid');
    }

    // 9–10: money-free render + 80mm ESC/POS encode, outside the gate.
    final Uint8List bytes;
    try {
      // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): render the OPTIONAL phone from
      // the decrypted local payload (a crash-recovery replay keeps the phone that
      // the server-derived `dispatch` deliberately never carried). Null on legacy
      // rows -> byte-identical to before.
      bytes = await _renderer.renderToBytes(
        dispatch,
        customerPhoneOverride: payload.customerPhone,
      );
    } on Object {
      return const _PrepFailure('kitchen_render_failed');
    }
    return _Prepared(gateKey: gateKey, send: () => sendBytes(bytes));
  }

  static String _fingerprint(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString();
}

sealed class _PrepResult {
  const _PrepResult();
}

/// Worker-internal prepared job: the gate key + a zero-argument single-shot
/// send closure over the already-rendered bytes.
final class _Prepared extends _PrepResult {
  const _Prepared({required this.gateKey, required this.send});

  final String gateKey;
  final Future<KitchenTransportOutcome> Function() send;
}

final class _PrepFailure extends _PrepResult {
  const _PrepFailure(this.code);

  /// Safe bounded token — never endpoint/payload/exception text.
  final String code;
}
