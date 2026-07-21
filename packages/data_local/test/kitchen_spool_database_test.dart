@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// A documents Directory that RESOLVES successfully but throws when its path is
/// read — models a stat/path failure AFTER the directory resolved.
class _ThrowingPathDirectory implements Directory {
  @override
  String get path => throw const FileSystemException('path inspection failed');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// KITCHEN-MODE-001C2B — the DEDICATED kitchen-spool database + factory.
void main() {
  const expectedSpoolIndexes = {
    'kitchen_spool_runnable_idx',
    'kitchen_spool_destination_idx',
    'kitchen_spool_unresolved_idx',
    'kitchen_spool_pending_ack_idx',
    'kitchen_spool_retention_idx',
    'kitchen_spool_order_sequence_idx',
  };

  const expectedSpoolColumns = {
    'local_job_id',
    'dispatch_id',
    'organization_id',
    'restaurant_id',
    'branch_id',
    'device_id',
    'order_id',
    'service_round_id',
    'dispatch_type',
    'status',
    'encrypted_payload_blob',
    'encryption_version',
    'destination_fingerprint',
    'destination_display_label',
    'transport_kind',
    'paper_width',
    'payload_version',
    'document_version',
    'raster_version',
    'attempt_count',
    'next_attempt_at',
    'last_attempt_at',
    'last_error_code',
    'server_claim_expires_at',
    'pending_server_ack_status',
    'server_ack_attempt_count',
    'server_ack_next_attempt_at',
    'server_ack_last_error_code',
    'server_ack_terminal_code',
    'created_at',
    'updated_at',
    'transport_accepted_at',
    'server_acknowledged_at',
    'reviewed_at',
    'reprint_of_local_job_id',
    'superseded_by_dispatch_id',
  };

  group('schema (dedicated v1)', () {
    late KitchenSpoolDatabase db;

    setUp(() async {
      db = KitchenSpoolDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() => db.close());

    test('contains ONLY kitchen_spool_jobs (+drift bookkeeping), v1', () async {
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table' "
                    "AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((r) => r.data['name'] as String)
              .toSet();
      expect(tables, {'kitchen_spool_jobs'});
      for (final absent in ['outbox_operations', 'menu_items', 'print_jobs']) {
        expect(tables, isNot(contains(absent)));
      }
      final version =
          (await db.customSelect('PRAGMA user_version').getSingle())
                  .data
                  .values
                  .first
              as int;
      expect(version, 1);
    });

    test(
      'exact column set (incl. server_ack_terminal_code) + all indexes',
      () async {
        final columns =
            (await db
                    .customSelect("PRAGMA table_info('kitchen_spool_jobs')")
                    .get())
                .map((r) => r.data['name'] as String)
                .toSet();
        expect(columns, expectedSpoolColumns);
        final indexes =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'index'",
                    )
                    .get())
                .map((r) => r.data['name'] as String)
                .toSet();
        expect(indexes, containsAll(expectedSpoolIndexes));
      },
    );

    test('SQLite CHECK constraints reject invalid states', () async {
      Future<void> expectRejected(String sqlValues) async {
        await expectLater(
          db.customStatement(
            'INSERT INTO kitchen_spool_jobs '
            '(local_job_id, dispatch_id, organization_id, restaurant_id, '
            'branch_id, device_id, order_id, dispatch_type, status, '
            'encrypted_payload_blob, encryption_version, payload_version, '
            'document_version, raster_version, attempt_count, '
            'server_ack_attempt_count, transport_accepted_at, '
            'superseded_by_dispatch_id, reprint_of_local_job_id, '
            'server_ack_terminal_code, created_at, updated_at) '
            'VALUES $sqlValues',
          ),
          throwsA(anything),
        );
      }

      // attempt_count >= 0
      await expectRejected(
        "('j1','d1','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, -1, 0, NULL, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // encryption_version > 0 (zero and negative)
      await expectRejected(
        "('j2','d2','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 0, 1, 1, 1, 0, 0, NULL, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      await expectRejected(
        "('j2b','d2b','o','r','b','dev','ord','initial_order','imported',"
        "x'01', -1, 1, 1, 1, 0, 0, NULL, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // transport_accepted requires timestamp
      await expectRejected(
        "('j3','d3','o','r','b','dev','ord','initial_order',"
        "'transport_accepted', x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, "
        "NULL, '2026-01-01', '2026-01-01')",
      );
      // possibly_printed cannot carry the timestamp
      await expectRejected(
        "('j4','d4','o','r','b','dev','ord','initial_order',"
        "'possibly_printed', x'01', 1, 1, 1, 1, 0, 0, '2026-01-01', NULL, "
        "NULL, NULL, '2026-01-01', '2026-01-01')",
      );
      // superseded requires the link
      await expectRejected(
        "('j5','d5','o','r','b','dev','ord','initial_order','superseded',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // self-supersession forbidden
      await expectRejected(
        "('j6','d6','o','r','b','dev','ord','initial_order','superseded',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, 'd6', NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // reprint cannot self-reference
      await expectRejected(
        "('j7','d7','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, 'j7', NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // empty blob forbidden
      await expectRejected(
        "('j8','d8','o','r','b','dev','ord','initial_order','imported',"
        "x'', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // KITCHEN-MODE-001C2B: terminal code is a CLOSED vocabulary
      await expectRejected(
        "('j9','d9','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, 'made_up_code', "
        "'2026-01-01', '2026-01-01')",
      );
      // ... and a VALID terminal code is accepted.
      await db.customStatement(
        'INSERT INTO kitchen_spool_jobs '
        '(local_job_id, dispatch_id, organization_id, restaurant_id, '
        'branch_id, device_id, order_id, dispatch_type, status, '
        'encrypted_payload_blob, encryption_version, payload_version, '
        'document_version, raster_version, server_ack_terminal_code, '
        'created_at, updated_at) VALUES '
        "('j10','d10','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, 'not_claim_owner', '2026-01-01', '2026-01-01')",
      );
      // dispatch_id unique
      await expectLater(
        db.customStatement(
          'INSERT INTO kitchen_spool_jobs '
          '(local_job_id, dispatch_id, organization_id, restaurant_id, '
          'branch_id, device_id, order_id, dispatch_type, status, '
          'encrypted_payload_blob, encryption_version, payload_version, '
          'document_version, raster_version, created_at, updated_at) VALUES '
          "('j11','d10','o','r','b','dev','ord','initial_order','imported',"
          "x'01', 1, 1, 1, 1, '2026-01-01', '2026-01-01')",
        ),
        throwsA(anything),
      );
    });
  });

  group('KitchenSpoolDatabaseFactory (001C2B hard precondition)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kmc2b_factory');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('the path is composed DIRECTLY from the pinned backup constants', () {
      final path = KitchenSpoolDatabaseFactory.databasePathUnder(tempDir);
      expect(
        path,
        p.join(
          tempDir.path,
          kKitchenSpoolDatabaseDirectoryName,
          kKitchenSpoolDatabaseFileName,
        ),
      );
      // The directory segment is exactly the Android-backup-excluded name.
      expect(p.split(path), contains(kKitchenSpoolDatabaseDirectoryName));
    });

    test(
      'open() creates the directory, persists across reopen, no key touch',
      () async {
        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async => tempDir,
        );
        expect(await factory.spoolFileExists(), isFalse);
        final db = await factory.open();
        await db.customStatement(
          'INSERT INTO kitchen_spool_jobs '
          '(local_job_id, dispatch_id, organization_id, restaurant_id, '
          'branch_id, device_id, order_id, dispatch_type, status, '
          'encrypted_payload_blob, encryption_version, payload_version, '
          'document_version, raster_version, created_at, updated_at) VALUES '
          "('persist','dp','o','r','b','dev','ord','initial_order','imported',"
          "x'0102', 1, 1, 1, 1, '2026-01-01', '2026-01-01')",
        );
        await db.close();
        expect(await factory.spoolFileExists(), isTrue);

        final reopened = await factory.open();
        final rows = await reopened
            .customSelect(
              "SELECT local_job_id FROM kitchen_spool_jobs "
              "WHERE local_job_id = 'persist'",
            )
            .get();
        expect(rows, hasLength(1), reason: 'restart persistence');
        await reopened.close();
      },
    );

    test(
      'a CORRUPTED file fails closed, typed, and is NEVER recreated',
      () async {
        final path = KitchenSpoolDatabaseFactory.databasePathUnder(tempDir);
        Directory(p.dirname(path)).createSync(recursive: true);
        File(path).writeAsStringSync('this is not a sqlite database at all');
        final before = File(path).readAsBytesSync();

        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async => tempDir,
        );
        await expectLater(
          factory.open(),
          throwsA(isA<KitchenSpoolDatabaseUnavailableException>()),
        );
        // The corrupt file is untouched — no destructive recreation.
        expect(File(path).readAsBytesSync(), before);
      },
    );

    test(
      'a failing documents-directory provider fails closed, typed',
      () async {
        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async =>
              throw const FileSystemException('no docs dir'),
        );
        await expectLater(
          factory.open(),
          throwsA(isA<KitchenSpoolDatabaseUnavailableException>()),
        );
        expect(await factory.spoolFileExists(), isFalse);
      },
    );

    test('spoolFileExists never CREATES the directory (kds stays footprint-'
        'free)', () async {
      final factory = KitchenSpoolDatabaseFactory(
        documentsDirectoryProvider: () async => tempDir,
      );
      expect(await factory.spoolFileExists(), isFalse);
      expect(
        Directory(
          p.join(tempDir.path, kKitchenSpoolDatabaseDirectoryName),
        ).existsSync(),
        isFalse,
        reason: 'probing must not grow a spool footprint',
      );
    });

    group('inspectSpoolFilePresence (001C3B1A2 truthful presence)', () {
      test('a documents-directory PROVIDER failure is UNKNOWN, never absent, '
          'and grows no footprint', () async {
        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async =>
              throw const FileSystemException('no docs dir'),
        );
        expect(
          await factory.inspectSpoolFilePresence(),
          KitchenSpoolFilePresence.unknown,
          reason: 'a provider failure is not proof the spool is absent',
        );
        // The bool convenience still reports false (safe skip), never asserting
        // presence.
        expect(await factory.spoolFileExists(), isFalse);
      });

      test('a path/stat inspection failure AFTER the directory resolves is '
          'UNKNOWN, never absent', () async {
        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async => _ThrowingPathDirectory(),
        );
        expect(
          await factory.inspectSpoolFilePresence(),
          KitchenSpoolFilePresence.unknown,
        );
        expect(await factory.spoolFileExists(), isFalse);
      });

      test('a resolved directory with NO file is confirmed ABSENT, creating '
          'nothing', () async {
        final factory = KitchenSpoolDatabaseFactory(
          documentsDirectoryProvider: () async => tempDir,
        );
        expect(
          await factory.inspectSpoolFilePresence(),
          KitchenSpoolFilePresence.absent,
        );
        expect(
          Directory(
            p.join(tempDir.path, kKitchenSpoolDatabaseDirectoryName),
          ).existsSync(),
          isFalse,
          reason: 'presence inspection must not grow a footprint',
        );
      });

      test(
        'a resolved directory with an existing file is confirmed PRESENT',
        () async {
          final path = KitchenSpoolDatabaseFactory.databasePathUnder(tempDir);
          Directory(p.dirname(path)).createSync(recursive: true);
          File(path).writeAsStringSync('placeholder');
          final factory = KitchenSpoolDatabaseFactory(
            documentsDirectoryProvider: () async => tempDir,
          );
          expect(
            await factory.inspectSpoolFilePresence(),
            KitchenSpoolFilePresence.present,
          );
          expect(await factory.spoolFileExists(), isTrue);
        },
      );
    });
  });
}
