@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/source_boundary.dart';

/// KITCHEN-MODE-001C2A CI fix — regression coverage for the CI-portable
/// source-boundary scan itself: the resolver must work from ANY working
/// directory and path style, the scanner must catch a real prohibited
/// reference, comments must not false-positive, and unrelated
/// test/build/.dart_tool content must be unable to influence the result.
void main() {
  test(
    'resolver finds the package root from the CURRENT working directory',
    () {
      final root = locateDataLocalPackageRoot();
      expect(p.isAbsolute(root.path), isTrue);
      expect(
        File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
        contains('name: restoflow_data_local'),
      );
    },
  );

  test('resolver works from BOTH the repository root and the package directory '
      '(the two CI/local working directories)', () {
    final canonical = locateDataLocalPackageRoot();
    final repoRoot = canonical.parent.parent; // packages/data_local -> repo
    final original = Directory.current;
    addTearDown(() => Directory.current = original);

    Directory.current = repoRoot;
    expect(
      p.equals(locateDataLocalPackageRoot().path, canonical.path),
      isTrue,
      reason: 'repo-root cwd (the CI invocation) must resolve',
    );

    Directory.current = canonical;
    expect(
      p.equals(locateDataLocalPackageRoot().path, canonical.path),
      isTrue,
      reason: 'package cwd (the local invocation) must resolve',
    );
  });

  test('resolver accepts POSIX-style and platform-style path input', () {
    final canonical = locateDataLocalPackageRoot();
    // Forward slashes are valid on every supported platform.
    final posixStyle = Directory(canonical.path.replaceAll(r'\', '/'));
    expect(
      p.equals(
        locateDataLocalPackageRoot(from: posixStyle).path,
        canonical.path,
      ),
      isTrue,
    );
    if (Platform.isWindows) {
      final windowsStyle = Directory(canonical.path.replaceAll('/', r'\'));
      expect(
        p.equals(
          locateDataLocalPackageRoot(from: windowsStyle).path,
          canonical.path,
        ),
        isTrue,
      );
    }
  });

  test(
    'resolver FAILS CLEARLY (never vacuously passes) outside the repo',
    () async {
      final outside = await Directory.systemTemp.createTemp('kmc2a_outside');
      addTearDown(() => outside.delete(recursive: true));
      expect(
        () => locateDataLocalPackageRoot(from: outside),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('refuses to pass vacuously'),
          ),
        ),
      );
    },
  );

  test('scan reads ONLY the named production database sources — synthetic '
      'test/build/.dart_tool content cannot influence the verdict', () async {
    final fake = await Directory.systemTemp.createTemp('kmc2a_fakepkg');
    addTearDown(() => fake.delete(recursive: true));
    File(
      p.join(fake.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: restoflow_data_local\n');
    final srcDir = Directory(p.join(fake.path, 'lib', 'src'))
      ..createSync(recursive: true);
    File(
      p.join(srcDir.path, 'local_database.dart'),
    ).writeAsStringSync('class LocalDatabase {}\n');
    File(
      p.join(srcDir.path, 'local_database.g.dart'),
    ).writeAsStringSync('mixin GeneratedBits {}\n');
    // Hostile content in places the scan must IGNORE.
    for (final ignored in [
      ['test', 'evil_test.dart'],
      ['build', 'junk.dart'],
      ['.dart_tool', 'cache.dart'],
    ]) {
      final dir = Directory(p.join(fake.path, ignored[0]))
        ..createSync(recursive: true);
      File(p.join(dir.path, ignored[1])).writeAsStringSync(
        'final k = KitchenSpoolKeyManager(store); // provisionKey',
      );
    }
    final code = readDatabaseSourcesCodeOnly(fake);
    expect(findCryptoBoundaryViolation(code), isNull);
  });

  test('a synthetic prohibited PRODUCTION reference IS detected', () async {
    final fake = await Directory.systemTemp.createTemp('kmc2a_dirty');
    addTearDown(() => fake.delete(recursive: true));
    File(
      p.join(fake.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: restoflow_data_local\n');
    final srcDir = Directory(p.join(fake.path, 'lib', 'src'))
      ..createSync(recursive: true);
    File(p.join(srcDir.path, 'local_database.dart')).writeAsStringSync(
      'class LocalDatabase {\n'
      '  Future<void> open() => manager.provisionKey();\n'
      '}\n',
    );
    File(
      p.join(srcDir.path, 'local_database.g.dart'),
    ).writeAsStringSync('mixin GeneratedBits {}\n');
    final code = readDatabaseSourcesCodeOnly(fake);
    expect(findCryptoBoundaryViolation(code), 'provisionKey');
  });

  test('comments never create false positives (code-only contract)', () {
    const commented = '''
// SecureKeyStore is mentioned here in a comment.
/// So is provisionKey and KitchenSpoolCipher.
class LocalDatabase {}
''';
    expect(
      findCryptoBoundaryViolation(stripFullLineComments(commented)),
      isNull,
    );
    // And every prohibited identifier IS caught when it appears in code
    // (detection is the contract; overlapping identifiers may report the
    // containing/earlier name, e.g. AesGcmKitchenSpoolCipher reports
    // KitchenSpoolCipher).
    for (final identifier in kSpoolCryptoBoundaryIdentifiers) {
      expect(
        findCryptoBoundaryViolation('final x = $identifier;'),
        isNotNull,
        reason: '$identifier must be detected',
      );
    }
  });

  test(
    'scan fails clearly when an expected database source is missing',
    () async {
      final fake = await Directory.systemTemp.createTemp('kmc2a_missing');
      addTearDown(() => fake.delete(recursive: true));
      File(
        p.join(fake.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: restoflow_data_local\n');
      expect(
        () => readDatabaseSourcesCodeOnly(fake),
        throwsA(isA<StateError>()),
      );
    },
  );
}
