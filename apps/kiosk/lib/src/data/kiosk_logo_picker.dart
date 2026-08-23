import 'dart:typed_data';
import 'dart:ui' as ui;

import 'kiosk_appearance.dart';
import 'kiosk_logo_picker_io.dart'
    if (dart.library.js_interop) 'kiosk_logo_picker_web.dart'
    as platform;

/// KIOSK-001-102 §6 — the device-local logo picker facade.
///
/// Android uses the platform photo picker (`image_picker`); web uses a plain
/// `<input type="file">` (the same zero-dependency pattern as the Dashboard's
/// menu-image picker). Bytes are VALIDATED before they may be stored:
/// magic-byte sniffing (PNG / JPEG / WebP only — the browser/OS-reported MIME
/// is advisory), a hard size cap, and a real decode — a corrupt or oversized
/// file is refused with a typed reason, never persisted. Nothing here logs
/// file paths or bytes.
enum KioskLogoPickError { unsupportedType, tooLarge, undecodable }

class KioskLogoPickResult {
  const KioskLogoPickResult.ok(Uint8List this.bytes) : error = null;
  const KioskLogoPickResult.failed(KioskLogoPickError this.error)
    : bytes = null;
  final Uint8List? bytes;
  final KioskLogoPickError? error;
}

/// True when this build target has a picker at all.
bool get kioskLogoPickerSupported => platform.kioskLogoPickerSupported;

/// Opens the picker; null when the user cancels. A picked file is validated;
/// failures come back typed so the UI can explain instead of silently eating
/// the tap.
Future<KioskLogoPickResult?> pickKioskLogo() async {
  final bytes = await platform.pickKioskLogoBytes();
  if (bytes == null) return null;
  return validateKioskLogoBytes(bytes);
}

/// PNG `\x89PNG`, JPEG `\xFF\xD8\xFF`, WebP `RIFF....WEBP`.
bool _sniffAllowedImage(Uint8List b) {
  if (b.length < 12) return false;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return true;
  }
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
  return b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;
}

Future<KioskLogoPickResult> validateKioskLogoBytes(Uint8List bytes) =>
    validateKioskImageBytes(bytes, maxBytes: KioskAppearanceLimits.logoBytes);

/// KIOSK-001-103: the same magic-byte + cap + real-decode validation, with a
/// caller-chosen size bound (the attract background allows a larger photo
/// than the 256KB logo).
Future<KioskLogoPickResult> validateKioskImageBytes(
  Uint8List bytes, {
  required int maxBytes,
}) async {
  if (!_sniffAllowedImage(bytes)) {
    return const KioskLogoPickResult.failed(KioskLogoPickError.unsupportedType);
  }
  if (bytes.length > maxBytes) {
    return const KioskLogoPickResult.failed(KioskLogoPickError.tooLarge);
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    codec.dispose();
  } catch (_) {
    return const KioskLogoPickResult.failed(KioskLogoPickError.undecodable);
  }
  return KioskLogoPickResult.ok(bytes);
}
