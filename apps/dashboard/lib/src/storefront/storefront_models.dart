import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// STOREFRONT-PUBLISH-001 — the typed data layer of the Dashboard Settings
/// "Storefront" editor.
///
/// Everything here is decoded from the READ-001 / PUBLISH-001 server envelopes
/// (`get_restaurant_storefront_profile`, `list_storefront_media`, the
/// `storefront-media-publish` function). Decoding is DEFENSIVE: a malformed
/// server field raises a typed [StorefrontDecodeException] that the
/// repositories turn into a typed `malformed` result — it never crashes the
/// editor and it never guesses a value. No money lives here (D-007).

// ---------------------------------------------------------------------------
// Typed decode failure
// ---------------------------------------------------------------------------

/// A server field could not be decoded into the typed model. [field] is the
/// dotted path of the offending field (e.g. `profile.opening_hours`); [detail]
/// says what was wrong, never echoing the raw value.
class StorefrontDecodeException implements Exception {
  const StorefrontDecodeException(this.field, [this.detail]);

  final String field;
  final String? detail;

  @override
  String toString() =>
      'StorefrontDecodeException($field${detail == null ? '' : ': $detail'})';
}

// ---------------------------------------------------------------------------
// Enumerations (wire values are the exact server strings)
// ---------------------------------------------------------------------------

/// `visual_preset` (CHECK `in ('dark','light')`).
enum StorefrontVisualPreset { dark, light }

/// `locale_default` (CHECK `in ('ar','he','en')`). Stored for later: the public
/// storefront currently chooses its language from the address.
enum StorefrontLocale { ar, he, en }

/// `card_mode` (CHECK `in ('list','grid')`).
enum StorefrontCardMode { list, grid }

/// `motion` (CHECK `in ('calm','full','lively')`).
enum StorefrontMotion { calm, full, lively }

/// A published derivative's size (CONTRACT §1.1: exactly `w480` | `w960`).
enum StorefrontVariant { w480, w960 }

/// A storefront_media row's lifecycle (CONTRACT §0): STAGED = registered but
/// not referenced by the public contract; `published` = LIVE; `retracted` =
/// unpublished (RETRACTED -> LIVE is allowed by re-publishing).
enum StorefrontMediaState { staged, published, retracted }

/// The PRIVATE bucket a derivative is made from (CONTRACT §2).
enum StorefrontSourceBucket {
  restaurantLogos('restaurant-logos'),
  menuImages('menu-images');

  const StorefrontSourceBucket(this.wire);

  /// The exact bucket id on the wire.
  final String wire;

  static StorefrontSourceBucket? fromWire(Object? value) {
    for (final b in values) {
      if (b.wire == value) return b;
    }
    return null;
  }
}

/// The two storefront media slots (CONTRACT §2, owner decisions D3/D4):
/// logo = `w480` from the receipt logo ONLY; hero = `w960` from the receipt
/// logo OR a menu item's original. Item images are NOT a slot of this ticket.
enum StorefrontSlot {
  logo(
    wire: 'logo',
    variant: StorefrontVariant.w480,
    profileKey: 'logo_media_id',
    allowedBuckets: [StorefrontSourceBucket.restaurantLogos],
  ),
  hero(
    wire: 'hero',
    variant: StorefrontVariant.w960,
    profileKey: 'hero_media_id',
    allowedBuckets: [
      StorefrontSourceBucket.restaurantLogos,
      StorefrontSourceBucket.menuImages,
    ],
  );

  const StorefrontSlot({
    required this.wire,
    required this.variant,
    required this.profileKey,
    required this.allowedBuckets,
  });

  /// `'logo'` | `'hero'` on the wire.
  final String wire;

  /// The derivative size this slot publishes.
  final StorefrontVariant variant;

  /// The profile pointer column this slot is assigned through.
  final String profileKey;

  /// The private buckets a source for this slot may come from.
  final List<StorefrontSourceBucket> allowedBuckets;

