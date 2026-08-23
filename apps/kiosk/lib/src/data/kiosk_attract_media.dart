import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kiosk_appearance.dart';
import 'kiosk_attract_media_io.dart'
    if (dart.library.js_interop) 'kiosk_attract_media_web.dart'
    as platform;
import 'kiosk_logo_picker.dart';

/// KIOSK-001-103 §5/§6 — DEVICE-LOCAL attract media storage.
///
/// One optional external image and one optional external video live in a
/// bounded app-private directory
/// (`<app documents>/restoflow_kiosk_media/<deviceId>/`); SharedPreferences
/// stores only a short generated REF (a file name this code minted — never a
/// user path, never base64 payloads, never a signed URL). Web builds have no
/// durable app-local file storage for this, so the store honestly reports
/// unsupported and the editor explains that custom media is installed-device
/// only. Nothing here logs a path or file contents.
///
/// Refs are validated against [kioskAttractMediaRefPattern] on every resolve,
/// so a hand-edited preference can never point outside the media directory.
final RegExp kioskAttractMediaRefPattern = RegExp(
  r'^attract_(image|video)_\d{1,17}\.[a-z0-9]{2,5}$',
);

/// Typed failure reasons for picking/persisting attract media.
enum KioskAttractMediaError {
  unsupportedPlatform,
  unsupportedType,
  tooLarge,
  tooLong,
  undecodable,
  storeFailed,
}

class KioskAttractMediaResult {
  const KioskAttractMediaResult.ok(String this.ref) : error = null;
  const KioskAttractMediaResult.failed(KioskAttractMediaError this.error)
    : ref = null;
  final String? ref;
  final KioskAttractMediaError? error;
}

/// Platform-backed store. All methods are safe no-ops (null / false) on web.
class KioskAttractMediaStore {
  const KioskAttractMediaStore();

  bool get supported => platform.kioskAttractMediaSupported;

  /// Persists validated image [bytes]; returns the stored ref.
  Future<KioskAttractMediaResult> persistImage({
    required String deviceId,
    required Uint8List bytes,
  }) async {
    if (!supported) {
      return const KioskAttractMediaResult.failed(
        KioskAttractMediaError.unsupportedPlatform,
      );
    }
    final ref = await platform.persistAttractBytes(
      deviceId: deviceId,
      kind: 'image',
      bytes: bytes,
      ext: _imageExtOf(bytes),
    );
    return ref == null
        ? const KioskAttractMediaResult.failed(
            KioskAttractMediaError.storeFailed,
          )
        : KioskAttractMediaResult.ok(ref);
  }

  /// Copies a picked video file (already extension/size vetted by the picker)
  /// into the bounded media directory; returns the stored ref.
  Future<KioskAttractMediaResult> persistVideoFromPath({
    required String deviceId,
    required String sourcePath,
    required String ext,
  }) async {
    if (!supported) {
      return const KioskAttractMediaResult.failed(
        KioskAttractMediaError.unsupportedPlatform,
      );
    }
    final ref = await platform.persistAttractFile(
      deviceId: deviceId,
      kind: 'video',
      sourcePath: sourcePath,
      ext: ext,
      maxBytes: KioskAppearanceLimits.attractVideoBytes,
    );
    return ref == null
        ? const KioskAttractMediaResult.failed(
            KioskAttractMediaError.storeFailed,
          )
        : KioskAttractMediaResult.ok(ref);
  }

  /// Absolute path for a stored ref — null when the ref is malformed, the
  /// platform is unsupported, or the file is gone (caller falls back).
  Future<String?> absolutePathOf({
    required String deviceId,
    required String ref,
  }) async {
    if (!supported || !kioskAttractMediaRefPattern.hasMatch(ref)) return null;
    return platform.attractMediaPath(deviceId: deviceId, ref: ref);
  }

  /// Best-effort cleanup of a replaced/removed media file.
  Future<void> delete({required String deviceId, required String ref}) async {
    if (!supported || !kioskAttractMediaRefPattern.hasMatch(ref)) return;
    await platform.deleteAttractMedia(deviceId: deviceId, ref: ref);
  }
}

String _imageExtOf(Uint8List b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  return 'webp';
}

/// Picks + validates an attract background IMAGE (PNG/JPEG/WebP, hard cap
/// [KioskAppearanceLimits.attractImageBytes], real decode). Null = canceled.
Future<Object?> pickKioskAttractImage() async {
  if (!platform.kioskAttractMediaSupported) {
    return const KioskAttractMediaResult.failed(
      KioskAttractMediaError.unsupportedPlatform,
    );
  }
  final bytes = await platform.pickAttractImageBytes();
  if (bytes == null) return null;
  final validated = await validateKioskImageBytes(
    bytes,
    maxBytes: KioskAppearanceLimits.attractImageBytes,
  );
  if (validated.error != null) {
    return KioskAttractMediaResult.failed(switch (validated.error!) {
      KioskLogoPickError.unsupportedType =>
        KioskAttractMediaError.unsupportedType,
      KioskLogoPickError.tooLarge => KioskAttractMediaError.tooLarge,
      KioskLogoPickError.undecodable => KioskAttractMediaError.undecodable,
    });
  }
  return validated.bytes!;
}

/// A picked (not yet persisted) video: source path + normalized extension.
class KioskPickedVideo {
  const KioskPickedVideo({required this.sourcePath, required this.ext});
  final String sourcePath;
  final String ext;
}

/// Picks a VIDEO from the platform gallery. Extension whitelist (mp4/m4v/mov
/// — H.264 containers Android decodes natively) and the size cap are checked
/// BEFORE any copy. Null = canceled; a typed result = refused.
Future<Object?> pickKioskAttractVideo() async {
  if (!platform.kioskAttractMediaSupported) {
    return const KioskAttractMediaResult.failed(
      KioskAttractMediaError.unsupportedPlatform,
    );
  }
  final picked = await platform.pickAttractVideo();
  if (picked == null) return null;
  final (sourcePath, sizeBytes) = picked;
  final dot = sourcePath.lastIndexOf('.');
  final ext = dot < 0 ? '' : sourcePath.substring(dot + 1).toLowerCase().trim();
  if (!const {'mp4', 'm4v', 'mov'}.contains(ext)) {
    return const KioskAttractMediaResult.failed(
      KioskAttractMediaError.unsupportedType,
    );
  }
  if (sizeBytes > KioskAppearanceLimits.attractVideoBytes) {
    return const KioskAttractMediaResult.failed(
      KioskAttractMediaError.tooLarge,
    );
  }
  return KioskPickedVideo(sourcePath: sourcePath, ext: ext);
}

/// Store seam: null in demo/tests; the REAL composition root provides the
/// platform-backed store.
final kioskAttractMediaStoreProvider = Provider<KioskAttractMediaStore?>(
  (ref) => null,
);

/// Optional duration probe (video_player-backed in the real Android root).
/// Returns the playable duration, or null when the file cannot be decoded.
typedef KioskVideoProbe = Future<Duration?> Function(String absolutePath);

final kioskVideoProbeProvider = Provider<KioskVideoProbe?>((ref) => null);

/// The platform's real decode-proving probe (null on web) — the REAL root
/// wires it into [kioskVideoProbeProvider].
KioskVideoProbe? get kioskPlatformVideoProbe => platform.videoProbe;
