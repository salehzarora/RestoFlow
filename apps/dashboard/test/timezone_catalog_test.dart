import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/admin/timezone_catalog.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TIMEZONE-GLOBAL-001 — the display/search layer for the global IANA catalog:
/// localized curated labels, derived city/region for the long tail, offset
/// formatting, and search by country / city / IANA id (incl. RTL Arabic).
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));
Future<AppLocalizations> _ar() =>
    AppLocalizations.delegate.load(const Locale('ar'));

void main() {
  test(
    'T1 Asia/Jerusalem is labeled Israel — Jerusalem (Jerusalem/Asia)',
    () async {
      final l10n = await _en();
      expect(timezoneLabel(l10n, 'Asia/Jerusalem'), 'Israel — Jerusalem');
      expect(timezoneCity('Asia/Jerusalem'), 'Jerusalem');
      expect(timezoneRegion('Asia/Jerusalem'), 'Asia');
      expect(kPilotDefaultTimezone, 'Asia/Jerusalem');
    },
  );

  test('T2 Asia/Gaza and Asia/Hebron keep distinct Palestine labels', () async {
    final l10n = await _en();
    expect(timezoneLabel(l10n, 'Asia/Gaza'), 'Palestine — Gaza');
    expect(timezoneLabel(l10n, 'Asia/Hebron'), 'Palestine — Hebron');
    // They are NOT reinterpreted as Jerusalem.
    expect(
      timezoneLabel(l10n, 'Asia/Gaza') == timezoneLabel(l10n, 'Asia/Jerusalem'),
      isFalse,
    );
  });

  test('T3 representative world zones derive city/region correctly', () async {
    final l10n = await _en();
    expect(timezoneLabel(l10n, 'America/New_York'), 'United States — New York');
    expect(timezoneCity('America/New_York'), 'New York');
    expect(timezoneRegion('America/New_York'), 'America');
    expect(timezoneLabel(l10n, 'Asia/Tokyo'), 'Japan — Tokyo');
    expect(timezoneLabel(l10n, 'Australia/Sydney'), 'Australia — Sydney');
    expect(timezoneLabel(l10n, 'Africa/Cairo'), 'Egypt — Cairo');
  });

  test('T4 a non-curated zone falls back to its derived city', () async {
    final l10n = await _en();
    // Europe/Paris is not in the curated set -> derived city label.
    expect(timezoneLabel(l10n, 'Europe/Paris'), 'Paris');
    // A 3-segment id uses the LAST segment as the city.
    expect(timezoneCity('America/Argentina/Buenos_Aires'), 'Buenos Aires');
    expect(timezoneRegion('America/Argentina/Buenos_Aires'), 'America');
  });

  test('T5 search matches by country, city, and IANA id', () async {
    final l10n = await _en();
    const jer = TimezoneOption(id: 'Asia/Jerusalem', offsetMinutes: 180);
    const tok = TimezoneOption(id: 'Asia/Tokyo', offsetMinutes: 540);
    const lon = TimezoneOption(id: 'Europe/London', offsetMinutes: 60);
    // by country (curated label)
    expect(timezoneMatches(l10n, jer, 'israel'), isTrue);
    // by city
    expect(timezoneMatches(l10n, tok, 'tokyo'), isTrue);
    // by IANA id fragment
    expect(timezoneMatches(l10n, lon, 'europe/lon'), isTrue);
    // negative
    expect(timezoneMatches(l10n, jer, 'tokyo'), isFalse);
    // empty query matches all
    expect(timezoneMatches(l10n, jer, ''), isTrue);
  });

  test('T6 search works in Arabic (RTL) by the localized country', () async {
    final ar = await _ar();
    const jer = TimezoneOption(id: 'Asia/Jerusalem', offsetMinutes: 180);
    expect(timezoneLabel(ar, 'Asia/Jerusalem'), 'إسرائيل — القدس');
    expect(timezoneMatches(ar, jer, 'القدس'), isTrue); // Jerusalem in Arabic
    // IANA id search still works regardless of locale.
    expect(timezoneMatches(ar, jer, 'asia/jer'), isTrue);
  });

  test('T7 offset formatting is UTC±HH:MM (no fixed-offset storage)', () {
    expect(formatTimezoneOffset(180), 'UTC+03:00');
    expect(formatTimezoneOffset(120), 'UTC+02:00');
    expect(formatTimezoneOffset(-300), 'UTC-05:00');
    expect(formatTimezoneOffset(0), 'UTC±00:00');
    expect(formatTimezoneOffset(330), 'UTC+05:30'); // India, half-hour
  });

  test('T8 the curated highlight set covers the pilot + all continents', () {
    // Pilot market + a representative from Europe/America/Asia/Africa/Australia.
    for (final id in [
      'Asia/Jerusalem',
      'Asia/Gaza',
      'Asia/Hebron',
      'Europe/London',
      'America/New_York',
      'Asia/Tokyo',
      'Africa/Cairo',
      'Australia/Sydney',
    ]) {
      expect(kCuratedTimezoneIds.contains(id), isTrue, reason: '$id curated');
    }
  });
}
