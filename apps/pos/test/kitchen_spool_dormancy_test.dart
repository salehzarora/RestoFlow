@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2A §13 — runtime dormancy / source-boundary proof.
///
/// The encrypted kitchen spool ships as DORMANT foundation code: nothing in
/// POS production composition may instantiate it, no server kitchen RPC may
/// gain a caller, and no browser storage may be involved anywhere near it.
/// These are STRING-LEVEL scans of the production sources (`lib/`), so a
/// future wiring attempt fails this test until it happens in its own
/// reviewed phase (001C2B+).
void main() {
  late final List<File> libSources;
  late final String mainSource;

  setUpAll(() {
    // CI-PORTABLE: CI runs `flutter test apps/pos` from the REPOSITORY ROOT
    // while local runs start inside the app — resolve the app root instead
    // of assuming the working directory.
    final appRoot = locatePosPackageRoot();
    libSources =
        Directory(p.join(appRoot.path, 'lib'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)); // deterministic order
    expect(libSources, isNotEmpty);
    mainSource = File(
      p.join(appRoot.path, 'lib', 'main.dart'),
    ).readAsStringSync();
  });

  String allSourcesExcept(bool Function(String path) excluded) {
    final buffer = StringBuffer();
    for (final f in libSources) {
      final normalized = f.path.replaceAll('\\', '/');
      if (excluded(normalized)) continue;
      // CLEANUP 7E: scan CODE ONLY — comment lines are stripped so a
      // doc-comment MENTION (e.g. outbox_repository's LocalDatabase note)
      // does not mask the detector, while any real import/alias/reference
      // (which must live in code) still trips it.
      for (final line in f.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  test(
    'main.dart (the production composition root) never touches the spool',
    () {
      expect(mainSource, isNot(contains('kitchen_spool')));
      expect(mainSource, isNot(contains('KitchenSpool')));
      expect(mainSource, isNot(contains('restoflow_data_local')));
      expect(mainSource, isNot(contains('LocalDatabase')));
      expect(mainSource, isNot(contains('ProtectedLocalDatabaseFactory')));
    },
  );

  test('NO production source outside lib/src/spool references the spool', () {
    final outside = allSourcesExcept((p) => p.contains('lib/src/spool/'));
    // CLEANUP 7E: identifier set hardened against alias/barrel/indirect
    // construction bypasses — an aliased import still carries the package
    // path string, and ANY reference to these types/members must name them.
    for (final needle in [
      'FlutterSecureKitchenSpoolKeyStore',
      'PosKitchenSpoolPlatform',
      'KitchenSpoolKeyManager',
      'KitchenSpoolCipher',
      'AesGcmKitchenSpoolCipher',
      'DriftKitchenSpoolStore',
      'KitchenSpoolStore',
      'KitchenSpoolAad',
      'KitchenSpoolLocalPayload',
      'kitchen_spool',
      'KitchenSpool',
      'provisionKey',
      'provisionPersistentKey',
      'LocalDatabase',
      'ProtectedLocalDatabaseFactory',
    ]) {
      expect(
        outside,
        isNot(contains(needle)),
        reason: '"$needle" must not appear outside lib/src/spool',
      );
    }
  });

  test(
    'POS production code has NO restoflow_data_local import (no runtime DB)',
    () {
      final all = allSourcesExcept((_) => false);
      expect(all, isNot(contains('package:restoflow_data_local')));
    },
  );

  test(
    'no readiness / dispatch-pull / ack / mode-setter caller exists in POS',
    () {
      final all = allSourcesExcept((_) => false);
      for (final rpc in [
        'report_kitchen_printer_readiness',
        'pull_kitchen_print_dispatches',
        'acknowledge_kitchen_print_dispatch',
        'set_kitchen_workflow_mode',
        'get_kitchen_workflow_transition_readiness',
      ]) {
        expect(all, isNot(contains(rpc)), reason: '$rpc must have NO caller');
      }
    },
  );

  test('the spool layer never touches SharedPreferences/localStorage', () {
    final spool = allSourcesExcept((p) => !p.contains('lib/src/spool/'));
    expect(spool, isNotEmpty);
    // Code-level usage patterns (doc comments may NAME the prohibition).
    expect(spool, isNot(contains('package:shared_preferences')));
    expect(spool, isNot(contains('SharedPreferences.')));
    expect(spool, isNot(contains('getInstance(')));
    expect(spool, isNot(contains('localStorage')));
    expect(spool, isNot(contains('window.')));
  });

  test('the spool layer never logs or prints (no secret leak channel)', () {
    final spool = allSourcesExcept((p) => !p.contains('lib/src/spool/'));
    expect(spool, isNot(contains('print(')));
    expect(spool, isNot(contains('debugPrint')));
    expect(spool, isNot(contains('log(')));
  });
}
