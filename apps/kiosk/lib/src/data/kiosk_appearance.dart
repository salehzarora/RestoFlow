import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/kiosk_theme.dart';
import 'kiosk_fixtures.dart';
import 'kiosk_menu_data.dart';

/// KIOSK-001-102 — DEVICE-LOCAL kiosk appearance customization.
///
/// Presentation only, never order truth: the restaurant identity the customer
/// sees on the attract/menu chrome (logo, wordmark + accent, colors,
/// taglines, menu copy, attract media pacing). Persisted per PAIRED DEVICE in
/// SharedPreferences (`restoflow.kiosk.appearance.<deviceId>`) so an APK
/// survives restarts and another kiosk never inherits this device's brand.
/// No auth material, no tokens, no money and no order state live here —
/// malformed storage fails safely back to defaults.
///
/// DEMO mode keeps the Phase-1 EMBER fixture identity via [demoDefaults] (the
/// approved V2 visuals, byte for byte); REAL mode has NO EMBER anywhere — its
/// defaults derive from the paired device/restaurant label.

/// One customer-facing string in the three kiosk languages. Empty entries
/// fall back to [en], then to '' — rendering decides how to collapse.
@immutable
class KioskLocalizedCopy {
  const KioskLocalizedCopy({this.ar = '', this.he = '', this.en = ''});

  final String ar;
  final String he;
  final String en;

  bool get isEmpty => ar.isEmpty && he.isEmpty && en.isEmpty;

  String of(String lang) {
    final direct = switch (lang) {
      'ar' => ar,
      'he' => he,
      _ => en,
    };
    if (direct.isNotEmpty) return direct;
    if (en.isNotEmpty) return en;
    if (ar.isNotEmpty) return ar;
    return he;
  }

  KioskLocalizedCopy withLang(String lang, String value) => KioskLocalizedCopy(
    ar: lang == 'ar' ? value : ar,
    he: lang == 'he' ? value : he,
    en: lang == 'en' ? value : en,
  );

  Map<String, Object?> toJson() => {'ar': ar, 'he': he, 'en': en};

  static KioskLocalizedCopy fromJson(Object? raw, {int maxLength = 120}) {
    if (raw is! Map) return const KioskLocalizedCopy();
    String read(String key) {
      final v = raw[key];
      if (v is! String) return '';
      final t = v.trim();
      return t.length > maxLength ? t.substring(0, maxLength) : t;
    }

    return KioskLocalizedCopy(ar: read('ar'), he: read('he'), en: read('en'));
  }

  @override
  bool operator ==(Object other) =>
      other is KioskLocalizedCopy &&
      other.ar == ar &&
      other.he == he &&
      other.en == en;

  @override
  int get hashCode => Object.hash(ar, he, en);
}

/// Bounded field lengths (visible counters in the editor; enforced on save
/// AND on load so a hand-edited store cannot smuggle unbounded strings).
abstract final class KioskAppearanceLimits {
  static const int name = 60;
  static const int title = 28;
  static const int accent = 28;
  static const int tagline = 90;
  static const int headline = 60;
  static const int subtitle = 90;

  /// Raw picked-logo byte cap (decoded/validated before storing; the base64
  /// representation stays well under SharedPreferences comfort).
  static const int logoBytes = 262144; // 256 KB

  static const List<int> intervalChoices = [4, 5, 6, 8];

  // KIOSK-001-103 §3 — curated attract media bounds.
  /// Operator-curated hero photos: an explicit selection is 4–8 items (all
  /// usable items with a warning when the whole menu has fewer than 4).
  static const int featuredMin = 4;
  static const int featuredMax = 8;
  static const int featuredIdLength = 64;

  /// External attract background image: full-bleed photo, so a larger cap
  /// than the logo — still bounded and decode-proven before storing.
  static const int attractImageBytes = 6 << 20; // 6 MB

  /// External looping video: bounded file size + playable duration.
  static const int attractVideoBytes = 80 << 20; // 80 MB
  static const int attractVideoMaxSeconds = 180;
}

/// KIOSK-001-103 §3 — how the attract screen sources its imagery.
enum KioskAttractMediaMode {
  /// Rotate ONLY operator-selected live-menu hero photos (empty selection =
  /// the Phase-102 automatic category-diverse rotation until curated).
  selectedMenuPhotos,

  /// One device-local external image as a STATIC background (no carousel).
  customImage,

