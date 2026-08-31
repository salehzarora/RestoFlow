import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADMIN-126B2 — the support handoff opens a CROSS-ORIGIN Dashboard tab, so its
/// web opener MUST sever `window.opener` (reverse-tabnabbing) and suppress the
/// Referer. `dart:html` cannot be imported under the VM test runner, so this is
/// a SOURCE-CONTRACT guard on the one web seam every support launch funnels
/// through (`supportUrlOpenerProvider` -> `openExternalUrl`). It fails the day
/// someone reintroduces a bare `window.open(url, '_blank')`.
File _repoFile(String fromAdmin, String fromRoot) {
  final local = File(fromAdmin);
  return local.existsSync() ? local : File(fromRoot);
}

void main() {
  group('support handoff opener is protected', () {
    final web = _repoFile(
      'lib/src/util/external_link_web.dart',
      'apps/admin/lib/src/util/external_link_web.dart',
    );

    test('the web opener exists', () {
      expect(
        web.existsSync(),
        isTrue,
        reason: 'the web opener seam is missing',
      );
    });

    test('window.open passes noopener and noreferrer', () {
      final src = web.readAsStringSync();
      // The exact protected call — a bare two-arg window.open must never return.
      expect(
        src.contains("html.window.open(url, '_blank', 'noopener,noreferrer')"),
        isTrue,
        reason: 'the support tab must be opened with noopener,noreferrer',
      );
      expect(
        RegExp(r"window\.open\(\s*url\s*,\s*'_blank'\s*\)").hasMatch(src),
        isFalse,
        reason: 'a bare _blank window.open leaks a usable opener (tabnabbing)',
      );
    });

    test('the opener seam never persists or query-strings the token', () {
      final src = web.readAsStringSync();
      // The token belongs only in the URL fragment the caller built; this seam
      // must not stash it or add a query param.
      expect(src.contains('localStorage'), isFalse);
      expect(src.contains('sessionStorage'), isFalse);
      expect(src.contains('?token'), isFalse);
    });
  });
}
