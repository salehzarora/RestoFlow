import 'dart:convert';

import 'storefront_content_unicode.dart' as unicode;
import 'storefront_models.dart';

/// BIZBOT-STOREFRONT-CONTENT-CONTRACT-001: dedicated management boundary.
/// This document never authorizes catalogue, order or media publication.
const storefrontContentEntity = 'restaurant_storefront_content';
const storefrontContentKeys = {
  'hero_headline',
  'hero_subline',
  'announcement_text',
  'hero',
  'announcement_segments',
  'promo',
  'story',
  'category_presentation',
  'item_presentation',
};
const storefrontContentReasons = {
  'document_not_object',
  'document_too_large',
  'unknown_field',
  'missing_field',
  'text_invalid',
  'headline_format_invalid',
  'segments_invalid',
  'target_invalid',
  'media_invalid',
  'presentation_invalid',
  'duplicate_id',
};
const storefrontContentWarningReasons = {
  'relation_unavailable',
  'media_unavailable',
  'legacy_value_invalid',
};

Map<String, dynamic> contentObject(
  Object? raw,
  Set<String> keys,
  String field,
) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String) ||
      raw.length != keys.length ||
      !keys.every(raw.containsKey)) {
    throw StorefrontDecodeException(field, 'invalid object shape');
  }
  return Map<String, dynamic>.from(raw);
}

bool contentId(Object? value) =>
    value is String && value == value.toLowerCase() && isCanonicalUuid(value);

bool contentFieldPath(Object? value) => const {
  'document',
  'hero_headline',
  'hero_subline',
  'announcement_text',
  'hero',
  'hero.item_id',
  'hero.format',
  'hero.eyebrow',
  'hero.stamp',
  'hero.footnote',
  'announcement_segments',
  'promo',
  'promo.target',
  'promo.editorial_media_id',
  'story',
  'story.editorial_media_id',
  'category_presentation',
  'item_presentation',
}.contains(value);

Object? _freeze(Object? value) => switch (value) {
  Map map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries) entry.key as String: _freeze(entry.value),
  }),
  List list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};

class StorefrontContentDocument {
  StorefrontContentDocument._(this.json);
  final Map<String, Object?> json;

