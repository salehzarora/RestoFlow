import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_unicode.dart'
    as unicode;
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

const org = '11111111-1111-4111-8111-111111111111';
const restaurant = '22222222-2222-4222-8222-222222222222';
const branch = '33333333-3333-4333-8333-333333333333';
const item = '44444444-4444-4444-8444-444444444444';
const category = '55555555-5555-4555-8555-555555555555';
const media = '66666666-6666-4666-8666-666666666666';
Map<String, dynamic> document() =>
    jsonDecode(
          jsonEncode(
            StorefrontContentDocument.defaults(headline: 'طَعْم رائع'),
          ),
        )
        as Map<String, dynamic>;
Map<String, dynamic> readEnvelope({
  int version = 3,
  Map<String, dynamic>? doc,
}) => {
  'ok': true,
  'entity': storefrontContentEntity,
  'restaurant_id': restaurant,
  'version': version,
  'storefront_branch_id': branch,
  'document': doc ?? document(),
  'warnings': [],
};
Map<String, dynamic> success({bool replay = false}) => {
  'ok': true,
  'entity': storefrontContentEntity,
  'restaurant_id': restaurant,
  'version': 4,
  'slug': 'synthetic',
  'is_published': true,
  'idempotent_replay': replay,
};

class ScriptTransport implements SyncRpcTransport {
  ScriptTransport(this.responses);
  final List<Object?> responses;
  final calls = <({String function, Map<String, dynamic> params})>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function: function, params: params));
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response;
  }
}

const lost = SyncTransportException(
  SyncTransportErrorKind.transient,
  message: 'synthetic timeout',
);
SupabaseStorefrontContentRepository repository(ScriptTransport t) =>
    SupabaseStorefrontContentRepository(
      transport: t,
      organizationId: org,
      restaurantId: restaurant,
      nonce: () => 123,
    );
StorefrontContentAttempt attempt(SupabaseStorefrontContentRepository r) =>
    r.prepareContent(
      expectedVersion: 3,
      expectedBranchId: branch,
      document: StorefrontContentDocument.fromJson(document()),
    );

