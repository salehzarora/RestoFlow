import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// PRINT-BRANDING-LOGO-001 — the POS receipt-logo raster cache (§15).
///
/// A processed logo is width-specific, reproducible, and NOT a secret, so it is
/// cached in PLAINTEXT (never [SecureKeyStore], never the encrypted/backup-
/// excluded kitchen-spool DB). The cache key includes the full tenant + version
/// + media identity so a change to ANY of them is a miss (never a stale or
/// cross-restaurant raster):
///
///   organizationId | restaurantId | receiptLogoVersion | mediaProfileId |
///   widthDots | rasterPreprocessingVersion
///
/// This file is web-safe (no `dart:io`): the native file-backed implementation
/// lives in `receipt_logo_raster_cache_native.dart` and is selected by a
/// conditional import; web/tests use [InMemoryReceiptLogoRasterCache].

/// The cache schema version. A bump invalidates every stored envelope.
const int kReceiptLogoCacheSchemaVersion = 1;

/// The fully-qualified cache key. Every field participates so no two distinct
/// (tenant, version, media, algorithm) tuples ever collide.
class ReceiptLogoCacheKey {
  const ReceiptLogoCacheKey({
    required this.organizationId,
    required this.restaurantId,
    required this.logoVersion,
    required this.mediaProfileId,
    required this.widthDots,
    required this.preprocessingVersion,
  });

  final String organizationId;
  final String restaurantId;
  final int logoVersion;
  final String mediaProfileId;
  final int widthDots;
  final int preprocessingVersion;

  /// The canonical string key (map key + basis for the file name).
  String get storageKey =>
      '$organizationId|$restaurantId|$logoVersion|$mediaProfileId|$widthDots|$preprocessingVersion';

  /// A filesystem-safe file name derived from a hash of [storageKey] (no tenant
  /// identifiers leak into the file name).
  String get fileName =>
      '${sha256.convert(utf8.encode(storageKey))}.logoraster';
}

/// A cached, print-ready logo: the 1bpp raster (for native ESC/POS) plus the
/// processed source bytes (for HTML/preview rendering).
class ReceiptLogoCacheEntry {
  ReceiptLogoCacheEntry({
    required this.rasterData,
    required this.widthBytes,
    required this.heightDots,
    required this.sourceBytes,
    required this.sourceMime,
  });

  final Uint8List rasterData;
  final int widthBytes;
  final int heightDots;
  final Uint8List sourceBytes;
  final String sourceMime;
}

/// The persistent (or in-memory) receipt-logo raster cache.
abstract class ReceiptLogoRasterCache {
  /// Return the cached entry for [key], or null on a miss / corrupt / stale
  /// envelope. Never throws.
  Future<ReceiptLogoCacheEntry?> read(ReceiptLogoCacheKey key);

  /// Store [entry] under [key]. Best-effort; a failure is swallowed (the caller
  /// still has the in-memory asset for THIS print).
  Future<void> write(ReceiptLogoCacheKey key, ReceiptLogoCacheEntry entry);
}

/// Encode a cache entry to a self-describing JSON envelope (with a raster
/// checksum for corruption detection). Pure + web-safe.
String encodeReceiptLogoEnvelope(
  ReceiptLogoCacheKey key,
  ReceiptLogoCacheEntry entry,
) {
  return jsonEncode(<String, Object?>{
    'schema': kReceiptLogoCacheSchemaVersion,
    'org': key.organizationId,
    'restaurant': key.restaurantId,
    'logoVersion': key.logoVersion,
    'profileId': key.mediaProfileId,
    'widthDots': key.widthDots,
    'prep': key.preprocessingVersion,
    'widthBytes': entry.widthBytes,
    'heightDots': entry.heightDots,
    'rasterSha': sha256.convert(entry.rasterData).toString(),
    'raster': base64Encode(entry.rasterData),
    'sourceMime': entry.sourceMime,
    'source': base64Encode(entry.sourceBytes),
  });
}

/// Decode + VALIDATE an envelope against the [expected] key. Returns null when
/// the JSON is malformed, the schema/key fields do not match, or the raster
/// checksum fails (so a stale / wrong / corrupt file is a clean miss). Never
/// throws.
ReceiptLogoCacheEntry? decodeReceiptLogoEnvelope(
  String json,
  ReceiptLogoCacheKey expected,
) {
  try {
    final map = jsonDecode(json);
    if (map is! Map) return null;
    if (map['schema'] != kReceiptLogoCacheSchemaVersion) return null;
    if (map['org'] != expected.organizationId) return null;
    if (map['restaurant'] != expected.restaurantId) return null;
    if (map['logoVersion'] != expected.logoVersion) return null;
    if (map['profileId'] != expected.mediaProfileId) return null;
    if (map['widthDots'] != expected.widthDots) return null;
    if (map['prep'] != expected.preprocessingVersion) return null;
    final rasterData = base64Decode(map['raster'] as String);
    if (sha256.convert(rasterData).toString() != map['rasterSha']) return null;
    final widthBytes = map['widthBytes'] as int;
    final heightDots = map['heightDots'] as int;
    if (rasterData.length != widthBytes * heightDots) return null;
    return ReceiptLogoCacheEntry(
      rasterData: rasterData,
      widthBytes: widthBytes,
      heightDots: heightDots,
      sourceBytes: base64Decode(map['source'] as String),
      sourceMime: map['sourceMime'] as String,
    );
  } catch (_) {
    return null;
  }
}

/// A process-lifetime, in-memory cache — the web + test implementation (web has
/// no durable native file store; the thermal raster is not needed there, and a
/// source-byte memory cache is enough for HTML/preview).
class InMemoryReceiptLogoRasterCache implements ReceiptLogoRasterCache {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<ReceiptLogoCacheEntry?> read(ReceiptLogoCacheKey key) async {
    final json = _store[key.storageKey];
    if (json == null) return null;
    return decodeReceiptLogoEnvelope(json, key);
  }

  @override
  Future<void> write(
    ReceiptLogoCacheKey key,
    ReceiptLogoCacheEntry entry,
  ) async {
    _store[key.storageKey] = encodeReceiptLogoEnvelope(key, entry);
  }
}
