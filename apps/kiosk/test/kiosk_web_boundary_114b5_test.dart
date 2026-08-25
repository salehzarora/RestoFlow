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

/// CI-portable kiosk package-root resolution (mirrors the POS
/// `locatePosPackageRoot` test support): CI runs `flutter test apps/kiosk`
/// from the REPOSITORY ROOT while local runs usually start inside the app, so
/// the current directory, its `apps/kiosk` child and each ancestor (with the
/// same child probe) are tried in that order; the root is identified by its
/// own pubspec name, never by directory shape alone.
Directory _kioskLib() {
  bool isKioskRoot(Directory dir) {
    final pubspec = File(_join([dir.path, 'pubspec.yaml']));
    return pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: restoflow_kiosk');
  }

  var dir = Directory.current.absolute;
  for (var depth = 0; depth < 10; depth++) {
    if (isKioskRoot(dir)) return Directory(_join([dir.path, 'lib']));
    final nested = Directory(_join([dir.path, 'apps', 'kiosk']));
    if (isKioskRoot(nested)) return Directory(_join([nested.path, 'lib']));
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
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