void main() {
  test(
    'versioned editorial usage preserves legacy slot enums and refuses unknown usage',
    () {
      Map<String, dynamic> row() => {
        'id': media,
        'source_bucket': 'menu-images',
        'source_key': 'synthetic/image.png',
        'variant': 'w960',
        'object_key': 'synthetic/w960.webp',
        'content_hash': 'a' * 64,
        'width': 960,
        'height': 640,
        'bytes': 123,
        'state': 'published',
        'published_at': '2026-10-22T00:00:00Z',
        'unpublished_at': null,
        'created_at': '2026-10-22T00:00:00Z',
        'in_use': ['hero'],
        'content_in_use': [
          {'kind': 'promo'},
          {'kind': 'story'},
          {'kind': 'category', 'category_id': category},
        ],
      };
      final decoded = StorefrontContentMediaRow.fromJson(row());
      expect(decoded.media.inUse, [StorefrontSlot.hero]);
      expect(decoded.contentInUse.length, 3);
      for (final invalid in <List<Object?>>[
        [
          {'kind': 'hero'},
        ],
        [
          {'kind': 'category', 'category_id': restaurant, 'extra': true},
        ],
        [
          {'kind': 'category', 'category_id': 'bad'},
        ],
      ]) {
        final raw = row()..['content_in_use'] = invalid;
        expect(
          () => StorefrontContentMediaRow.fromJson(raw),
          throwsA(isA<StorefrontDecodeException>()),
        );
      }
    },
  );
  test(
    'versioned media read validates restaurant version and fixed envelope',
    () async {
      for (final raw in <Map<String, dynamic>>[
        {
          'ok': true,
          'entity': 'storefront_content_media',
          'restaurant_id': restaurant,
          'version': 3,
          'media_prefix': 'synthetic',
          'media': [],
        },
        {
          'ok': true,
          'entity': 'storefront_content_media',
          'restaurant_id': org,
          'version': 3,
          'media_prefix': 'synthetic',
          'media': [],
        },
        {
          'ok': true,
          'entity': 'storefront_content_media',
          'restaurant_id': restaurant,
          'version': 0,
          'media_prefix': 'synthetic',
          'media': [],
        },
      ]) {
        final t = ScriptTransport([raw]);
        final result = await repository(t).listContentMedia();
        expect(
          result != null,
          raw['restaurant_id'] == restaurant && raw['version'] == 3,
        );
        expect(
          t.calls.single.function,
          SupabaseStorefrontContentRepository.mediaFunction,
        );
      }
    },
  );
  test(
    'database refusal after a lost first request remains uncertain',
    () async {
      final t = ScriptTransport([
        lost,
        const SyncTransportException(
          SyncTransportErrorKind.server,
          code: '42501',
          message: 'synthetic denied',
        ),
        readEnvelope(),
      ]);
      final r = repository(t);
      final a = attempt(r);
      final result = await r.saveContent(a);
      expect(result.status, StorefrontContentWriteStatus.uncertain);
      expect(identical(result.attempt, a), true);
      expect(t.calls.length, 3);
    },
  );
  test('complete nine-field defaults and immutable nested request body', () {
    final raw = document();
    final parsed = StorefrontContentDocument.fromJson(raw);
    expect(parsed.json.keys.toSet(), storefrontContentKeys);
    (raw['hero'] as Map)['eyebrow'] = 'changed later';
    expect((parsed.json['hero'] as Map)['eyebrow'], null);
    expect(
      () => (parsed.json['hero'] as Map)['eyebrow'] = 'mutate',
      throwsUnsupportedError,
    );
  });
  test('all controls decode together without catalogue or price mutation', () {
    final doc = document();
    doc['hero'] = {
      'mode': 'item',
      'item_id': item,
      'format': {
        'text': 'طَعْم رائع',
        'highlight': {'start': 0, 'end': 5},
        'break_before': 6,
      },
      'eyebrow': 'أهلاً',
      'stamp': 'בית',
      'footnote': 'Original',
    };
    doc['announcement_segments'] = ['واحد', 'שתיים'];
    doc['promo'] = {
      'target': {'kind': 'category', 'category_id': category},
      'kicker': 'K',
      'title': 'T',
      'body': 'B',
      'editorial_media_id': media,
    };
    doc['story'] = {
      'kicker': 'K',
      'title': 'T',
      'body': 'B',
      'editorial_media_id': media,
      'facts': ['حقيقة'],
    };
    doc['category_presentation'] = [
      {
        'category_id': category,
        'heading': 'H',
        'blurb': null,
        'editorial_media_id': media,
        'image_fit': 'whole-image',
        'card_layout': 'cutout',
      },
    ];
    doc['item_presentation'] = [
      {'item_id': item, 'image_fit': 'fill', 'card_layout': 'standard'},
    ];
    expect(
      StorefrontContentDocument.fromJson(doc).json['hero_headline'],
      'طَعْم رائع',
    );
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing key': (j) => j.remove('story'),
    'unknown key': (j) => j['private'] = 'never allowed',
    'null hero': (j) => j['hero'] = null,
    'unknown mode': (j) => (j['hero'] as Map)['mode'] = 'guess',
    'item mode no id': (j) => (j['hero'] as Map)['mode'] = 'item',
    'uppercase uuid': (j) =>
        (j['hero'] as Map)['item_id'] = 'ABCDEFAB-1111-4111-8111-111111111111',
    'malformed surrogate': (j) =>
        j['hero_headline'] = String.fromCharCode(0xd800),
    'legacy control': (j) => j['hero_headline'] = 'bad\ntext',
    'new C1 control': (j) => (j['hero'] as Map)['eyebrow'] = 'bad\u0085text',
    'unconfirmed trim': (j) => j['hero_headline'] = ' padded ',
    'blank required promo': (j) => j['promo'] = {
      'target': {'kind': 'item', 'item_id': item},
      'kicker': '',
      'title': 'T',
      'body': 'B',
    },
    'wrong union editorial key': (j) => j['promo'] = {
      'target': {'kind': 'item', 'item_id': item},
      'kicker': 'K',
      'title': 'T',
      'body': 'B',
      'editorial_media_id': media,
    },
    'wrong target': (j) => j['promo'] = {
      'target': {'kind': 'arbitrary', 'item_id': item},
      'kicker': 'K',
      'title': 'T',
      'body': 'B',
    },
    'empty segments wire': (j) => j['announcement_segments'] = [],
    'null segment': (j) => j['announcement_segments'] = [null],
    'segments over count': (j) =>
        j['announcement_segments'] = List.filled(7, 'x'),
    'segment over codepoints': (j) => j['announcement_segments'] = ['x' * 41],
    'stale headline binding': (j) => (j['hero'] as Map)['format'] = {
      'text': 'different',
      'highlight': {'start': 0, 'end': 5},
      'break_before': null,
    },
    'split Arabic token': (j) => (j['hero'] as Map)['format'] = {
      'text': j['hero_headline'],
      'highlight': {'start': 0, 'end': 1},
      'break_before': null,
    },
    'empty format': (j) => (j['hero'] as Map)['format'] = {
      'text': j['hero_headline'],
      'highlight': null,
      'break_before': null,
    },
    'fractional offset': (j) => (j['hero'] as Map)['format'] = {
      'text': j['hero_headline'],
      'highlight': {'start': 0.0, 'end': 5},
      'break_before': null,
    },
    'presentation unknown enum': (j) => j['item_presentation'] = [
      {'item_id': item, 'image_fit': 'contain', 'card_layout': null},
    ],
    'presentation price': (j) => j['item_presentation'] = [
      {'item_id': item, 'image_fit': null, 'card_layout': null, 'price': 5},
    ],
    'duplicate product': (j) => j['item_presentation'] = List.generate(
      2,
      (_) => {'item_id': item, 'image_fit': null, 'card_layout': null},
    ),
    'over categories': (j) => j['category_presentation'] = List.filled(101, {}),
    'over items': (j) => j['item_presentation'] = List.filled(501, {}),
  };
  for (final mutation in mutations.entries) {
    test('document refuses ${mutation.key}', () {
      final doc = document();
      mutation.value(doc);
      expect(
        () => StorefrontContentDocument.fromJson(doc),
        throwsA(isA<StorefrontDecodeException>()),
      );
    });
  }
  test('legacy separator stays compatible but cannot have formatting', () {
    final doc = document()..['hero_headline'] = 'A\u0085B';
    expect(
      StorefrontContentDocument.fromJson(doc).json['hero_headline'],
      'A\u0085B',
    );
    (doc['hero'] as Map)['format'] = {
      'text': 'A\u0085B',
      'highlight': {'start': 0, 'end': 1},
      'break_before': null,
    };
    expect(
      () => StorefrontContentDocument.fromJson(doc),
      throwsA(isA<StorefrontDecodeException>()),
    );
  });
  test('read strict restaurant binding and closed warnings', () {
    expect(
      StorefrontContentSnapshot.fromJson(readEnvelope(), restaurant).version,
      3,
    );
    for (final change in <void Function(Map<String, dynamic>)>[
      (j) => j['restaurant_id'] = org,
      (j) => j['extra'] = 'x',
      (j) => j['version'] = 0,
      (j) => j['warnings'] = [
        {'field': 'hero.item_id', 'reason': 'unknown'},
      ],
      (j) => j['warnings'] = [
        {'field': 'raw.foreign.id', 'reason': 'relation_unavailable'},
      ],
    ]) {
      final j = readEnvelope();
      change(j);
      expect(
        () => StorefrontContentSnapshot.fromJson(j, restaurant),
        throwsA(isA<StorefrontDecodeException>()),
      );
    }
  });
  test(
    'production profile composition exposes same scoped authenticated content path',
    () async {
      final t = ScriptTransport([readEnvelope()]);
      final profile = SupabaseStorefrontProfileRepository(
        transport: t,
        organizationId: org,
        restaurantId: restaurant,
      );
      final read = await profile.contentRepository.readContent();
      expect(read.isOk, true);
      expect(
        t.calls.single.function,
        SupabaseStorefrontContentRepository.readFunction,
      );
      expect(t.calls.single.params, {
        'p_organization_id': org,
        'p_restaurant_id': restaurant,
      });
    },
  );
  test(
    'one save includes exact branch/global CAS and no other writer',
    () async {
      final t = ScriptTransport([success()]);
      final r = repository(t);
      final a = attempt(r);
      expect((await r.saveContent(a)).status, StorefrontContentWriteStatus.ok);
      expect(t.calls.length, 1);
      expect(
        t.calls.single.function,
        SupabaseStorefrontContentRepository.writeFunction,
      );
      expect(t.calls.single.params.keys.toSet(), {
        'p_organization_id',
        'p_restaurant_id',
        'p_client_request_id',
        'p_expected_version',
        'p_expected_storefront_branch_id',
        'p_document',
      });
      expect(t.calls.single.params['p_expected_version'], 3);
      expect(t.calls.single.params['p_expected_storefront_branch_id'], branch);
    },
  );
  test('bounded lost-response retry retains exact tuple and replay', () async {
    final t = ScriptTransport([lost, success(replay: true)]);
    final r = repository(t);
    final a = attempt(r);
    final result = await r.saveContent(a);
    expect(result.replay, true);
    expect(t.calls.length, 2);
    expect(identical(t.calls[0].params, t.calls[1].params), true);
    expect(identical(t.calls[0].params['p_document'], a.document.json), true);
  });
  test(
    'two losses and matching readback remain uncertain, no fabricated success',
    () async {
      final t = ScriptTransport([lost, lost, readEnvelope(version: 4)]);
      final r = repository(t);
      final a = attempt(r);
      final result = await r.saveContent(a);
      expect(result.status, StorefrontContentWriteStatus.uncertain);
      expect(identical(result.attempt, a), true);
      expect(result.readback?.isOk, true);
      expect(t.calls.length, 3);
      expect(
        t.calls
            .where(
              (call) =>
                  call.function ==
                  SupabaseStorefrontContentRepository.writeFunction,
            )
            .length,
        2,
      );
    },
  );
  for (final error in [
    'permission_denied',
    'not_found',
    'branch_conflict',
    'version_conflict',
    'invalid',
  ]) {
    test('typed $error is definitive and never auto retried', () async {
      final response = <String, dynamic>{
        'ok': false,
        'entity': storefrontContentEntity,
        'error': error,
        if (error == 'branch_conflict' || error == 'version_conflict')
          'version': 9,
        if (error == 'version_conflict') ...{
          'restaurant_id': restaurant,
          'slug': 'synthetic',
          'is_published': true,
        },
        if (error == 'invalid') ...{
          'reason': 'target_invalid',
          'field': 'hero.item_id',
        },
      };
      final t = ScriptTransport([response]);
      final r = repository(t);
      final result = await r.saveContent(attempt(r));
      expect(
        result.status,
        {
          'permission_denied': StorefrontContentWriteStatus.denied,
          'not_found': StorefrontContentWriteStatus.notFound,
          'branch_conflict': StorefrontContentWriteStatus.branchConflict,
          'version_conflict': StorefrontContentWriteStatus.conflict,
          'invalid': StorefrontContentWriteStatus.invalid,
        }[error],
      );
      expect(t.calls.length, 1);
    });
  }
  test(
    'unknown server field or reason cannot escape into client copy',
    () async {
      final t = ScriptTransport([
        {
          'ok': false,
          'entity': storefrontContentEntity,
          'error': 'invalid',
          'reason': 'secret detail',
          'field': 'untrusted value',
        },
        readEnvelope(),
      ]);
      final r = repository(t);
      final result = await r.saveContent(attempt(r));
      expect(result.status, StorefrontContentWriteStatus.uncertain);
      expect(result.reason, null);
      expect(result.field, null);
    },
  );
  test('local invalid authorization tuple transmits nothing', () async {
    final t = ScriptTransport([]);
    final r = repository(t);
    final result = await r.saveContent(
      StorefrontContentAttempt(
        requestId: 'bad',
        expectedVersion: 3,
        expectedBranchId: branch,
        document: StorefrontContentDocument.fromJson(document()),
      ),
    );
    expect(result.status, StorefrontContentWriteStatus.invalid);
    expect(t.calls, isEmpty);
  });
  test('Unicode15.1 corpus matches all1187 official grapheme vectors', () {
    final path =
        Platform.environment['BIZBOT_CONTENT_UNICODE_VECTORS'] ??
        '../../tools/storefront_content_unicode/vectors.json';
    final corpus = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(corpus['unicode'], '15.1.0');
    expect(corpus['uax29'], 43);
    expect((corpus['vectors'] as List).length, 1187);
    for (final raw in corpus['vectors'] as List) {
      final row = raw as Map;
      final text = String.fromCharCodes(
        (row['codepoints'] as List).cast<int>(),
      );
      expect(
        unicode.graphemeBoundaries(text),
        (row['boundaries'] as List).cast<int>(),
      );
    }
  });
  test(
    'Arabic Hebrew emoji exact UTF16 mapping, no normalization or snapping',
    () {
      expect(unicode.utf16SelectionToCodepoints('🍔 טָעִים', 3, 9), [2, 8]);
      expect(unicode.utf16SelectionToCodepoints('🍔 טָעִים', 1, 9), null);
      expect(unicode.utf16SelectionToCodepoints('👩‍🍳 برجر', 5, 0), [0, 3]);
      expect(unicode.heroFormatValid('طَعْم رائع', 0, 5, 6), true);
      expect(unicode.heroFormatValid('שָׁלוֹם טעים', 0, 7, 8), true);
      expect(unicode.heroFormatValid('A\u00a0 B', 3, 4, 3), true);
      expect(unicode.heroFormatValid('A \u0301B', 2, 4, null), false);
      expect(unicode.normalizeContentText('Cafe\u0301', 120), 'Cafe\u0301');
      expect(unicode.scalarValues(String.fromCharCode(0xd800)), null);
    },
  );
}
