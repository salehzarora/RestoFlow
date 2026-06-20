import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:drift/native.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

// Codegen-free tombstone contract test (RF018-B1): proves the DECISION D-020
// soft-delete semantics using real Drift + in-memory SQLite, with NO test-only
// generated database. A syncable-shaped table mirroring the SyncableColumns
// contract (lib/src/tables/syncable_columns.dart) is created at runtime via
// custom SQL on the production LocalDatabase connection. It is NOT part of the
// shipped @DriftDatabase, so the shipped schema still contains no syncable
// business table (asserted below).

const _t1 = '2026-01-02T12:00:00.000Z';
const _t2 = '2026-01-03T12:00:00.000Z';

// Mirrors SyncableColumns: id, organization_id, device_id, local_operation_id,
// revision, client_updated_at, server_updated_at?, created_at, updated_at,
// deleted_at? (nullable = tombstone marker, DECISION D-020).
const _createSyncEntities = '''
CREATE TABLE sync_entities (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  local_operation_id TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  client_updated_at TEXT NOT NULL,
  server_updated_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
''';

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.customStatement(_createSyncEntities);
    await db.customStatement(
      "INSERT INTO sync_entities "
      "(id, organization_id, device_id, local_operation_id, "
      " client_updated_at, created_at, updated_at) "
      "VALUES ('e1','org-1','D1','L-e1','$_t1','$_t1','$_t1')",
    );
  });
  tearDown(() => db.close());

  Future<List<QueryRow>> allRows() =>
      db.customSelect('SELECT * FROM sync_entities').get();

  // Soft delete = tombstone the FIRST time only (the `deleted_at IS NULL` guard
  // makes repeated calls a no-op), so it is idempotent and preserves the
  // original tombstone timestamp. The row is never physically removed. Returns
  // the number of rows changed (1 first time, 0 afterwards).
  Future<int> softDelete(String id, String at) => db.customUpdate(
    'UPDATE sync_entities SET deleted_at = ?2, updated_at = ?2 '
    'WHERE id = ?1 AND deleted_at IS NULL',
    variables: [Variable.withString(id), Variable.withString(at)],
  );

  group('Tombstone / revision contract (DECISION D-020)', () {
    test(
      'deleted_at is nullable and a fresh syncable row is live (null)',
      () async {
        final rows = await allRows();
        expect(rows, hasLength(1));
        expect(rows.single.data['deleted_at'], isNull);
        expect(rows.single.data['revision'], 1); // default concurrency token
      },
    );

    test('soft-delete sets deleted_at and the row REMAINS present', () async {
      expect(await softDelete('e1', _t1), 1);
      final rows = await allRows();
      expect(rows, hasLength(1)); // not physically removed
      expect(rows.single.data['deleted_at'], _t1);
    });

    test(
      'repeated soft-delete is idempotent (no-op, original tombstone kept)',
      () async {
        expect(await softDelete('e1', _t1), 1); // first tombstones
        expect(await softDelete('e1', _t2), 0); // second is a no-op
        final rows = await allRows();
        expect(rows, hasLength(1));
        expect(rows.single.data['deleted_at'], _t1); // original kept, not _t2
      },
    );

    test('the syncable contract declares the standard sync/tombstone columns '
        'with a nullable deleted_at', () async {
      final info = await db
          .customSelect('PRAGMA table_info(sync_entities)')
          .get();
      final byName = {for (final r in info) r.data['name'] as String: r};
      expect(
        byName.keys,
        containsAll(<String>[
          'id',
          'organization_id',
          'device_id',
          'local_operation_id',
          'revision',
          'client_updated_at',
          'server_updated_at',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
      // The tombstone marker and the server clock are nullable (notnull == 0).
      expect(byName['deleted_at']!.data['notnull'], 0);
      expect(byName['server_updated_at']!.data['notnull'], 0);
    });
  });

  group('No hard-delete path for syncable rows (DECISION D-020)', () {
    test('shipped LocalDatabase contains NO syncable business tables', () {
      // The declared schema is only the sync foundation; the ad-hoc
      // sync_entities table above lives solely in this test connection.
      final tableNames = db.allTables.map((t) => t.actualTableName).toSet();
      expect(tableNames, {'outbox_operations', 'processed_pull_log'});
    });
  });
}
