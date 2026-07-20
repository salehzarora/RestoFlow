@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:test/test.dart';

import 'support/source_boundary.dart';

/// KITCHEN-MODE-001C2B — general LocalDatabase v5 migration safety.
///
/// v5 moves the kitchen spool to the DEDICATED [KitchenSpoolDatabase]: the
/// general database drops its (only-ever-empty) `kitchen_spool_jobs` copy
/// behind a FAIL-CLOSED guard — any unexpected spool row ABORTS the
/// migration without advancing the version or deleting anything.
///
/// Harness = the house pattern: raw sqlite3 old-version fixtures with seeded
/// rows + `PRAGMA user_version`, then open [LocalDatabase] to run
/// `onUpgrade`.
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
  };

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kmc2b_migration');
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

  Future<int> userVersion(LocalDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  void createLegacyCoreTables(raw_sqlite.Database raw) {
    raw
      ..execute('CREATE TABLE outbox_operations (id TEXT NOT NULL PRIMARY KEY)')
      ..execute(
        'CREATE TABLE processed_pull_log (id TEXT NOT NULL PRIMARY KEY)',
      );
  }

  void createLegacyMenuTables(raw_sqlite.Database raw) {
    raw
      ..execute('CREATE TABLE menu_categories (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE menu_items (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE item_sizes (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE item_variants (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE modifiers (id TEXT NOT NULL PRIMARY KEY)')
      ..execute('CREATE TABLE modifier_options (id TEXT NOT NULL PRIMARY KEY)');
  }

  test(
    'fresh database creates the v5 schema WITHOUT kitchen_spool_jobs',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final tables = await tableNames(db);
      expect(tables, containsAll(expectedTables));
      expect(tables, isNot(contains('kitchen_spool_jobs')));
      expect(await userVersion(db), 5);
    },
  );

  test(
    'v1 -> v5 adds menu + print_jobs, never the spool; data survives',
    () async {
      final dbPath = '${tempDir.path}/v1.sqlite';
      final raw = raw_sqlite.sqlite3.open(dbPath);
      createLegacyCoreTables(raw);
      raw
        ..execute('INSERT INTO outbox_operations (id) VALUES (?)', ['keep-v1'])
        ..execute('PRAGMA user_version = 1')
        ..dispose();

      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final tables = await tableNames(db);
      expect(tables, containsAll(expectedTables));
      expect(tables, isNot(contains('kitchen_spool_jobs')));
      final kept = await db
          .customSelect("SELECT id FROM outbox_operations WHERE id = 'keep-v1'")
          .get();
      expect(kept, hasLength(1), reason: 'no destructive recreation');
      expect(await userVersion(db), 5);
    },
  );

  test(
    'v2 -> v5 adds print_jobs; menu data survives; no spool table',
    () async {
      final dbPath = '${tempDir.path}/v2.sqlite';
      final raw = raw_sqlite.sqlite3.open(dbPath);
      createLegacyCoreTables(raw);
      createLegacyMenuTables(raw);
      raw
        ..execute('INSERT INTO menu_items (id) VALUES (?)', ['menu-keep'])
        ..execute('PRAGMA user_version = 2')
        ..dispose();

      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final tables = await tableNames(db);
      expect(tables, containsAll(expectedTables));
      expect(tables, isNot(contains('kitchen_spool_jobs')));
      final kept = await db
          .customSelect("SELECT id FROM menu_items WHERE id = 'menu-keep'")
          .get();
      expect(kept, hasLength(1));
      expect(await userVersion(db), 5);
    },
  );

  test(
    'v3 -> v5 preserves outbox/menu/print_jobs data; no spool table',
    () async {
      final dbPath = '${tempDir.path}/v3.sqlite';
      final raw = raw_sqlite.sqlite3.open(dbPath);
      createLegacyCoreTables(raw);
      createLegacyMenuTables(raw);
      raw
        ..execute('CREATE TABLE print_jobs (id TEXT NOT NULL PRIMARY KEY)')
        ..execute('INSERT INTO outbox_operations (id) VALUES (?)', ['ob-keep'])
        ..execute('INSERT INTO menu_items (id) VALUES (?)', ['menu-keep'])
        ..execute('INSERT INTO print_jobs (id) VALUES (?)', ['pj-keep'])
        ..execute('PRAGMA user_version = 3')
        ..dispose();

      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final tables = await tableNames(db);
      expect(tables, containsAll(expectedTables));
      expect(tables, isNot(contains('kitchen_spool_jobs')));
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
      expect(await userVersion(db), 5);
    },
  );

  test('v4 with an EMPTY spool table -> v5 drops it and its indexes', () async {
    final dbPath = '${tempDir.path}/v4-empty.sqlite';
    final raw = raw_sqlite.sqlite3.open(dbPath);
    createLegacyCoreTables(raw);
    createLegacyMenuTables(raw);
    raw
      ..execute('CREATE TABLE print_jobs (id TEXT NOT NULL PRIMARY KEY)')
      ..execute(
        'CREATE TABLE kitchen_spool_jobs '
        '(local_job_id TEXT NOT NULL PRIMARY KEY)',
      )
      ..execute(
        'CREATE INDEX kitchen_spool_runnable_idx '
        'ON kitchen_spool_jobs (local_job_id)',
      )
      ..execute('INSERT INTO print_jobs (id) VALUES (?)', ['pj-keep'])
      ..execute('PRAGMA user_version = 4')
      ..dispose();

    final db = LocalDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final tables = await tableNames(db);
    expect(tables, isNot(contains('kitchen_spool_jobs')));
    final indexes =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index'",
                )
                .get())
            .map((r) => r.data['name'] as String)
            .toSet();
    expect(indexes, isNot(contains('kitchen_spool_runnable_idx')));
    final kept = await db
        .customSelect("SELECT id FROM print_jobs WHERE id = 'pj-keep'")
        .get();
    expect(kept, hasLength(1));
    expect(await userVersion(db), 5);
  });

  test('v4 with a NON-EMPTY spool table -> v5 REFUSES: no version advance, '
      'no row deleted (fail-closed guard)', () async {
    final dbPath = '${tempDir.path}/v4-rows.sqlite';
    final raw = raw_sqlite.sqlite3.open(dbPath);
    createLegacyCoreTables(raw);
    createLegacyMenuTables(raw);
    raw
      ..execute('CREATE TABLE print_jobs (id TEXT NOT NULL PRIMARY KEY)')
      ..execute(
        'CREATE TABLE kitchen_spool_jobs '
        '(local_job_id TEXT NOT NULL PRIMARY KEY)',
      )
      ..execute('INSERT INTO kitchen_spool_jobs (local_job_id) VALUES (?)', [
        'unexpected-row',
      ])
      ..execute('PRAGMA user_version = 4')
      ..dispose();

    final db = LocalDatabase(NativeDatabase(File(dbPath)));
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
    await db.close();

    // The refused migration left EVERYTHING intact: version unchanged,
    // the unexpected row preserved.
    final verify = raw_sqlite.sqlite3.open(dbPath);
    final version =
        verify.select('PRAGMA user_version').first.values.first as int;
    expect(version, 4, reason: 'refused migration must not advance');
    final rows = verify.select(
      "SELECT local_job_id FROM kitchen_spool_jobs "
      "WHERE local_job_id = 'unexpected-row'",
    );
    expect(rows, hasLength(1), reason: 'no spool row may be dropped');
    verify.dispose();
  });

  test(
    'database open/migration never touches crypto keys (source boundary)',
    () async {
      // Covers BOTH database sources (general + dedicated spool) via the
      // CI-portable helper; the scan refuses to pass vacuously.
      final packageRoot = locateDataLocalPackageRoot();
      final code = readDatabaseSourcesCodeOnly(packageRoot);
      expect(
        findCryptoBoundaryViolation(code),
        isNull,
        reason: 'database open/migration code must never touch crypto keys',
      );

      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get(); // opens + migrates, no keys
      expect(await userVersion(db), 5);
    },
  );
}
