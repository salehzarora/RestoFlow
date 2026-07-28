import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart' show LogoRaster;

/// PRINT-BRANDING-LOGO-001 — a resolved, ready-to-print receipt logo.
///
/// It is produced by the composition/controller layer (never inside
/// [buildReceiptDocument], which stays pure and synchronous) and carries
/// everything the three receipt renderers need:
///  * [sourceBytes] + [sourceMime] — the processed source image, for the POS-web
///    HTML `<img>` and the in-app on-screen preview;
///  * [raster] — the 1bpp bitmap ALREADY rasterized for the active media
///    profile, for the native ESC/POS path (null on web, where there is no
///    thermal path).
///
/// A null asset (or a null [raster] on native) means "no logo" — the receipt
/// stays text-only. The kitchen document model never sees this type (customer
/// receipts only, enforced structurally).
class ReceiptLogoAsset {
  const ReceiptLogoAsset({
    required this.sourceBytes,
    required this.sourceMime,
    this.raster,
  });

  /// The processed source image bytes (PNG/JPEG/WebP) for HTML/preview.
  final Uint8List sourceBytes;

  /// The source MIME (`image/png` | `image/jpeg` | `image/webp`).
  final String sourceMime;

  /// The print-ready 1bpp raster for the active media profile (native only).
  final LogoRaster? raster;
}
