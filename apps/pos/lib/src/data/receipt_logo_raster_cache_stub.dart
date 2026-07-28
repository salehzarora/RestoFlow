import 'receipt_logo_raster_cache.dart';

/// PRINT-BRANDING-LOGO-001 — the WEB default: an in-memory cache. Web has no
/// durable native file store and no thermal ESC/POS path, so a process-lifetime
/// source-byte/raster memory cache is sufficient for HTML/preview rendering; a
/// miss simply reloads the source image or prints text-only.
ReceiptLogoRasterCache createDefaultReceiptLogoRasterCache() =>
    InMemoryReceiptLogoRasterCache();
