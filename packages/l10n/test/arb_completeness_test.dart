import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RF-020: ARB completeness — every locale must define exactly the same set of
/// translation keys (a missing/extra key fails this check). Metadata keys
/// (starting with `@`, incl. `@@locale`) are ignored.
///
/// The ARB directory is located robustly so the test works whether the working
/// directory is the package root (`flutter test` run inside packages/l10n) or
/// the repo root (`flutter test packages/l10n`).
String _arbDir() {
  for (final candidate in <String>['lib/l10n', 'packages/l10n/lib/l10n']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  fail('Could not locate the ARB directory from CWD ${Directory.current.path}');
}

Set<String> _translationKeys(String path) {
  final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return map.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('ar/he/en ARB files expose identical translation key sets', () {
    final dir = _arbDir();
    final en = _translationKeys('$dir/app_en.arb');
    final ar = _translationKeys('$dir/app_ar.arb');
    final he = _translationKeys('$dir/app_he.arb');

    expect(en, isNotEmpty, reason: 'template (en) must define keys');

    expect(
      en.difference(ar),
      isEmpty,
      reason: 'ar is MISSING keys present in en: ${en.difference(ar)}',
    );
    expect(
      ar.difference(en),
      isEmpty,
      reason: 'ar has EXTRA keys not in en: ${ar.difference(en)}',
    );
    expect(
      en.difference(he),
      isEmpty,
      reason: 'he is MISSING keys present in en: ${en.difference(he)}',
    );
    expect(
      he.difference(en),
      isEmpty,
      reason: 'he has EXTRA keys not in en: ${he.difference(en)}',
    );
  });
}
