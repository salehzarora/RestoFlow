import 'dart:typed_data';

import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/outbox_repository.dart' show OrderSubmitPhoneLookupKey;
import '../data/round_print_claim_store.dart' show PosRoundPrintClaimState;
import 'kitchen_destination_resolver.dart';

/// KITCHEN-MODE-001C2B — the durable import transaction (steps 3–14 of the
/// locked order; the runtime validates session/scope + trusted mode BEFORE
/// calling here).
///
/// Per dispatch: decode the server row's money-free payload with the CLOSED
/// decoder, run the client-side hostile-key defence, pin the destination (or
/// the missing-destination blocked variant), build the local payload,
/// encrypt (AES-256-GCM, canonical AAD), insert IDEMPOTENTLY by dispatch id,
/// commit — and only THEN set + attempt the server acknowledgement
/// (`imported` / `blocked_configuration` only). An acknowledgement failure
/// never deletes, re-encrypts, or reroutes the local job.
///
/// CORRECTION-001: after the first committed import, the DURABLE ROW is the
/// sole authority. A re-drive (crash-window recovery, duplicate page) looks
/// the row up FIRST and never re-decodes, re-resolves, re-pins, or
/// re-encrypts — and the pending server acknowledgement is derived ONLY from
/// the stored row status (imported → `imported`, blockedConfiguration →
/// `blocked_configuration`), never from freshly recomputed destination
/// state. Any other durable state yields a typed local-state conflict count:
/// no acknowledgement is invented and the row is left untouched.
///
/// [POS-OFFLINE-OPERATIONS-002] Pass C (C1): BEFORE a NEW `initial_order`
/// dispatch is imported, the injected mirror-claim reader is consulted — a
/// `sent`/`claimed` claim means this POS already printed that order's initial
/// ticket locally at submit, so the dispatch is acknowledged and skipped
/// without ever becoming a print job (see `_readInitialPrintClaim`).
final class KitchenImportScope {
  const KitchenImportScope({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
  });

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;
}

final class KitchenImportSummary {
  const KitchenImportSummary({
    required this.imported,
    required this.duplicates,
    required this.blocked,
    required this.rejected,
    required this.acked,
    required this.ackRetriesScheduled,
    required this.ackTerminal,
    required this.superseded,
    required this.supersessionLinks,
    required this.localStateConflicts,
    required this.alreadyPrintedLocally,
  });

  final int imported;
  final int duplicates;
  final int blocked;
  final int rejected;
  final int acked;
  final int ackRetriesScheduled;
  final int ackTerminal;
  final int superseded;
  final int supersessionLinks;

  /// [POS-OFFLINE-OPERATIONS-002] Pass C (C1): `initial_order` dispatches
  /// SKIPPED because the order-scoped mirror claim
  /// (`posInitialKitchenPrintClaimKey`) says this POS already printed the
  /// initial ticket locally at submit (offline direct-print). No local job
  /// row is created — there is nothing for any worker to ever print — and
  /// the server is acknowledged with the honest non-physical status
  /// (`transport_accepted` for a `sent` claim, `possibly_printed` for a
  /// crash-window `claimed`). Safe scalar count only.
  final int alreadyPrintedLocally;

  /// CORRECTION-001: re-driven dispatches whose durable row is OUTSIDE this
  /// coordinator's acknowledgement authority (later print states, or an
  /// already-terminal server verdict). No acknowledgement is invented; the
  /// row is preserved untouched. Safe scalar count only — never a payload,
  /// endpoint, or raw error.
  final int localStateConflicts;
}

final class KitchenDispatchImportCoordinator {
  KitchenDispatchImportCoordinator({
    required KitchenSpoolStore store,
    required KitchenSpoolCipher cipher,
    required SecretValue key,
    required KitchenImportScope scope,
    required KitchenDestinationResolution destination,
    required SupabaseKitchenDispatchAckRepository ackRepository,
    required String Function() localJobIdGenerator,
    DateTime Function()? now,
    Future<String?> Function(OrderSubmitPhoneLookupKey key)?
    resolveCustomerPhone,
    PosRoundPrintClaimState? Function(String orderId)? readInitialPrintClaim,
  }) : _store = store,
       _cipher = cipher,
       _key = key,
       _scope = scope,
       _destination = destination,
       _ackRepository = ackRepository,
       _newLocalJobId = localJobIdGenerator,
       _now = now ?? DateTime.now,
       _resolveCustomerPhone = resolveCustomerPhone,
       _readInitialPrintClaim = readInitialPrintClaim;

