import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'converters.dart';
import 'kitchen_spool/drift_kitchen_spool_store.dart'
    show kKitchenSpoolDatabaseDirectoryName, kKitchenSpoolDatabaseFileName;
// Brings the closed kitchen-spool enums into the library scope so the
// generated `part` can reference the converter types.
import 'kitchen_spool/kitchen_spool_status.dart';
import 'tables/kitchen_spool_jobs.dart';

part 'kitchen_spool_database.g.dart';

/// KITCHEN-MODE-001C2B — the DEDICATED runtime kitchen-spool database.
///
/// CONTRACT (review-approved 001C2B hard precondition): the runtime kitchen
/// spool lives EXCLUSIVELY in this database, at the exact Android
/// backup-excluded path composed from [kKitchenSpoolDatabaseDirectoryName] +
/// [kKitchenSpoolDatabaseFileName]. Opening `kitchen_spool_jobs` through the
/// general [LocalDatabase] is PROHIBITED — the general database is (or may
/// become) part of Android backup, and restoring encrypted spool rows without
/// the matching Keystore key would strand them in a mismatched state.
///
/// This database contains ONLY [KitchenSpoolJobs] (the SHARED table class —
/// no duplicate model), never outbox/menu/print_jobs. Construction and
/// migration NEVER touch crypto keys or secure storage: the payload column is
/// an opaque encrypted blob at this layer, so the database can open before or
/// after key inspection without any plaintext exposure.
@DriftDatabase(tables: [KitchenSpoolJobs])
class KitchenSpoolDatabase extends _$KitchenSpoolDatabase {
  /// Opens on [executor] (e.g. `NativeDatabase.memory()` in tests; the
  /// production executor comes from [KitchenSpoolDatabaseFactory]).
  KitchenSpoolDatabase(super.executor);

  /// v1 = KITCHEN-MODE-001C2B initial dedicated schema.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// UTC ISO-8601 text timestamps — same convention as the general database.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

/// Typed, fail-closed unavailability of the dedicated spool database:
/// path creation failure, open failure, or corruption. The message never
/// contains payload data; the original cause is preserved for diagnostics.
final class KitchenSpoolDatabaseUnavailableException implements Exception {
  const KitchenSpoolDatabaseUnavailableException(this.reason);

  /// A short, safe reason token (no payload, no endpoint, no key material).
  final String reason;

  @override
  String toString() => 'KitchenSpoolDatabaseUnavailableException: $reason';
}

/// KITCHEN-MODE-001C3B1A2 — the TRUTHFUL, non-mutating result of asking whether
/// a spool database file exists, distinguishing a CONFIRMED answer from an
/// undeterminable one:
///  * [present] — the documents directory resolved AND the file is confirmed
///    to exist;
///  * [absent]  — the documents directory resolved AND the file is confirmed
///    NOT to exist (a proven-empty footprint);
///  * [unknown] — the documents directory / path could not be resolved or
///    inspected, so presence is UNDETERMINED. A provider/IO failure is NEVER
///    proof of absence — collapsing it to [absent] would let the future
///    `printer_only -> kds` escape gate treat an unreadable device as
///    proven-empty. Fail closed to [unknown] instead.
enum KitchenSpoolFilePresence { present, absent, unknown }

/// KITCHEN-MODE-001C2B — the ONLY production factory for the dedicated
/// spool database.
///
///  * Path: `<documentsDir>/kKitchenSpoolDatabaseDirectoryName/`
///    `kKitchenSpoolDatabaseFileName` — composed DIRECTLY from the pinned
///    constants the Android backup rules exclude.
///  * Directory creation is recursive; every IO/open failure is a typed
///    [KitchenSpoolDatabaseUnavailableException] (fail closed).
///  * A corrupt existing file surfaces as unavailable and is NEVER
///    destructively recreated — unresolved encrypted rows are sacred.
///  * No crypto-key or secure-storage access happens here, ever.
///  * Web never constructs this factory (the POS platform seam guards it).
final class KitchenSpoolDatabaseFactory {
  KitchenSpoolDatabaseFactory({
    required Future<Directory> Function() documentsDirectoryProvider,
  }) : _documentsDirectoryProvider = documentsDirectoryProvider;

