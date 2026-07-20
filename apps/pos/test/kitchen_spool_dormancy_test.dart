@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    libSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(libSources, isNotEmpty);
    mainSource = File('lib/main.dart').readAsStringSync();
  });

  String allSourcesExcept(bool Function(String path) excluded) {
    final buffer = StringBuffer();
    for (final f in libSources) {
      final normalized = f.path.replaceAll('\\', '/');
      if (excluded(normalized)) continue;
      buffer.writeln(f.readAsStringSync());
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
    expect(outside, isNot(contains('FlutterSecureKitchenSpoolKeyStore')));
    expect(outside, isNot(contains('PosKitchenSpoolPlatform')));
    expect(outside, isNot(contains('KitchenSpoolKeyManager')));
    expect(outside, isNot(contains('kitchen_spool')));
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
