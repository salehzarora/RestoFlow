import 'dart:typed_data';

/// PRINT-BRANDING-LOGO-001 — the downloaded restaurant-logo source image.
class ReceiptLogoBytes {
  const ReceiptLogoBytes({required this.bytes, required this.mime});

  /// The raw compressed source image (PNG/JPEG/WebP).
  final Uint8List bytes;

  /// The sniffed MIME (`image/png` | `image/jpeg` | `image/webp`).
  final String mime;
}

/// Read-only seam: download THIS device's restaurant-logo object bytes from the
/// private `restaurant-logos` bucket, server-gated by the
/// `restaurant_logos_device_select` storage policy (an ACTIVE POS device
/// session bound to this anonymous principal; KDS excluded). Returns null on any
/// failure (missing object / policy-denied / offline / corrupt) — the POS then
/// prints text-only. Implemented over Supabase in `auth_identity`; faked in
/// tests. Anon-key only, money-free (D-011/T-003).
abstract class DeviceReceiptLogoReader {
  Future<ReceiptLogoBytes?> load(String objectPath);
}
