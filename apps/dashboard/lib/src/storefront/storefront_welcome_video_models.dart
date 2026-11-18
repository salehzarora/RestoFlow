import 'dart:math';

import 'storefront_models.dart';

const welcomeVideoPrivateBucket = 'storefront-welcome-video-originals';
const welcomeVideoPublicBucket = 'storefront-welcome-videos';
const welcomeVideoMaxBytes = 20 * 1024 * 1024;
const welcomeVideoMaxDurationMs = 30000;
final welcomeVideoSourceKeyPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.mp4$',
);
final _publicKey = RegExp(r'^[0-9a-f]{32}/[0-9a-f]{64}\.mp4$');
final _hash = RegExp(r'^[0-9a-f]{64}$');

bool welcomeVideoUuid(Object? value) =>
    value is String && value == value.toLowerCase() && isCanonicalUuid(value);

bool welcomeVideoSourceBelongsTo(
  String key,
  String organizationId,
  String restaurantId,
) =>
    welcomeVideoUuid(organizationId) &&
    welcomeVideoUuid(restaurantId) &&
    welcomeVideoSourceKeyPattern.hasMatch(key) &&
    key.startsWith('$organizationId/$restaurantId/');

String newWelcomeVideoId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Manager-only published metadata. No private source key is exposed here.
class StorefrontWelcomeVideoMedia {
  const StorefrontWelcomeVideoMedia({
    required this.id,
    required this.objectKey,
    required this.contentHash,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.byteLength,
    required this.published,
    required this.publicPath,
  });

  final String id, objectKey, contentHash;
  final int width, height, durationMs, byteLength;
  final bool published;
  final String? publicPath;

  factory StorefrontWelcomeVideoMedia.fromJson(
    Object? raw, {
    bool requirePublished = true,
  }) {
    const keys = {
      'id',
      'object_key',
      'content_hash',
      'mime_type',
      'width',
      'height',
      'duration_ms',
      'bytes',
      'published',
      'url',
    };
    Never invalid() => throw const StorefrontDecodeException(
      'welcome_video.media',
      'invalid published video metadata',
    );
    if (raw is! Map ||
        raw.length != keys.length ||
        !keys.every(raw.containsKey) ||
        raw.keys.any((k) => k is! String)) {
      invalid();
    }
    final j = Map<String, Object?>.from(raw);
    final id = j['id'], key = j['object_key'], hash = j['content_hash'];
    if (!welcomeVideoUuid(id) ||
        key is! String ||
        !_publicKey.hasMatch(key) ||
        hash is! String ||
        !_hash.hasMatch(hash) ||
        key.split('/').last != '$hash.mp4' ||
        j['mime_type'] != 'video/mp4') {
      invalid();
    }
    int bounded(String field, int maximum) {
      final value = j[field];
      if (value is! int || value < 1 || value > maximum) invalid();
      return value;
    }

    final width = bounded('width', 1920), height = bounded('height', 1080);
    final duration = bounded('duration_ms', welcomeVideoMaxDurationMs);
    final bytes = bounded('bytes', welcomeVideoMaxBytes);
    final published = j['published'], url = j['url'];
    if (published is! bool ||
        (requirePublished && !published) ||
        (published
            ? url != '/storage/v1/object/public/$welcomeVideoPublicBucket/$key'
            : url != null)) {
      invalid();
    }
    return StorefrontWelcomeVideoMedia(
      id: id as String,
      objectKey: key,
      contentHash: hash,
      width: width,
      height: height,
      durationMs: duration,
      byteLength: bytes,
      published: published,
      publicPath: url as String?,
    );
  }
}
