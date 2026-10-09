import 'package:restoflow_core/restoflow_core.dart' show SecretValue;
import 'package:restoflow_data_local/restoflow_data_local.dart';

/// KITCHEN-MODE-001C2C — the idempotent LOCAL VOID sweep.
///
/// Re-applies durable VOID evidence to this scope's unresolved jobs so a
/// crash between the void's durable import and its reconciliation — or a
/// job that was PRINTING when the void arrived and later fell back to
/// failedRetryable — can never print a voided order's ticket:
///
///  * imported / queued / failedRetryable / blockedConfiguration →
///    superseded (the store's evidence transition; printing is excluded
///    there by design and transportAccepted stays history);
///  * possiblyPrinted keeps its ambiguity and only gains the evidence link;
///  * the VOID dispatch itself is never superseded by this sweep;
///  * other orders and other scopes are untouched.
///
/// Evidence source: UNRESOLVED void rows in scope (resolved voids already
/// ran the import-time reconciliation before their acknowledgement).
///
/// ORDER-EDIT-001F: the runtime now runs this through
/// [reconcileLocalSupersessionEvidence], which adds the ORDERED order-edit
/// sweep after it; the VOID semantics here are unchanged.
Future<({int superseded, int links})> reconcileLocalVoidEvidence(
  KitchenSpoolStore store, {
  required String deviceId,
  required String branchId,
  required DateTime now,
}) async {
  var superseded = 0, links = 0;
  final unresolved = await store.listUnresolved(
    deviceId: deviceId,
    branchId: branchId,
  );
  final voids = [
    for (final row in unresolved)
      if (row.dispatchType == KitchenSpoolDispatchType.voidNotice) row,
  ];
  for (final evidence in voids) {
    for (final prior in unresolved) {
      if (prior.orderId != evidence.orderId) continue;
      if (prior.dispatchId == evidence.dispatchId) continue;
      if (prior.dispatchType == KitchenSpoolDispatchType.voidNotice) continue;
      if (prior.status == KitchenSpoolJobStatus.possiblyPrinted) {
        if (await store.linkSupersessionEvidence(
          dispatchId: prior.dispatchId,
          supersededByDispatchId: evidence.dispatchId,
          now: now,
        )) {
          links++;
        }
      } else if (await store.markSupersededFromServerEvidence(
        dispatchId: prior.dispatchId,
        supersededByDispatchId: evidence.dispatchId,
        now: now,
      )) {
        superseded++;
      }
    }
  }
  return (superseded: superseded, links: links);
}

/// ORDER-EDIT-001F — one piece of ORDER-EDIT supersession evidence: an edit of
/// [orderId], created on the server at [createdAt], whose `order_edit`
/// dispatch is [dispatchId]. Its change slip ends with ORDER NOW (every live
/// line, "Replaces earlier tickets"), so an older kitchen job of the same
/// order would only put stale paper in the kitchen.
///
/// Sources: an `order_edit` job imported into this spool, or this till's own
/// DIRECT print of a slip (the external evidence: that dispatch completes on
/// the server and never reaches the spool).
final class KitchenEditSupersessionEvidence {
  const KitchenEditSupersessionEvidence({
    required this.orderId,
    required this.dispatchId,
    required this.createdAt,
  });

  final String orderId;
  final String dispatchId;

  /// The EDIT's server creation instant (the payload's `created_at`).
  final DateTime createdAt;
}

/// ORDER-EDIT-001F — the idempotent LOCAL SUPERSESSION sweep: the VOID sweep
/// ([reconcileLocalVoidEvidence], semantics unchanged) followed by the ORDERED
/// order-edit sweep ([reconcileOrderEditEvidence]).
///
/// Order-edit evidence = every UNRESOLVED `order_edit` job of this scope (its
/// creation time read from its own decrypted payload) plus [externalEdits]
/// (this till's direct prints). Undecryptable evidence is no evidence.
///
/// The two sweeps are counted apart so the run report keeps the VOID numbers
/// it always had.
Future<({int voidSuperseded, int voidLinks, int editSuperseded, int editLinks})>
reconcileLocalSupersessionEvidence(
  KitchenSpoolStore store, {
  required KitchenSpoolCipher cipher,
  required SecretValue key,
  required String deviceId,
  required String branchId,
  required DateTime now,
  List<KitchenEditSupersessionEvidence> externalEdits = const [],
}) async {
  final voids = await reconcileLocalVoidEvidence(
    store,
    deviceId: deviceId,
    branchId: branchId,
    now: now,
  );
  final unresolved = await store.listUnresolved(
    deviceId: deviceId,
    branchId: branchId,
  );
  final evidence = <KitchenEditSupersessionEvidence>[
    for (final e in externalEdits)
      if (e.orderId.isNotEmpty && e.dispatchId.isNotEmpty) e,
  ];
  for (final row in unresolved) {
    if (row.dispatchType != KitchenSpoolDispatchType.orderEdit) continue;
    final createdAt = await kitchenJobPayloadCreatedAt(
      row,
      cipher: cipher,
      key: key,
    );
    if (createdAt == null) continue; // undecryptable: no evidence
    evidence.add(
      KitchenEditSupersessionEvidence(
        orderId: row.orderId,
        dispatchId: row.dispatchId,
        createdAt: createdAt,
      ),
    );
  }
  final edits = await reconcileOrderEditEvidence(
    store,
    evidence,
    cipher: cipher,
    key: key,
    deviceId: deviceId,
    branchId: branchId,
    now: now,
  );
  return (
    voidSuperseded: voids.superseded,
    voidLinks: voids.links,
    editSuperseded: edits.superseded,
    editLinks: edits.links,
  );
}

