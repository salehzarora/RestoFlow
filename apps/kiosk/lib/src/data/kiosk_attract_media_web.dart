import 'dart:typed_data';

/// Web attract-media backend: web has no durable app-local file storage that
/// could hold a large image/video across restarts without abusing
/// SharedPreferences with megabyte base64 blobs — so custom attract media is
/// honestly INSTALLED-DEVICE ONLY (KIOSK-001-103 §5/§6). Every entry point is
/// a safe no-op; the editor shows the honest explanation instead of a picker.
const bool kioskAttractMediaSupported = false;

Future<String?> persistAttractBytes({
  required String deviceId,
  required String kind,
  required Uint8List bytes,
  required String ext,
}) async => null;

Future<String?> persistAttractFile({
  required String deviceId,
  required String kind,
  required String sourcePath,
  required String ext,
  required int maxBytes,
}) async => null;

Future<String?> attractMediaPath({
  required String deviceId,
  required String ref,
}) async => null;

Future<void> deleteAttractMedia({
  required String deviceId,
  required String ref,
}) async {}

Future<Uint8List?> pickAttractImageBytes() async => null;

Future<(String, int)?> pickAttractVideo() async => null;

/// Web: no device-local video files, no probe.
Future<Duration?> Function(String)? get videoProbe => null;