  static StorefrontSlot? fromWire(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Server code registries (the UI maps each to localized copy + a fallback)
// ---------------------------------------------------------------------------

/// Every `reason` the profile writer (`app.set_restaurant_storefront_profile`)
/// can return with `error: 'invalid'`, in the order the migration defines them.
const List<String> kStorefrontInvalidReasons = [
  'slug_invalid',
  'slug_immutable',
  'slug_taken',
  'branch_invalid',
  'display_name_invalid',
  'tagline_invalid',
  'public_city_invalid',
  'public_address_invalid',
  'public_phone_invalid',
  'primary_color_invalid',
  'accent_color_invalid',
  'visual_preset_invalid',
  'locale_default_invalid',
  'card_mode_invalid',
  'motion_invalid',
  'pickup_enabled_invalid',
  'paused_until_invalid',
  'pause_reason_invalid',
  'opening_hours_invalid',
  'logo_media_id_invalid',
  'hero_media_id_invalid',
  'is_published_invalid',
  'branch_missing',
  'slug_missing',
  'publish_precondition',
  'unknown_field',
  'patch_not_object',
];

/// The ordered publish blockers of `app.storefront_publish_blockers`.
const List<String> kStorefrontPublishBlockers = [
  'slug_missing',
  'branch_missing',
  'timezone_missing',
  'currency_not_ils',
  'tax_not_exclusive',
  'no_live_item',
  'hours_missing',
];

/// The blockers under which the public read (READ-001 `public.storefront_menu`)
/// answers `not_found` even though the profile is PUBLISHED: no resolvable
/// slug / live storefront branch, no time zone, a currency other than ILS, or
/// tax included in prices. Visitors then see a "not found" page.
const Set<String> kStorefrontBlockersHidingPage = {
  'slug_missing',
  'branch_missing',
  'timezone_missing',
  'currency_not_ils',
  'tax_not_exclusive',
};

/// The blockers under which a PUBLISHED storefront is still served, only
/// incomplete: `no_live_item` (an empty menu) and `hours_missing` (no weekly
/// hours, so it shows as closed).
const Set<String> kStorefrontBlockersPageOnline = {
  'no_live_item',
  'hours_missing',
};

/// What the public page of a PUBLISHED profile does, from the SAVED
/// profile's blockers (STOREFRONT-PUBLISH-001: the card never claims "public"
/// while the public read answers `not_found`).
enum StorefrontPublishedPage {
  /// No blockers: the page is served.
  online,

  /// Only [kStorefrontBlockersPageOnline] codes: served, but incomplete.
  incomplete,

  /// At least one [kStorefrontBlockersHidingPage] code: `not_found`.
  offline,

  /// An unknown (newer) blocker code: its effect cannot be known here.
  unknown,
}

/// Classifies a PUBLISHED profile's [blockers] (see [StorefrontPublishedPage]).
StorefrontPublishedPage storefrontPublishedPageOf(List<String> blockers) {
  if (blockers.any(kStorefrontBlockersHidingPage.contains)) {
    return StorefrontPublishedPage.offline;
  }
  if (blockers.isEmpty) return StorefrontPublishedPage.online;
  return blockers.every(kStorefrontBlockersPageOnline.contains)
      ? StorefrontPublishedPage.incomplete
      : StorefrontPublishedPage.unknown;
}

/// The typed, deterministic `422 refused` codes of the publish function
/// (CONTRACT §2) — "do not retry": the source image is refused as it is
/// (the hero slot may pick another source; the logo slot's only source is the
/// receipt logo, which has to be replaced in Branding).
///
/// A content-address mismatch is deliberately NOT here: the function never
/// answers it as a 422 — a stage `content_mismatch` or a different object at
/// the address is its `409 object_conflict` (see
/// `StorefrontPublishStatus.objectConflict`). Nor is the retired c3
/// `encode_warning`: recipe `storefront-media-c4` answers any non-trap codec
/// failure (decode, resize or encode) as `decode_failed`.
const List<String> kStorefrontRefusalCodes = [
  'unsupported_format',
  'empty',
  'input_too_large',
  'too_many_pixels',
  'dimensions_too_large',
  'aspect_ratio',
  'animated',
  'truncated',
  'corrupt',
  'metadata_too_large',
  'too_many_scans',
  'decode_failed',
  'decode_warning',
  'output_too_large',
  'self_check_failed',
];

/// `422 refused` codes that are NOT about the source image: the stage step's
/// validation reasons (`stage_storefront_media` answers `invalid` + reason,
/// which the function relays as its 422 `code`, falling back to `invalid`)
/// and the recipe's own argument checks. They mean a programming / server
/// fault — never "pick another source image" — so the publisher reports them
/// as an invalid request.
const List<String> kStorefrontPublishFaultCodes = [
  'source_bucket_invalid',
  'variant_invalid',
  'variant_not_allowed',
  'source_key_invalid',
  'content_hash_invalid',
  'dimensions_invalid',
  'bytes_invalid',
  'invalid',
  'unknown_variant',
  'unknown_source',
  'unknown_rung',
];

// ---------------------------------------------------------------------------
// Request ids + small grammars
// ---------------------------------------------------------------------------

final RegExp _canonicalUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// True for canonical LOWER-CASE UUID text (what Postgres prints and what the
/// publish function's validator accepts for `request_id`).
bool isCanonicalUuid(String value) => _canonicalUuid.hasMatch(value);

/// One stable, v5-shaped idempotency key for ONE logical request (the house
/// pattern of `SupabaseRestaurantLogoRepository`): sha256 of
/// `prefix + parts + nonce`, version/variant bits set, canonical lower-case
/// text. The caller reuses the SAME key for every retry of that request (the
/// server ledger replays a committed result); a new deliberate press takes a
/// new [nonce], so it is its own request.
String storefrontRequestId(String prefix, List<String> parts, int nonce) {
  final seed = [...parts, nonce.toString()].join('|');
  final bytes = sha256
      .convert(utf8.encode('$prefix$seed'))
      .bytes
      .sublist(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
  String hx(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
}

/// The writer's slug grammar: `^[a-z0-9]+(-[a-z0-9]+)*$`, 3..48 chars, and not
/// a reserved word. Client-side mirror only — the server stays authoritative.
const List<String> kStorefrontReservedSlugs = [
  'api',
  'order',
  'admin',
  'pos',
  'kds',
  'kiosk',
  'app',
  'ar',
  'en',
  'he',
  'www',
  's',
  'r',
];

final RegExp _slugShape = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidStorefrontSlug(String slug) =>
    slug.length >= 3 &&
    slug.length <= 48 &&
    _slugShape.hasMatch(slug) &&
    !kStorefrontReservedSlugs.contains(slug);

/// The writer's `paused_until` wire grammar: RFC 3339 with an EXPLICIT `Z` or
/// offset (an offset-less string would be read in the session zone and is
/// refused by the server).
final RegExp _instantText = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$',
);

bool isStorefrontInstantText(String value) => _instantText.hasMatch(value);

/// Formats [instant] as the wall-clock time at [offset] with that offset
/// spelled out, e.g. `2026-10-01T18:00:00+03:00` — the one canonical
/// `paused_until` wire form. Sub-second precision is dropped.
String formatStorefrontInstant(
  DateTime instant, {
  Duration offset = Duration.zero,
}) {
  if (offset.inSeconds % 60 != 0 || offset.abs() >= const Duration(hours: 24)) {
    throw ArgumentError.value(offset, 'offset', 'whole minutes below 24 h');
  }
  final wall = instant.toUtc().add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  final abs = offset.abs();
  final sign = offset.isNegative ? '-' : '+';
  return '${wall.year.toString().padLeft(4, '0')}-${two(wall.month)}-'
      '${two(wall.day)}T${two(wall.hour)}:${two(wall.minute)}:'
      '${two(wall.second)}$sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
}

// ---------------------------------------------------------------------------
// Defensive JSON reader
// ---------------------------------------------------------------------------

class _Json {
  _Json(this.map, this.path);

  factory _Json.of(Object? value, String path) {
    if (value is! Map) {
      throw StorefrontDecodeException(path, 'not an object');
    }
    return _Json(value, path);
  }

  final Map<dynamic, dynamic> map;
  final String path;

  String at(String key) => path.isEmpty ? key : '$path.$key';

  Object? operator [](String key) => map[key];

  String string(String key) {
    final v = map[key];
    if (v is! String || v.isEmpty) {
      throw StorefrontDecodeException(at(key), 'expected a non-empty string');
    }
    return v;
  }

  String? optString(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is! String) {
      throw StorefrontDecodeException(at(key), 'expected a string or null');
    }
    return v;
  }

  bool boolean(String key) {
    final v = map[key];
    if (v is! bool) throw StorefrontDecodeException(at(key), 'expected a bool');
    return v;
  }

  int integer(String key, {int? min}) {
    final v = map[key];
    if (v is! int || (min != null && v < min)) {
      throw StorefrontDecodeException(at(key), 'expected an integer');
    }
    return v;
  }

  int? optInteger(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is! int) {
      throw StorefrontDecodeException(at(key), 'expected an integer or null');
    }
    return v;
  }

  DateTime? optInstant(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is! String) {
      throw StorefrontDecodeException(at(key), 'expected a timestamp or null');
    }
    final parsed = DateTime.tryParse(v);
    if (parsed == null) {
      throw StorefrontDecodeException(at(key), 'unparseable timestamp');
    }
    return parsed.toUtc();
  }

