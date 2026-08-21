import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KIOSK-001 Phase 3 — client security guards, enforced as source scans (the
/// dashboard `dashboard_kitchen_workflow_toggle_test.dart` idiom, CWD-agnostic
/// for `flutter test apps/kiosk` from the repo root or the app dir).
///
/// Phase-3 contract: the kiosk client has NO submit path, NO offline order
/// machinery, NO privileged credentials, and NEVER handles the raw session
/// token outside the shared secret-store seam.
Directory _libDir() {
  for (final candidate in ['lib', 'apps/kiosk/lib']) {
    final dir = Directory(candidate);
    if (dir.existsSync() && File('${dir.path}/main.dart').existsSync()) {
      return dir;
    }
  }
  throw StateError('apps/kiosk/lib not found from ${Directory.current.path}');
}

Iterable<File> _dartSources() => _libDir()
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no kiosk_submit_order reference exists anywhere in the client', () {
    for (final f in _dartSources()) {
      expect(
        f.readAsStringSync().contains('kiosk_submit_order'),
        isFalse,
        reason:
            '${f.path} references the submit RPC — Phase 3 must not wire it',
      );
    }
  });

  test('no privileged credential material can appear in the client', () {
    for (final f in _dartSources()) {
      final src = f.readAsStringSync();
      expect(src.contains('service_role'), isFalse, reason: f.path);
      expect(src.contains('sb_secret_'), isFalse, reason: f.path);
    }
  });

  test('no offline order machinery (owner: ONLINE-REQUIRED, no outbox)', () {
    for (final f in _dartSources()) {
      final src = f.readAsStringSync().toLowerCase();
      expect(src.contains('outbox'), isFalse, reason: f.path);
      expect(src.contains('sync_push'), isFalse, reason: f.path);
    }
  });

  test('the raw session token is never logged or printed', () {
    for (final f in _dartSources()) {
      final src = f.readAsStringSync();
      // The kiosk client contains no print/debugPrint/log call at all, so a
      // token can never reach one. Tighten deliberately: any future logging
      // must come back through this guard with a redaction argument.
      expect(src.contains('print('), isFalse, reason: f.path);
      expect(src.contains('log('), isFalse, reason: f.path);
      // The token is only ever passed as the RPC param / secret-store value —
      // never interpolated into a string.
      expect(src.contains(r'$sessionToken'), isFalse, reason: f.path);
      expect(src.contains(r'${cred.sessionToken}'), isFalse, reason: f.path);
    }
  });

  test('the kiosk web surface uses its OWN session-store prefix', () {
    final main = File('${_libDir().path}/main.dart').readAsStringSync();
    expect(main.contains('kKioskDeviceSessionPrefix'), isTrue);
    expect(main.contains('kPosDeviceSessionPrefix'), isFalse);
    expect(main.contains('kKdsDeviceSessionPrefix'), isFalse);
  });

  test('no storage-policy or bucket surface was added to the client', () {
    for (final f in _dartSources()) {
      final src = f.readAsStringSync();
      expect(src.contains('createSignedUrl'), isFalse, reason: f.path);
      expect(src.contains('storage.'), isFalse, reason: f.path);
      expect(src.contains('menu-images'), isFalse, reason: f.path);
    }
  });
}
