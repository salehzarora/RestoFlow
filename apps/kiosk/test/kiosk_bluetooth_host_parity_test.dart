import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KIOSK-001-106 — the kiosk Android host must carry the SAME in-house
/// Bluetooth Classic (SPP) MethodChannel as POS/KDS.
///
/// The v3 hardware failure happened because the kiosk shipped only the DART
/// half of `restoflow_native_printing`: without the native
/// `restoflow.native_printing/bluetooth` host in MainActivity.kt,
/// pairedDevices returns nothing and every Test Print fails. This guard
/// pins the host channel + its full method/behavior fingerprint against the
/// POS reference so a future kiosk change can never ship Dart-only
/// Bluetooth again. CWD-agnostic (repo root or app dir).
String _read(List<String> candidates) {
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError('none of $candidates found from ${Directory.current.path}');
}

void main() {
  final kiosk = _read([
    'android/app/src/main/kotlin/com/restoflow/kiosk/MainActivity.kt',
    'apps/kiosk/android/app/src/main/kotlin/com/restoflow/kiosk/MainActivity.kt',
  ]);
  final pos = _read([
    '../pos/android/app/src/main/kotlin/com/restoflow/pos/MainActivity.kt',
    'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/MainActivity.kt',
  ]);

  test('the kiosk host registers the exact shared Bluetooth channel with the '
      'full POS/KDS method set', () {
    expect(kiosk, contains('"restoflow.native_printing/bluetooth"'));
    for (final method in [
      '"permissionsGranted"',
      '"isEnabled"',
      '"pairedDevices"',
      '"printBytes"',
    ]) {
      expect(kiosk, contains(method), reason: '$method must be handled');
    }
    // The kiosk's own Phase-1 posture survives the port.
    expect(kiosk, contains('FLAG_KEEP_SCREEN_ON'));
    expect(kiosk, contains('package com.restoflow.kiosk'));
  });

  test('the kiosk host carries the POS/KDS behavioral fingerprint '
      '(SPP + secure->insecure RFCOMM + watchdog + chunked writes + '
      'serialized jobs), never a simplified rewrite', () {
    for (final marker in [
      // SPP + both RFCOMM variants (cheap printers need the insecure one).
      '00001101-0000-1000-8000-00805F9B34FB',
      'createRfcommSocketToServiceRecord',
      'createInsecureRfcommSocketToServiceRecord',
      // EVERY bonded device is listed (no printer-class filtering).
      'bondedDevices',
      'majorClass',
      // per-attempt native watchdog + serialized stateless jobs.
      'newSingleThreadExecutor',
      'newSingleThreadScheduledExecutor',
      'watchdog.schedule',
      'cancelDiscovery',
      // exact-byte chunked writes with pacing + drain, executor shutdown.
      'chunkBytes',
      'chunkDelayMs',
      'drainMs',
      'shutdownNow',
      // Android 12+ runtime permission behavior.
      'BLUETOOTH_CONNECT',
      'Build.VERSION_CODES.S',
    ]) {
      expect(kiosk, contains(marker), reason: 'missing POS/KDS marker $marker');
      expect(pos, contains(marker), reason: 'reference drifted: $marker');
    }
    // No device-class filtering was smuggled in: the list maps EVERY bonded
    // device; majorClass is a sort hint only.
    expect(kiosk, isNot(contains('majorDeviceClass ==')));
  });
}