  final Future<Directory> Function() _documentsDirectoryProvider;

  /// The canonical database file path under [docs] — exposed so tests can
  /// bind it to the backup-exclusion contract.
  static String databasePathUnder(Directory docs) => p.join(
    docs.path,
    kKitchenSpoolDatabaseDirectoryName,
    kKitchenSpoolDatabaseFileName,
  );

  /// KITCHEN-MODE-001C3B1A2 — the NON-MUTATING, TRUTHFUL presence inspection.
  ///
  /// Distinguishes a confirmed [KitchenSpoolFilePresence.absent] file from an
  /// undeterminable [KitchenSpoolFilePresence.unknown] one:
  ///  * the documents-directory provider throwing → [unknown] (a provider
  ///    failure is NOT proof the spool is empty);
  ///  * any path/stat inspection failure AFTER the directory resolved →
  ///    [unknown];
  ///  * the path resolves and the file is confirmed present → [present];
  ///  * the path resolves and the file is confirmed missing → [absent].
  ///
  /// NEVER creates the directory or database, NEVER touches a crypto key, and
  /// NEVER leaks a raw exception (fail closed to [unknown] on ANY failure).
  Future<KitchenSpoolFilePresence> inspectSpoolFilePresence() async {
    final Directory docs;
    try {
      docs = await _documentsDirectoryProvider();
    } on Object {
      // Documents-directory resolution failed: presence is UNKNOWN, never
      // absent (a directory-provider failure is not proof of an empty spool).
      return KitchenSpoolFilePresence.unknown;
    }
    try {
      return File(databasePathUnder(docs)).existsSync()
          ? KitchenSpoolFilePresence.present
          : KitchenSpoolFilePresence.absent;
    } on Object {
      // A path/stat inspection failure after the directory resolved is also
      // UNKNOWN — confirmed absence requires a successful, negative check.
      return KitchenSpoolFilePresence.unknown;
    }
  }

  /// Whether a spool database file is CONFIRMED present (WITHOUT creating the
  /// directory — a verified-kds device must not grow a spool footprint).
  ///
  /// A convenience over [inspectSpoolFilePresence]: `true` ONLY for a confirmed
  /// [KitchenSpoolFilePresence.present]; both [KitchenSpoolFilePresence.absent]
  /// and [KitchenSpoolFilePresence.unknown] map to `false`. This is SAFE for
  /// callers whose only reaction to `false` is to skip work and touch nothing
  /// (e.g. the runtime drain worker's "no footprint" skip). Count-CERTAINTY
  /// callers MUST use [inspectSpoolFilePresence] instead, because a `false`
  /// here cannot tell a proven-empty spool from an undeterminable one.
  Future<bool> spoolFileExists() async =>
      await inspectSpoolFilePresence() == KitchenSpoolFilePresence.present;

  /// Opens (creating the directory/file when needed) and PROBES the database
  /// so corruption fails here, typed, instead of on first use. On probe
  /// failure the handle is closed and the file is left untouched.
  Future<KitchenSpoolDatabase> open() async {
    final Directory docs;
    try {
      docs = await _documentsDirectoryProvider();
    } on Exception {
      throw const KitchenSpoolDatabaseUnavailableException(
        'documents_directory_unavailable',
      );
    }
    final path = databasePathUnder(docs);
    try {
      Directory(p.dirname(path)).createSync(recursive: true);
    } on IOException {
      throw const KitchenSpoolDatabaseUnavailableException(
        'spool_directory_create_failed',
      );
    }
    final db = KitchenSpoolDatabase(NativeDatabase(File(path)));
    try {
      // Forces open + migration + a real read; a corrupt file throws here.
      await db.customSelect('SELECT count(*) FROM kitchen_spool_jobs').get();
    } on Exception {
      await db.close();
      throw const KitchenSpoolDatabaseUnavailableException(
        'spool_database_open_failed',
      );
    }
    return db;
  }
}