  DateTime instant(String key) {
    final v = optInstant(key);
    if (v == null) throw StorefrontDecodeException(at(key), 'missing');
    return v;
  }

  T enumValue<T extends Enum>(String key, List<T> values) {
    final v = _enumByName(values, map[key]);
    if (v == null) {
      throw StorefrontDecodeException(at(key), 'unknown value');
    }
    return v;
  }

  List<String> stringList(String key) {
    final v = map[key];
    if (v is! List) throw StorefrontDecodeException(at(key), 'expected a list');
    final out = <String>[];
    for (var i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is! String || e.isEmpty) {
        throw StorefrontDecodeException('${at(key)}[$i]', 'expected a string');
      }
      out.add(e);
    }
    return List.unmodifiable(out);
  }
}

// ---------------------------------------------------------------------------
// Opening hours
// ---------------------------------------------------------------------------

final RegExp _hhmm = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
final RegExp _ymd = RegExp(
  r'^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$',
);

/// True for `HH:MM` (HH 00..23, MM 00..59) — the validator's time grammar.
bool isStorefrontHhmm(String value) => _hhmm.hasMatch(value);

/// True for `YYYY-MM-DD` in the validator's date grammar (shape only, exactly
/// as the server checks it).
bool isStorefrontDate(String value) => _ymd.hasMatch(value);

/// Minutes since midnight of an `HH:MM` time, or null when it is not one.
int? _minutesOf(String hhmm) {
  if (!_hhmm.hasMatch(hhmm)) return null;
  return int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3));
}

