/// The global IANA timezone catalog for the Dashboard Settings picker
/// (TIMEZONE-GLOBAL-001).
///
/// The list of ids comes from the backend `list_timezones` RPC (which reads
/// PostgreSQL's `pg_timezone_names` — the SAME catalog the save path validates
/// against, so every offered id is acceptable). This file is only the display /
/// search layer: it derives a friendly "Region · City" label + a localized
/// "Country — City" label for a curated common set, and matches a search query
/// against the id, city, region, and (curated) country. No fixed offsets are
/// stored — the canonical value is always the IANA id.
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

/// One selectable IANA timezone: the canonical `id` plus its CURRENT UTC offset
/// (DST-aware as of load time, for the "(UTC±HH:MM)" hint only — never stored).
class TimezoneOption {
  const TimezoneOption({required this.id, required this.offsetMinutes});

  final String id;
  final int offsetMinutes;

  /// The city segment of the id, human-readable (last '/'-segment, '_'→' ').
  String get city => timezoneCity(id);

  /// The region (continent) segment of the id (first '/'-segment).
  String get region => timezoneRegion(id);
}

/// The city part of an IANA id: the last '/'-segment with underscores spaced.
/// e.g. `America/Argentina/Buenos_Aires` → `Buenos Aires`.
String timezoneCity(String id) {
  final seg = id.contains('/') ? id.substring(id.lastIndexOf('/') + 1) : id;
  return seg.replaceAll('_', ' ');
}

/// The region (continent) part of an IANA id: the first '/'-segment.
String timezoneRegion(String id) =>
    id.contains('/') ? id.substring(0, id.indexOf('/')) : id;

/// A friendly primary label for a zone: a localized "Country — City" for the
/// curated common set (the pilot market + representative world zones), else the
/// derived city. The IANA id is always shown as secondary text by the UI.
String timezoneLabel(AppLocalizations l10n, String id) =>
    _curatedLabel(l10n, id) ?? timezoneCity(id);

/// The curated localized "Country — City" label, or null for the long tail.
String? _curatedLabel(AppLocalizations l10n, String id) => switch (id) {
  'Asia/Jerusalem' => l10n.timezoneLabelAsiaJerusalem,
  'Asia/Gaza' => l10n.timezoneLabelAsiaGaza,
  'Asia/Hebron' => l10n.timezoneLabelAsiaHebron,
  'Europe/London' => l10n.timezoneLabelEuropeLondon,
  'Europe/Berlin' => l10n.timezoneLabelEuropeBerlin,
  'America/New_York' => l10n.timezoneLabelAmericaNewYork,
  'America/Los_Angeles' => l10n.timezoneLabelAmericaLosAngeles,
  'Asia/Tokyo' => l10n.timezoneLabelAsiaTokyo,
  'Australia/Sydney' => l10n.timezoneLabelAustraliaSydney,
  'Africa/Cairo' => l10n.timezoneLabelAfricaCairo,
  _ => null,
};

/// The IANA ids that get a fully-localized curated label (used to rank them
/// first / to highlight the pilot default).
const List<String> kCuratedTimezoneIds = [
  'Asia/Jerusalem',
  'Asia/Gaza',
  'Asia/Hebron',
  'Europe/London',
  'Europe/Berlin',
  'America/New_York',
  'America/Los_Angeles',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Africa/Cairo',
];

/// The pilot default highlighted in the picker.
const String kPilotDefaultTimezone = 'Asia/Jerusalem';

/// The current UTC offset formatted as `UTC+03:00` / `UTC-05:00` / `UTC±00:00`.
String formatTimezoneOffset(int offsetMinutes) {
  final sign = offsetMinutes < 0
      ? '-'
      : offsetMinutes > 0
      ? '+'
      : '±';
  final abs = offsetMinutes.abs();
  final h = (abs ~/ 60).toString().padLeft(2, '0');
  final m = (abs % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$m';
}

/// Whether [option] matches the search [query] (case-insensitive), by IANA id,
/// city, region, or the curated (localized) country — so a user can search
/// "israel", "jerusalem", "asia/jer", or "القدس".
bool timezoneMatches(
  AppLocalizations l10n,
  TimezoneOption option,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = <String>[
    option.id.toLowerCase(),
    option.city.toLowerCase(),
    option.region.toLowerCase(),
    (_curatedLabel(l10n, option.id) ?? '').toLowerCase(),
  ].join(' ');
  return haystack.contains(q);
}
