/// PRINT-BRANDING-LOGO-001 — restaurant-logo object-key + client helpers.
///
/// The object key matches the migration's `app.restaurant_logo_scope` parser:
///   {organization_id}/{restaurant_id}/logo/{image_id}.{ext}
/// A fresh random [image_id] per upload keeps objects immutable/versioned, so a
/// fixed key is never overwritten and cross-restaurant collisions cannot occur.
library;

import 'dart:math';

/// The private restaurant-logo bucket id.
const String kRestaurantLogosBucketId = 'restaurant-logos';

/// Allowed extensions (the parser accepts jpg and jpeg).
const Set<String> kAllowedRestaurantLogoExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
};

/// Allowed upload MIME types (the bucket `allowed_mime_types`).
const Set<String> kAllowedRestaurantLogoMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
};

/// The bucket size limit: 2 MiB (mirrors `kMaxLogoBytes` in restoflow_printing).
const int kMaxRestaurantLogoBytes = 2 * 1024 * 1024;

String _normalizeExtension(String extension) =>
    extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');

/// The canonical file extension for a MIME type (jpeg -> jpg).
String extensionForLogoMime(String mimeType) {
  switch (mimeType.trim().toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'image/webp':
      return 'webp';
    default:
      return 'png';
  }
}

/// Builds the restaurant-logo object key.
String buildRestaurantLogoObjectKey({
  required String organizationId,
  required String restaurantId,
  required String imageId,
  required String extension,
}) {
  final ext = _normalizeExtension(extension);
  return '$organizationId/$restaurantId/logo/$imageId.$ext';
}

bool isAllowedRestaurantLogoMime(String mimeType) =>
    kAllowedRestaurantLogoMimeTypes.contains(mimeType.trim().toLowerCase());

bool isWithinRestaurantLogoSizeLimit(int byteCount) =>
    byteCount > 0 && byteCount <= kMaxRestaurantLogoBytes;

/// A seam for the `{image_id}` UUID, so tests can inject a deterministic id.
abstract class LogoImageIdGenerator {
  String newImageId();
}

/// RFC-4122 v4 UUID from a CSPRNG (mirrors the menu-image generator).
class RandomLogoImageIdGenerator implements LogoImageIdGenerator {
  RandomLogoImageIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String newImageId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
    return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
        '${hex(4)}${hex(5)}-'
        '${hex(6)}${hex(7)}-'
        '${hex(8)}${hex(9)}-'
        '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
  }
}

/// A deterministic [LogoImageIdGenerator] for tests.
class FixedLogoImageIdGenerator implements LogoImageIdGenerator {
  const FixedLogoImageIdGenerator(this.id);
  final String id;
  @override
  String newImageId() => id;
}