/// `HH:MM` for minutes since midnight (0..1439).
String _hhmmOf(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// A window's span in minutes from its weekday's midnight, `[start, end)`,
/// exactly as the public read (`app.storefront_service_window`) lays it out:
/// an overnight window (close earlier than open) ends past 1440, on the next
/// morning. Null for a window the validator refuses (a bad time, open ==
/// close) — flagging those is [OpeningHours.validate]'s job.
(int, int)? _spanOf(String open, String close) {
  final o = _minutesOf(open);
  final c = _minutesOf(close);
  if (o == null || c == null || o == c) return null;
  return (o, c > o ? c : c + 1440);
}

/// One weekly service window. [dow] 0..6 with 0 = Sunday. A [close] EARLIER
/// than [open] crosses midnight (e.g. 18:00 -> 02:00); open == close is
/// refused (there is no zero-length or 24 h form).
class WeeklyWindow {
  const WeeklyWindow({
    required this.dow,
    required this.open,
    required this.close,
  });

  final int dow;
  final String open;
  final String close;

  /// The window ends on the NEXT day (close earlier than open).
  bool get crossesMidnight => close.compareTo(open) < 0;

  Map<String, Object?> toJson() => {'dow': dow, 'open': open, 'close': close};

  @override
  bool operator ==(Object other) =>
      other is WeeklyWindow &&
      other.dow == dow &&
      other.open == open &&
      other.close == close;

  @override
  int get hashCode => Object.hash(dow, open, close);

  @override
  String toString() => 'WeeklyWindow($dow $open-$close)';
}

/// A date exception: closed all day ([HoursException.closed]) or ONE window
/// ([HoursException.window]). The two shapes are the only ones the validator
/// accepts — `closed: false` is NOT a shape and is never emitted.
class HoursException {
  const HoursException.closed(this.date)
    : closed = true,
      open = null,
      close = null;

  const HoursException.window({
    required this.date,
    required String this.open,
    required String this.close,
  }) : closed = false;

  /// `YYYY-MM-DD`.
  final String date;
  final bool closed;
  final String? open;
  final String? close;

  bool get crossesMidnight =>
      !closed && close != null && open != null && close!.compareTo(open!) < 0;

  Map<String, Object?> toJson() => closed
      ? {'date': date, 'closed': true}
      : {'date': date, 'open': open, 'close': close};

  @override
  bool operator ==(Object other) =>
      other is HoursException &&
      other.date == date &&
      other.closed == closed &&
      other.open == open &&
      other.close == close;

  @override
  int get hashCode => Object.hash(date, closed, open, close);

  @override
  String toString() => closed
      ? 'HoursException($date closed)'
      : 'HoursException($date $open-$close)';
}

/// What [OpeningHours.validate] found wrong.
enum OpeningHoursIssueKind {
  /// More than [OpeningHours.maxWeekly] weekly windows.
  tooManyWeekly,

  /// More than [OpeningHours.maxExceptions] exception dates.
  tooManyExceptions,

  /// A weekly `dow` outside 0..6.
  dowOutOfRange,

  /// An `open`/`close` that is not `HH:MM`.
  invalidTime,

  /// `open == close` (refused: no zero-length / 24 h window).
  openEqualsClose,

  /// An exception `date` that is not `YYYY-MM-DD`.
  invalidDate,
}

/// One validation finding. [index] points into [OpeningHours.weekly] (or
/// [OpeningHours.exceptions] when [inExceptions]); null for list-level caps.
class OpeningHoursIssue {
  const OpeningHoursIssue(this.kind, {this.inExceptions = false, this.index});

  final OpeningHoursIssueKind kind;
  final bool inExceptions;
  final int? index;

  @override
  bool operator ==(Object other) =>
      other is OpeningHoursIssue &&
      other.kind == kind &&
      other.inExceptions == inExceptions &&
      other.index == index;

  @override
  int get hashCode => Object.hash(kind, inExceptions, index);

  @override
  String toString() =>
      'OpeningHoursIssue($kind, ${inExceptions ? 'exceptions' : 'weekly'}'
      '${index == null ? '' : '[$index]'})';
}

/// What [OpeningHours.overlaps] found. ADVISORY only: the server validator
/// does not check overlap and accepts every one of these shapes, so they
/// never block a save. They are flagged because the public read
/// (`app.storefront_service_window`) announces ONE window's closing time —
/// the earliest-opening window that contains the moment — so overlapping
/// windows can make the page say the restaurant closes earlier than it does.
enum OpeningHoursOverlapKind {
  /// Two windows of one weekday with the same open AND close time.
  duplicate,

  /// Two different windows of one weekday that share time (an overnight
  /// window counts until its end on the next morning).
  sameDay,

  /// An overnight window that runs past midnight into a window of the NEXT
  /// weekday (Saturday runs into Sunday).
  overnightSpill,
}

/// One advisory finding of [OpeningHours.overlaps]. [index] / [otherIndex]
/// point into [OpeningHours.windowsFor] of [dow] / [otherDow]; for
/// [OpeningHoursOverlapKind.overnightSpill] the first window is the overnight
/// one and [otherDow] is the next weekday, otherwise both days are equal.
class OpeningHoursOverlap {
  const OpeningHoursOverlap(
    this.kind, {
    required this.dow,
    required this.index,
    required this.otherDow,
    required this.otherIndex,
  });

  final OpeningHoursOverlapKind kind;
  final int dow;
  final int index;
  final int otherDow;
  final int otherIndex;

  @override
  bool operator ==(Object other) =>
      other is OpeningHoursOverlap &&
      other.kind == kind &&
      other.dow == dow &&
      other.index == index &&
      other.otherDow == otherDow &&
      other.otherIndex == otherIndex;

  @override
  int get hashCode => Object.hash(kind, dow, index, otherDow, otherIndex);

  @override
  String toString() =>
      'OpeningHoursOverlap($kind, $dow[$index] ~ $otherDow[$otherIndex])';
}

/// The profile's `opening_hours` (validated server-side by
/// `app.storefront_opening_hours_is_valid`). Times are wall-clock times in the
/// storefront branch's timezone (`StorefrontDerived.timezone`).
class OpeningHours {
  const OpeningHours({
    this.weekly = const <WeeklyWindow>[],
    this.exceptions = const <HoursException>[],
    this.hasUnreadableEntries = false,
  }) : storedRaw = null;

  /// A STORED value with entries this editor cannot represent: the readable
  /// entries for display, plus the untouched authoritative JSON.
  const OpeningHours._unreadable({
    required this.weekly,
    required this.exceptions,
    required Object this.storedRaw,
  }) : hasUnreadableEntries = true;

  /// Validator caps.
  static const int maxWeekly = 21;
  static const int maxExceptions = 62;

  /// The editor's per-weekday cap (7 x 3 = [maxWeekly]).
  static const int maxWindowsPerDay = 3;

  static const OpeningHours empty = OpeningHours();

  final List<WeeklyWindow> weekly;
  final List<HoursException> exceptions;

  /// True only for a STORED value (see [OpeningHours.fromStored]) that held
  /// entries the database check lets through but this editor cannot represent
  /// (an entry MISSING its `dow` / `open` / `close` / `date` key — e.g.
  /// written by a direct RPC call). Those entries are left out of [weekly] /
  /// [exceptions] (shown), while [storedRaw] keeps the authoritative value
  /// untouched: nothing replaces it until the manager EXPLICITLY repairs the
  /// hours (a value built without this flag) and saves. Part of equality: a
  /// value the editor builds (always false) differs from such a stored value,
  /// so a repair makes the draft dirty and the next save writes the clean
  /// form.
  final bool hasUnreadableEntries;

  /// The exact stored JSON of a value flagged [hasUnreadableEntries] (null
  /// otherwise). [toJson] answers it unchanged, so no code path can write back
  /// a lossy copy of hours the editor cannot represent.
  final Object? storedRaw;

  /// The weekly windows of one weekday (0 = Sunday), in stored order.
  List<WeeklyWindow> windowsFor(int dow) =>
      weekly.where((w) => w.dow == dow).toList(growable: false);

  bool get hasWeeklyWindow => weekly.isNotEmpty;

  /// The EXACT validator grammar, with every documented key required:
  /// an object with only `weekly` / `exceptions`; `weekly` an array of at most
  /// 21 `{dow: JSON integer 0..6, open: "HH:MM", close: "HH:MM"}` (no other
  /// key, open != close); `exceptions` an array of at most 62
  /// `{date: "YYYY-MM-DD", closed: true}` (no open/close) or
  /// `{date, open, close}` with NO `closed` key (`closed: false` is invalid),
  /// open != close.
  ///
  /// It is deliberately a hair STRICTER than the SQL, which lets an object
  /// with a MISSING `dow`/`open`/`close`/`date` key through (NULL propagation
  /// in its IF conditions); this client never emits such a shape, and reads a
  /// stored one through [OpeningHours.fromStored] (flagged, not fatal).
  static bool isValidJson(Object? json) {
    if (json is! Map) return false;
    for (final k in json.keys) {
      if (k != 'weekly' && k != 'exceptions') return false;
    }
    if (json.containsKey('weekly')) {
      final weekly = json['weekly'];
      if (weekly is! List || weekly.length > maxWeekly) return false;
      for (final w in weekly) {
        if (w is! Map) return false;
        for (final k in w.keys) {
          if (k != 'dow' && k != 'open' && k != 'close') return false;
        }
        final dow = w['dow'];
        if (dow is! int || dow < 0 || dow > 6) return false;
        if (!_validWindowJson(w)) return false;
      }
    }
    if (json.containsKey('exceptions')) {
      final exceptions = json['exceptions'];
      if (exceptions is! List || exceptions.length > maxExceptions) {
        return false;
      }
      for (final e in exceptions) {
        if (e is! Map) return false;
        for (final k in e.keys) {
          if (k != 'date' && k != 'closed' && k != 'open' && k != 'close') {
            return false;
          }
        }
        final date = e['date'];
        if (date is! String || !_ymd.hasMatch(date)) return false;
        if (e['closed'] == true) {
          if (e.containsKey('open') || e.containsKey('close')) return false;
        } else {
          if (e.containsKey('closed')) return false; // closed:false etc.
          if (!_validWindowJson(e)) return false;
        }
      }
    }
    return true;
  }

  static bool _validWindowJson(Map<dynamic, dynamic> w) {
    final open = w['open'];
    final close = w['close'];
    return open is String &&
        close is String &&
        _hhmm.hasMatch(open) &&
        _hhmm.hasMatch(close) &&
        open != close;
  }

  /// Decodes a stored/served value. Anything outside [isValidJson] raises a
  /// [StorefrontDecodeException] (never a crash, never a silent repair).
  factory OpeningHours.fromJson(Object? json, {String path = 'opening_hours'}) {
    if (!isValidJson(json)) {
      throw StorefrontDecodeException(path, 'outside the validator grammar');
    }
    final map = json! as Map;
    final weekly = <WeeklyWindow>[
      for (final w in (map['weekly'] as List?) ?? const [])
        WeeklyWindow(
          dow: (w as Map)['dow'] as int,
          open: w['open'] as String,
          close: w['close'] as String,
        ),
    ];
    final exceptions = <HoursException>[
      for (final e in (map['exceptions'] as List?) ?? const [])
        if ((e as Map)['closed'] == true)
          HoursException.closed(e['date'] as String)
        else
          HoursException.window(
            date: e['date'] as String,
            open: e['open'] as String,
            close: e['close'] as String,
          ),
    ];
    return OpeningHours(
      weekly: List.unmodifiable(weekly),
      exceptions: List.unmodifiable(exceptions),
    );
  }

  /// Decodes the value STORED on the profile row. A value in the exact
  /// grammar decodes as [OpeningHours.fromJson]. A value the database check
  /// (`app.storefront_opening_hours_is_valid`) accepts only through its NULL
  /// propagation — some entry lacks a `dow` / `open` / `close` / `date` key —
  /// shows its COMPLETE entries, is flagged [hasUnreadableEntries] and keeps
  /// the exact stored JSON in [storedRaw] (instead of the whole profile read
  /// failing for good, and without ever silently turning it into empty or
  /// default hours); only an explicit repair followed by a save replaces it.
  /// Anything the check itself refuses raises a [StorefrontDecodeException].
  factory OpeningHours.fromStored(
    Object? json, {
    String path = 'opening_hours',
  }) {
    if (isValidJson(json)) return OpeningHours.fromJson(json, path: path);
    if (!_storedShapeOk(json)) {
      throw StorefrontDecodeException(path, 'outside the validator grammar');
    }
    final map = json! as Map;
    final weekly = <WeeklyWindow>[];
    final exceptions = <HoursException>[];
    for (final w in (map['weekly'] as List?) ?? const []) {
      final e = w as Map;
      if (e.containsKey('dow') &&
          e.containsKey('open') &&
          e.containsKey('close')) {
        weekly.add(
          WeeklyWindow(
            dow: e['dow'] as int,
            open: e['open'] as String,
            close: e['close'] as String,
          ),
        );
      }
    }
    for (final x in (map['exceptions'] as List?) ?? const []) {
      final e = x as Map;
      final date = e['date'];
      if (date is! String) continue;
      if (e['closed'] == true) {
        exceptions.add(HoursException.closed(date));
      } else if (e.containsKey('open') && e.containsKey('close')) {
        exceptions.add(
          HoursException.window(
            date: date,
            open: e['open'] as String,
            close: e['close'] as String,
          ),
        );
      }
    }
    // Outside the exact grammar but accepted by the database check: some
    // entry lacks a key (it is left out of what is shown). The authoritative
    // JSON is kept verbatim — never replaced by the readable subset — until
    // an explicit repair.
    return OpeningHours._unreadable(
      weekly: List.unmodifiable(weekly),
      exceptions: List.unmodifiable(exceptions),
      storedRaw: jsonDecode(jsonEncode(map)) as Object,
    );
  }

  /// The database check as written, INCLUDING its NULL propagation: a key
  /// that is present must be well-formed, but a missing `dow` / `open` /
  /// `close` / `date` key passes (an IF over NULL does not return false).
  static bool _storedShapeOk(Object? json) {
    if (json is! Map) return false;
    for (final k in json.keys) {
      if (k != 'weekly' && k != 'exceptions') return false;
    }
    bool timeOk(Map<dynamic, dynamic> e, String key) =>
        !e.containsKey(key) || (e[key] is String && _hhmm.hasMatch(e[key]));
    bool distinct(Map<dynamic, dynamic> e) =>
        !(e.containsKey('open') && e.containsKey('close')) ||
        e['open'] != e['close'];
    if (json.containsKey('weekly')) {
      final weekly = json['weekly'];
      if (weekly is! List || weekly.length > maxWeekly) return false;
      for (final w in weekly) {
        if (w is! Map) return false;
        for (final k in w.keys) {
          if (k != 'dow' && k != 'open' && k != 'close') return false;
        }
        if (w.containsKey('dow')) {
          final dow = w['dow'];
          if (dow is! int || dow < 0 || dow > 6) return false;
        }
        if (!timeOk(w, 'open') || !timeOk(w, 'close') || !distinct(w)) {
          return false;
        }
      }
    }
    if (json.containsKey('exceptions')) {
      final exceptions = json['exceptions'];
      if (exceptions is! List || exceptions.length > maxExceptions) {
        return false;
      }
      for (final e in exceptions) {
        if (e is! Map) return false;
        for (final k in e.keys) {
          if (k != 'date' && k != 'closed' && k != 'open' && k != 'close') {
            return false;
          }
        }
        if (e.containsKey('date')) {
          final date = e['date'];
          if (date is! String || !_ymd.hasMatch(date)) return false;
        }
        if (e['closed'] == true) {
          if (e.containsKey('open') || e.containsKey('close')) return false;
        } else {
          if (e.containsKey('closed')) return false; // closed:false etc.
          if (!timeOk(e, 'open') || !timeOk(e, 'close') || !distinct(e)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  /// The wire form: always both keys, windows as `{dow, open, close}`,
  /// exceptions as `{date, closed: true}` or `{date, open, close}`. A stored
  /// value flagged [hasUnreadableEntries] answers its [storedRaw] instead —
  /// the authoritative value, never the lossy readable subset.
  Map<String, Object?> toJson() {
    final raw = storedRaw;
    if (hasUnreadableEntries && raw is Map) {
      return <String, Object?>{
        for (final e in (jsonDecode(jsonEncode(raw)) as Map).entries)
          e.key as String: e.value,
      };
    }
    return {
      'weekly': [for (final w in weekly) w.toJson()],
      'exceptions': [for (final e in exceptions) e.toJson()],
    };
  }

  /// The ADVISORY overlap findings of the weekly windows (see
  /// [OpeningHoursOverlapKind]): same-weekday duplicates and overlaps, and
  /// overnight windows running into the next weekday's windows. Windows the
  /// validator refuses are skipped ([validate] reports them). Exceptions are
  /// one window per date and are not compared. Empty = nothing to warn about.
  List<OpeningHoursOverlap> overlaps() {
    final out = <OpeningHoursOverlap>[];
    for (var dow = 0; dow < 7; dow++) {
      final day = windowsFor(dow);
      final next = (dow + 1) % 7;
      final nextDay = windowsFor(next);
      for (var i = 0; i < day.length; i++) {
        final a = _spanOf(day[i].open, day[i].close);
        if (a == null) continue;
        for (var j = i + 1; j < day.length; j++) {
          final b = _spanOf(day[j].open, day[j].close);
          if (b == null) continue;
          final kind =
              day[i].open == day[j].open && day[i].close == day[j].close
              ? OpeningHoursOverlapKind.duplicate
              : (a.$1 < b.$2 && b.$1 < a.$2)
              ? OpeningHoursOverlapKind.sameDay
              : null;
          if (kind != null) {
            out.add(
              OpeningHoursOverlap(
                kind,
                dow: dow,
                index: i,
                otherDow: dow,
                otherIndex: j,
              ),
            );
          }
        }
        // The part of an overnight window that falls on the next weekday.
        final spillEnd = a.$2 - 1440;
        if (spillEnd <= 0) continue;
        for (var k = 0; k < nextDay.length; k++) {
          final b = _spanOf(nextDay[k].open, nextDay[k].close);
          if (b != null && b.$1 < spillEnd) {
            out.add(
              OpeningHoursOverlap(
                OpeningHoursOverlapKind.overnightSpill,
                dow: dow,
                index: i,
                otherDow: next,
                otherIndex: k,
              ),
            );
          }
        }
      }
    }
    return out;
  }

  /// The window "Add hours" seeds for weekday [dow] — never an exact
  /// duplicate of a window that day already has:
  /// * an empty day: 09:00–17:00;
  /// * else, an hour after the day's latest close, up to four hours long,
  ///   ending by 23:59 (at least an hour must fit);
  /// * else, ending an hour before the day's earliest open, up to four hours
  ///   long, starting at 00:00 at the earliest (at least an hour must fit);
  /// * else, the first of 09:00–17:00, 12:00–15:00, 18:00–22:00, 00:00–01:00
  ///   the day does not have yet (a day holds at most three windows).
  WeeklyWindow suggestWindow(int dow) {
    final day = windowsFor(dow);
    WeeklyWindow window(int open, int close) =>
        WeeklyWindow(dow: dow, open: _hhmmOf(open), close: _hhmmOf(close));
    bool taken(WeeklyWindow w) =>
        day.any((d) => d.open == w.open && d.close == w.close);
    const gap = 60;
    const minLength = 60;
    const maxLength = 240;
    const lastMinute = 23 * 60 + 59;
    if (day.isEmpty) return window(9 * 60, 17 * 60);
    int? latestEnd;
    int? earliestStart;
    for (final w in day) {
      final s = _spanOf(w.open, w.close);
      if (s == null) continue;
      if (latestEnd == null || s.$2 > latestEnd) latestEnd = s.$2;
      if (earliestStart == null || s.$1 < earliestStart) earliestStart = s.$1;
    }
    if (latestEnd != null) {
      final start = latestEnd + gap;
      if (start + minLength <= lastMinute) {
        final w = window(start, math.min(start + maxLength, lastMinute));
        if (!taken(w)) return w;
      }
    }
    if (earliestStart != null) {
      final end = earliestStart - gap;
      if (end - minLength >= 0) {
        final w = window(math.max(0, end - maxLength), end);
        if (!taken(w)) return w;
      }
    }
    for (final (open, close) in const [
      (9 * 60, 17 * 60),
      (12 * 60, 15 * 60),
      (18 * 60, 22 * 60),
      (0, 60),
    ]) {
      final w = window(open, close);
      if (!taken(w)) return w;
    }
    // Unreachable while a day holds at most three windows.
    return window(0, 60);
  }

  /// Client-side mirror of the validator (the server stays authoritative and
  /// may still answer `opening_hours_invalid`). Empty = valid.
  List<OpeningHoursIssue> validate() {
    final issues = <OpeningHoursIssue>[];
    if (weekly.length > maxWeekly) {
      issues.add(const OpeningHoursIssue(OpeningHoursIssueKind.tooManyWeekly));
    }
    for (var i = 0; i < weekly.length; i++) {
      final w = weekly[i];
      if (w.dow < 0 || w.dow > 6) {
        issues.add(
          OpeningHoursIssue(OpeningHoursIssueKind.dowOutOfRange, index: i),
        );
      }
      _windowIssues(w.open, w.close, issues, index: i, inExceptions: false);
    }
    if (exceptions.length > maxExceptions) {
      issues.add(
        const OpeningHoursIssue(
          OpeningHoursIssueKind.tooManyExceptions,
          inExceptions: true,
        ),
      );
    }
    for (var i = 0; i < exceptions.length; i++) {
      final e = exceptions[i];
      if (!_ymd.hasMatch(e.date)) {
        issues.add(
          OpeningHoursIssue(
            OpeningHoursIssueKind.invalidDate,
            inExceptions: true,
            index: i,
          ),
        );
      }
      if (!e.closed) {
        _windowIssues(
          e.open ?? '',
          e.close ?? '',
          issues,
          index: i,
          inExceptions: true,
        );
      }
    }
    return issues;
  }

  static void _windowIssues(
    String open,
    String close,
    List<OpeningHoursIssue> issues, {
    required int index,
    required bool inExceptions,
  }) {
    if (!_hhmm.hasMatch(open) || !_hhmm.hasMatch(close)) {
      issues.add(
        OpeningHoursIssue(
          OpeningHoursIssueKind.invalidTime,
          inExceptions: inExceptions,
          index: index,
        ),
      );
    } else if (open == close) {
      issues.add(
        OpeningHoursIssue(
          OpeningHoursIssueKind.openEqualsClose,
          inExceptions: inExceptions,
          index: index,
        ),
      );
    }
  }

  bool get isValid => validate().isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! OpeningHours) return false;
    if (other.hasUnreadableEntries != hasUnreadableEntries) return false;
    if (jsonEncode(other.storedRaw) != jsonEncode(storedRaw)) return false;
    if (other.weekly.length != weekly.length ||
        other.exceptions.length != exceptions.length) {
      return false;
    }
    for (var i = 0; i < weekly.length; i++) {
      if (other.weekly[i] != weekly[i]) return false;
    }
    for (var i = 0; i < exceptions.length; i++) {
      if (other.exceptions[i] != exceptions[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(weekly),
    Object.hashAll(exceptions),
    hasUnreadableEntries,
    jsonEncode(storedRaw),
  );

  @override
  String toString() => 'OpeningHours(${jsonEncode(toJson())})';
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

/// One restaurant's storefront profile as the manager read serves it
/// (`profile` of `get_restaurant_storefront_profile`: the row minus
/// organization_id / deleted_at). `ordering_enabled` / `delivery_enabled` are
/// pinned false by CHECK in this slice and are deliberately NOT modelled — no
/// Dashboard control may exist for them.
class StorefrontProfile {
  const StorefrontProfile({
    required this.restaurantId,
    required this.storefrontBranchId,
    required this.slug,
    required this.displayName,
    this.tagline,
    this.publicCity,
    this.publicAddress,
    this.publicPhone,
    required this.primaryColor,
    required this.accentColor,
    required this.visualPreset,
    required this.localeDefault,
    required this.cardMode,
    required this.motion,
    required this.pickupEnabled,
    this.pausedUntil,
    this.pauseReason,
    required this.openingHours,
    this.logoMediaId,
    this.heroMediaId,
    required this.isPublished,
    required this.version,
  });

  /// The writer's patch allowlist (`c_allowed` of the migration). `slug` is
  /// accepted only while creating (expected version 0).
  static const List<String> patchableKeys = [
    'slug',
    'storefront_branch_id',
    'display_name',
    'tagline',
    'public_city',
    'public_address',
    'public_phone',
    'primary_color',
    'accent_color',
    'visual_preset',
    'locale_default',
    'card_mode',
    'motion',
    'pickup_enabled',
    'paused_until',
    'pause_reason',
    'opening_hours',
    'logo_media_id',
    'hero_media_id',
    'is_published',
  ];

  final String restaurantId;
  final String storefrontBranchId;
  final String slug;
  final String displayName;
  final String? tagline;
  final String? publicCity;
  final String? publicAddress;
  final String? publicPhone;

  /// `#rrggbb` (the writer lower-cases it).
  final String primaryColor;
  final String accentColor;
  final StorefrontVisualPreset visualPreset;
  final StorefrontLocale localeDefault;
  final StorefrontCardMode cardMode;
  final StorefrontMotion motion;
  final bool pickupEnabled;

  /// The pause instant (UTC), or null when not paused.
  final DateTime? pausedUntil;

  /// Staff-only: the public page never shows it.
  final String? pauseReason;
  final OpeningHours openingHours;
  final String? logoMediaId;
  final String? heroMediaId;
  final bool isPublished;
  final int version;

  /// The profile pointer of [slot].
  String? mediaIdFor(StorefrontSlot slot) => switch (slot) {
    StorefrontSlot.logo => logoMediaId,
    StorefrontSlot.hero => heroMediaId,
  };

  factory StorefrontProfile.fromJson(Object? json, {String path = 'profile'}) {
    final j = _Json.of(json, path);
    return StorefrontProfile(
      restaurantId: j.string('restaurant_id'),
      storefrontBranchId: j.string('storefront_branch_id'),
      slug: j.string('slug'),
      displayName: j.string('display_name'),
      tagline: j.optString('tagline'),
      publicCity: j.optString('public_city'),
      publicAddress: j.optString('public_address'),
      publicPhone: j.optString('public_phone'),
      primaryColor: j.string('primary_color'),
      accentColor: j.string('accent_color'),
      visualPreset: j.enumValue('visual_preset', StorefrontVisualPreset.values),
      localeDefault: j.enumValue('locale_default', StorefrontLocale.values),
      cardMode: j.enumValue('card_mode', StorefrontCardMode.values),
      motion: j.enumValue('motion', StorefrontMotion.values),
      pickupEnabled: j.boolean('pickup_enabled'),
      pausedUntil: j.optInstant('paused_until'),
      pauseReason: j.optString('pause_reason'),
      openingHours: OpeningHours.fromStored(
        j['opening_hours'],
        path: j.at('opening_hours'),
      ),
      logoMediaId: j.optString('logo_media_id'),
      heroMediaId: j.optString('hero_media_id'),
      isPublished: j.boolean('is_published'),
      version: j.integer('version', min: 1),
    );
  }

  /// Every patchable field in its WIRE form (the value the writer accepts),
  /// keyed by [patchableKeys]. The editor diffs a draft against this to send
  /// ONLY changed keys. `paused_until` uses [formatStorefrontInstant] (UTC).
  Map<String, Object?> toWireFields() => {
    'slug': slug,
    'storefront_branch_id': storefrontBranchId,
    'display_name': displayName,
    'tagline': tagline,
    'public_city': publicCity,
    'public_address': publicAddress,
    'public_phone': publicPhone,
    'primary_color': primaryColor,
    'accent_color': accentColor,
    'visual_preset': visualPreset.name,
    'locale_default': localeDefault.name,
    'card_mode': cardMode.name,
    'motion': motion.name,
    'pickup_enabled': pickupEnabled,
    'paused_until': pausedUntil == null
        ? null
        : formatStorefrontInstant(pausedUntil!),
    'pause_reason': pauseReason,
    'opening_hours': openingHours.toJson(),
    'logo_media_id': logoMediaId,
    'hero_media_id': heroMediaId,
    'is_published': isPublished,
  };
}

/// The branch tax facts the publish preconditions look at.
class StorefrontTax {
  const StorefrontTax({
    required this.enabled,
    required this.rateBp,
    required this.mode,
  });

  final bool enabled;

  /// Basis points (100 bp = 1.00%) — an integer, never a float (D-007).
  final int rateBp;

  /// `exclusive` | `inclusive`.
  final String mode;
}

/// The derived facts of the manager read (`derived`): the timezone the hours
/// are interpreted in, the currency / tax the preconditions check, the CURRENT
/// publish blockers (computed on the SAVED profile) and the opaque media
/// prefix.
class StorefrontDerived {
  const StorefrontDerived({
    this.timezone,
    this.currencyCode,
    this.tax,
    required this.publishReady,
    required this.publishBlockers,
    required this.mediaPrefix,
  });

  /// The storefront branch's IANA timezone (branch, else restaurant); null
  /// when no branch is chosen yet or none is set.
  final String? timezone;
  final String? currencyCode;
  final StorefrontTax? tax;
  final bool publishReady;

  /// Ordered blocker codes (see [kStorefrontPublishBlockers]); unknown future
  /// codes are kept verbatim so the UI can show a fallback label.
  final List<String> publishBlockers;
  final String mediaPrefix;

  factory StorefrontDerived.fromJson(Object? json, {String path = 'derived'}) {
    final j = _Json.of(json, path);
    final taxRaw = j['tax'];
    StorefrontTax? tax;
    if (taxRaw != null) {
      final t = _Json.of(taxRaw, j.at('tax'));
      tax = StorefrontTax(
        enabled: t.boolean('enabled'),
        rateBp: t.integer('rate_bp', min: 0),
        mode: t.string('mode'),
      );
    }
    final blockers = j.stringList('publish_blockers');
    final ready = j.boolean('publish_ready');
    if (ready != blockers.isEmpty) {
      throw StorefrontDecodeException(
        j.at('publish_ready'),
        'disagrees with publish_blockers',
      );
    }
    return StorefrontDerived(
      timezone: j.optString('timezone'),
      currencyCode: j.optString('currency_code'),
      tax: tax,
      publishReady: ready,
      publishBlockers: blockers,
      mediaPrefix: j.string('media_prefix'),
    );
  }
}

// ---------------------------------------------------------------------------
// Media rows
// ---------------------------------------------------------------------------

/// One row of `list_storefront_media` (CONTRACT §1.5), newest first.
class StorefrontMediaRow {
  const StorefrontMediaRow({
    required this.id,
    required this.sourceBucket,
    required this.sourceKey,
    required this.variant,
    required this.objectKey,
    required this.contentHash,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.state,
    this.publishedAt,
    this.unpublishedAt,
    required this.createdAt,
    this.inUse = const <StorefrontSlot>[],
  });

  final String id;
  final StorefrontSourceBucket sourceBucket;

  /// The PRIVATE original's key (never public; shown to staff only).
  final String sourceKey;
  final StorefrontVariant variant;

  /// The PUBLIC derivative's key in `storefront-media`.
  final String objectKey;
  final String contentHash;
  final int width;
  final int height;

  /// The derivative's size in bytes (`bytes` on the wire).
  final int byteLength;
  final StorefrontMediaState state;
  final DateTime? publishedAt;
  final DateTime? unpublishedAt;
  final DateTime createdAt;

  /// The profile slots currently pointing at this row.
  final List<StorefrontSlot> inUse;

  bool get isLive => state == StorefrontMediaState.published;
  bool get isStaged => state == StorefrontMediaState.staged;
  bool get isRetracted => state == StorefrontMediaState.retracted;

  factory StorefrontMediaRow.fromJson(Object? json, {String path = 'media'}) {
    final j = _Json.of(json, path);
    final bucket = StorefrontSourceBucket.fromWire(j['source_bucket']);
    if (bucket == null) {
      throw StorefrontDecodeException(j.at('source_bucket'), 'unknown value');
    }
    final inUseRaw = j['in_use'] ?? const <Object?>[];
    if (inUseRaw is! List) {
      throw StorefrontDecodeException(j.at('in_use'), 'expected a list');
    }
    final inUse = <StorefrontSlot>[];
    for (var i = 0; i < inUseRaw.length; i++) {
      final slot = StorefrontSlot.fromWire(inUseRaw[i]);
      if (slot == null) {
        throw StorefrontDecodeException(
          '${j.at('in_use')}[$i]',
          'unknown slot',
        );
      }
      inUse.add(slot);
    }
    return StorefrontMediaRow(
      id: j.string('id'),
      sourceBucket: bucket,
      sourceKey: j.string('source_key'),
      variant: j.enumValue('variant', StorefrontVariant.values),
      objectKey: j.string('object_key'),
      contentHash: j.string('content_hash'),
      width: j.integer('width', min: 1),
      height: j.integer('height', min: 1),
      byteLength: j.integer('bytes', min: 1),
      state: j.enumValue('state', StorefrontMediaState.values),
      publishedAt: j.optInstant('published_at'),
      unpublishedAt: j.optInstant('unpublished_at'),
      createdAt: j.instant('created_at'),
      inUse: List.unmodifiable(inUse),
    );
  }
}

/// Library-internal decoding entry points shared by the repositories (kept
/// here so the defensive reader has a single implementation).
List<StorefrontMediaRow> decodeStorefrontMediaRows(Object? raw, String path) {
  if (raw is! List) throw StorefrontDecodeException(path, 'expected a list');
  return List.unmodifiable([
    for (var i = 0; i < raw.length; i++)
      StorefrontMediaRow.fromJson(raw[i], path: '$path[$i]'),
  ]);
}

/// Reads a required non-empty string field of a server envelope, raising a
/// [StorefrontDecodeException] otherwise.
String decodeStorefrontString(Object? envelope, String key, String path) =>
    _Json.of(envelope, path).string(key);

/// Reads a required integer field (>= [min]) of a server envelope.
int decodeStorefrontInt(
  Object? envelope,
  String key,
  String path, {
  int? min,
}) => _Json.of(envelope, path).integer(key, min: min);