  factory StorefrontContentDocument.fromJson(Object? raw) {
    final j = contentObject(raw, storefrontContentKeys, 'document');
    if (utf8.encode(jsonEncode(j)).length > 256 * 1024) {
      throw const StorefrontDecodeException('document', 'document_too_large');
    }
    void text(
      Object? value,
      int max,
      String field, {
      bool legacy = false,
      bool required = false,
    }) {
      if (value == null && !required) return;
      if (value is! String)
        throw StorefrontDecodeException(field, 'text_invalid');
      try {
        final normalized = unicode.normalizeContentText(
          value,
          max,
          legacy: legacy,
        );
        if ((required && normalized == null) || normalized != value) {
          throw const FormatException();
        }
      } on FormatException {
        throw StorefrontDecodeException(field, 'text_invalid');
      }
    }

    void id(Object? value, String field, {bool nullable = false}) {
      if (nullable && value == null) return;
      if (!contentId(value))
        throw StorefrontDecodeException(field, 'target_invalid');
    }

    void choice(Object? value, Set<String> values, String field) {
      if (value != null && !values.contains(value)) {
        throw StorefrontDecodeException(field, 'presentation_invalid');
      }
    }

    List<dynamic> array(Object? value, int max, String field) {
      if (value is! List || value.length > max) {
        throw StorefrontDecodeException(field, 'invalid list');
      }
      return value;
    }

    for (final (field, max) in [
      ('hero_headline', 120),
      ('hero_subline', 180),
      ('announcement_text', 240),
    ]) {
      text(j[field], max, field, legacy: true);
    }
    final hero = contentObject(j['hero'], {
      'mode',
      'item_id',
      'format',
      'eyebrow',
      'stamp',
      'footnote',
    }, 'hero');
    if (!{'editorial', 'item'}.contains(hero['mode'])) {
      throw const StorefrontDecodeException('hero.mode', 'target_invalid');
    }
    id(hero['item_id'], 'hero.item_id', nullable: hero['mode'] == 'editorial');
    for (final (field, max) in [
      ('eyebrow', 60),
      ('stamp', 80),
      ('footnote', 120),
    ]) {
      text(hero[field], max, 'hero.$field');
    }
    if (hero['format'] != null) {
      final f = contentObject(hero['format'], {
        'text',
        'highlight',
        'break_before',
      }, 'hero.format');
      final headline = j['hero_headline'];
      int? start, end;
      if (f['highlight'] != null) {
        final range = contentObject(f['highlight'], {
          'start',
          'end',
        }, 'hero.format');
        if (range['start'] is! int || range['end'] is! int) {
          throw const StorefrontDecodeException(
            'hero.format',
            'headline_format_invalid',
          );
        }
        start = range['start'];
        end = range['end'];
      }
      final b = f['break_before'];
      if (headline is! String ||
          f['text'] != headline ||
          (b != null && b is! int) ||
          (start == null && b == null) ||
          !unicode.heroFormatValid(headline, start, end, b as int?)) {
        throw const StorefrontDecodeException(
          'hero.format',
          'headline_format_invalid',
        );
      }
    }
    if (j['announcement_segments'] != null) {
      final segments = array(
        j['announcement_segments'],
        6,
        'announcement_segments',
      );
      if (segments.isEmpty)
        throw const StorefrontDecodeException(
          'announcement_segments',
          'segments_invalid',
        );
      var count = 0;
      for (final segment in segments) {
        text(segment, 40, 'announcement_segments', required: true);
        count += unicode.scalarValues(segment as String)!.length;
      }
      if (count > 240)
        throw const StorefrontDecodeException(
          'announcement_segments',
          'segments_invalid',
        );
    }
    final promo = j['promo'];
    if (promo != null) {
      if (promo is! Map || promo['target'] is! Map) {
        throw const StorefrontDecodeException('promo', 'target_invalid');
      }
      final target = promo['target'] as Map;
      final category = target['kind'] == 'category';
      if (!category && target['kind'] != 'item') {
        throw const StorefrontDecodeException('promo.target', 'target_invalid');
      }
      final p = contentObject(promo, {
        'target',
        'kicker',
        'title',
        'body',
        if (category) 'editorial_media_id',
      }, 'promo');
      final t = contentObject(target, {
        'kind',
        category ? 'category_id' : 'item_id',
      }, 'promo.target');
      id(t[category ? 'category_id' : 'item_id'], 'promo.target');
      if (category) id(p['editorial_media_id'], 'promo.editorial_media_id');
      for (final (field, max) in [
        ('kicker', 60),
        ('title', 120),
        ('body', 600),
      ]) {
        text(p[field], max, 'promo.$field', required: true);
      }
    }
    if (j['story'] != null) {
      final s = contentObject(j['story'], {
        'kicker',
        'title',
        'body',
        'editorial_media_id',
        'facts',
      }, 'story');
      id(s['editorial_media_id'], 'story.editorial_media_id');
      for (final (field, max) in [
        ('kicker', 60),
        ('title', 120),
        ('body', 600),
      ]) {
        text(s[field], max, 'story.$field', required: true);
      }
      for (final fact in array(s['facts'], 3, 'story.facts')) {
        text(fact, 80, 'story.facts', required: true);
      }
    }
    for (final (field, max, idKey) in [
      ('category_presentation', 100, 'category_id'),
      ('item_presentation', 500, 'item_id'),
    ]) {
      final seen = <String>{};
      for (final raw in array(j[field], max, field)) {
        final category = field == 'category_presentation';
        final row = contentObject(raw, {
          idKey,
          'image_fit',
          'card_layout',
          if (category) ...['heading', 'blurb', 'editorial_media_id'],
        }, field);
        id(row[idKey], field);
        if (!seen.add(row[idKey] as String))
          throw StorefrontDecodeException(field, 'duplicate_id');
        choice(row['image_fit'], {'fill', 'whole-image'}, field);
        choice(row['card_layout'], {'standard', 'cutout'}, field);
        if (category) {
          text(row['heading'], 80, field);
          text(row['blurb'], 120, field);
          id(row['editorial_media_id'], field, nullable: true);
        }
      }
    }
    return StorefrontContentDocument._(_freeze(j) as Map<String, Object?>);
  }

  static Map<String, Object?> defaults({
    String? headline,
    String? subline,
    String? announcement,
  }) => {
    'hero_headline': headline,
    'hero_subline': subline,
    'announcement_text': announcement,
    'hero': {
      'mode': 'editorial',
      'item_id': null,
      'format': null,
      'eyebrow': null,
      'stamp': null,
      'footnote': null,
    },
    'announcement_segments': null,
    'promo': null,
    'story': null,
    'category_presentation': <Object?>[],
    'item_presentation': <Object?>[],
  };

