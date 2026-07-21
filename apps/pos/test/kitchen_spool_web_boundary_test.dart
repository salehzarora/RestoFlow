@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition.dart';
import 'package:restoflow_pos/src/spool/pos_kitchen_spool_composition_web.dart'
    as web;

import 'support/pos_package_root.dart';

/// KITCHEN-MODE-001C2B — the WEB compile boundary (PR #178 Vercel fix).
///
/// The Flutter WEB compiler must be able to link `main.dart` without ever
/// reaching dart:io / dart:ffi / drift/NativeDatabase / sqlite3 /
/// path_provider. The composition seam guarantees that with a conditional
/// import whose DEFAULT branch is the web file; these tests pin the
/// boundary so a future edit cannot silently re-open it. Imports are parsed
/// as REAL directive URIs (never bare substring scans).
final RegExp _importDirective = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Libraries that must NEVER be reachable from the web-visible spool
/// composition unit (exact URI prefixes).
const List<String> _bannedWebImports = [
  'dart:io',
  'dart:ffi',
  'package:restoflow_data_local/',
  'package:path_provider/',
  'package:drift/',
  'package:sqlite3/',
  'package:flutter_secure_storage/',
];

List<String> _importsOf(File file) => [
  for (final match in _importDirective.allMatches(file.readAsStringSync()))
    match.group(1)!,
];

void main() {
  late final Directory appRoot;
  late final Directory spoolDir;

  setUpAll(() {
    appRoot = locatePosPackageRoot();
    spoolDir = Directory(p.join(appRoot.path, 'lib', 'src', 'spool'));
  });

  File spoolFile(String name) => File(p.join(spoolDir.path, name));

  test('the composition conditional import DEFAULTS to the web branch and '
      'links the native branch ONLY under dart.library.io', () {
    final source = spoolFile(
      'pos_kitchen_spool_composition.dart',
    ).readAsStringSync();
    final conditional = RegExp(
      "import\\s+'pos_kitchen_spool_composition_web\\.dart'\\s*"
      "if\\s*\\(dart\\.library\\.io\\)\\s*"
      "'pos_kitchen_spool_composition_native\\.dart'\\s*;",
    );
    expect(
      conditional.hasMatch(source),
      isTrue,
      reason:
          'the DEFAULT (web) target must be the web file; the native '
          'file may be linked only behind dart.library.io',
    );
  });

  test('the WEB-REACHABLE spool closure (composition default branch) never '
      'imports a native-only library', () {
    // Walk the web branch's transitive closure over RELATIVE imports; the
    // native file is excluded because the conditional default never links
    // it on web.
    final visited = <String>{};
    final queue = ['pos_kitchen_spool_composition.dart'];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!visited.add(name)) continue;
      // The conditional import's io-branch URI appears in the directive
      // list too — skip exactly that native target, as the web compiler
      // does.
      for (final uri in _importsOf(spoolFile(name))) {
        if (uri == 'pos_kitchen_spool_composition_native.dart') continue;
        for (final banned in _bannedWebImports) {
          expect(
            uri == banned || uri.startsWith(banned),
            isFalse,
            reason: '$name imports "$uri" — banned on the web path',
          );
        }
        if (!uri.contains(':')) queue.add(uri);
      }
    }
    expect(
      visited,
      containsAll([
        'pos_kitchen_spool_composition.dart',
        'pos_kitchen_spool_composition_web.dart',
        'pos_kitchen_spool_hooks.dart',
        // PASS 2: the capability surface is web-visible and must stay pure.
        'pos_kitchen_spool_capability.dart',
      ]),
      reason: 'refuses to pass vacuously',
    );
  });

  test('the capability surface is PURE Dart (zero imports)', () {
    expect(_importsOf(spoolFile('pos_kitchen_spool_capability.dart')), isEmpty);
  });

  test('the hooks surface is PURE Dart (zero imports)', () {
    expect(_importsOf(spoolFile('pos_kitchen_spool_hooks.dart')), isEmpty);
  });

  test('the lifecycle hook imports ONLY the composition seam — never the '
      'native runtime file directly', () {
    final imports = _importsOf(
      File(
        p.join(
          appRoot.path,
          'lib',
          'src',
          'widgets',
          'pos_sync_lifecycle.dart',
        ),
      ),
    );
    expect(imports, contains('../spool/pos_kitchen_spool_composition.dart'));
    expect(
      imports.any((uri) => uri.endsWith('pos_kitchen_spool_runtime.dart')),
      isFalse,
      reason: 'a direct runtime import would re-open the web ffi chain',
    );
  });

  test('the NATIVE branch is the only composition file allowed to reach '
      'data_local/path_provider (sanity: the boundary is not vacuous)', () {
    final nativeImports = _importsOf(
      spoolFile('pos_kitchen_spool_composition_native.dart'),
    );
    expect(
      nativeImports.any(
        (uri) => uri.startsWith('package:restoflow_data_local/'),
      ),
      isTrue,
    );
    expect(
      nativeImports.any((uri) => uri.startsWith('package:path_provider/')),
      isTrue,
    );
  });

  test(
    'the WEB composition branch returns null (fail closed, no fallback)',
    () {
      final probe = Provider<Object?>(
        (ref) => web.buildPosKitchenSpoolRuntime(ref),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(probe), isNull);
    },
  );

  test('the NATIVE composition provider stays wired and inert in demo mode '
      '(VM links the io branch of the SAME conditional)', () {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(posKitchenSpoolRuntimeProvider), isNull);
  });
}