  static const Duration _ackBackoffBase = Duration(seconds: 2);
  static const Duration _ackBackoffCap = Duration(minutes: 5);

  final KitchenSpoolStore _store;
  final KitchenSpoolCipher _cipher;
  final SecretValue _key;
  final KitchenImportScope _scope;
  final KitchenDestinationResolution _destination;
  final SupabaseKitchenDispatchAckRepository _ackRepository;
  final String Function() _newLocalJobId;
  final DateTime Function() _now;

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C, Codex HIGH): resolves the ORDER's
  /// phone LOCALLY (never from the redacted server payload) so it can be stored in
  /// the encrypted local payload and printed on a crash-recovery replay. Called
  /// with a FULLY-SCOPED [OrderSubmitPhoneLookupKey] built from THIS run's import
  /// scope + the dispatch order id, so the durable lookup cannot cross scopes.
  /// Optional + best-effort: a miss/failure/absence yields null (name-only).
  final Future<String?> Function(OrderSubmitPhoneLookupKey key)?
  _resolveCustomerPhone;

  /// [POS-OFFLINE-OPERATIONS-002] Pass C (C1) — THE DUPLICATE-PRINT DEFENCE
  /// for locally-printed initial tickets: reads this device's ORDER-scoped
  /// mirror claim (`posInitialKitchenPrintClaimKey(orderId)`, recorded when
  /// the POS printed the offline direct-print ticket itself at submit).
  /// Consulted BEFORE an `initial_order` dispatch becomes a local print job:
  /// every accepted submit on a printer_only branch creates an
  /// `initial:<order_id>` dispatch row server-side — INCLUDING an offline
  /// order once it syncs — so without this consult the drain would re-print
  /// tickets the POS already printed. `sent`/`claimed` skip + acknowledge;
  /// `failed`/absent import normally (the local attempt failed or another
  /// till took the order — the drain printing it is the desired outcome).
  /// Null (not wired: tests, web) keeps the pre-Pass-C behaviour.
  final PosRoundPrintClaimState? Function(String orderId)?
  _readInitialPrintClaim;

  /// The fully-scoped durable-phone lookup identity for [dispatch] in THIS run's
  /// import scope (organization/restaurant/branch/device from [_scope]). The
  /// pulled dispatch carries no local_operation_id, so it is left null.
  OrderSubmitPhoneLookupKey _phoneLookupKey(PulledKitchenDispatch dispatch) =>
      OrderSubmitPhoneLookupKey(
        organizationId: _scope.organizationId,
        restaurantId: _scope.restaurantId,
        branchId: _scope.branchId,
        deviceId: _scope.deviceId,
        orderId: dispatch.orderId,
      );

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): enrich a previously
  /// phone-less imported row when the phone is now resolvable. Decrypt-check the
  /// existing ciphertext (so an existing non-null phone is never overwritten, and
  /// a cross-scope row — whose AAD will not match — is left untouched), then
  /// re-encrypt with the SAME AAD and replace ONLY the encrypted blob. Fully
  /// best-effort and idempotent: any resolve/decode/crypto miss leaves the row
  /// byte-identical, and re-running with the same phone is a no-op write.
  Future<void> _maybeEnrichPhone(
    KitchenSpoolJobRow row,
    PulledKitchenDispatch dispatch,
    DateTime now,
  ) async {
    final resolver = _resolveCustomerPhone;
    if (resolver == null) return;
    String? resolved;
    try {
      resolved = await resolver(_phoneLookupKey(dispatch));
    } on Object {
      return;
    }
    if (resolved == null || resolved.isEmpty) return;

    final aad = KitchenSpoolAad(
      dispatchId: row.dispatchId,
      organizationId: _scope.organizationId,
      restaurantId: _scope.restaurantId,
      branchId: _scope.branchId,
      deviceId: _scope.deviceId,
      encryptionVersion: row.encryptionVersion,
    );
    KitchenSpoolLocalPayload payload;
    try {
      final bytes = await _cipher.decrypt(
        envelope: row.encryptedPayloadBlob,
        aad: aad,
        key: _key,
      );
      payload = KitchenSpoolLocalPayload.fromBytes(bytes);
    } on Object {
      return; // undecryptable (e.g. a different scope) -> never touched
    }
    if (payload.customerPhone != null) return; // never overwrite a phone

    final enriched = KitchenSpoolLocalPayload(
      dispatch: payload.dispatch,
      destination: payload.destination,
      paperWidth: payload.paperWidth,
      documentVersion: payload.documentVersion,
      rasterVersion: payload.rasterVersion,
      customerPhone: resolved,
    );
    final Uint8List envelope = await _cipher.encrypt(
      plaintext: enriched.toBytes(),
      aad: aad,
      key: _key,
    );
    await _store.updateEncryptedPayload(row.localJobId, envelope, now);
  }

  Future<KitchenImportSummary> importDispatches(
    List<PulledKitchenDispatch> dispatches,
  ) async {
    var imported = 0, duplicates = 0, blocked = 0, rejected = 0;
    var acked = 0, retries = 0, terminal = 0;
    var superseded = 0, links = 0, conflicts = 0;
    var alreadyPrinted = 0;
    for (final dispatch in dispatches) {
      final now = _now();

      // ROW-LOCAL: only server payload contract v1 is supported by this
      // build's closed decoder/renderer pins.
      if (dispatch.payloadVersion != 1) {
        rejected++;
        continue;
      }

      // Pass C (C1): the mirror-claim consult, BEFORE any local job exists.
      // Scoped to NEW `initial_order` dispatches only: a row that already
      // exists keeps the durable-row-is-authority contract untouched, and
      // service rounds / voids have their own identities. A skipped dispatch
      // creates NO local row — there is nothing for any worker to ever print
      // — and the server is told the honest non-physical status. A refused
      // acknowledgement schedules nothing: the un-acknowledged dispatch is
      // simply re-served after its claim window and this consult runs again,
      // converging on the acknowledgement without ever printing.
      if (dispatch.dispatchType ==
              KitchenSpoolDispatchType.initialOrder.wireName &&
          _readInitialPrintClaim != null &&
          await _store.findByDispatchId(dispatch.dispatchId) == null) {
        PosRoundPrintClaimState? claim;
        try {
          claim = _readInitialPrintClaim(dispatch.orderId);
        } on Object {
          // An unreadable claim answers "this POS MAY already have printed
          // it" — fail toward not printing (the claim store's own unreadable
          // envelope reads the same way).
          claim = PosRoundPrintClaimState.claimed;
        }
        if (claim == PosRoundPrintClaimState.sent ||
            claim == PosRoundPrintClaimState.claimed) {
          alreadyPrinted++;
          final result = await _ackRepository.acknowledge(
            dispatchId: dispatch.dispatchId,
            // `sent` = the transport accepted the bytes at submit;
            // `claimed` = a crash window where paper MAY exist — the
            // server's own vocabulary for exactly those two facts.
            status: claim == PosRoundPrintClaimState.sent
                ? KitchenImportAckStatus.transportAccepted
                : KitchenImportAckStatus.possiblyPrinted,
          );
          switch (result) {
            case KitchenAckAccepted():
              acked++;
            case KitchenAckTerminal():
              terminal++;
            case KitchenAckInvalidSession():
            case KitchenAckInvalidRequest():
            case KitchenAckTransientFailure():
            case KitchenAckServerFailure():
            case KitchenAckMalformedResponse():
              break; // re-served later; never printed meanwhile.
          }
          continue;
        }
      }

      // CORRECTION-001: the durable row is looked up FIRST. A re-drive of an
      // already-committed dispatch (crash-window recovery, duplicate page)
      // must never re-decode, re-resolve, re-pin, or re-encrypt — the stored
      // ciphertext, destination, status, fingerprint, paper width, and safe
      // error code all stay byte-identical.
      KitchenSpoolJobRow row;
      final existing = await _store.findByDispatchId(dispatch.dispatchId);
      if (existing != null) {
        duplicates++;
        row = existing;
        // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 2): a re-drive may now be
        // able to resolve a phone the FIRST import lacked (it raced ahead of both
        // the durable op and the recent-order registration). Enrich ONLY the
        // encrypted customerPhone — never a duplicate, a status/attempt/
        // destination change, or an overwrite of an existing non-null phone.
        await _maybeEnrichPhone(existing, dispatch, now);
      } else {
        // 3–4: closed decode + defence in depth. A hostile/malformed payload
        // rejects THIS dispatch only (typed) — it is never persisted.
        final KitchenDispatchDocument document;
        try {
          rejectHostileKitchenKeys(dispatch.moneyFreePayload, path: 'dispatch');
          document = KitchenDispatchDocument.fromJson(
            dispatch.moneyFreePayload,
          );
          if (document.kind.wireName != dispatch.dispatchType) {
            throw const KitchenSpoolPayloadFormatException(
              'row/payload dispatch type mismatch',
            );
          }
        } on KitchenSpoolPayloadFormatException {
          rejected++;
          continue;
        } on ArgumentError {
          rejected++;
          continue;
        }

        // POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap C): resolve the ORDER's phone
        // from the LOCAL order (never the redacted server payload) so it is stored
        // in the encrypted local payload and printed on a crash-recovery replay.
        // Best-effort: any miss/failure keeps the phone null (name-only, unchanged).
        String? resolvedCustomerPhone;
        final resolver = _resolveCustomerPhone;
        if (resolver != null) {
          try {
            resolvedCustomerPhone = await resolver(_phoneLookupKey(dispatch));
          } on Object {
            resolvedCustomerPhone = null;
          }
        }

        // 5–7: destination pinning or the encrypted blocked variant.
        final resolution = _destination;
        final bool isBlocked = resolution is BlockedKitchenDestination;
        final localPayload = KitchenSpoolLocalPayload(
          dispatch: document,
          destination: switch (resolution) {
            ResolvedKitchenDestination(:final destination) => destination,
            BlockedKitchenDestination() => const MissingKitchenDestination(),
          },
          paperWidth: switch (resolution) {
            ResolvedKitchenDestination(:final paperWidth) => paperWidth,
            BlockedKitchenDestination() => null,
          },
          documentVersion: 1,
          rasterVersion: 1,
          customerPhone: resolvedCustomerPhone,
        );

        // 8–9: encrypt bound to the canonical AAD.
        final Uint8List envelope = await _cipher.encrypt(
          plaintext: localPayload.toBytes(),
          aad: KitchenSpoolAad(
            dispatchId: dispatch.dispatchId,
            organizationId: _scope.organizationId,
            restaurantId: _scope.restaurantId,
            branchId: _scope.branchId,
            deviceId: _scope.deviceId,
            encryptionVersion: _cipher.encryptionVersion,
          ),
          key: _key,
        );

        // 10–11: idempotent durable insert (a same-moment racer keeps the
        // EXISTING row untouched — no re-encryption, no rerouting).
        final generatedId = _newLocalJobId();
        row = await _store.insertImportedJob(
          NewKitchenSpoolJob(
            localJobId: generatedId,
            dispatchId: dispatch.dispatchId,
            organizationId: _scope.organizationId,
            restaurantId: _scope.restaurantId,
            branchId: _scope.branchId,
            deviceId: _scope.deviceId,
            orderId: dispatch.orderId,
            serviceRoundId: dispatch.serviceRoundId,
            dispatchType: KitchenSpoolDispatchType.fromWire(
              dispatch.dispatchType,
            ),
            initialStatus: isBlocked
                ? KitchenSpoolJobStatus.blockedConfiguration
                : KitchenSpoolJobStatus.imported,
            encryptedPayloadBlob: envelope,
            encryptionVersion: _cipher.encryptionVersion,
            destinationFingerprint: switch (resolution) {
              ResolvedKitchenDestination(:final fingerprint) => fingerprint,
              BlockedKitchenDestination() => null,
            },
            destinationDisplayLabel: switch (resolution) {
              ResolvedKitchenDestination(:final displayLabel) => displayLabel,
              BlockedKitchenDestination() => null,
            },
            transportKind: switch (resolution) {
              ResolvedKitchenDestination(:final transportKind) => transportKind,
              BlockedKitchenDestination() => null,
            },
            paperWidth: switch (resolution) {
              ResolvedKitchenDestination(:final paperWidth) => paperWidth,
              BlockedKitchenDestination() => null,
            },
            lastErrorCode: switch (resolution) {
              ResolvedKitchenDestination() => null,
              BlockedKitchenDestination(:final reasonCode) => reasonCode,
            },
            payloadVersion: dispatch.payloadVersion,
            documentVersion: 1,
            rasterVersion: 1,
            serverClaimExpiresAt: dispatch.claimExpiresAt == null
                ? null
                : DateTime.tryParse(dispatch.claimExpiresAt!),
            createdAt: now,
          ),
        );
        if (row.localJobId != generatedId) {
          duplicates++;
        } else if (isBlocked) {
          blocked++;
        } else {
          imported++;
        }
      }

      // Server-derived supersession reconciliation: a durably imported VOID
      // marks this order's unresolved prior local jobs (possiblyPrinted
      // keeps its ambiguity and only gains the evidence LINK). Idempotent —
      // and deliberately re-run on re-drives so a crash between the insert
      // and this reconciliation recovers.
      if (dispatch.dispatchType == 'void') {
        final unresolved = await _store.listUnresolved(
          deviceId: _scope.deviceId,
          branchId: _scope.branchId,
        );
        for (final prior in unresolved) {
          if (prior.orderId != dispatch.orderId) continue;
          if (prior.dispatchId == dispatch.dispatchId) continue;
          if (prior.status == KitchenSpoolJobStatus.possiblyPrinted) {
            if (await _store.linkSupersessionEvidence(
              dispatchId: prior.dispatchId,
              supersededByDispatchId: dispatch.dispatchId,
              now: now,
            )) {
              links++;
            }
          } else if (await _store.markSupersededFromServerEvidence(
            dispatchId: prior.dispatchId,
            supersededByDispatchId: dispatch.dispatchId,
            now: now,
          )) {
            superseded++;
          }
        }
      }

      // 12–14 (CORRECTION-001): the acknowledgement is derived ONLY from the
      // DURABLE row status — never from freshly recomputed destination
      // state. Rows in any later/terminal state are outside this
      // coordinator's acknowledgement authority: typed conflict count, no
      // invented acknowledgement, row untouched.
      if (row.status != KitchenSpoolJobStatus.imported &&
          row.status != KitchenSpoolJobStatus.blockedConfiguration) {
        conflicts++;
        continue;
      }
      if (row.serverAckTerminalCode != null) {
        conflicts++;
        continue;
      }
      if (row.pendingServerAckStatus == null &&
          row.serverAcknowledgedAt == null) {
        await _store.setPendingServerAck(
          row.localJobId,
          row.status == KitchenSpoolJobStatus.blockedConfiguration
              ? KitchenServerAckStatus.blockedConfiguration
              : KitchenServerAckStatus.imported,
          now,
        );
      }
      final outcome = await flushAck(
        _store,
        _ackRepository,
        (await _store.getByLocalJobId(row.localJobId))!,
        _now(),
        backoffBase: _ackBackoffBase,
        backoffCap: _ackBackoffCap,
      );
      switch (outcome) {
        case KitchenAckFlushOutcome.acked:
          acked++;
        case KitchenAckFlushOutcome.retryScheduled:
          retries++;
        case KitchenAckFlushOutcome.terminal:
          terminal++;
        case KitchenAckFlushOutcome.skipped:
          break;
      }
    }
    return KitchenImportSummary(
      imported: imported,
      duplicates: duplicates,
      blocked: blocked,
      rejected: rejected,
      acked: acked,
      ackRetriesScheduled: retries,
      ackTerminal: terminal,
      superseded: superseded,
      supersessionLinks: links,
      localStateConflicts: conflicts,
      alreadyPrintedLocally: alreadyPrinted,
    );
  }
}