/// ORDER-EDIT-001F — the ORDERED order-edit sweep (decision D4).
///
/// Unlike a VOID, an edit does NOT end its order: a service round added AFTER
/// the edit must still print. On a till that did not make the edit, that
/// newer round can even be imported BEFORE the edit's dispatch (the acting
/// till holds the edit's claim for its lease). So each piece of [evidence]
/// supersedes only the jobs it is NEWER than, by SERVER creation order:
///
///  * an `initial_order` job of the same order — always (an order's initial
///    ticket is older than any edit of it);
///  * a `service_round` or `order_edit` job of the same order — only when its
///    decrypted payload `created_at` (the round's, the edit's) is STRICTLY
///    earlier than the evidence. A tie, or a payload that cannot be read,
///    KEEPS the job (never guess toward dropping kitchen paper);
///  * a `void` job — never;
///  * a `possiblyPrinted` job keeps its ambiguity and only gains the link; a
///    job PRINTING right now and resolved history are left alone (the store's
///    own transition rules);
///  * other orders and other scopes are untouched.
///
/// The link written is the evidence's dispatch id. Idempotent.
///
/// RISK R-002 residual: `created_at` is the server transaction's start, so two
/// tills racing in the same instant could order a round and an edit wrongly
/// here; the server's own supersession stays authoritative.
Future<({int superseded, int links})> reconcileOrderEditEvidence(
  KitchenSpoolStore store,
  List<KitchenEditSupersessionEvidence> evidence, {
  required KitchenSpoolCipher cipher,
  required SecretValue key,
  required String deviceId,
  required String branchId,
  required DateTime now,
}) async {
  var superseded = 0, links = 0;
  if (evidence.isEmpty) return (superseded: 0, links: 0);
  final unresolved = await store.listUnresolved(
    deviceId: deviceId,
    branchId: branchId,
  );
  // Each job's payload is decrypted at most once per sweep.
  final createdAtCache = <String, DateTime?>{};
  for (final e in evidence) {
    for (final prior in unresolved) {
      if (prior.orderId != e.orderId) continue;
      if (prior.dispatchId == e.dispatchId) continue;
      final bool older;
      switch (prior.dispatchType) {
        case KitchenSpoolDispatchType.voidNotice:
          continue;
        case KitchenSpoolDispatchType.initialOrder:
          older = true;
        case KitchenSpoolDispatchType.serviceRound:
        case KitchenSpoolDispatchType.orderEdit:
          if (!createdAtCache.containsKey(prior.localJobId)) {
            createdAtCache[prior.localJobId] = await kitchenJobPayloadCreatedAt(
              prior,
              cipher: cipher,
              key: key,
            );
          }
          final created = createdAtCache[prior.localJobId];
          older = created != null && created.isBefore(e.createdAt);
      }
      if (!older) continue;
      if (prior.status == KitchenSpoolJobStatus.possiblyPrinted) {
        if (await store.linkSupersessionEvidence(
          dispatchId: prior.dispatchId,
          supersededByDispatchId: e.dispatchId,
          now: now,
        )) {
          links++;
        }
      } else if (await store.markSupersededFromServerEvidence(
        dispatchId: prior.dispatchId,
        supersededByDispatchId: e.dispatchId,
        now: now,
      )) {
        superseded++;
      }
    }
  }
  return (superseded: superseded, links: links);
}

/// The SERVER creation instant carried by [job]'s encrypted payload
/// (`created_at`: the order's for an initial ticket, the round's for a
/// service round, the edit's for an `order_edit`), decrypted under the
/// canonical AAD rebuilt from the DURABLE row. Null when it cannot be read —
/// wrong key, tampered blob, malformed payload, or no `created_at`.
Future<DateTime?> kitchenJobPayloadCreatedAt(
  KitchenSpoolJobRow job, {
  required KitchenSpoolCipher cipher,
  required SecretValue key,
}) async {
  try {
    final clear = await cipher.decrypt(
      envelope: job.encryptedPayloadBlob,
      aad: KitchenSpoolAad(
        dispatchId: job.dispatchId,
        organizationId: job.organizationId,
        restaurantId: job.restaurantId,
        branchId: job.branchId,
        deviceId: job.deviceId,
        encryptionVersion: job.encryptionVersion,
      ),
      key: key,
    );
    final created = KitchenSpoolLocalPayload.fromBytes(
      clear,
    ).dispatch.createdAt;
    return created == null ? null : DateTime.tryParse(created);
  } on Object {
    return null;
  }
}
