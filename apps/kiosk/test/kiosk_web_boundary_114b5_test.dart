import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KIOSK-PRINT-114B.5A — the kiosk WEB boundary.
///
/// The kiosk ships as a web route (`/kiosk`) too. 114B.2 imported the
/// `restoflow_data_local` package BARREL from the kitchen lane, which drags the
/// Drift/SQLite FFI stack onto `flutter build web` ("Only JS interop members
/// may be 'external'" from sqlite3's native bindings). The lane now reaches the
/// dispatch document model through the dedicated, drift-free library
/// `package:restoflow_data_local/kitchen_dispatch_document.dart`; this pins
/// that no kiosk library ever re-opens the FFI chain.
const _bannedWebImports = [
  'package:restoflow_data_local/restoflow_data_local.dart',
  'dart:ffi',
  'package:drift/',
  'package:sqlite3/',
];

final RegExp _importDirective = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

Directory _kioskLib() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final candidate = Directory(_join([dir.path, 'lib', 'src', 'print']));
    if (candidate.existsSync() &&
        File(_join([dir.path, 'pubspec.yaml'])).existsSync()) {
      return Directory(_join([dir.path, 'lib']));
    }
    dir = dir.parent;
  }
  throw StateError('kiosk package root not found from ${Directory.current}');
}

void main() {
  test('no kiosk library imports the data_local barrel / FFI stack', () {
    final offenders = <String>[];
    for (final file
        in _kioskLib()
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final match in _importDirective.allMatches(
        file.readAsStringSync(),
      )) {
        final uri = match.group(1)!;
        if (_bannedWebImports.any(uri.startsWith)) {
          offenders.add('${file.path} -> $uri');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'the kiosk web build must stay drift/ffi-free: $offenders',
    );
  });

  test('the kitchen lane reaches the dispatch model through the web-safe '
      'dedicated library', () {
    final lane = File(
      _join([
        _kioskLib().path,
        'src',
        'print',
        'kiosk_kitchen_auto_print.dart',
      ]),
    ).readAsStringSync();
    expect(
      lane,
      contains('package:restoflow_data_local/kitchen_dispatch_document.dart'),
    );
  });
}
