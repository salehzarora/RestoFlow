@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2A CI fix — regression coverage for the POS package-root
/// resolver: it must work from BOTH working directories CI/local actually
/// use, restore any global state it touches even when assertions throw, and
/// fail clearly rather than pass vacuously.
void main() {
  test('resolver finds the app root from the current working directory', () {
    final root = locatePosPackageRoot();
    expect(p.isAbsolute(root.path), isTrue);
    expect(
      File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
      contains('name: restoflow_pos'),
    );
  });

  test(
    'resolver works from BOTH the repository root (CI) and the app '
    'directory (local), and Directory.current is restored even on failure',
    () {
      final canonical = locatePosPackageRoot();
      final repoRoot = canonical.parent.parent; // apps/pos -> repo root
      final original = Directory.current;
      // addTearDown runs on BOTH success and thrown assertions, so the
      // process-global working directory can never leak into later tests.
      addTearDown(() => Directory.current = original);

      Directory.current = repoRoot;
      expect(
        p.equals(locatePosPackageRoot().path, canonical.path),
        isTrue,
        reason: 'repo-root cwd (the CI invocation) must resolve',
      );

      Directory.current = canonical;
      expect(
        p.equals(locatePosPackageRoot().path, canonical.path),
        isTrue,
        reason: 'app cwd (the local invocation) must resolve',
      );
    },
  );

  test(
    'resolver FAILS CLEARLY (never vacuously) outside the repository',
    () async {
      final outside = await Directory.systemTemp.createTemp('kmc2a_pos_out');
      addTearDown(() => outside.delete(recursive: true));
      expect(
        () => locatePosPackageRoot(from: outside),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('refuse to pass vacuously'),
          ),
        ),
      );
    },
  );
}
