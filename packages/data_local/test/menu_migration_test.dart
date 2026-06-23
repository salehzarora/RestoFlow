import 'dart:io';

import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// RF-030 migration: opening a schema-version-1 database (the RF-018 sync
/// foundation only) at the new version 2 must ADD the six menu tables WITHOUT
/// dropping or recreating the RF-018 tables.
void main() {
  test(
    'v1 -> v2 creates the menu tables and keeps the RF-018 tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('rf030_migration');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      final dbPath = '${dir.path}/menu_migration.db';

      // 1) Build a user_version=1 database containing ONLY the RF-018 tables.
      final raw = sqlite3.open(dbPath);
      raw
        ..execute(
          'CREATE TABLE outbox_operations (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute(
          'CREATE TABLE processed_pull_log (id TEXT NOT NULL PRIMARY KEY)',
        )
        ..execute('INSERT INTO outbox_operations (id) VALUES (?)', ['keep-me'])
        ..execute('PRAGMA user_version = 1')
        ..dispose();

      // 2) Open LocalDatabase (schemaVersion 2) -> runs onUpgrade(1, 2).
      final db = LocalDatabase(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get(); // force open + migration

      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
              .map((r) => r.data['name'] as String)
              .toSet();

      // RF-018 tables survived; the six RF-030 menu tables were created; and
      // the RF-071 print_jobs table was added (onUpgrade runs from<2 + from<3).
      expect(
        tables,
        containsAll(<String>{
          'outbox_operations',
          'processed_pull_log',
          'menu_categories',
          'menu_items',
          'item_sizes',
          'item_variants',
          'modifiers',
          'modifier_options',
          'print_jobs',
        }),
      );

      // The pre-existing RF-018 row was not dropped (no destructive recreate).
      final kept = await db
          .customSelect("SELECT id FROM outbox_operations WHERE id = 'keep-me'")
          .get();
      expect(kept, hasLength(1));

      // user_version advanced to the current schema (v3 since RF-071).
      final version = (await db.customSelect('PRAGMA user_version').get())
          .single
          .data
          .values
          .first;
      expect(version, 3);
    },
  );
}
