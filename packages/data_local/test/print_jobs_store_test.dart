import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// RF-071: the Drift-backed durable print spool — table create-in-memory,
/// idempotency uniqueness (D-022), store CRUD, crash recovery, document
/// round-trip, and reprint-field persistence.
void main() {
  late LocalDatabase db;
  late DriftPrintSpoolStore store;

  final t0 = DateTime.utc(2026, 6, 23, 12);

  PrintJob job({
    String id = 'j1',
    String op = 'op1',
    PrintJobState status = PrintJobState.created,
    PrintDocument? document,
    String? reprintOf,
    String? reprintReason,
    DateTime? createdAt,
    DateTime? nextAttemptAt,
  }) => PrintJob(
    id: id,
    organizationId: 'org',
    branchId: 'b1',
    deviceId: 'dev1',
    stationId: 'grill',
    localOperationId: op,
    jobType: PrintJobType.receipt,
    document: document ?? const PrintDocument([PrintTextLine('Hello')]),
    status: status,
    reprintOf: reprintOf,
    reprintReason: reprintReason,
    createdAt: createdAt ?? t0,
    updatedAt: createdAt ?? t0,
    nextAttemptAt: nextAttemptAt,
  );

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    store = DriftPrintSpoolStore(db);
  });
  tearDown(() => db.close());

  test(
    'print_jobs table is created in memory; save + getById round-trip',
    () async {
      await store.save(job());
      final got = await store.getById('j1');
      expect(got, isNotNull);
      expect(got!.organizationId, 'org');
      expect(got.stationId, 'grill');
      expect(got.jobType, PrintJobType.receipt);
      expect(got.status, PrintJobState.created);
      expect(got.maxRetries, 12);
    },
  );

  test('unique (device_id, local_operation_id) is enforced (D-022)', () async {
    await store.save(job(id: 'a', op: 'dup'));
    expect(
      () => store.save(job(id: 'b', op: 'dup')),
      throwsA(isA<Exception>()),
      reason: 'a different id reusing the idempotency key must be rejected',
    );
  });

  test('findByIdempotencyKey locates the job', () async {
    await store.save(job(id: 'x', op: 'opX'));
    final found = await store.findByIdempotencyKey('dev1', 'opX');
    expect(found?.id, 'x');
    expect(await store.findByIdempotencyKey('dev1', 'nope'), isNull);
  });

  test(
    'listRunnable returns runnable jobs FIFO and respects nextAttemptAt',
    () async {
      await store.save(job(id: 'a', op: 'a', createdAt: t0));
      await store.save(
        job(
          id: 'b',
          op: 'b',
          status: PrintJobState.printed,
          createdAt: t0.add(const Duration(seconds: 1)),
        ),
      );
      await store.save(
        job(
          id: 'c',
          op: 'c',
          status: PrintJobState.retrying,
          nextAttemptAt: t0.add(const Duration(minutes: 5)),
          createdAt: t0.add(const Duration(seconds: 2)),
        ),
      );

      // At t0: only 'a' (created, no nextAttemptAt). 'b' printed (terminal), 'c' not due.
      final atT0 = await store.listRunnable(t0);
      expect(atT0.map((j) => j.id), ['a']);

      // After 'c's backoff elapses, it becomes runnable too (FIFO by createdAt).
      final later = await store.listRunnable(
        t0.add(const Duration(minutes: 6)),
      );
      expect(later.map((j) => j.id), ['a', 'c']);
    },
  );

  test('update (save) reflects state changes', () async {
    await store.save(job());
    await store.save(
      (await store.getById('j1'))!.copyWith(
        status: PrintJobState.printed,
        printedAt: t0.add(const Duration(seconds: 1)),
      ),
    );
    final got = await store.getById('j1');
    expect(got!.status, PrintJobState.printed);
    expect(got.printedAt, isNotNull);
  });

  test(
    'markPossiblyPrintedOnRecovery moves printing -> possiblyPrinted',
    () async {
      await store.save(job(id: 'p1', op: 'p1', status: PrintJobState.printing));
      await store.save(job(id: 'q1', op: 'q1', status: PrintJobState.created));
      final moved = await store.markPossiblyPrintedOnRecovery(
        t0.add(const Duration(minutes: 1)),
      );
      expect(moved, 1);
      expect(
        (await store.getById('p1'))!.status,
        PrintJobState.possiblyPrinted,
      );
      expect((await store.getById('q1'))!.status, PrintJobState.created);
    },
  );

  test(
    'document JSON persists and round-trips (re-renders identical bytes)',
    () async {
      final doc = PrintDocument([
        const PrintTextLine(
          'RestoFlow',
          alignment: PrintAlignment.center,
          emphasis: TextEmphasis.bold,
        ),
        const PrintFeedLine(2),
        PrintRasterImageLine(
          data: Uint8List.fromList([0xFF, 0x0F]),
          widthBytes: 1,
          heightDots: 2,
        ),
        const PrintCutLine(),
      ], localeTag: 'en');
      await store.save(job(document: doc));
      final restored = (await store.getById('j1'))!.document;

      const adapter = EscPosPrintAdapter();
      expect(
        adapter.encode(restored, PrinterProfile.escPos80mm),
        adapter.encode(doc, PrinterProfile.escPos80mm),
      );
      expect(restored.localeTag, 'en');
    },
  );

  test(
    'claim atomicity: a second claim returns null; status stays printing (RF071-B1)',
    () async {
      await store.save(job(id: 'c1', op: 'c1', status: PrintJobState.queued));

      final first = await store.claimRunnableForPrinting('c1', t0);
      expect(first, isNotNull);
      expect(first!.status, PrintJobState.printing);

      final second = await store.claimRunnableForPrinting('c1', t0);
      expect(second, isNull, reason: 'already claimed -> no double dispatch');
      expect((await store.getById('c1'))!.status, PrintJobState.printing);
    },
  );

  test(
    'claim respects nextAttemptAt: a not-due retrying job is not claimed',
    () async {
      await store.save(
        job(
          id: 'r1',
          op: 'r1',
          status: PrintJobState.retrying,
          nextAttemptAt: t0.add(const Duration(minutes: 5)),
        ),
      );
      // Before the backoff elapses: refused, status unchanged.
      expect(await store.claimRunnableForPrinting('r1', t0), isNull);
      expect((await store.getById('r1'))!.status, PrintJobState.retrying);
      // After it elapses: claimable.
      final claimed = await store.claimRunnableForPrinting(
        'r1',
        t0.add(const Duration(minutes: 6)),
      );
      expect(claimed?.status, PrintJobState.printing);
    },
  );

  test(
    'claim refuses terminal / possiblyPrinted / printing statuses',
    () async {
      final refused = {
        'p1': PrintJobState.printing,
        't1': PrintJobState.printed,
        'x1': PrintJobState.cancelled,
        'a1': PrintJobState.abandoned,
        'm1': PrintJobState.possiblyPrinted,
      };
      for (final entry in refused.entries) {
        await store.save(
          job(id: entry.key, op: entry.key, status: entry.value),
        );
        expect(
          await store.claimRunnableForPrinting(entry.key, t0),
          isNull,
          reason: '${entry.value} is not claimable',
        );
        expect(
          (await store.getById(entry.key))!.status,
          entry.value,
          reason: '${entry.value} unchanged',
        );
      }
      // Missing job -> null.
      expect(await store.claimRunnableForPrinting('ghost', t0), isNull);
    },
  );

  test('reprint fields persist', () async {
    await store.save(
      job(
        id: 'rp1',
        op: 'rp1',
        reprintOf: 'orig-1',
        reprintReason: 'lost receipt',
      ),
    );
    final got = (await store.getById('rp1'))!;
    expect(got.isReprint, isTrue);
    expect(got.reprintOf, 'orig-1');
    expect(got.reprintReason, 'lost receipt');
  });
}
