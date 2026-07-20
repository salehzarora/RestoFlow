/// KITCHEN-MODE-001C2A — CI-portable POS package-root resolution for tests
/// that read repository files (the backup-contract and dormancy scans).
///
/// CI runs `flutter test apps/pos` from the REPOSITORY ROOT while local runs
/// usually start inside the app, so no file-reading test may assume the
/// process working directory or a path-separator style. Mirrors the
/// `restoflow_data_local` test-support resolver.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the `restoflow_pos` app root regardless of the current working
/// directory: probes the current directory, its `apps/pos` child, and each
/// ancestor (with the same child probe), in that deterministic order.
/// Throws a CLEAR [StateError] when the root cannot be found — the scans
/// must fail loudly, never vacuously pass.
Directory locatePosPackageRoot({Directory? from}) {
  bool isPosRoot(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    return pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: restoflow_pos');
  }

  var current = (from ?? Directory.current).absolute;
  for (var depth = 0; depth < 10; depth++) {
    if (isPosRoot(current)) return current;
    final nested = Directory(p.join(current.path, 'apps', 'pos'));
    if (isPosRoot(nested)) return nested;
    final parent = current.parent;
    if (p.equals(parent.path, current.path)) break;
    current = parent;
  }
  throw StateError(
    'Could not locate the restoflow_pos app root from '
    '"${(from ?? Directory.current).path}" — the repository-file scans '
    'refuse to pass vacuously.',
  );
}
