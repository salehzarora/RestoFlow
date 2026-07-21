import 'dart:convert' show utf8;
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2A §10 + 001C2C PASS-1 — the bounded KitchenSpoolStore
/// invariants: the queued claim state machine, atomic transition+ack
/// writes, and the widened destination single-flight.
void main() {
  late KitchenSpoolDatabase db;
  late DriftKitchenSpoolStore store;
  late AesGcmKitchenSpoolCipher cipher;
  late SecretValue key;

  const orgId = 'a0000000-0000-0000-0000-00000000000a';
  const restId = 'a1000000-0000-0000-0000-00000000000a';
  const branchId = 'b1000000-0000-0000-0000-00000000000b';
  const deviceId = 'de000000-0000-0000-0000-00000000000d';
  const otherBranch = 'b2000000-0000-0000-0000-00000000000b';
  const otherDevice = 'df000000-0000-0000-0000-00000000000d';

  final t0 = DateTime.utc(2026, 7, 20, 10);
  final t1 = DateTime.utc(2026, 7, 20, 10, 1);
  final t2 = DateTime.utc(2026, 7, 20, 10, 2);

  setUp(() async {
    db = KitchenSpoolDatabase(NativeDatabase.memory());
    store = DriftKitchenSpoolStore(db);
    cipher = AesGcmKitchenSpoolCipher();
    final keyStore = InMemorySecureKeyStore();
    final manager = KitchenSpoolKeyManager(keyStore);
    await manager.provisionKey();
    key = (await manager.readKey())!;
  });

  tearDown(() => db.close());

  Future<Uint8List> encryptedPayload(
    String dispatchId, {
    String customer = 'Layla',
    String host = '10.0.0.5',
  }) async {
    final payload = KitchenSpoolLocalPayload(
      dispatch: KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#AB12CD',
        orderType: 'dine_in',
        customerDisplayName: customer,
        items: [
          KitchenDispatchItem(
            qty: 2,
            name: 'Falafel Deluxe',
            modifiers: [KitchenDispatchModifier(qty: 1, name: 'Extra pickles')],
          ),
        ],
      ),
      destination: NetworkKitchenDestination(host: host, port: 9100),
      paperWidth: '80mm',
      documentVersion: 1,
      rasterVersion: 1,
    );
    return cipher.encrypt(
      plaintext: payload.toBytes(),
      aad: KitchenSpoolAad(
        dispatchId: dispatchId,
        organizationId: orgId,
        restaurantId: restId,
        branchId: branchId,
        deviceId: deviceId,
        encryptionVersion: cipher.encryptionVersion,
      ),
      key: key,
    );
  }

  var jobSeq = 0;
  Future<NewKitchenSpoolJob> newJob(
    String dispatchId, {
    String? localJobId,
    KitchenSpoolJobStatus initialStatus = KitchenSpoolJobStatus.imported,
    String? destinationFingerprint = 'fp-default',
    String? displayLabel = 'Kitchen Printer',
    String branch = branchId,
    String device = deviceId,
    DateTime? createdAt,
  }) async {
    jobSeq += 1;
    return NewKitchenSpoolJob(
      localJobId: localJobId ?? 'job-$jobSeq',
      dispatchId: dispatchId,
      organizationId: orgId,
      restaurantId: restId,
      branchId: branch,
      deviceId: device,
      orderId: 'ord-1',
      dispatchType: KitchenSpoolDispatchType.initialOrder,
      initialStatus: initialStatus,
      encryptedPayloadBlob: await encryptedPayload(dispatchId),
      encryptionVersion: cipher.encryptionVersion,
      destinationFingerprint: destinationFingerprint,
      destinationDisplayLabel: displayLabel,
      transportKind: 'network',
      paperWidth: '80mm',
      payloadVersion: 1,
      documentVersion: 1,
      rasterVersion: 1,
      createdAt: createdAt ?? t0.add(Duration(seconds: jobSeq)),
    );
  }

  /// KITCHEN-MODE-001C2B: imports AND completes the server acknowledgement,
  /// satisfying the print-eligibility invariant (only server-acknowledged
  /// jobs may ever become runnable).
  Future<KitchenSpoolJobRow> importAcked(NewKitchenSpoolJob job) async {
    final row = await store.insertImportedJob(job);
    await store.setPendingServerAck(
      row.localJobId,
      KitchenServerAckStatus.imported,
      t0,
    );
    await store.markServerAcked(row.localJobId, t0);
    return (await store.getByLocalJobId(row.localJobId))!;
  }

  /// KITCHEN-MODE-001C2C: THE atomic claim (runnable -> queued) with this
  /// fixture's scope tuple.
  Future<KitchenSpoolJobRow?> claimQ(
    String localJobId,
    DateTime now, {
    String branch = branchId,
    String device = deviceId,
  }) => store.claimRunnableForQueued(
    localJobId,
    organizationId: orgId,
    restaurantId: restId,
    branchId: branch,
    deviceId: device,
    now: now,
  );

  /// The worker's two-step path: atomic claim to queued, then printing
  /// immediately before the transport boundary.
  Future<bool> claimToPrinting(String localJobId, DateTime now) async {
    if (await claimQ(localJobId, now) == null) return false;
    return store.markPrinting(localJobId, now);
  }

  group('import', () {
    test('unique dispatch import + idempotent duplicate', () async {
      final a = await store.insertImportedJob(await newJob('disp-1'));
      final dup = await store.insertImportedJob(
        await newJob('disp-1', localJobId: 'job-other'),
      );
      expect(dup.localJobId, a.localJobId, reason: 'returns the ORIGINAL');
      expect(dup.status, KitchenSpoolJobStatus.imported);
      final all = await store.listUnresolved(
        deviceId: deviceId,
        branchId: branchId,
      );
      expect(all, hasLength(1));
    });

    test('an import may only start as imported or blockedConfiguration', () {
      expect(
        () => NewKitchenSpoolJob(
          localJobId: 'x',
          dispatchId: 'd',
          organizationId: orgId,
          restaurantId: restId,
          branchId: branchId,
          deviceId: deviceId,
          orderId: 'o',
          dispatchType: KitchenSpoolDispatchType.initialOrder,
          initialStatus: KitchenSpoolJobStatus.printing,
          encryptedPayloadBlob: Uint8List.fromList([1]),
          encryptionVersion: 1,
          payloadVersion: 1,
          documentVersion: 1,
          rasterVersion: 1,
          createdAt: t0,
        ),
        throwsArgumentError,
      );
    });

    test('missing-printer import: blockedConfiguration with NO destination '
        'still preserves the authoritative encrypted payload', () async {
      final row = await store.insertImportedJob(
        await newJob(
          'disp-blocked',
          initialStatus: KitchenSpoolJobStatus.blockedConfiguration,
          destinationFingerprint: null,
          displayLabel: null,
        ),
      );
      expect(row.status, KitchenSpoolJobStatus.blockedConfiguration);
      expect(row.destinationFingerprint, isNull);
      expect(row.encryptedPayloadBlob, isNotEmpty);
      // Never runnable while blocked; never claimable.
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(await claimQ(row.localJobId, t0), isNull);
    });

    test('destination display label is normalized before storage', () async {
      final row = await store.insertImportedJob(
        await newJob('disp-label', displayLabel: 'EPSON 10.0.0.5:9100'),
      );
      expect(row.destinationDisplayLabel, 'kitchen-printer');
    });
  });

  group('runnable + claim (001C2C LOCKED DECISION 1)', () {
    test(
      'runnable ordering is createdAt asc and respects nextAttemptAt',
      () async {
        final a = await importAcked(await newJob('d-a'));
        final b = await importAcked(await newJob('d-b'));
        final list = await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(minutes: 5)),
        );
        expect(list.map((r) => r.localJobId), [a.localJobId, b.localJobId]);
        // A future retry gate hides the job until due: claim, enter the
        // transport boundary, prove definitely-not-sent, and re-acknowledge.
        expect(await claimToPrinting(a.localJobId, t1), isTrue);
        expect(
          await store.markFailedRetryableWithAck(
            a.localJobId,
            errorCode: 'printer_unreachable',
            nextAttemptAt: t0.add(const Duration(minutes: 30)),
            now: t1,
          ),
          isTrue,
        );
        await store.markServerAcked(a.localJobId, t1);
        final gated = await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(minutes: 10)),
        );
        expect(gated.map((r) => r.localJobId), [b.localJobId]);
        final afterDue = await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(minutes: 31)),
        );
        expect(afterDue.map((r) => r.localJobId), [a.localJobId, b.localJobId]);
      },
    );

    test('the claim moves runnable -> QUEUED (never directly printing), '
        'bookkeeping exactly once', () async {
      final row = await importAcked(await newJob('d-claim'));
      final claimed = await claimQ(row.localJobId, t1);
      expect(claimed, isNotNull);
      expect(claimed!.status, KitchenSpoolJobStatus.queued);
      expect(claimed.attemptCount, 1);
      expect(claimed.lastAttemptAt, t1);
    });

    test('a SAME-INSTANT duplicate claim has exactly one winner', () async {
      final row = await importAcked(await newJob('d-dup'));
      final first = await claimQ(row.localJobId, t1);
      expect(first, isNotNull);
      final second = await claimQ(row.localJobId, t1);
      expect(second, isNull, reason: 'one winner per instant');
      expect(
        (await store.getByLocalJobId(row.localJobId))!.attemptCount,
        1,
        reason: 'attemptCount incremented exactly once',
      );
    });

    test('a stale QUEUED row is reclaimable by a strictly LATER claim '
        '(restart recovery), counting a fresh attempt', () async {
      final row = await importAcked(await newJob('d-requeue'));
      expect(await claimQ(row.localJobId, t1), isNotNull);
      // Simulated restart: the row is still queued; a later claim adopts it.
      final reclaimed = await claimQ(row.localJobId, t2);
      expect(reclaimed, isNotNull);
      expect(reclaimed!.status, KitchenSpoolJobStatus.queued);
      expect(reclaimed.attemptCount, 2);
    });

    test('claim requires the FULL matching scope tuple', () async {
      final row = await importAcked(await newJob('d-scope'));
      expect(
        await claimQ(row.localJobId, t1, branch: otherBranch),
        isNull,
        reason: 'wrong branch',
      );
      expect(
        await claimQ(row.localJobId, t1, device: otherDevice),
        isNull,
        reason: 'wrong device',
      );
      expect(await claimQ(row.localJobId, t1), isNotNull);
    });

    test('destination single-flight blocks on QUEUED and PRINTING holders '
        '(the widened predicate)', () async {
      final a = await importAcked(
        await newJob('d-dest-a', destinationFingerprint: 'fp-shared'),
      );
      final b = await importAcked(
        await newJob('d-dest-b', destinationFingerprint: 'fp-shared'),
      );
      final c = await importAcked(
        await newJob('d-dest-c', destinationFingerprint: 'fp-other'),
      );
      // A is QUEUED (not yet printing) — and that ALREADY blocks B.
      expect(await claimQ(a.localJobId, t0), isNotNull);
      expect(
        await claimQ(b.localJobId, t0),
        isNull,
        reason: 'queued holder blocks the destination',
      );
      // A different destination is unaffected.
      expect(await claimQ(c.localJobId, t0), isNotNull);
      // A printing holder blocks too.
      expect(await store.markPrinting(a.localJobId, t0), isTrue);
      expect(await claimQ(b.localJobId, t1), isNull);
      // Once A resolves (atomic transition+ack), B becomes claimable.
      expect(
        await store.markTransportAcceptedWithAck(
          a.localJobId,
          t0.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
      expect(await claimQ(b.localJobId, t2), isNotNull);
    });

    test('a row never blocks ITSELF on the destination check', () async {
      final row = await importAcked(
        await newJob('d-self', destinationFingerprint: 'fp-self'),
      );
      expect(await claimQ(row.localJobId, t1), isNotNull);
      // Reclaim later: its own queued state must not refuse the claim.
      expect(await claimQ(row.localJobId, t2), isNotNull);
    });

    test(
      'markPrinting is queued-ONLY and refuses every other source',
      () async {
        final row = await importAcked(await newJob('d-mp'));
        // imported -> printing is forbidden (no bypass around the claim).
        expect(await store.markPrinting(row.localJobId, t0), isFalse);
        expect(await claimQ(row.localJobId, t1), isNotNull);
        expect(await store.markPrinting(row.localJobId, t1), isTrue);
        // printing -> printing is refused.
        expect(await store.markPrinting(row.localJobId, t1), isFalse);
        final failed = await importAcked(
          await newJob('d-mp2', destinationFingerprint: 'fp-mp2'),
        );
        expect(await claimToPrinting(failed.localJobId, t1), isTrue);
        await store.markFailedRetryableWithAck(
          failed.localJobId,
          errorCode: 'printer_unreachable',
          nextAttemptAt: t2,
          now: t1,
        );
        // failedRetryable -> printing is forbidden without a fresh claim.
        expect(await store.markPrinting(failed.localJobId, t2), isFalse);
      },
    );
  });

  group('atomic transition+ack (001C2C)', () {
    test('transportAccepted + pending transport_accepted are ONE write; the '
        'pending status always describes row.status', () async {
      final row = await importAcked(await newJob('d-taw'));
      // Only printing may complete.
      expect(
        await store.markTransportAcceptedWithAck(row.localJobId, t0),
        isFalse,
      );
      expect(await claimToPrinting(row.localJobId, t1), isTrue);
      expect(
        await store.markTransportAcceptedWithAck(row.localJobId, t1),
        isTrue,
      );
      final done = (await store.getByLocalJobId(row.localJobId))!;
      expect(done.status, KitchenSpoolJobStatus.transportAccepted);
      expect(done.transportAcceptedAt, t1);
      expect(
        done.pendingServerAckStatus,
        KitchenServerAckStatus.transportAccepted,
      );
      expect(done.serverAckNextAttemptAt, t1);
      expect(done.lastErrorCode, isNull);
      expect(done.nextAttemptAt, isNull);
    });

    test('failedRetryable + pending failed_retryable + retry time are ONE '
        'write, from printing OR queued', () async {
      // From printing (post-boundary definitely-not-sent).
      final a = await importAcked(await newJob('d-frw-a'));
      expect(await claimToPrinting(a.localJobId, t1), isTrue);
      expect(
        await store.markFailedRetryableWithAck(
          a.localJobId,
          errorCode: 'printer_unreachable',
          nextAttemptAt: t2,
          now: t1,
        ),
        isTrue,
      );
      final failedA = (await store.getByLocalJobId(a.localJobId))!;
      expect(failedA.status, KitchenSpoolJobStatus.failedRetryable);
      expect(
        failedA.pendingServerAckStatus,
        KitchenServerAckStatus.failedRetryable,
      );
      expect(failedA.nextAttemptAt, t2);
      expect(failedA.lastErrorCode, 'printer_unreachable');
      // From queued (pre-boundary failure that is retryable).
      final b = await importAcked(await newJob('d-frw-b'));
      expect(await claimQ(b.localJobId, t1), isNotNull);
      expect(
        await store.markFailedRetryableWithAck(
          b.localJobId,
          errorCode: 'printer_unreachable',
          nextAttemptAt: t2,
          now: t1,
        ),
        isTrue,
      );
      // From imported: forbidden.
      final c = await importAcked(await newJob('d-frw-c'));
      expect(
        await store.markFailedRetryableWithAck(
          c.localJobId,
          errorCode: 'printer_unreachable',
          nextAttemptAt: t2,
          now: t1,
        ),
        isFalse,
      );
    });

    test('possiblyPrinted + pending possibly_printed are ONE write, from '
        'printing only, preserving destination + payload', () async {
      final row = await importAcked(await newJob('d-ppw'));
      expect(
        await store.markPossiblyPrintedWithAck(row.localJobId, t1),
        isFalse,
      );
      expect(await claimToPrinting(row.localJobId, t1), isTrue);
      expect(
        await store.markPossiblyPrintedWithAck(row.localJobId, t1),
        isTrue,
      );
      final held = (await store.getByLocalJobId(row.localJobId))!;
      expect(held.status, KitchenSpoolJobStatus.possiblyPrinted);
      expect(
        held.pendingServerAckStatus,
        KitchenServerAckStatus.possiblyPrinted,
      );
      expect(held.nextAttemptAt, isNull, reason: 'no automatic retry');
      expect(held.destinationFingerprint, 'fp-default');
      expect(held.encryptedPayloadBlob, isNotEmpty);
    });

    test('blockedConfiguration + pending blocked_configuration are ONE '
        'write, from QUEUED only (pre-transport, zero paper risk)', () async {
      final row = await importAcked(await newJob('d-bcw'));
      expect(
        await store.markBlockedConfigurationWithAck(
          row.localJobId,
          errorCode: 'kitchen_payload_undecryptable',
          now: t1,
        ),
        isFalse,
        reason: 'imported may not blocked-transition here',
      );
      expect(await claimQ(row.localJobId, t1), isNotNull);
      expect(
        await store.markBlockedConfigurationWithAck(
          row.localJobId,
          errorCode: 'kitchen_payload_undecryptable',
          now: t1,
        ),
        isTrue,
      );
      final blocked = (await store.getByLocalJobId(row.localJobId))!;
      expect(blocked.status, KitchenSpoolJobStatus.blockedConfiguration);
      expect(
        blocked.pendingServerAckStatus,
        KitchenServerAckStatus.blockedConfiguration,
      );
      expect(blocked.lastErrorCode, 'kitchen_payload_undecryptable');
      // From printing: forbidden (past the boundary it is never "blocked").
      final p = await importAcked(await newJob('d-bcw2'));
      expect(await claimToPrinting(p.localJobId, t1), isTrue);
      expect(
        await store.markBlockedConfigurationWithAck(
          p.localJobId,
          errorCode: 'kitchen_payload_undecryptable',
          now: t1,
        ),
        isFalse,
      );
    });

    test('a forced SQL CHECK failure proves NO half-transition (status and '
        'pending move together or not at all)', () async {
      final row = await importAcked(await newJob('d-atomic'));
      expect(await claimToPrinting(row.localJobId, t1), isTrue);
      // Sabotage: a printing row with transport_accepted_at set violates the
      // possibly_printed CHECK the moment the transition tries to commit.
      await db.customStatement(
        "UPDATE kitchen_spool_jobs SET transport_accepted_at = '2026-07-20T10:00:00.000Z' "
        "WHERE local_job_id = '${row.localJobId}'",
      );
      await expectLater(
        store.markPossiblyPrintedWithAck(row.localJobId, t1),
        throwsA(anything),
      );
      final after = (await store.getByLocalJobId(row.localJobId))!;
      expect(
        after.status,
        KitchenSpoolJobStatus.printing,
        reason: 'status unchanged',
      );
      expect(
        after.pendingServerAckStatus,
        isNull,
        reason: 'no orphaned pending acknowledgement',
      );
    });

    test('recovery maps ONLY stale printing rows IN SCOPE to possiblyPrinted '
        'WITH the pending ack, idempotently', () async {
      final printing = await importAcked(await newJob('d-p1'));
      expect(await claimToPrinting(printing.localJobId, t0), isTrue);
      final queued = await importAcked(
        await newJob('d-p2', destinationFingerprint: 'fp-p2'),
      );
      expect(await claimQ(queued.localJobId, t0), isNotNull);
      final foreign = await importAcked(
        await newJob(
          'd-p3',
          device: otherDevice,
          destinationFingerprint: 'fp-p3',
        ),
      );
      expect(
        await claimQ(foreign.localJobId, t0, device: otherDevice),
        isNotNull,
      );
      expect(await store.markPrinting(foreign.localJobId, t0), isTrue);
      final changed = await store.markPossiblyPrintedOnRecoveryWithAck(
        deviceId: deviceId,
        branchId: branchId,
        now: t1,
      );
      expect(changed, 1);
      final recovered = (await store.getByLocalJobId(printing.localJobId))!;
      expect(recovered.status, KitchenSpoolJobStatus.possiblyPrinted);
      expect(
        recovered.pendingServerAckStatus,
        KitchenServerAckStatus.possiblyPrinted,
        reason: 'the owed ack is set IN the recovery update',
      );
      expect(
        (await store.getByLocalJobId(queued.localJobId))!.status,
        KitchenSpoolJobStatus.queued,
      );
      expect(
        (await store.getByLocalJobId(foreign.localJobId))!.status,
        KitchenSpoolJobStatus.printing,
        reason: 'out-of-scope printing rows are untouched',
      );
      // Idempotent: a second sweep changes nothing.
      expect(
        await store.markPossiblyPrintedOnRecoveryWithAck(
          deviceId: deviceId,
          branchId: branchId,
          now: t2,
        ),
        0,
      );
    });
  });

  group('terminal + recovery invariants', () {
    test('possiblyPrinted can NEVER become runnable again', () async {
      final row = await importAcked(await newJob('d-pp'));
      expect(await claimToPrinting(row.localJobId, t0), isTrue);
      await store.markPossiblyPrintedOnRecoveryWithAck(
        deviceId: deviceId,
        branchId: branchId,
        now: t0,
      );
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 30)),
        ),
        isEmpty,
      );
      expect(await claimQ(row.localJobId, t1), isNull);
      expect(await store.markPrinting(row.localJobId, t1), isFalse);
      // Still unresolved (needs an operator), never silently dropped.
      expect(
        await store.countUnresolved(deviceId: deviceId, branchId: branchId),
        1,
      );
    });

    test('transportAccepted is terminal and never re-runnable, even while '
        'its acknowledgement retries', () async {
      final row = await importAcked(await newJob('d-ta'));
      expect(await claimToPrinting(row.localJobId, t0), isTrue);
      expect(
        await store.markTransportAcceptedWithAck(row.localJobId, t0),
        isTrue,
      );
      final done = (await store.getByLocalJobId(row.localJobId))!;
      expect(done.status, KitchenSpoolJobStatus.transportAccepted);
      expect(done.transportAcceptedAt, isNotNull);
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(await claimQ(row.localJobId, t1), isNull);
    });

    test(
      'superseded comes ONLY from server evidence and is terminal',
      () async {
        final row = await store.insertImportedJob(await newJob('d-sup'));
        final ok = await store.markSupersededFromServerEvidence(
          dispatchId: 'd-sup',
          supersededByDispatchId: 'void-disp-9',
          now: t0,
        );
        expect(ok, isTrue);
        final sup = (await store.getByLocalJobId(row.localJobId))!;
        expect(sup.status, KitchenSpoolJobStatus.superseded);
        expect(sup.supersededByDispatchId, 'void-disp-9');
        expect(await claimQ(row.localJobId, t1), isNull);
        expect(await store.markPrinting(row.localJobId, t1), isFalse);
        // Resolved: no longer counted as unresolved.
        expect(
          await store.countUnresolved(deviceId: deviceId, branchId: branchId),
          0,
        );
      },
    );

    test(
      'server evidence supersedes a QUEUED job (it stops printing), but '
      'never transportAccepted history or a job printing right now',
      () async {
        final queued = await importAcked(await newJob('d-q-sup'));
        expect(await claimQ(queued.localJobId, t0), isNotNull);
        expect(
          await store.markSupersededFromServerEvidence(
            dispatchId: 'd-q-sup',
            supersededByDispatchId: 'void-1',
            now: t0,
          ),
          isTrue,
        );
        // A superseded queued row can no longer enter the transport boundary.
        expect(await store.markPrinting(queued.localJobId, t1), isFalse);

        final done = await importAcked(await newJob('d-done'));
        expect(await claimToPrinting(done.localJobId, t0), isTrue);
        await store.markTransportAcceptedWithAck(done.localJobId, t0);
        expect(
          await store.markSupersededFromServerEvidence(
            dispatchId: 'd-done',
            supersededByDispatchId: 'void-1',
            now: t0,
          ),
          isFalse,
        );
        final printing = await importAcked(await newJob('d-mid'));
        expect(await claimToPrinting(printing.localJobId, t0), isTrue);
        expect(
          await store.markSupersededFromServerEvidence(
            dispatchId: 'd-mid',
            supersededByDispatchId: 'void-1',
            now: t0,
          ),
          isFalse,
        );
      },
    );

    test('a TERMINAL server verdict can never be cleared by print-state '
        'transitions and blocks every claim', () async {
      final row = await store.insertImportedJob(await newJob('d-term-keep'));
      await store.setPendingServerAck(
        row.localJobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      await store.markServerAckTerminal(
        row.localJobId,
        terminalCode: 'not_claim_owner',
        now: t0,
      );
      expect(await claimQ(row.localJobId, t1), isNull);
      expect(await store.markPrinting(row.localJobId, t1), isFalse);
      final after = (await store.getByLocalJobId(row.localJobId))!;
      expect(after.serverAckTerminalCode, 'not_claim_owner');
      expect(after.encryptedPayloadBlob, isNotEmpty);
    });
  });

  group('server acknowledgement independence', () {
    test('pending ack is retained independently; ack retries NEVER make a '
        'transportAccepted job runnable again', () async {
      final row = await importAcked(await newJob('d-ack'));
      expect(await claimToPrinting(row.localJobId, t0), isTrue);
      // The atomic transition sets the pending ack itself.
      expect(
        await store.markTransportAcceptedWithAck(row.localJobId, t0),
        isTrue,
      );
      // Two failed ack attempts.
      for (var i = 1; i <= 2; i++) {
        expect(
          await store.updateServerAckRetry(
            row.localJobId,
            errorCode: 'network_unreachable',
            nextAttemptAt: t0.add(Duration(minutes: i * 5)),
            now: t0.add(Duration(minutes: i)),
          ),
          isTrue,
        );
      }
      final pending = (await store.getByLocalJobId(row.localJobId))!;
      expect(pending.status, KitchenSpoolJobStatus.transportAccepted);
      expect(
        pending.pendingServerAckStatus,
        KitchenServerAckStatus.transportAccepted,
      );
      expect(pending.serverAckAttemptCount, 2);
      expect(pending.attemptCount, 1, reason: 'print attempts untouched');
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 1)),
        ),
        isEmpty,
        reason: 'ack failure never re-queues the PRINT',
      );
      // Ack completes -> pending cleared, timestamps stamped.
      expect(await store.markServerAcked(row.localJobId, t0), isTrue);
      final acked = (await store.getByLocalJobId(row.localJobId))!;
      expect(acked.pendingServerAckStatus, isNull);
      expect(acked.serverAcknowledgedAt, isNotNull);
      // markServerAcked is conditional on a pending ack existing.
      expect(await store.markServerAcked(row.localJobId, t0), isFalse);
    });
  });

  group('scope + counting', () {
    test('unresolved count and listings are device/branch scoped', () async {
      await importAcked(await newJob('d-s1'));
      await store.insertImportedJob(await newJob('d-s2', branch: otherBranch));
      await store.insertImportedJob(await newJob('d-s3', device: otherDevice));
      expect(
        await store.countUnresolved(deviceId: deviceId, branchId: branchId),
        1,
      );
      expect(
        await store.listUnresolved(deviceId: deviceId, branchId: branchId),
        hasLength(1),
      );
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(minutes: 5)),
        ),
        hasLength(1),
      );
    });
  });

  group('retention', () {
    test('prune removes ONLY fully server-acked transportAccepted history '
        'older than the cutoff', () async {
      // Fully resolved + old -> prunable.
      final old = await importAcked(await newJob('d-old'));
      expect(await claimToPrinting(old.localJobId, t0), isTrue);
      await store.markTransportAcceptedWithAck(old.localJobId, t0);
      await store.markServerAcked(old.localJobId, t0);
      // Accepted but ack still pending -> NOT prunable.
      final pendingAck = await importAcked(await newJob('d-pa'));
      expect(await claimToPrinting(pendingAck.localJobId, t0), isTrue);
      await store.markTransportAcceptedWithAck(pendingAck.localJobId, t0);
      // possiblyPrinted -> NEVER prunable.
      final ambiguous = await importAcked(await newJob('d-amb'));
      expect(await claimToPrinting(ambiguous.localJobId, t0), isTrue);
      await store.markPossiblyPrintedWithAck(ambiguous.localJobId, t0);
      // blocked -> NEVER prunable.
      await store.insertImportedJob(
        await newJob(
          'd-blk',
          initialStatus: KitchenSpoolJobStatus.blockedConfiguration,
          destinationFingerprint: null,
        ),
      );

      final pruned = await store.pruneTransportAcceptedOlderThan(
        t0.add(const Duration(days: 30)),
      );
      expect(pruned, 1);
      expect(await store.getByLocalJobId(old.localJobId), isNull);
      expect(await store.getByLocalJobId(pendingAck.localJobId), isNotNull);
      expect(await store.getByLocalJobId(ambiguous.localJobId), isNotNull);
      expect(
        await store.countUnresolvedTotal(),
        2, // ambiguous + blocked stay unresolved; pendingAck is resolved.
      );
    });
  });

  group('plaintext hygiene', () {
    test('the stored blob is ciphertext (no known plaintext fixture strings) '
        'and NO plaintext column carries payload/endpoint data', () async {
      final row = await store.insertImportedJob(
        await newJob('d-hyg', displayLabel: 'Pass-through label'),
      );
      final blobText = String.fromCharCodes(row.encryptedPayloadBlob);
      for (final needle in [
        'Falafel Deluxe',
        'Layla',
        'Extra pickles',
        '10.0.0.5',
        '9100',
        'kitchen_ticket',
      ]) {
        expect(blobText, isNot(contains(needle)));
      }
      // Every PLAINTEXT column value, checked against payload + endpoint
      // fixtures (IDs/enums/labels only by contract).
      final plaintextValues = <String?>[
        row.localJobId,
        row.dispatchId,
        row.organizationId,
        row.restaurantId,
        row.branchId,
        row.deviceId,
        row.orderId,
        row.serviceRoundId,
        row.dispatchType.wireName,
        row.status.wireName,
        row.destinationFingerprint,
        row.destinationDisplayLabel,
        row.transportKind,
        row.paperWidth,
        row.lastErrorCode,
        row.pendingServerAckStatus?.wireName,
        row.serverAckLastErrorCode,
        row.reprintOfLocalJobId,
        row.supersededByDispatchId,
      ];
      for (final value in plaintextValues.whereType<String>()) {
        expect(value, isNot(contains('10.0.0.5')));
        expect(value, isNot(contains('Falafel')));
        expect(value, isNot(contains('Layla')));
        expect(value.contains(RegExp(r'\d+\.\d+\.\d+\.\d+')), isFalse);
      }
      // And the decrypted round trip still works (the data is IN the blob).
      final clear = await cipher.decrypt(
        envelope: Uint8List.fromList(row.encryptedPayloadBlob),
        aad: KitchenSpoolAad(
          dispatchId: row.dispatchId,
          organizationId: row.organizationId,
          restaurantId: row.restaurantId,
          branchId: row.branchId,
          deviceId: row.deviceId,
          encryptionVersion: row.encryptionVersion,
        ),
        key: key,
      );
      expect(utf8.decode(clear), contains('Falafel Deluxe'));
    });
  });

  group('KITCHEN-MODE-001C2B print-eligibility + server evidence', () {
    test(
      'an imported-but-UNACKNOWLEDGED job can never become runnable',
      () async {
        final row = await store.insertImportedJob(await newJob('d-unacked'));
        expect(
          await store.listRunnable(
            deviceId: deviceId,
            branchId: branchId,
            now: t0.add(const Duration(days: 1)),
          ),
          isEmpty,
        );
        expect(await claimQ(row.localJobId, t1), isNull);
        expect(await store.markPrinting(row.localJobId, t1), isFalse);
      },
    );

    test('a TRANSIENT ack failure keeps the job non-runnable', () async {
      final row = await store.insertImportedJob(await newJob('d-transient'));
      await store.setPendingServerAck(
        row.localJobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      await store.updateServerAckRetry(
        row.localJobId,
        errorCode: 'network_unreachable',
        nextAttemptAt: t0.add(const Duration(minutes: 5)),
        now: t0,
      );
      expect(await claimQ(row.localJobId, t1), isNull);
      // Once the server acknowledges, the job becomes runnable.
      await store.markServerAcked(row.localJobId, t0);
      expect(await claimQ(row.localJobId, t1), isNotNull);
    });

    test('a TERMINAL server verdict stops retries and is permanently '
        'non-runnable while preserving the encrypted job', () async {
      final row = await store.insertImportedJob(await newJob('d-terminal'));
      await store.setPendingServerAck(
        row.localJobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      expect(
        await store.markServerAckTerminal(
          row.localJobId,
          terminalCode: 'not_claim_owner',
          now: t0,
        ),
        isTrue,
      );
      final after = (await store.getByLocalJobId(row.localJobId))!;
      expect(after.serverAckTerminalCode, 'not_claim_owner');
      expect(after.pendingServerAckStatus, isNull);
      expect(after.serverAcknowledgedAt, isNull);
      expect(after.encryptedPayloadBlob, isNotEmpty);
      // Retry loop is over; never runnable.
      expect(
        await store.listPendingServerAcks(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(await claimQ(row.localJobId, t1), isNull);
      // Terminal is one-shot: no pending ack remains to terminate.
      expect(
        await store.markServerAckTerminal(
          row.localJobId,
          terminalCode: 'conflict',
          now: t0,
        ),
        isFalse,
      );
    });

    test(
      'linkSupersessionEvidence keeps possiblyPrinted AMBIGUITY while '
      'attaching the void link; markSuperseded refuses possiblyPrinted',
      () async {
        final row = await importAcked(await newJob('d-pp-link'));
        expect(await claimToPrinting(row.localJobId, t0), isTrue);
        await store.markPossiblyPrintedWithAck(row.localJobId, t0);
        // The blunt supersession path must NOT erase the ambiguity.
        expect(
          await store.markSupersededFromServerEvidence(
            dispatchId: 'd-pp-link',
            supersededByDispatchId: 'void-9',
            now: t0,
          ),
          isFalse,
        );
        // The link path attaches evidence and PRESERVES the state.
        expect(
          await store.linkSupersessionEvidence(
            dispatchId: 'd-pp-link',
            supersededByDispatchId: 'void-9',
            now: t0,
          ),
          isTrue,
        );
        final linked = (await store.getByLocalJobId(row.localJobId))!;
        expect(linked.status, KitchenSpoolJobStatus.possiblyPrinted);
        expect(linked.supersededByDispatchId, 'void-9');
        // Idempotent: an existing link is never overwritten.
        expect(
          await store.linkSupersessionEvidence(
            dispatchId: 'd-pp-link',
            supersededByDispatchId: 'void-10',
            now: t0,
          ),
          isFalse,
        );
        expect(
          (await store.getByLocalJobId(row.localJobId))!.supersededByDispatchId,
          'void-9',
        );
      },
    );

    test('listPendingServerAcks honors due time and scope', () async {
      final due = await store.insertImportedJob(await newJob('d-ack-due'));
      await store.setPendingServerAck(
        due.localJobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      final later = await store.insertImportedJob(await newJob('d-ack-later'));
      await store.setPendingServerAck(
        later.localJobId,
        KitchenServerAckStatus.blockedConfiguration,
        t0,
      );
      await store.updateServerAckRetry(
        later.localJobId,
        errorCode: 'network_unreachable',
        nextAttemptAt: t0.add(const Duration(hours: 1)),
        now: t0,
      );
      final other = await store.insertImportedJob(
        await newJob('d-ack-other', branch: otherBranch),
      );
      await store.setPendingServerAck(
        other.localJobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      final pending = await store.listPendingServerAcks(
        deviceId: deviceId,
        branchId: branchId,
        now: t0.add(const Duration(minutes: 1)),
      );
      expect(pending.map((r) => r.localJobId), [due.localJobId]);
    });

    test('countTotalRows counts every scope (metadata only)', () async {
      expect(await store.countTotalRows(), 0);
      await store.insertImportedJob(await newJob('d-count-1'));
      await store.insertImportedJob(
        await newJob('d-count-2', branch: otherBranch),
      );
      expect(await store.countTotalRows(), 2);
    });
  });

  twoConnectionClaimTests();
}

// ---------------------------------------------------------------------------
// CLEANUP 7F — REAL two-connection SQLite claim safety. Two independent
// NativeDatabase connections open the SAME on-disk file; the destination
// single-flight guard must hold ACROSS connections (committed state is what
// the second connection sees). Genuinely in-flight cross-connection
// transactions are serialized by SQLite file locking (SQLITE_BUSY), which
// the current harness cannot exercise deterministically — that limitation is
// reported honestly in the phase report; the conditional-update correctness
// itself is what this proves cross-connection.
// ---------------------------------------------------------------------------
void twoConnectionClaimTests() {
  test('CLEANUP 7F: destination single-flight holds ACROSS two real SQLite '
      'connections to the same database file', () async {
    final dir = await Directory.systemTemp.createTemp('kmc2a_2conn');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/spool.sqlite');

    final db1 = KitchenSpoolDatabase(NativeDatabase(file));
    final db2 = KitchenSpoolDatabase(NativeDatabase(file));
    addTearDown(db1.close);
    addTearDown(db2.close);
    final store1 = DriftKitchenSpoolStore(db1);
    final store2 = DriftKitchenSpoolStore(db2);

    final t0 = DateTime.utc(2026, 7, 20, 12);
    final t1 = DateTime.utc(2026, 7, 20, 12, 1);
    Future<void> seed(String jobId, String dispatchId) =>
        store1.insertImportedJob(
          NewKitchenSpoolJob(
            localJobId: jobId,
            dispatchId: dispatchId,
            organizationId: 'org',
            restaurantId: 'rest',
            branchId: 'branch',
            deviceId: 'dev',
            orderId: 'ord',
            dispatchType: KitchenSpoolDispatchType.initialOrder,
            initialStatus: KitchenSpoolJobStatus.imported,
            encryptedPayloadBlob: Uint8List.fromList([1, 2, 3]),
            encryptionVersion: 1,
            destinationFingerprint: 'fp-shared-2conn',
            payloadVersion: 1,
            documentVersion: 1,
            rasterVersion: 1,
            createdAt: t0,
          ),
        );
    await seed('conn-job-a', 'conn-disp-a');
    await seed('conn-job-b', 'conn-disp-b');
    // Satisfy the 001C2B print-eligibility invariant for both jobs.
    for (final jobId in ['conn-job-a', 'conn-job-b']) {
      await store1.setPendingServerAck(
        jobId,
        KitchenServerAckStatus.imported,
        t0,
      );
      await store1.markServerAcked(jobId, t0);
    }

    Future<KitchenSpoolJobRow?> claim(
      DriftKitchenSpoolStore s,
      String jobId,
      DateTime now,
    ) => s.claimRunnableForQueued(
      jobId,
      organizationId: 'org',
      restaurantId: 'rest',
      branchId: 'branch',
      deviceId: 'dev',
      now: now,
    );

    // Connection 1 claims job A into QUEUED.
    final winner = await claim(store1, 'conn-job-a', t0);
    expect(winner, isNotNull);
    expect(winner!.status, KitchenSpoolJobStatus.queued);

    // Connection 2 — a SEPARATE SQLite connection — must observe the
    // committed claim and REFUSE job B on the same destination.
    final refused = await claim(store2, 'conn-job-b', t0);
    expect(refused, isNull, reason: 'cross-connection single-flight');

    // Never two queued/printing jobs on one destination, from either view.
    final holders =
        await (db2.select(db2.kitchenSpoolJobs)..where(
              (t) => t.status.isInValues(const [
                KitchenSpoolJobStatus.queued,
                KitchenSpoolJobStatus.printing,
              ]),
            ))
            .get();
    expect(holders, hasLength(1));

    // Winner resolves on connection 1 -> connection 2 can now claim B.
    expect(await store1.markPrinting('conn-job-a', t0), isTrue);
    expect(await store1.markTransportAcceptedWithAck('conn-job-a', t0), isTrue);
    final second = await claim(store2, 'conn-job-b', t1);
    expect(second, isNotNull);
    expect(second!.status, KitchenSpoolJobStatus.queued);
  });
}

extension on DriftKitchenSpoolStore {
  Future<int> countUnresolvedTotal() async {
    // Test-only helper: unresolved across ALL scopes in this small fixture.
    const orgDevice = 'de000000-0000-0000-0000-00000000000d';
    const orgBranch = 'b1000000-0000-0000-0000-00000000000b';
    return countUnresolved(deviceId: orgDevice, branchId: orgBranch);
  }
}
