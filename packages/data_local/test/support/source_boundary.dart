/// KITCHEN-MODE-001C2A — CI-portable helpers for the kitchen-spool
/// SOURCE-BOUNDARY scan.
///
/// The security assertion they serve: the database open/migration code
/// (`lib/src/local_database.dart` and its generated part) must NEVER touch
/// crypto keys — no key store, no key manager, no cipher, no provisioning.
///
/// CI runs `dart test packages/data_local` from the REPOSITORY ROOT while
/// local runs usually start inside the package, so nothing here may assume
/// the process working directory or a path-separator style. Paths are
/// resolved via [locateDataLocalPackageRoot] (a deterministic ancestor
/// search) and joined with `package:path`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the `restoflow_data_local` package root regardless of the current
/// working directory: probes the current directory, its
/// `packages/data_local` child, and each ancestor (with the same child
/// probe), in that deterministic order. Throws a CLEAR [StateError] when the
/// package root cannot be found — the scan must fail loudly, never
/// vacuously pass.
Directory locateDataLocalPackageRoot({Directory? from}) {
  bool isPackageRoot(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    return pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: restoflow_data_local');
  }

  var current = (from ?? Directory.current).absolute;
  for (var depth = 0; depth < 10; depth++) {
    if (isPackageRoot(current)) return current;
    final nested = Directory(p.join(current.path, 'packages', 'data_local'));
    if (isPackageRoot(nested)) return nested;
    final parent = current.parent;
    if (p.equals(parent.path, current.path)) break;
    current = parent;
  }
  throw StateError(
    'Could not locate the restoflow_data_local package root from '
    '"${(from ?? Directory.current).path}" — the source-boundary scan '
    'refuses to pass vacuously.',
  );
}

/// The database/migration production sources under the boundary — EXACTLY
/// these two files, in this fixed order. Nothing under `test/`, `build/` or
/// `.dart_tool/` is ever read (the scan targets named production files, so
/// unrelated/generated/test content cannot influence it).
const List<String> kDatabaseSourceRelativePaths = [
  'lib/src/local_database.dart',
  'lib/src/local_database.g.dart',
];

/// Reads the database/migration sources as CODE ONLY: full-line comments are
/// stripped, so a doc-comment MENTION of a prohibited identifier can never
/// false-positive while any real import/reference (which must live in code)
/// still trips the scan.
String readDatabaseSourcesCodeOnly(Directory packageRoot) {
  final buffer = StringBuffer();
  for (final relative in kDatabaseSourceRelativePaths) {
    final file = File(p.join(packageRoot.path, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) {
      throw StateError(
        'Expected database source "$relative" under '
        '"${packageRoot.path}" — refusing a vacuous scan.',
      );
    }
    buffer.writeln(stripFullLineComments(file.readAsStringSync()));
  }
  return buffer.toString();
}

/// Removes full-line `//`/`///` comments (the scan contract ignores
/// comments; code lines are kept verbatim).
String stripFullLineComments(String source) {
  final kept = <String>[];
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    kept.add(line);
  }
  return kept.join('\n');
}

/// The prohibited crypto/key identifiers for the database/migration
/// boundary. Deliberately UNWEAKENED: every identifier that could smuggle a
/// key-store, key-manager, cipher, adapter or provisioning dependency into
/// database open/migration code.
const List<String> kSpoolCryptoBoundaryIdentifiers = [
  'SecureKeyStore',
  'KitchenSpoolKeyManager',
  'KitchenSpoolCipher',
  'AesGcmKitchenSpoolCipher',
  'FlutterSecureKitchenSpoolKeyStore',
  'provisionKey',
  'provisionPersistentKey',
  'kitchen_spool_cipher',
  'kitchen_spool_key_manager',
  'revealForCryptoBoundary',
];

/// Returns the FIRST prohibited identifier present in [codeOnlySource], or
/// `null` when the boundary holds. Deterministic (fixed identifier order).
String? findCryptoBoundaryViolation(String codeOnlySource) {
  for (final identifier in kSpoolCryptoBoundaryIdentifiers) {
    if (codeOnlySource.contains(identifier)) return identifier;
  }
  return null;
}
