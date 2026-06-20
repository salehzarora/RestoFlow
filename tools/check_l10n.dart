// RestoFlow - Flutter-FREE l10n structural check (RF-020 / RF020-B1).
//
// Proves the ARB resources and the COMMITTED Flutter gen-l10n output are present
// and structurally consistent WITHOUT invoking the Flutter tool. This complements
// (does NOT replace) `flutter test packages/l10n`, which additionally proves the
// runtime RTL/LTR directionality. Useful as a CI gate that still works if the
// Flutter tool itself is unavailable in an environment.
//
// Checks: (1) the three ARB files exist, parse, are non-empty, and share an
// identical translation-key set (ignoring @-metadata); (2) the four committed
// gen-l10n files exist; (3) the generated AppLocalizations base declares the
// class and a getter for every ARB key.
//
// Run from the repo root:  dart run tools/check_l10n.dart
// Exit codes: 0 = OK, 1 = a structural problem was found.
import 'dart:convert';
import 'dart:io';

const String _arbDir = 'packages/l10n/lib/l10n';
const String _genDir = 'packages/l10n/lib/src/generated';

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

Set<String> _translationKeys(String path) {
  final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return map.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  var ok = true;
  void fail(String msg) {
    stderr.writeln('FAIL: $msg');
    ok = false;
  }

  // (1) ARB files: exist, parse, non-empty, identical key sets.
  final keys = <String, Set<String>>{};
  for (final locale in <String>['en', 'ar', 'he']) {
    final path = '$_arbDir/app_$locale.arb';
    if (!File(path).existsSync()) {
      fail('missing ARB file: $path');
      continue;
    }
    keys[locale] = _translationKeys(path);
  }
  if (keys.length == 3) {
    if (keys['en']!.isEmpty) fail('template (en) ARB defines no keys');
    for (final locale in <String>['ar', 'he']) {
      if (!_setEquals(keys[locale]!, keys['en']!)) {
        fail(
          '$locale ARB key set != en '
          '(missing: ${keys['en']!.difference(keys[locale]!)}, '
          'extra: ${keys[locale]!.difference(keys['en']!)})',
        );
      }
    }
  }

  // (2) Committed gen-l10n output present.
  const generated = <String>[
    'app_localizations.dart',
    'app_localizations_en.dart',
    'app_localizations_ar.dart',
    'app_localizations_he.dart',
  ];
  for (final name in generated) {
    final path = '$_genDir/$name';
    if (!File(path).existsSync()) {
      fail('missing committed gen-l10n file: $path');
    }
  }

  // (3) Generated base declares AppLocalizations + a getter for every ARB key.
  final base = File('$_genDir/app_localizations.dart');
  if (base.existsSync() && keys['en'] != null) {
    final src = base.readAsStringSync();
    if (!src.contains('class AppLocalizations')) {
      fail('generated base does not declare class AppLocalizations');
    }
    for (final key in keys['en']!) {
      if (!RegExp('\\b$key\\b').hasMatch(src)) {
        fail('generated base is missing a member for ARB key "$key"');
      }
    }
  }

  if (ok) {
    stdout.writeln(
      'OK: l10n ARB + committed gen-l10n output are present and structurally '
      'consistent (Flutter-free check).',
    );
    exit(0);
  }
  exit(1);
}
