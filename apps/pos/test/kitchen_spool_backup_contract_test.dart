@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show kKitchenSpoolDatabaseDirectoryName, kKitchenSpoolDatabaseFileName;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2A CLEANUP 1 — the Android backup-path CONTRACT guard.
///
/// The review-approved cross-phase precondition: 001C2B MUST open the runtime
/// kitchen spool as a DEDICATED database at the exact path the Android backup
/// rules exclude. This test binds the actual Dart constants (the single
/// source of truth — deliberately NOT re-hardcoded here) to the XML backup
/// resources and the manifest, so renaming the constant without updating the
/// XML fails the build, and vice versa.
void main() {
  late final String backupRules;
  late final String extractionRules;
  late final String manifest;

  setUpAll(() {
    // CI-PORTABLE: CI runs `flutter test apps/pos` from the REPOSITORY ROOT
    // while local runs start inside the app — resolve the app root instead
    // of assuming the working directory.
    final appRoot = locatePosPackageRoot();
    String readUnderMain(List<String> parts) => File(
      p.joinAll([appRoot.path, 'android', 'app', 'src', 'main', ...parts]),
    ).readAsStringSync();
    backupRules = readUnderMain(['res', 'xml', 'backup_rules.xml']);
    extractionRules = readUnderMain([
      'res',
      'xml',
      'data_extraction_rules.xml',
    ]);
    manifest = readUnderMain(['AndroidManifest.xml']);
  });

  // Every Android backup domain the spool directory must be excluded under
  // (root covers Flutter's app_flutter documents dir; file covers
  // getFilesDir; database covers the databases dir).
  final requiredDirectoryExcludes = [
    'domain="root" path="app_flutter/$kKitchenSpoolDatabaseDirectoryName"',
    'domain="file" path="$kKitchenSpoolDatabaseDirectoryName"',
    'domain="database" path="$kKitchenSpoolDatabaseDirectoryName"',
  ];

  const secureStorageExcludes = [
    'domain="sharedpref" path="FlutterSecureStorage.xml"',
    'domain="sharedpref" path="FlutterSecureKeyStorage.xml"',
  ];

  test('001C2B PRECONDITION: backup_rules.xml excludes the DEDICATED spool '
      'directory (from the Dart constant) under every required domain', () {
    for (final exclude in requiredDirectoryExcludes) {
      expect(backupRules, contains('<exclude $exclude'));
    }
  });

  test('001C2B PRECONDITION: data_extraction_rules.xml excludes the spool '
      'directory in BOTH cloud-backup and device-transfer sections', () {
    final cloud = extractionRules.substring(
      extractionRules.indexOf('<cloud-backup>'),
      extractionRules.indexOf('</cloud-backup>'),
    );
    final transfer = extractionRules.substring(
      extractionRules.indexOf('<device-transfer>'),
      extractionRules.indexOf('</device-transfer>'),
    );
    for (final section in [cloud, transfer]) {
      for (final exclude in requiredDirectoryExcludes) {
        expect(section, contains('<exclude $exclude'));
      }
    }
  });

  test('both secure-storage preference files (current + legacy plugin names) '
      'are excluded in BOTH resources', () {
    for (final exclude in secureStorageExcludes) {
      expect(backupRules, contains('<exclude $exclude'));
    }
    final cloud = extractionRules.substring(
      extractionRules.indexOf('<cloud-backup>'),
      extractionRules.indexOf('</cloud-backup>'),
    );
    final transfer = extractionRules.substring(
      extractionRules.indexOf('<device-transfer>'),
      extractionRules.indexOf('</device-transfer>'),
    );
    for (final section in [cloud, transfer]) {
      for (final exclude in secureStorageExcludes) {
        expect(section, contains('<exclude $exclude'));
      }
    }
  });

  test('AndroidManifest wires BOTH backup resources', () {
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('001C2B PRECONDITION: the database FILE lives under the excluded '
      'directory contract (bare filename; no path separators)', () {
    // The file constant must be a bare name so the dedicated-database open
    // (001C2B) composes it UNDER the excluded directory — a path separator
    // here would silently escape the backup exclusion.
    expect(kKitchenSpoolDatabaseFileName, isNot(contains('/')));
    expect(kKitchenSpoolDatabaseFileName, isNot(contains(r'\')));
    expect(kKitchenSpoolDatabaseFileName, isNotEmpty);
    expect(kKitchenSpoolDatabaseDirectoryName, isNot(contains('/')));
    expect(kKitchenSpoolDatabaseDirectoryName, isNotEmpty);
  });

  test('backup XML resources are well-formed enough to compile (smoke)', () {
    // aapt-level validation happens in an Android build; this smoke check
    // catches unbalanced tags/quotes without requiring a gradle run.
    for (final xml in [backupRules, extractionRules]) {
      expect('<'.allMatches(xml).length, '>'.allMatches(xml).length);
      expect(
        xml.contains('<full-backup-content>') ||
            xml.contains('<data-extraction-rules>'),
        isTrue,
      );
      expect('"'.allMatches(xml).length.isEven, isTrue);
    }
  });
}
