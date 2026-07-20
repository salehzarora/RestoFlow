@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:test/test.dart';

/// KITCHEN-MODE-001C2A §11 — LocalDatabase v4 migration safety.
///
/// The harness matches the house pattern (menu_migration_test.dart): build a
/// raw sqlite3 database with hand-written minimal old-version tables + seeded
/// rows, stamp `PRAGMA user_version`, then open [LocalDatabase] to run
/// `onUpgrade`, and assert additive creation + data survival.
void main() {
  const expectedTables = {
    'outbox_operations',
    'processed_pull_log',
    'menu_categories',
    'menu_items',
    'item_sizes',
    'item_variants',
    'modifiers',
    'modifier_options',
    'print_jobs',
    'kitchen_spool_jobs',
  };

  const expectedSpoolIndexes = {
    'kitchen_spool_runnable_idx',
    'kitchen_spool_destination_idx',
    'kitchen_spool_unresolved_idx',
    'kitchen_spool_pending_ack_idx',
    'kitchen_spool_retention_idx',
    'kitchen_spool_order_sequence_idx',
  };

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kmc2a_migration');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<Set<String>> tableNames(LocalDatabase db) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get())
          .map((r) => r.data['name'] as String)
          .toSet();

  Future<Set<String>> indexNames(LocalDatabase db) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((r) => r.data['name'] as String)
          .toSet();

  Future<int> userVersion(LocalDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  Future<Set<String>> spoolColumns(LocalDatabase db) async =>
      (await db.customSelect("PRAGMA table_info('kitchen_spool_jobs')").get())
          .map((r) => r.data['name'] as String)
          .toSet();

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
    'created_at',
    'updated_at',
    'transport_accepted_at',
    'server_acknowledged_at',
    'reviewed_at',
    'reprint_of_local_job_id',
    'superseded_by_dispatch_id',
  };

  test(
    'fresh database creates the full v4 schema (tables + indexes)',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      expect(await tableNames(db), containsAll(expectedTables));
      expect(await indexNames(db), containsAll(expectedSpoolIndexes));
      expect(await spoolColumns(db), expectedSpoolColumns);
      expect(await userVersion(db), 4);
    },
  );

  test(
    'v1 -> v4 adds menu + print_jobs + kitchen_spool_jobs; RF-018 data survives',
    () async {
      final dbPath = '${tempDir.path}/v1.sqlite';
      final raw = raw_sqlite.sqlite3.open(dbPath);
      raw
        ..execute(
          'CREATE TABLE outbox_operations (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute(
          'CREATE TABLE processed_pull_log (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute('INSERT INTO outbox_operations (id) VALUES (?)', ['keep-v1'])
        ..execute('PRAGMA user_version = 1')
        ..dispose();

      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      expect(await tableNames(db), containsAll(expectedTables));
      expect(await indexNames(db), containsAll(expectedSpoolIndexes));
      final kept = await db
          .customSelect("SELECT id FROM outbox_operations WHERE id = 'keep-v1'")
          .get();
      expect(kept, hasLength(1), reason: 'no destructive recreation');
      expect(await userVersion(db), 4);
    },
  );

  test(
    'v2 -> v4 adds print_jobs + kitchen_spool_jobs; menu data survives',
    () async {
      final dbPath = '${tempDir.path}/v2.sqlite';
      final raw = raw_sqlite.sqlite3.open(dbPath);
      raw
        ..execute(
          'CREATE TABLE outbox_operations (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute(
          'CREATE TABLE processed_pull_log (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute('CREATE TABLE menu_categories (id TEXT NOT NULL PRIMARY KEY)')
        ..execute('CREATE TABLE menu_items (id TEXT NOT NULL PRIMARY KEY)')
        ..execute('CREATE TABLE item_sizes (id TEXT NOT NULL PRIMARY KEY)')
        ..execute('CREATE TABLE item_variants (id TEXT NOT NULL PRIMARY KEY)')
        ..execute('CREATE TABLE modifiers (id TEXT NOT NULL PRIMARY KEY)')
        ..execute(
          'CREATE TABLE modifier_options (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute('INSERT INTO menu_items (id) VALUES (?)', ['menu-keep'])
        ..execute('PRAGMA user_version = 2')
        ..dispose();

      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      expect(await tableNames(db), containsAll(expectedTables));
      final kept = await db
          .customSelect("SELECT id FROM menu_items WHERE id = 'menu-keep'")
          .get();
      expect(kept, hasLength(1));
      expect(await userVersion(db), 4);
    },
  );

  test('v3 -> v4 adds ONLY kitchen_spool_jobs (+indexes); outbox/menu/'
      'print_jobs data survives untouched', () async {
    final dbPath = '${tempDir.path}/v3.sqlite';
    final raw = raw_sqlite.sqlite3.open(dbPath);
    raw
      ..execute('CREATE TABLE outbox_operations (id TEXT NOT NULL PRIMARY KEY)')
      ..execute(
        'CREATE TABLE processed_pull_log (id TEXT NOT NULL PRIMARY KEY)',
      )
      ..execute('CREATE TABLE menu_categories (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE menu_items (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE item_sizes (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE item_variants (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE modifiers (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE modifier_options (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE print_jobs (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('INSERT INTO outbox_operations (id) VALUES (?)', ['ob-keep'])
      ..execute('INSERT INTO menu_items (id) VALUES (?)', ['menu-keep'])
      ..execute('INSERT INTO print_jobs (id) VALUES (?)', ['pj-keep'])
      ..execute('PRAGMA user_version = 3')
      ..dispose();

    final db = LocalDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(await tableNames(db), containsAll(expectedTables));
    expect(await indexNames(db), containsAll(expectedSpoolIndexes));
    expect(await spoolColumns(db), expectedSpoolColumns);
    for (final probe in [
      ('outbox_operations', 'ob-keep'),
      ('menu_items', 'menu-keep'),
      ('print_jobs', 'pj-keep'),
    ]) {
      final kept = await db
          .customSelect(
            'SELECT id FROM ${probe.$1} WHERE id = ?',
            variables: [Variable.withString(probe.$2)],
          )
          .get();
      expect(kept, hasLength(1), reason: '${probe.$1} row must survive');
    }
    expect(await userVersion(db), 4);
  });

  test(
    'SQLite CHECK constraints reject invalid kitchen_spool_jobs states',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

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
            'created_at, updated_at) VALUES $sqlValues',
          ),
          throwsA(anything),
        );
      }

      // attempt_count >= 0
      await expectRejected(
        "('j1','d1','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, -1, 0, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // transport_accepted requires transport_accepted_at
      await expectRejected(
        "('j2','d2','o','r','b','dev','ord','initial_order',"
        "'transport_accepted', x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, "
        "'2026-01-01', '2026-01-01')",
      );
      // possibly_printed cannot carry transport_accepted_at
      await expectRejected(
        "('j3','d3','o','r','b','dev','ord','initial_order',"
        "'possibly_printed', x'01', 1, 1, 1, 1, 0, 0, '2026-01-01', NULL, "
        "NULL, '2026-01-01', '2026-01-01')",
      );
      // superseded requires superseded_by_dispatch_id
      await expectRejected(
        "('j4','d4','o','r','b','dev','ord','initial_order','superseded',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // reprint_of_local_job_id cannot equal local_job_id
      await expectRejected(
        "('j5','d5','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, 0, 0, NULL, NULL, 'j5', '2026-01-01', "
        "'2026-01-01')",
      );
      // encrypted blob may not be empty
      await expectRejected(
        "('j6','d6','o','r','b','dev','ord','initial_order','imported',"
        "x'', 1, 1, 1, 1, 0, 0, NULL, NULL, NULL, '2026-01-01', "
        "'2026-01-01')",
      );
      // dispatch_id unique
      await db.customStatement(
        'INSERT INTO kitchen_spool_jobs '
        '(local_job_id, dispatch_id, organization_id, restaurant_id, '
        'branch_id, device_id, order_id, dispatch_type, status, '
        'encrypted_payload_blob, encryption_version, payload_version, '
        'document_version, raster_version, created_at, updated_at) VALUES '
        "('j7','d7','o','r','b','dev','ord','initial_order','imported',"
        "x'01', 1, 1, 1, 1, '2026-01-01', '2026-01-01')",
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO kitchen_spool_jobs '
          '(local_job_id, dispatch_id, organization_id, restaurant_id, '
          'branch_id, device_id, order_id, dispatch_type, status, '
          'encrypted_payload_blob, encryption_version, payload_version, '
          'document_version, raster_version, created_at, updated_at) VALUES '
          "('j8','d7','o','r','b','dev','ord','initial_order','imported',"
          "x'01', 1, 1, 1, 1, '2026-01-01', '2026-01-01')",
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'database open/migration never touches crypto keys (source boundary)',
    () async {
      // LocalDatabase takes only a QueryExecutor: there is no SecureKeyStore
      // anywhere in its construction, and this test opens + migrates with NO
      // key material in existence. The stronger structural proof: the
      // database/migration source has no key-store or crypto import.
      final source = File('lib/src/local_database.dart').readAsStringSync();
      expect(source, isNot(contains('SecureKeyStore')));
      expect(source, isNot(contains('kitchen_spool_cipher')));
      expect(source, isNot(contains('kitchen_spool_key_manager')));
      expect(source, isNot(contains('provisionKey')));
      expect(source, isNot(contains('provisionPersistentKey')));

      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get(); // opens + migrates, no keys
      expect(await userVersion(db), 4);
    },
  );
}
