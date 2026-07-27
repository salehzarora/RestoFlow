import 'dart:io';

import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'receipt_logo_raster_cache.dart';

/// PRINT-BRANDING-LOGO-001 — the NATIVE (Android/desktop) file-backed receipt-
/// logo raster cache. Plaintext binary envelopes under an app-support
/// subdirectory, written atomically (temp + rename). Corrupt or stale envelopes
/// are deleted and treated as a miss. Survives app restart and worker sign-out;
/// a scope/pairing/version change lands under a DIFFERENT key, so an old raster
/// is never reachable across restaurants.

/// The cache subdirectory name under the app-support directory.
const String kReceiptLogoCacheDirName = 'restoflow_logo_cache';

class FileReceiptLogoRasterCache implements ReceiptLogoRasterCache {
  FileReceiptLogoRasterCache({required this.directoryProvider});

  /// Resolves the base directory (injected so tests can point at a temp dir).
  final Future<Directory> Function() directoryProvider;

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await directoryProvider();
    final dir = Directory('${base.path}/$kReceiptLogoCacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  @override
  Future<ReceiptLogoCacheEntry?> read(ReceiptLogoCacheKey key) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${key.fileName}');
      if (!await file.exists()) return null;
      final json = await file.readAsString();
      final entry = decodeReceiptLogoEnvelope(json, key);
      if (entry == null) {
        // Corrupt / stale / wrong-key envelope: delete and miss.
        try {
          await file.delete();
        } catch (_) {}
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    ReceiptLogoCacheKey key,
    ReceiptLogoCacheEntry entry,
  ) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${key.fileName}');
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        encodeReceiptLogoEnvelope(key, entry),
        flush: true,
      );
      // Atomic replace where the platform supports rename-over.
      await tmp.rename(file.path);
    } catch (_) {
      // Best-effort: a cache-write failure never blocks a print.
    }
  }
}

/// The platform default for native builds.
ReceiptLogoRasterCache createDefaultReceiptLogoRasterCache() =>
    FileReceiptLogoRasterCache(
      directoryProvider: getApplicationSupportDirectory,
    );
