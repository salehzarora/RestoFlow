import 'dart:convert' show utf8;
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_core/testing.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2A §10 — the bounded KitchenSpoolStore invariants.
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
      expect(await store.claimRunnableForPrinting(row.localJobId, t0), isNull);
    });

    test('destination display label is normalized before storage', () async {
      final row = await store.insertImportedJob(
        await newJob('disp-label', displayLabel: 'EPSON 10.0.0.5:9100'),
      );
      expect(row.destinationDisplayLabel, 'kitchen-printer');
    });
  });

  group('runnable + claim', () {
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
        // A future retry gate hides the job until due.
        await store.markFailedRetryable(
          a.localJobId,
          errorCode: 'printer_unreachable',
          nextAttemptAt: t0.add(const Duration(minutes: 30)),
          now: t0.add(const Duration(minutes: 5)),
        );
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

    test(
      'claim is single-flight per job (second claim returns null)',
      () async {
        final row = await importAcked(await newJob('d-claim'));
        final claimed = await store.claimRunnableForPrinting(
          row.localJobId,
          t0.add(const Duration(minutes: 1)),
        );
        expect(claimed, isNotNull);
        expect(claimed!.status, KitchenSpoolJobStatus.printing);
        expect(claimed.attemptCount, 1);
        expect(claimed.lastAttemptAt, isNotNull);
        final second = await store.claimRunnableForPrinting(
          row.localJobId,
          t0.add(const Duration(minutes: 1)),
        );
        expect(second, isNull);
      },
    );

    test('claim is single-flight per DESTINATION fingerprint', () async {
      final a = await importAcked(
        await newJob('d-dest-a', destinationFingerprint: 'fp-shared'),
      );
      final b = await importAcked(
        await newJob('d-dest-b', destinationFingerprint: 'fp-shared'),
      );
      final c = await importAcked(
        await newJob('d-dest-c', destinationFingerprint: 'fp-other'),
      );
      expect(await store.claimRunnableForPrinting(a.localJobId, t0), isNotNull);
      // Same destination is busy -> refused; different destination fine.
      expect(await store.claimRunnableForPrinting(b.localJobId, t0), isNull);
      expect(await store.claimRunnableForPrinting(c.localJobId, t0), isNotNull);
      // Once A resolves, B becomes claimable.
      await store.markTransportAccepted(
        a.localJobId,
        t0.add(const Duration(minutes: 2)),
      );
      expect(await store.claimRunnableForPrinting(b.localJobId, t0), isNotNull);
    });

    test(
      'markQueued only from imported; markPrinting only from runnable',
      () async {
        final row = await importAcked(await newJob('d-q'));
        expect(await store.markQueued(row.localJobId, t0), isTrue);
        expect(await store.markQueued(row.localJobId, t0), isFalse);
        expect(await store.markPrinting(row.localJobId, t0), isTrue);
        expect(await store.markPrinting(row.localJobId, t0), isFalse);
      },
    );
  });

  group('terminal + recovery invariants', () {
    test(
      'printing -> possiblyPrinted recovery maps ONLY printing rows',
      () async {
        final printing = await importAcked(await newJob('d-p1'));
        await store.claimRunnableForPrinting(printing.localJobId, t0);
        final queued = await importAcked(await newJob('d-p2'));
        await store.markQueued(queued.localJobId, t0);
        final changed = await store.markPossiblyPrintedOnRecovery(
          t0.add(const Duration(minutes: 1)),
        );
        expect(changed, 1);
        expect(
          (await store.getByLocalJobId(printing.localJobId))!.status,
          KitchenSpoolJobStatus.possiblyPrinted,
        );
        expect(
          (await store.getByLocalJobId(queued.localJobId))!.status,
          KitchenSpoolJobStatus.queued,
        );
      },
    );

    test('possiblyPrinted can NEVER become runnable again', () async {
      final row = await importAcked(await newJob('d-pp'));
      await store.claimRunnableForPrinting(row.localJobId, t0);
      await store.markPossiblyPrintedOnRecovery(t0);
      expect(
        await store.listRunnable(
          deviceId: deviceId,
          branchId: branchId,
          now: t0.add(const Duration(days: 30)),
        ),
        isEmpty,
      );
      expect(await store.claimRunnableForPrinting(row.localJobId, t0), isNull);
      expect(await store.markQueued(row.localJobId, t0), isFalse);
      expect(await store.markPrinting(row.localJobId, t0), isFalse);
      // Still unresolved (needs an operator), never silently dropped.
      expect(
        await store.countUnresolved(deviceId: deviceId, branchId: branchId),
        1,
      );
    });

    test(
      'transportAccepted is terminal for printing and never re-runnable',
      () async {
        final row = await importAcked(await newJob('d-ta'));
        // Only printing may complete.
        expect(await store.markTransportAccepted(row.localJobId, t0), isFalse);
        await store.claimRunnableForPrinting(row.localJobId, t0);
        expect(await store.markTransportAccepted(row.localJobId, t0), isTrue);
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
        expect(
          await store.claimRunnableForPrinting(row.localJobId, t0),
          isNull,
        );
      },
    );

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
        expect(
          await store.claimRunnableForPrinting(row.localJobId, t0),
          isNull,
        );
        expect(await store.markQueued(row.localJobId, t0), isFalse);
        // Resolved: no longer counted as unresolved.
        expect(
          await store.countUnresolved(deviceId: deviceId, branchId: branchId),
          0,
        );
      },
    );

    test(
      'server evidence does NOT supersede transportAccepted history or a job printing right now',
      () async {
        final done = await importAcked(await newJob('d-done'));
        await store.claimRunnableForPrinting(done.localJobId, t0);
        await store.markTransportAccepted(done.localJobId, t0);
        expect(
          await store.markSupersededFromServerEvidence(
            dispatchId: 'd-done',
            supersededByDispatchId: 'void-1',
            now: t0,
          ),
          isFalse,
        );
        final printing = await importAcked(await newJob('d-mid'));
        await store.claimRunnableForPrinting(printing.localJobId, t0);
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
  });

  group('server acknowledgement independence', () {
    test('pending ack is retained independently; ack retries NEVER make a '
        'transportAccepted job runnable again', () async {
      final row = await importAcked(await newJob('d-ack'));
      await store.claimRunnableForPrinting(row.localJobId, t0);
      await store.markTransportAccepted(row.localJobId, t0);
      await store.setPendingServerAck(
        row.localJobId,
        KitchenServerAckStatus.transportAccepted,
        t0,
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
      await store.claimRunnableForPrinting(old.localJobId, t0);
      await store.markTransportAccepted(old.localJobId, t0);
      await store.setPendingServerAck(
        old.localJobId,
        KitchenServerAckStatus.transportAccepted,
        t0,
      );
      await store.markServerAcked(old.localJobId, t0);
      // Accepted but ack still pending -> NOT prunable.
      final pendingAck = await importAcked(await newJob('d-pa'));
      await store.claimRunnableForPrinting(pendingAck.localJobId, t0);
      await store.markTransportAccepted(pendingAck.localJobId, t0);
      await store.setPendingServerAck(
        pendingAck.localJobId,
        KitchenServerAckStatus.transportAccepted,
        t0,
      );
      // possiblyPrinted -> NEVER prunable.
      final ambiguous = await importAcked(await newJob('d-amb'));
      await store.claimRunnableForPrinting(ambiguous.localJobId, t0);
      await store.markPossiblyPrintedOnRecovery(t0);
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
        expect(
          await store.claimRunnableForPrinting(row.localJobId, t0),
          isNull,
        );
        expect(await store.markQueued(row.localJobId, t0), isFalse);
        expect(await store.markPrinting(row.localJobId, t0), isFalse);
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
      expect(await store.claimRunnableForPrinting(row.localJobId, t0), isNull);
      // Once the server acknowledges, the job becomes runnable.
      await store.markServerAcked(row.localJobId, t0);
      expect(
        await store.claimRunnableForPrinting(row.localJobId, t0),
        isNotNull,
      );
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
      expect(await store.claimRunnableForPrinting(row.localJobId, t0), isNull);
      expect(await store.markQueued(row.localJobId, t0), isFalse);
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
        await store.claimRunnableForPrinting(row.localJobId, t0);
        await store.markPossiblyPrintedOnRecovery(t0);
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

    // Connection 1 claims job A.
    final winner = await store1.claimRunnableForPrinting('conn-job-a', t0);
    expect(winner, isNotNull);

    // Connection 2 — a SEPARATE SQLite connection — must observe the
    // committed claim and REFUSE job B on the same destination.
    final refused = await store2.claimRunnableForPrinting('conn-job-b', t0);
    expect(refused, isNull, reason: 'cross-connection single-flight');

    // Never two printing jobs on one destination, from either view.
    final printing =
        await (db2.select(db2.kitchenSpoolJobs)..where(
              (t) => t.status.equalsValue(KitchenSpoolJobStatus.printing),
            ))
            .get();
    expect(printing, hasLength(1));

    // Winner resolves on connection 1 -> connection 2 can now claim B.
    await store1.markTransportAccepted('conn-job-a', t0);
    final second = await store2.claimRunnableForPrinting('conn-job-b', t0);
    expect(second, isNotNull);
    expect(second!.status, KitchenSpoolJobStatus.printing);
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
