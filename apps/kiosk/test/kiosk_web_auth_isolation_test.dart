import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KIOSK-001-WEB-089 — the kiosk web entry must carry the SAME
/// WEB-AUTH-SESSION-ISOLATION-001 BroadcastChannel guard as POS/KDS: on the
/// shared hosted origin (/, /pos/, /kds/, /kiosk/), GoTrue's
/// `sb-<ref>-auth-token` channel would otherwise let a Dashboard staff
/// session and the kiosk's anonymous device session cross-adopt.
File _repoFile(String relative) {
  for (final prefix in ['', '../../']) {
    final f = File('$prefix$relative');
    if (f.existsSync()) return f;
  }
  throw StateError('$relative not found from ${Directory.current.path}');
}

/// The guard's executable block: from the IIFE opening to the script close.
String _guardScript(String indexHtml) {
  final marker = indexHtml.indexOf('WEB-AUTH-SESSION-ISOLATION-001');
  expect(marker, greaterThanOrEqualTo(0), reason: 'guard marker missing');
  final start = indexHtml.indexOf('(function () {', marker);
  final end = indexHtml.indexOf('</script>', start);
  expect(start, greaterThan(marker));
  expect(end, greaterThan(start));
  return indexHtml.substring(start, end).trim();
}

void main() {
  final kiosk = _repoFile('apps/kiosk/web/index.html').readAsStringSync();

  test('the kiosk index carries the guard BEFORE flutter_bootstrap.js', () {
    expect(kiosk, contains('WEB-AUTH-SESSION-ISOLATION-001'));
    final guardAt = kiosk.indexOf('WEB-AUTH-SESSION-ISOLATION-001');
    // Anchor on the ACTUAL loader tag (a doc comment mentions the file name
    // earlier in the template).
    final bootstrapAt = kiosk.indexOf('<script src="flutter_bootstrap.js"');
    expect(bootstrapAt, greaterThanOrEqualTo(0));
    expect(
      guardAt,
      lessThan(bootstrapAt),
      reason: 'the channel must be replaced before the app engine loads',
    );
    // The shared-origin doc names all FOUR public routes.
    for (final route in ['/pos/', '/kds/', '/kiosk/']) {
      expect(kiosk, contains(route));
    }
  });

  test('the guard intercepts EXACTLY the Supabase auth channel and delegates '
      'every other channel to the native implementation', () {
    final script = _guardScript(kiosk);
    // Exact interception regex — never broader.
    expect(script, contains(r'/^sb-.*-auth-token$/'));
    // The silent same-shape stand-in for the auth channel...
    expect(script, contains('postMessage: function () {}'));
    // ...and native delegation for everything else.
    expect(script, contains('return new Native(name);'));
    expect(script, contains('Isolated.prototype = Native.prototype;'));
    expect(script, contains('window.BroadcastChannel = Isolated;'));
  });

  test(
    'the kiosk guard SCRIPT is byte-identical to the POS and KDS guards',
    () {
      final pos = _guardScript(
        _repoFile('apps/pos/web/index.html').readAsStringSync(),
      );
      final kds = _guardScript(
        _repoFile('apps/kds/web/index.html').readAsStringSync(),
      );
      final ours = _guardScript(kiosk);
      expect(ours, pos, reason: 'kiosk guard must match POS exactly');
      expect(ours, kds, reason: 'kiosk guard must match KDS exactly');
    },
  );

  test('the kiosk index stays free of secrets and submit wiring', () {
    expect(kiosk.contains('service_role'), isFalse);
    expect(kiosk.contains('sb_secret_'), isFalse);
    expect(kiosk.contains('kiosk_submit_order'), isFalse);
  });
}