enum KitchenAckFlushOutcome { acked, retryScheduled, terminal, skipped }

/// Shared single-job acknowledgement flush (import path, the pending-ack
/// coordinator, and the 001C2C worker).
///
/// The wire status is derived ONLY from the DURABLE pending marker — which
/// every transition writes atomically with `row.status` — never invented
/// from current settings. Each pending is consumed exactly once
/// (markServerAcked / markServerAckTerminal clear it).
Future<KitchenAckFlushOutcome> flushAck(
  KitchenSpoolStore store,
  SupabaseKitchenDispatchAckRepository ackRepository,
  KitchenSpoolJobRow job,
  DateTime now, {
  required Duration backoffBase,
  required Duration backoffCap,
}) async {
  final pending = job.pendingServerAckStatus;
  if (pending == null) return KitchenAckFlushOutcome.skipped;
  final status = switch (pending) {
    KitchenServerAckStatus.imported => KitchenImportAckStatus.imported,
    KitchenServerAckStatus.transportAccepted =>
      KitchenImportAckStatus.transportAccepted,
    KitchenServerAckStatus.possiblyPrinted =>
      KitchenImportAckStatus.possiblyPrinted,
    KitchenServerAckStatus.failedRetryable =>
      KitchenImportAckStatus.failedRetryable,
    KitchenServerAckStatus.blockedConfiguration =>
      KitchenImportAckStatus.blockedConfiguration,
  };
  // The server accepts an optional safe error code for the failure-class
  // statuses; the durable row's bounded lastErrorCode is the only source.
  final errorCode = switch (status) {
    KitchenImportAckStatus.blockedConfiguration =>
      job.lastErrorCode ?? 'kitchen_printer_not_configured',
    KitchenImportAckStatus.failedRetryable ||
    KitchenImportAckStatus.possiblyPrinted => job.lastErrorCode,
    KitchenImportAckStatus.imported ||
    KitchenImportAckStatus.transportAccepted => null,
  };

  final result = await ackRepository.acknowledge(
    dispatchId: job.dispatchId,
    status: status,
    errorCode: errorCode,
  );
  switch (result) {
    case KitchenAckAccepted():
      await store.markServerAcked(job.localJobId, now);
      return KitchenAckFlushOutcome.acked;
    case KitchenAckTerminal(:final code):
      await store.markServerAckTerminal(
        job.localJobId,
        terminalCode: code.wireName,
        now: now,
      );
      return KitchenAckFlushOutcome.terminal;
    case KitchenAckInvalidSession():
    case KitchenAckTransientFailure():
    case KitchenAckServerFailure():
    case KitchenAckMalformedResponse():
    case KitchenAckInvalidRequest():
      final attempt = job.serverAckAttemptCount + 1;
      var delay = backoffBase * (1 << (attempt > 8 ? 8 : attempt));
      if (delay > backoffCap) delay = backoffCap;
      await store.updateServerAckRetry(
        job.localJobId,
        errorCode: switch (result) {
          KitchenAckInvalidSession() => 'invalid_session',
          KitchenAckTransientFailure() => 'network_unreachable',
          KitchenAckServerFailure() => 'server_failure',
          // A request-contract rejection is a CLIENT bug: kept visible in
          // the ack error code (capped backoff; safe typed token only).
          KitchenAckInvalidRequest() => 'invalid_request',
          _ => 'malformed_response',
        },
        nextAttemptAt: now.add(delay),
        now: now,
      );
      return KitchenAckFlushOutcome.retryScheduled;
  }
}
