import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';

/// STOREFRONT-PUBLISH-001 — the small grammars and wire helpers of the
/// storefront data layer (slug, request ids, the paused_until instant, the
/// patch allowlist, slot metadata), and the code registries checked against
/// the SQL / function SOURCES that emit those codes.

/// A repository file, located from either test cwd (the package or the
/// repository root) — a wrong path must fail, never pass vacuously.
File _repoFile(String rel) {
  for (final prefix in ['', '../../', '../']) {
    final f = File('$prefix$rel');
    if (f.existsSync()) return f;
  }
  fail('cannot find $rel (cwd: ${Directory.current.path})');
}

/// Every `.mjs` module of the publish function's `lib/` (whatever the engine
/// is split into), in a stable order.
String _functionLibSource() {
  const rel = 'supabase/functions/storefront-media-publish/lib';
  for (final prefix in ['', '../../', '../']) {
    final dir = Directory('$prefix$rel');
    if (!dir.existsSync()) continue;
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.mjs'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: rel);
    return [for (final f in files) f.readAsStringSync()].join('\n');
  }
  fail('cannot find $rel (cwd: ${Directory.current.path})');
}

Set<String> _codes(String pattern, String source) => {
  for (final m in RegExp(pattern).allMatches(source)) m.group(1)!,
};

