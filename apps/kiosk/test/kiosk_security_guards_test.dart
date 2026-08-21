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

  test('media access goes ONLY through the shared resolver abstraction '
      '(KIOSK-001-PREREQ-083)', () {
    for (final f in _dartSources()) {
      final src = f.readAsStringSync();
      // The raw storage SDK, bucket names, and signing calls stay
      // forbidden in the client — signing happens behind the shared
      // DeviceImageUrlResolver seam (`createSignedUrl` also covers the
      // batch `createSignedUrlsResult`).
      expect(src.contains('createSignedUrl'), isFalse, reason: f.path);
      expect(src.contains('SupabaseClient'), isFalse, reason: f.path);
      expect(src.contains('.storage'), isFalse, reason: f.path);
      expect(src.contains('StorageFileApi'), isFalse, reason: f.path);
      expect(src.contains('menu-images'), isFalse, reason: f.path);
    }
    // The one allowed media seam exists where the runtime consumes it.
    final runtime = File(
      '${_libDir().path}/src/state/kiosk_live_runtime.dart',
    ).readAsStringSync();
    expect(runtime.contains('DeviceImageUrlResolver'), isTrue);
  });

  test('no signed URL is ever persisted (in-memory state only)', () {
    // URLs expire in minutes; persisting one would serve dead images after
    // a restart and leak a (time-limited) capability into device storage.
    for (final f in _dartSources()) {
      final src = f.readAsStringSync();
      if (src.contains('imageUrls') || src.contains('signedUrlsFor')) {
        expect(
          src.contains('SharedPreferences'),
          f.path.endsWith('main.dart'),
          reason:
              '${f.path}: prefs may appear only in the composition root '
              '(the session secret store), never beside URL state',
        );
      }
    }
  });
}