  /// One device-local external video, looping and muted.
  customVideo;

  String get wire => switch (this) {
    selectedMenuPhotos => 'selected_menu_photos',
    customImage => 'custom_image',
    customVideo => 'custom_video',
  };

  static KioskAttractMediaMode? tryParse(Object? raw) => switch (raw) {
    'selected_menu_photos' => selectedMenuPhotos,
    'custom_image' => customImage,
    'custom_video' => customVideo,
    _ => null,
  };
}

/// The compact curated palette offered beside strict hex input.
const List<Color> kKioskBrandPalette = [
  Colors.white,
  KioskColors.accentTop, // the V2 orange
  Color(0xFFFFD166), // warm gold
  Color(0xFF4ADE80), // fresh green
  Color(0xFF60A5FA), // cool blue
  Color(0xFFF87171), // soft red
];

/// Strictly parses `#RRGGBB` (with or without '#'); null on anything else.
Color? parseKioskHexColor(String raw) {
  final t = raw.trim().replaceFirst('#', '');
  if (t.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

@immutable
class KioskAppearanceSettings {
  const KioskAppearanceSettings({
    required this.restaurantDisplayName,
    required this.brandTitlePrimary,
    required this.brandTitleAccent,
    required this.brandPrimaryColor,
    required this.brandAccentColor,
    required this.tagline,
    required this.menuHeadline,
    required this.menuSubtitle,
    required this.logoOverridePngB64,
    required this.attractIntervalSeconds,
    this.attractMediaMode = KioskAttractMediaMode.selectedMenuPhotos,
    this.featuredMenuItemIds = const [],
    this.customImageRef,
    this.customVideoRef,
  });

  /// REAL defaults: derived from the paired device/restaurant label — the one
  /// rule is NO EMBER fixture identity in real mode.
  factory KioskAppearanceSettings.defaults({required String fallbackName}) {
    final name = fallbackName.trim().isEmpty ? 'Kiosk' : fallbackName.trim();
    return KioskAppearanceSettings(
      restaurantDisplayName: name.length > KioskAppearanceLimits.name
          ? name.substring(0, KioskAppearanceLimits.name)
          : name,
      brandTitlePrimary: name.length > KioskAppearanceLimits.title
          ? name.substring(0, KioskAppearanceLimits.title)
          : name,
      brandTitleAccent: '',
      brandPrimaryColor: Colors.white,
      brandAccentColor: KioskColors.accentTop,
      tagline: const KioskLocalizedCopy(),
      menuHeadline: const KioskLocalizedCopy(),
      menuSubtitle: const KioskLocalizedCopy(),
      logoOverridePngB64: null,
      attractIntervalSeconds: 5,
    );
  }

  /// DEMO defaults: the Phase-1 EMBER fixture identity, so every approved V2
  /// demo visual stays byte-identical.
  factory KioskAppearanceSettings.demoDefaults() => KioskAppearanceSettings(
    restaurantDisplayName: KioskBrand.subtitle, // BURGER HOUSE
    brandTitlePrimary: KioskBrand.wordmark, // EMBER
    brandTitleAccent: KioskBrand.wordmarkSuffix, // .
    brandPrimaryColor: Colors.white,
    brandAccentColor: KioskColors.accentTop,
    tagline: const KioskLocalizedCopy(),
    menuHeadline: const KioskLocalizedCopy(),
    menuSubtitle: const KioskLocalizedCopy(),
    logoOverridePngB64: null,
    attractIntervalSeconds: 5,
  );

  final String restaurantDisplayName;
  final String brandTitlePrimary;
  final String brandTitleAccent;
  final Color brandPrimaryColor;
  final Color brandAccentColor;
  final KioskLocalizedCopy tagline;
  final KioskLocalizedCopy menuHeadline;
  final KioskLocalizedCopy menuSubtitle;

  /// Optional device-local logo override, stored as validated base64 image
  /// bytes (PNG/JPEG/WebP, bounded by [KioskAppearanceLimits.logoBytes]).
  final String? logoOverridePngB64;

  final int attractIntervalSeconds;

  // ---- KIOSK-001-103 §3: curated attract media --------------------------
  final KioskAttractMediaMode attractMediaMode;

  /// Operator-picked hero items — STABLE menu item ids in the chosen display
  /// order. Never image paths, never signed URLs. Stale/deleted/no-image
  /// entries are skipped at render time, never silently substituted.
  final List<String> featuredMenuItemIds;

  /// Device-local media REFS (generated file names, resolved through
  /// KioskAttractMediaStore) — never absolute paths, never URLs.
  final String? customImageRef;
  final String? customVideoRef;

  Uint8List? get logoOverrideBytes {
    final b64 = logoOverridePngB64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null; // corrupt stored reference fails safely to no-override
    }
  }

  /// Elegant monogram source: first two initials of the display name.
  String get monogram {
    final words = restaurantDisplayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '•';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words[0].characters.first + words[1].characters.first)
        .toUpperCase();
  }

  KioskAppearanceSettings copyWith({
    String? restaurantDisplayName,
    String? brandTitlePrimary,
    String? brandTitleAccent,
    Color? brandPrimaryColor,
    Color? brandAccentColor,
    KioskLocalizedCopy? tagline,
    KioskLocalizedCopy? menuHeadline,
    KioskLocalizedCopy? menuSubtitle,
    Object? logoOverridePngB64 = _sentinel,
    int? attractIntervalSeconds,
    KioskAttractMediaMode? attractMediaMode,
    List<String>? featuredMenuItemIds,
    Object? customImageRef = _sentinel,
    Object? customVideoRef = _sentinel,
  }) => KioskAppearanceSettings(
    restaurantDisplayName: restaurantDisplayName ?? this.restaurantDisplayName,
    brandTitlePrimary: brandTitlePrimary ?? this.brandTitlePrimary,
    brandTitleAccent: brandTitleAccent ?? this.brandTitleAccent,
    brandPrimaryColor: brandPrimaryColor ?? this.brandPrimaryColor,
    brandAccentColor: brandAccentColor ?? this.brandAccentColor,
    tagline: tagline ?? this.tagline,
    menuHeadline: menuHeadline ?? this.menuHeadline,
    menuSubtitle: menuSubtitle ?? this.menuSubtitle,
    logoOverridePngB64: identical(logoOverridePngB64, _sentinel)
        ? this.logoOverridePngB64
        : logoOverridePngB64 as String?,
    attractIntervalSeconds:
        attractIntervalSeconds ?? this.attractIntervalSeconds,
    attractMediaMode: attractMediaMode ?? this.attractMediaMode,
    featuredMenuItemIds: featuredMenuItemIds ?? this.featuredMenuItemIds,
    customImageRef: identical(customImageRef, _sentinel)
        ? this.customImageRef
        : customImageRef as String?,
    customVideoRef: identical(customVideoRef, _sentinel)
        ? this.customVideoRef
        : customVideoRef as String?,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'restaurant_display_name': restaurantDisplayName,
    'brand_title_primary': brandTitlePrimary,
    'brand_title_accent': brandTitleAccent,
    'brand_primary_color': brandPrimaryColor.toARGB32(),
    'brand_accent_color': brandAccentColor.toARGB32(),
    'tagline': tagline.toJson(),
    'menu_headline': menuHeadline.toJson(),
    'menu_subtitle': menuSubtitle.toJson(),
    if (logoOverridePngB64 != null) 'logo_override_b64': logoOverridePngB64,
    'attract_interval_seconds': attractIntervalSeconds,
    'attract_media_mode': attractMediaMode.wire,
    'featured_menu_item_ids': featuredMenuItemIds,
    if (customImageRef != null) 'custom_image_ref': customImageRef,
    if (customVideoRef != null) 'custom_video_ref': customVideoRef,
  };

  /// Tolerant, bounded decode: any malformed field falls back to [fallback]'s
  /// value — a corrupt store can degrade a field, never crash the kiosk.
  static KioskAppearanceSettings fromJson(
    Object? raw,
    KioskAppearanceSettings fallback,
  ) {
    if (raw is! Map) return fallback;
    String str(String key, String fb, int max) {
      final v = raw[key];
      if (v is! String) return fb;
      final t = v.trim();
      return t.length > max ? t.substring(0, max) : t;
    }

    Color color(String key, Color fb) {
      final v = raw[key];
      return v is int ? Color(0xFF000000 | (v & 0x00FFFFFF)) : fb;
    }

    final b64 = raw['logo_override_b64'];
    final interval = raw['attract_interval_seconds'];
    // KIOSK-001-103: bounded featured-id list — strings only, deduped in
    // stored order, each id length-capped, list capped at featuredMax.
    final rawFeatured = raw['featured_menu_item_ids'];
    final featured = <String>[];
    if (rawFeatured is List) {
      for (final entry in rawFeatured) {
        if (featured.length >= KioskAppearanceLimits.featuredMax) break;
        if (entry is! String) continue;
        final id = entry.trim();
        if (id.isEmpty ||
            id.length > KioskAppearanceLimits.featuredIdLength ||
            featured.contains(id)) {
          continue;
        }
        featured.add(id);
      }
    }
    String? mediaRef(String key) {
      final v = raw[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty || t.length > 60 ? null : t;
    }

    return KioskAppearanceSettings(
      restaurantDisplayName: str(
        'restaurant_display_name',
        fallback.restaurantDisplayName,
        KioskAppearanceLimits.name,
      ),
      brandTitlePrimary: str(
        'brand_title_primary',
        fallback.brandTitlePrimary,
        KioskAppearanceLimits.title,
      ),
      brandTitleAccent: str(
        'brand_title_accent',
        fallback.brandTitleAccent,
        KioskAppearanceLimits.accent,
      ),
      brandPrimaryColor: color(
        'brand_primary_color',
        fallback.brandPrimaryColor,
      ),
      brandAccentColor: color('brand_accent_color', fallback.brandAccentColor),
      tagline: KioskLocalizedCopy.fromJson(
        raw['tagline'],
        maxLength: KioskAppearanceLimits.tagline,
      ),
      menuHeadline: KioskLocalizedCopy.fromJson(
        raw['menu_headline'],
        maxLength: KioskAppearanceLimits.headline,
      ),
      menuSubtitle: KioskLocalizedCopy.fromJson(
        raw['menu_subtitle'],
        maxLength: KioskAppearanceLimits.subtitle,
      ),
      logoOverridePngB64: b64 is String && b64.isNotEmpty ? b64 : null,
      attractIntervalSeconds:
          interval is int &&
              KioskAppearanceLimits.intervalChoices.contains(interval)
          ? interval
          : fallback.attractIntervalSeconds,
      attractMediaMode:
          KioskAttractMediaMode.tryParse(raw['attract_media_mode']) ??
          fallback.attractMediaMode,
      featuredMenuItemIds: List.unmodifiable(featured),
      customImageRef: mediaRef('custom_image_ref'),
      customVideoRef: mediaRef('custom_video_ref'),
    );
  }

  static const _sentinel = Object();
}

/// Device-scoped persistence. The key embeds the PAIRED device id so two
/// kiosks sharing one OS profile can never inherit each other's brand.
class KioskAppearanceStore {
  KioskAppearanceStore(this._prefs);

  final SharedPreferences _prefs;

  static String keyFor(String deviceId) =>
      'restoflow.kiosk.appearance.$deviceId';

  KioskAppearanceSettings? load(
    String deviceId,
    KioskAppearanceSettings fallback,
  ) {
    final raw = _prefs.getString(keyFor(deviceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return KioskAppearanceSettings.fromJson(jsonDecode(raw), fallback);
    } catch (_) {
      return null; // malformed JSON fails safely to defaults
    }
  }

  Future<bool> save(String deviceId, KioskAppearanceSettings settings) =>
      _prefs.setString(keyFor(deviceId), jsonEncode(settings.toJson()));

  Future<bool> clear(String deviceId) => _prefs.remove(keyFor(deviceId));
}

/// True only under the REAL composition root (paired production client). The
/// customer chrome uses it to decide fixture-vs-tenant fallbacks; it never
/// gates money or order behavior.
final kioskRealModeProvider = Provider<bool>((ref) => false);

/// The store seam (null in demo/tests; the real root provides the
/// SharedPreferences-backed store).
final kioskAppearanceStoreProvider = Provider<KioskAppearanceStore?>(
  (ref) => null,
);

/// Device id + fallback label the controller keys storage by (real root
/// publishes it once the pairing gate activates).
typedef KioskAppearanceScope = ({String deviceId, String fallbackName});

final kioskAppearanceScopeProvider = StateProvider<KioskAppearanceScope?>(
  (ref) => null,
);

final kioskAppearanceProvider =
    NotifierProvider<KioskAppearanceController, KioskAppearanceSettings>(
      KioskAppearanceController.new,
    );

class KioskAppearanceController extends Notifier<KioskAppearanceSettings> {
  @override
  KioskAppearanceSettings build() {
    final real = ref.watch(kioskRealModeProvider);
    if (!real) return KioskAppearanceSettings.demoDefaults();
    final scope = ref.watch(kioskAppearanceScopeProvider);
    final defaults = KioskAppearanceSettings.defaults(
      fallbackName: scope?.fallbackName ?? 'Kiosk',
    );
    if (scope == null) return defaults;
    final store = ref.watch(kioskAppearanceStoreProvider);
    return store?.load(scope.deviceId, defaults) ?? defaults;
  }

  /// Persists (real mode) and publishes the new appearance.
  Future<void> save(KioskAppearanceSettings settings) async {
    state = settings;
    final scope = ref.read(kioskAppearanceScopeProvider);
    final store = ref.read(kioskAppearanceStoreProvider);
    if (scope != null && store != null) {
      await store.save(scope.deviceId, settings);
    }
  }

  /// Resets this DEVICE back to its real-mode defaults (confirmed in the UI).
  Future<void> resetToDefaults() async {
    final scope = ref.read(kioskAppearanceScopeProvider);
    final store = ref.read(kioskAppearanceStoreProvider);
    if (scope != null && store != null) await store.clear(scope.deviceId);
    state = ref.read(kioskRealModeProvider)
        ? KioskAppearanceSettings.defaults(
            fallbackName: scope?.fallbackName ?? 'Kiosk',
          )
        : KioskAppearanceSettings.demoDefaults();
  }
}

/// KIOSK-001-102 §7 — the attract carousel's image list: one representative
/// LIVE photo per category first (display order, first item with a resolved
/// signed URL), then a second pass tops the list up — capped so egress stays
/// controlled. Deterministic for a given menu + resolution set.
List<String> kioskAttractCarouselUrls(
  KioskMenuData menu,
  Map<String, String> resolvedUrls, {
  int max = 6,
}) {
  final urls = <String>[];
  // Pass 1: category diversity.
  for (final category in menu.categories) {
    if (urls.length >= max) break;
    for (final item in category.items) {
      final path = item.imagePath;
      if (path == null || !item.available) continue;
      final url = resolvedUrls[path];
      if (url != null && !urls.contains(url)) {
        urls.add(url);
        break;
      }
    }
  }
  // Pass 2: fill remaining slots in stable menu order.
  for (final category in menu.categories) {
    if (urls.length >= max) break;
    for (final item in category.items) {
      if (urls.length >= max) break;
      final path = item.imagePath;
      if (path == null || !item.available) continue;
      final url = resolvedUrls[path];
      if (url != null && !urls.contains(url)) urls.add(url);
    }
  }
  return urls;
}

/// KIOSK-001-103 §7 — the CURATED carousel list: stored featured item ids
/// mapped onto the CURRENT live menu in the operator's chosen order. An id
/// that no longer exists, is unavailable, has no image, or has no resolved
/// signed URL is SKIPPED (shown stale in the picker) — never substituted
/// with an unrelated product.
List<String> kioskFeaturedCarouselUrls(
  KioskMenuData menu,
  Map<String, String> resolvedUrls,
  List<String> featuredIds,
) {
  if (featuredIds.isEmpty) return const [];
  final itemsById = <String, KioskFixtureItem>{
    for (final category in menu.categories)
      for (final item in category.items) item.id: item,
  };
  final urls = <String>[];
  for (final id in featuredIds) {
    final item = itemsById[id];
    if (item == null || !item.available) continue;
    final path = item.imagePath;
    if (path == null) continue;
    final url = resolvedUrls[path];
    if (url != null && !urls.contains(url)) urls.add(url);
  }
  return urls;
}

/// KIOSK-001-102 §11 — one representative product photo URL per category id
/// (first display-order AVAILABLE item with a resolved image); categories
/// without one are simply absent (the wheel falls back to its icon).
Map<String, String> kioskCategoryImageUrls(
  KioskMenuData menu,
  Map<String, String> resolvedUrls,
) {
  final byCategory = <String, String>{};
  for (final category in menu.categories) {
    for (final item in category.items) {
      final path = item.imagePath;
      if (path == null || !item.available) continue;
      final url = resolvedUrls[path];
      if (url != null) {
        byCategory[category.id] = url;
        break;
      }
    }
  }
  return byCategory;
}
