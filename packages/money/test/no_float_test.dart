import 'dart:io';

import 'package:test/test.dart';

/// Package-local static assertion (RF-036 AC#1, DECISION D-007): no `double`,
/// `float`, or `num` whole-word token appears in any `packages/money/lib`
/// source file. Complements the repo-wide `tools/check_no_float_money.sh`.
///
/// Scans `lib/` only (not `test/`), so this test file's own regex literals are
/// not scanned. Word-boundary matching keeps `numerator`/`denominator`/`number`
/// safe.
void main() {
  test('packages/money/lib contains no fractional money types', () {
    Directory? libDir;
    for (final candidate in const ['packages/money/lib', 'lib']) {
      final dir = Directory(candidate);
      if (dir.existsSync()) {
        libDir = dir;
        break;
      }
    }
    expect(libDir, isNotNull, reason: 'could not locate packages/money/lib');

    final forbidden = RegExp(r'\b(double|float|num)\b');
    final offenders = <String>[];
    for (final entity in libDir!.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (forbidden.hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'forbidden fractional-money type(s) found in: $offenders',
    );
  });
}