void main() {
  group('slug grammar (client mirror of the writer)', () {
    test('accepts the storage grammar', () {
      for (final s in ['abc', 'maps-burger', 'a1-b2-c3', 'x' * 48, '123']) {
        expect(isValidStorefrontSlug(s), isTrue, reason: s);
      }
    });

    test('refuses shape, length and reserved words', () {
      for (final s in [
        'ab',
        'x' * 49,
        'Maps',
        'maps_burger',
        '-maps',
        'maps-',
        'maps--burger',
        'maps burger',
        'مطعم',
        '',
        ...kStorefrontReservedSlugs,
      ]) {
        expect(isValidStorefrontSlug(s), isFalse, reason: s);
      }
      expect(kStorefrontReservedSlugs, containsAll(['api', 'kiosk', 'www']));
    });
  });

  group('request ids', () {
    test('canonical lower-case v5-shaped UUID text', () {
      final id = storefrontRequestId('pbl:storefront:', ['a', 'b'], 1);
      expect(isCanonicalUuid(id), isTrue);
      expect(id[14], '5', reason: 'version nibble');
      expect('89ab'.contains(id[19]), isTrue, reason: 'RFC-4122 variant');
    });

    test('stable for the same input, different per prefix / part / nonce', () {
      final a = storefrontRequestId('pbl:storefront:', ['x'], 1);
      expect(storefrontRequestId('pbl:storefront:', ['x'], 1), a);
      expect(storefrontRequestId('pbl:storefront-media:', ['x'], 1), isNot(a));
      expect(storefrontRequestId('pbl:storefront:', ['y'], 1), isNot(a));
      expect(storefrontRequestId('pbl:storefront:', ['x'], 2), isNot(a));
    });

    test('isCanonicalUuid refuses upper case and malformed text', () {
      expect(isCanonicalUuid('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'), isTrue);
      expect(isCanonicalUuid('AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE'), isFalse);
      expect(isCanonicalUuid('aaaaaaaabbbb4ccc8dddeeeeeeeeeeee'), isFalse);
      expect(isCanonicalUuid(''), isFalse);
    });
  });

  group('paused_until wire form', () {
    test('RFC 3339 with an explicit offset', () {
      final instant = DateTime.utc(2026, 10, 1, 15, 0, 0, 123);
      expect(
        formatStorefrontInstant(instant, offset: const Duration(hours: 3)),
        '2026-10-01T18:00:00+03:00',
      );
      expect(formatStorefrontInstant(instant), '2026-10-01T15:00:00+00:00');
      expect(
        formatStorefrontInstant(
          instant,
          offset: const Duration(hours: -4, minutes: -30),
        ),
        '2026-10-01T10:30:00-04:30',
      );
      // Crossing a date boundary.
      expect(
        formatStorefrontInstant(
          DateTime.utc(2026, 12, 31, 22, 30),
          offset: const Duration(hours: 2),
        ),
        '2027-01-01T00:30:00+02:00',
      );
    });

    test('every formatted value passes the writer grammar and round-trips', () {
      final instant = DateTime.utc(2026, 3, 27, 23, 59, 59);
      for (final minutes in [0, 120, 180, -300, 330, -570]) {
        final text = formatStorefrontInstant(
          instant,
          offset: Duration(minutes: minutes),
        );
        expect(isStorefrontInstantText(text), isTrue, reason: text);
        expect(DateTime.parse(text).isAtSameMomentAs(instant), isTrue);
      }
    });

    test('the grammar refuses offset-less and relative values', () {
      for (final bad in [
        '2026-10-01T18:00:00',
        '2026-10-01 18:00:00+03:00',
        'tomorrow',
        'infinity',
        '2026-10-01T18:00:00+0300',
      ]) {
        expect(isStorefrontInstantText(bad), isFalse, reason: bad);
      }
      expect(isStorefrontInstantText('2026-10-01T18:00Z'), isTrue);
      expect(isStorefrontInstantText('2026-10-01T18:00:00.123456Z'), isTrue);
    });

    test('rejects offsets the wire cannot express', () {
      expect(
        () => formatStorefrontInstant(
          DateTime.utc(2026),
          offset: const Duration(seconds: 30),
        ),
        throwsArgumentError,
      );
      expect(
        () => formatStorefrontInstant(
          DateTime.utc(2026),
          offset: const Duration(hours: 24),
        ),
        throwsArgumentError,
      );
    });
  });

  group('profile wire fields', () {
    final profile = StorefrontProfile.fromJson({
      'restaurant_id': '22222222-2222-4222-8222-222222222222',
      'storefront_branch_id': '33333333-3333-4333-8333-333333333333',
      'slug': 'maps-burger',
      'display_name': 'Maps Burger',
      'tagline': 'Since 1999',
      'public_city': null,
      'public_address': null,
      'public_phone': null,
      'primary_color': '#13322a',
      'accent_color': '#e07b2c',
      'visual_preset': 'light',
      'locale_default': 'he',
      'card_mode': 'grid',
      'motion': 'lively',
      'pickup_enabled': false,
      'delivery_enabled': false,
      'ordering_enabled': false,
      'paused_until': '2026-10-01T15:00:00+00:00',
      'pause_reason': 'Staff training',
      'opening_hours': {'weekly': <Object>[], 'exceptions': <Object>[]},
      'logo_media_id': '44444444-4444-4444-8444-444444444444',
      'hero_media_id': null,
      'is_published': true,
      'version': 12,
    });

    test('covers exactly the writer allowlist (no ordering/delivery)', () {
      final fields = profile.toWireFields();
      expect(fields.keys.toSet(), StorefrontProfile.patchableKeys.toSet());
      expect(fields.containsKey('ordering_enabled'), isFalse);
      expect(fields.containsKey('delivery_enabled'), isFalse);
      expect(StorefrontProfile.patchableKeys, hasLength(20));
    });

    test('values are in their wire form', () {
      final f = profile.toWireFields();
      expect(f['visual_preset'], 'light');
      expect(f['locale_default'], 'he');
      expect(f['card_mode'], 'grid');
      expect(f['motion'], 'lively');
      expect(f['pickup_enabled'], false);
      expect(f['paused_until'], '2026-10-01T15:00:00+00:00');
      expect(isStorefrontInstantText(f['paused_until']! as String), isTrue);
      expect(f['opening_hours'], {
        'weekly': <Object>[],
        'exceptions': <Object>[],
      });
      expect(f['logo_media_id'], '44444444-4444-4444-8444-444444444444');
      expect(f['hero_media_id'], isNull);
      expect(profile.pausedUntil!.isUtc, isTrue);
      expect(profile.mediaIdFor(StorefrontSlot.logo), profile.logoMediaId);
      expect(profile.mediaIdFor(StorefrontSlot.hero), isNull);
    });
  });

  group('slots', () {
    test('logo = w480 from the receipt logo only; hero = w960 from either', () {
      expect(StorefrontSlot.logo.variant, StorefrontVariant.w480);
      expect(StorefrontSlot.logo.allowedBuckets, [
        StorefrontSourceBucket.restaurantLogos,
      ]);
      expect(StorefrontSlot.logo.profileKey, 'logo_media_id');
      expect(StorefrontSlot.hero.variant, StorefrontVariant.w960);
      expect(StorefrontSlot.hero.allowedBuckets, [
        StorefrontSourceBucket.restaurantLogos,
        StorefrontSourceBucket.menuImages,
      ]);
      expect(StorefrontSlot.hero.profileKey, 'hero_media_id');
      expect(StorefrontSlot.fromWire('hero'), StorefrontSlot.hero);
      expect(StorefrontSlot.fromWire('Hero'), isNull);
      expect(
        StorefrontSourceBucket.fromWire('menu-images'),
        StorefrontSourceBucket.menuImages,
      );
      expect(StorefrontSourceBucket.fromWire('storefront-media'), isNull);
    });
  });

  group('derived facts', () {
    test('decode + typed failures', () {
      final d = StorefrontDerived.fromJson({
        'timezone': null,
        'currency_code': 'USD',
        'tax': null,
        'publish_ready': false,
        'publish_blockers': [
          'timezone_missing',
          'currency_not_ils',
          'future_code',
        ],
        'media_prefix': '0123456789abcdef0123456789abcdef',
      });
      expect(d.timezone, isNull);
      expect(d.tax, isNull);
      expect(d.publishBlockers.last, 'future_code', reason: 'kept verbatim');
      expect(
        () => StorefrontDerived.fromJson({
          'publish_ready': true,
          'publish_blockers': <Object>[],
          'media_prefix': 'x',
          'tax': {'enabled': true, 'rate_bp': 1.5, 'mode': 'exclusive'},
        }),
        throwsA(
          isA<StorefrontDecodeException>().having(
            (e) => e.field,
            'field',
            'derived.tax.rate_bp',
          ),
        ),
      );
    });

    test('the registries match the codes the SQL and the publish function '
        'actually emit (read from their sources)', () {
      final readSql = _repoFile(
        'supabase/migrations/20260923120000_storefront_read_001.sql',
      ).readAsStringSync();
      final publishSql = _repoFile(
        'supabase/migrations/20260925100000_storefront_publish_001.sql',
      ).readAsStringSync();
      final fn = _functionLibSource();

      // The writer's typed `invalid` reasons: every literal one, plus the
      // two pointer keys it spells as `v_key || '_invalid'`.
      expect(readSql, contains("when 'logo_media_id', 'hero_media_id' then"));
      expect(readSql, contains("v_key || '_invalid'"));
      expect({
        ..._codes(r"'reason',\s*'([a-z_]+)'", readSql),
        'logo_media_id_invalid',
        'hero_media_id_invalid',
      }, kStorefrontInvalidReasons.toSet());
      expect(kStorefrontInvalidReasons.toSet(), hasLength(27));
      expect(kStorefrontInvalidReasons, hasLength(27), reason: 'no dupes');

      // The publish blockers, in the order the SQL appends them.
      final blockers = <String>[];
      for (final m in RegExp(
        r"array_append\(v_out,\s*'([a-z_]+)'\)",
      ).allMatches(readSql)) {
        if (!blockers.contains(m.group(1))) blockers.add(m.group(1)!);
      }
      expect(kStorefrontPublishBlockers, blockers);

      // Every 422 code the function can emit — thrown by the sniffer /
      // recipe, returned directly, or relayed from the stage step's
      // `invalid` reasons (with its fallback) — is known to the client,
      // either as a refusal of the source image or as a fault.
      final emitted = {
        ..._codes(r"new (?:SourceRejected|DerivationError)\('([a-z_]+)'", fn),
        ..._codes(r"fail\(422, 'refused', \{ code: '([a-z_]+)'", fn),
        ..._codes(r"staged\.reason : '([a-z_]+)'", fn),
        ..._codes(r"'reason',\s*'([a-z_]+)'", publishSql),
      }..remove('engine_unavailable'); // relayed as 503, never 422
      expect(emitted, isNotEmpty);
      expect(emitted, contains('variant_not_allowed'));
      final known = {
        ...kStorefrontRefusalCodes,
        ...kStorefrontPublishFaultCodes,
      };
      expect(emitted.difference(known), isEmpty);
      // ...and every source refusal listed is one the function emits.
      expect(kStorefrontRefusalCodes.toSet().difference(emitted), isEmpty);
      // CRIT-3: the stage's `content_mismatch` is answered as a 409
      // `object_conflict` — never a 422 — so the client lists no such
      // refusal (no unreachable mapping).
      expect(
        RegExp(
          r"case 'content_mismatch':\s*return fail\(409, 'object_conflict'\)",
        ).hasMatch(fn),
        isTrue,
      );
      expect(emitted, isNot(contains('content_mismatch')));
      expect(kStorefrontRefusalCodes, isNot(contains('content_mismatch')));
      expect(
        kStorefrontRefusalCodes.toSet().intersection(
          kStorefrontPublishFaultCodes.toSet(),
        ),
        isEmpty,
      );
    });

    test('a PUBLISHED storefront\'s public page, by blocker (mirrors the '
        'not_found gate of public.storefront_menu)', () {
      // Every known blocker is classified exactly once.
      expect({
        ...kStorefrontBlockersHidingPage,
        ...kStorefrontBlockersPageOnline,
      }, kStorefrontPublishBlockers.toSet());
      expect(
        kStorefrontBlockersHidingPage.intersection(
          kStorefrontBlockersPageOnline,
        ),
        isEmpty,
      );
      expect(
        storefrontPublishedPageOf(const []),
        StorefrontPublishedPage.online,
      );
      expect(
        storefrontPublishedPageOf(const ['no_live_item', 'hours_missing']),
        StorefrontPublishedPage.incomplete,
      );
      for (final code in kStorefrontBlockersHidingPage) {
        expect(
          storefrontPublishedPageOf([code, 'no_live_item']),
          StorefrontPublishedPage.offline,
          reason: code,
        );
      }
      expect(
        storefrontPublishedPageOf(const ['future_code']),
        StorefrontPublishedPage.unknown,
      );
      expect(
        storefrontPublishedPageOf(const ['future_code', 'currency_not_ils']),
        StorefrontPublishedPage.offline,
      );

      // The public read's not_found gate carries the conditions behind the
      // page-hiding blockers (a live branch, a zone, ILS, tax exclusive).
      final readSql = _repoFile(
        'supabase/migrations/20260923120000_storefront_read_001.sql',
      ).readAsStringSync();
      final gate = RegExp(
        r'if not v_p\.is_published([\s\S]*?)then\s+return c_not_found;',
      ).firstMatch(readSql);
      expect(gate, isNotNull);
      for (final condition in [
        'v_p.b_deleted is not null',
        'v_p.tz is null',
        "v_p.currency is distinct from 'ILS'",
        "v_p.tax_mode <> 'exclusive'",
      ]) {
        expect(gate!.group(1), contains(condition), reason: condition);
      }
    });
  });
}
