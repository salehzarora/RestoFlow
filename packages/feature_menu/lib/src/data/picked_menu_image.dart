import 'dart:typed_data';

/// A locally-picked image file (bytes only — nothing has been uploaded yet).
///
/// Produced by the zero-dependency platform picker (`image_file_picker.dart`);
/// consumed by the item image panel, which validates it against the RF-110
/// bucket rules (`kAllowedMenuImageMimeTypes`, `kMaxMenuImageBytes`), previews
/// it, and only uploads on an explicit confirm.
class PickedMenuImage {
  const PickedMenuImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  /// The raw file bytes.
  final Uint8List bytes;

  /// The browser-reported MIME type (e.g. `image/png`). Validated against
  /// `kAllowedMenuImageMimeTypes` before any upload.
  final String mimeType;

  /// The original file name (display only — the storage object key is always
  /// built via `buildMenuImageObjectKey`, never from the user's file name).
  final String fileName;
}