  Map<String, dynamic> editableCopy() =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

class StorefrontContentWarning {
  const StorefrontContentWarning(this.field, this.reason);
  final String field, reason;
  factory StorefrontContentWarning.fromJson(Object? raw) {
    final j = contentObject(raw, {'field', 'reason'}, 'warnings');
    if (!contentFieldPath(j['field']) ||
        !storefrontContentWarningReasons.contains(j['reason'])) {
      throw const StorefrontDecodeException('warnings', 'invalid warning');
    }
    return StorefrontContentWarning(
      j['field'] as String,
      j['reason'] as String,
    );
  }
}

class StorefrontContentSnapshot {
  const StorefrontContentSnapshot({
    required this.restaurantId,
    required this.version,
    required this.branchId,
    required this.document,
    required this.warnings,
  });
  final String restaurantId, branchId;
  final int version;
  final StorefrontContentDocument document;
  final List<StorefrontContentWarning> warnings;
  factory StorefrontContentSnapshot.fromJson(
    Object? raw,
    String expectedRestaurant,
  ) {
    final j = contentObject(raw, {
      'ok',
      'entity',
      'restaurant_id',
      'version',
      'storefront_branch_id',
      'document',
      'warnings',
    }, 'content');
    if (j['ok'] != true ||
        j['entity'] != storefrontContentEntity ||
        j['restaurant_id'] != expectedRestaurant ||
        !contentId(j['restaurant_id']) ||
        !contentId(j['storefront_branch_id']) ||
        j['version'] is! int ||
        (j['version'] as int) < 1 ||
        j['warnings'] is! List) {
      throw const StorefrontDecodeException('content', 'invalid envelope');
    }
    return StorefrontContentSnapshot(
      restaurantId: j['restaurant_id'],
      version: j['version'],
      branchId: j['storefront_branch_id'],
      document: StorefrontContentDocument.fromJson(j['document']),
      warnings: List.unmodifiable(
        (j['warnings'] as List).map(StorefrontContentWarning.fromJson),
      ),
    );
  }
}

class StorefrontContentChoice {
  const StorefrontContentChoice({
    required this.id,
    required this.name,
    this.categoryId,
    this.available = true,
    this.hasImage = false,
  });
  final String id, name;
  final String? categoryId;
  final bool available, hasImage;
}

class StorefrontContentCatalogData {
  const StorefrontContentCatalogData({
    required this.categories,
    required this.items,
  });
  final List<StorefrontContentChoice> categories, items;
}

abstract interface class StorefrontContentCatalog {
  Future<StorefrontContentCatalogData?> loadContent(String savedBranchId);
}

/// Publish a w960 editorial derivative only. Deliberately has no profileKey.
/// The existing recipe's hero wire is reused, never a Hero slot assignment.
enum StorefrontEditorialTarget implements StorefrontPublishTarget {
  editorial;

  @override
  String get wire => 'hero';
  @override
  StorefrontVariant get variant => StorefrontVariant.w960;
  @override
  List<StorefrontSourceBucket> get allowedBuckets => const [
    StorefrontSourceBucket.restaurantLogos,
    StorefrontSourceBucket.menuImages,
  ];
}

class StorefrontContentMediaRow {
  const StorefrontContentMediaRow(this.media, this.contentInUse);
  final StorefrontMediaRow media;
  final List<Map<String, String>> contentInUse;
  factory StorefrontContentMediaRow.fromJson(Object? raw) {
    if (raw is! Map || raw['content_in_use'] is! List)
      throw const StorefrontDecodeException('media', 'invalid usage');
    final row = Map<String, dynamic>.from(raw)..remove('content_in_use');
    final usages = <Map<String, String>>[];
    final seen = <String>{};
    for (final rawUsage in raw['content_in_use'] as List) {
      if (rawUsage is! Map)
        throw const StorefrontDecodeException('media', 'invalid usage');
      final category = rawUsage['kind'] == 'category';
      final u = contentObject(rawUsage, {
        'kind',
        if (category) 'category_id',
      }, 'media');
      if (!{'category', 'promo', 'story'}.contains(u['kind']) ||
          (category && !contentId(u['category_id'])) ||
          !seen.add(jsonEncode(u))) {
        throw const StorefrontDecodeException('media', 'invalid usage');
      }
      usages.add(
        Map.unmodifiable(u.map((key, value) => MapEntry(key, value as String))),
      );
    }
    final media = StorefrontMediaRow.fromJson(row);
    if (media.variant != StorefrontVariant.w960 || !contentId(media.id))
      throw const StorefrontDecodeException('media', 'invalid editorial');
    return StorefrontContentMediaRow(media, List.unmodifiable(usages));
  }
}
