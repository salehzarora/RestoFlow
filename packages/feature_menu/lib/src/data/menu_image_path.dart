/// RF-110 menu image object-key + client validation helpers (RF-111).
///
/// These are the ONLY image pieces RF-111 implements end-to-end; the production
/// upload / signed-URL wiring and the "current image of an item" association are
/// DEFERRED (there is no authenticated session yet, D1, and no backend metadata
/// pointer, D2 / D-032). The object key matches the RF-110 storage policy:
///   {organization_id}/{restaurant_id}/{branch_id|'global'}/menu_item/{menu_item_id}/{image_id}.{ext}
library;

import 'dart:math';

/// Allowed image extensions (the RF-110 path parser accepts both jpg and jpeg).
const Set<String> kAllowedMenuImageExtensions = {'png', 'jpg', 'jpeg', 'webp'};

/// Allowed upload MIME types (RF-110 bucket `allowed_mime_types`).
const Set<String> kAllowedMenuImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
};

/// The RF-110 bucket size limit: 5 MiB.
const int kMaxMenuImageBytes = 5 * 1024 * 1024;

/// The private RF-110 bucket id.
const String kMenuImagesBucketId = 'menu-images';

String _normalizeExtension(String extension) =>
    extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');

/// Builds the RF-110 object key. A `null` [branchId] maps to the literal
/// `global` (restaurant-scoped item).
String buildMenuImageObjectKey({
  required String organizationId,
  required String restaurantId,
  required String? branchId,
  required String menuItemId,
  required String imageId,
  required String extension,
}) {
  final branchSegment = branchId ?? 'global';
  final ext = _normalizeExtension(extension);
  return '$organizationId/$restaurantId/$branchSegment/menu_item/$menuItemId/$imageId.$ext';
}

/// Whether [extension] (with or without a leading dot, any case) is allowed.
bool isAllowedMenuImageExtension(String extension) =>
    kAllowedMenuImageExtensions.contains(_normalizeExtension(extension));

/// Whether [mimeType] is an allowed upload MIME type.
bool isAllowedMenuImageMime(String mimeType) =>
    kAllowedMenuImageMimeTypes.contains(mimeType.trim().toLowerCase());

/// Whether [byteCount] is a positive size within the 5 MiB limit.
bool isWithinMenuImageSizeLimit(int byteCount) =>
    byteCount > 0 && byteCount <= kMaxMenuImageBytes;

/// A seam for generating the `{image_id}` UUID in an object key, so tests can
/// inject a deterministic id.
abstract class ImageIdGenerator {
  String newImageId();
}

/// Generates an RFC-4122 v4 UUID from a CSPRNG (mirrors the auth_identity
/// idempotency-key generator; no external `uuid` dependency).
class RandomImageIdGenerator implements ImageIdGenerator {
  RandomImageIdGenerator([Random? random])
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

/// A deterministic [ImageIdGenerator] for tests/demos.
class FixedImageIdGenerator implements ImageIdGenerator {
  const FixedImageIdGenerator(this.id);

  final String id;

  @override
  String newImageId() => id;
}
