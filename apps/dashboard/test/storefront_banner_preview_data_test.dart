import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_banner_preview_data.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_color_picker.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_profile_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

const _profile = StorefrontProfile(
  restaurantId: '22222222-2222-4222-8222-222222222222',
  storefrontBranchId: '33333333-3333-4333-8333-333333333333',
  slug: 'test-store',
  displayName: 'Saved identity',
  tagline: 'Saved tagline',
  publicCity: 'Saved city',
  primaryColor: '#292929',
  accentColor: '#ff8000',
  visualPreset: StorefrontVisualPreset.light,
  localeDefault: StorefrontLocale.he,
  cardMode: StorefrontCardMode.list,
  motion: StorefrontMotion.calm,
  pickupEnabled: true,
  openingHours: OpeningHours.empty,
  isPublished: true,
  version: 7,
);
Map<String, dynamic> _document() =>
    jsonDecode(
          jsonEncode({
            'hero_headline': 'Draft headline',
            'hero_subline': 'Draft subline',
            'announcement_text': 'Draft announcement',
            'announcement_segments': ['one', 'two'],
            'hero': {
              'mode': 'item',
              'item_id': 'item-a',
              'eyebrow': 'Draft eyebrow',
              'footnote': 'Draft footnote',
            },
            'appearance': {
              'text_color': null,
              'button_text_color': null,
              'menu_banner_enabled': true,
              'menu_intro_visible': true,
              'font_family': 'rubik',
            },
          }),
        )
        as Map<String, dynamic>;
Map<String, dynamic> _menu({String state = 'open', bool ordering = true}) =>
    jsonDecode(
          jsonEncode({
            'ok': true,
            'entity': 'storefront_menu',
            'restaurant': {
              'slug': _profile.slug,
              'display_name': 'Public name is not the saved profile',
              'currency_code': 'ILS',
            },
            'service': {
              'state': state,
              'pickup_enabled': true,
              'delivery_enabled': false,
              'ordering_enabled': ordering,
            },
            'hours': {'opens': '09:00', 'closes': '22:00', 'next_open': null},
            'categories': [
              {'id': 'category-a', 'name': 'Actual category'},
            ],
            'items': [
              {
                'id': 'item-a',
                'category_id': 'category-a',
                'name': 'Actual item',
                'image_url': '/storage/v1/object/public/menu-images/source.jpg',
                'base_price_minor': 4200,
                'availability': 'available',
              },
            ],
          }),
        )
        as Map<String, dynamic>;
Map<String, Object?> _build({
  StorefrontProfile profile = _profile,
  Map<String, dynamic>? document,
  Map<String, dynamic>? menu,
  String locale = 'en',
  StorefrontColorSample sample = const StorefrontColorSample(
    background: '#292929',
    accent: '#ff8000',
  ),
}) => storefrontBannerPreviewData(
  profile: profile,
  document: document ?? _document(),
  publishedMenu: menu,
  logoUrl: Uri.parse(
    'https://media.example/storage/v1/object/public/storefront-media/logo.webp',
  ),
  colorSample: sample,
  locale: locale,
);

class _Transport implements SyncRpcTransport {
  _Transport(this.reply);
  final Object? reply;
  final calls = <({String function, Map<String, dynamic> params})>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function: function, params: params));
    if (reply is Exception) throw reply!;
    return reply;
  }
}

SupabaseStorefrontProfileRepository _repository(_Transport t) =>
    SupabaseStorefrontProfileRepository(
      transport: t,
      organizationId: '11111111-1111-4111-8111-111111111111',
      restaurantId: _profile.restaurantId,
    );

void main() {
  test(
    'reader invokes existing public v9 exactly once, with only the requested slug',
    () async {
      final menu = _menu(), transport = _Transport(menu);
      final repository = _repository(transport);
      expect(repository, isA<StorefrontBannerPreviewReader>());
      expect(await repository.readPublishedBannerPreview(_profile.slug), menu);
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.function, 'storefront_menu_v9');
      expect(transport.calls.single.params, {'p_slug': _profile.slug});
    },
  );
  test(
    'reader refuses unavailable, wrong-scope, wrong-entity and non-Boolean service replies without retry',
    () async {
      final cases = <Object?>[
        null,
        [],
        {'ok': false},
        {..._menu(), 'entity': 'another'},
        {
          ..._menu(),
          'restaurant': {'slug': 'other-store'},
        },
      ];
      for (final field in [
        'pickup_enabled',
        'delivery_enabled',
        'ordering_enabled',
      ]) {
        for (final invalid in [null, 'false', 0]) {
          final menu = _menu();
          (menu['service'] as Map<String, dynamic>)[field] = invalid;
          cases.add(menu);
        }
        final missing = _menu();
        (missing['service'] as Map<String, dynamic>).remove(field);
        cases.add(missing);
      }
      final state = _menu();
      (state['service'] as Map<String, dynamic>)['state'] = 'unknown';
      cases.add(state);
      cases.add(
        const SyncTransportException(
          SyncTransportErrorKind.transient,
          message: 'isolated timeout',
        ),
      );
      for (final value in cases) {
        final t = _Transport(value);
        expect(
          await _repository(t).readPublishedBannerPreview(_profile.slug),
          isNull,
        );
        expect(t.calls, hasLength(1));
      }
      final t = _Transport(_menu());
      expect(
        await _repository(t).readPublishedBannerPreview(' invalid '),
        isNull,
      );
      expect(t.calls, isEmpty);
    },
  );
  test(
    'builder combines saved identity with draft copy and actual served items without mutation',
    () {
      final document = _document(), menu = _menu();
      final before = jsonEncode([document, menu, _profile.toWireFields()]);
      final result = _build(document: document, menu: menu);
      expect(result['displayName'], 'Saved identity');
      expect(result['city'], 'Saved city');
      expect(result['announcement'], 'Draft announcement');
      expect(result['segments'], ['one', 'two']);
      expect(result['categoryNames'], ['Actual category']);
      expect(result['notices'], isEmpty);
      final hero = result['hero'] as Map;
      expect(hero['title'], 'Draft headline');
      expect(hero['name'], 'Actual item');
      expect(hero['price'], '₪42');
      expect(hero['photo'], '/storage/v1/object/public/menu-images/source.jpg');
      expect(result['service'], {
        'state': 'open',
        'pickupEnabled': true,
        'deliveryEnabled': false,
        'orderingEnabled': true,
      });
      expect(jsonEncode([document, menu, _profile.toWireFields()]), before);
    },
  );
  test(
    'unavailable public state is never inferred as open, pickup enabled or a served hero',
    () {
      final result = _build();
      expect(result['publicStateAvailable'], isFalse);
      expect(result['service'], isNull);
      for (final key in [
        'state',
        'pickupEnabled',
        'deliveryEnabled',
        'orderingEnabled',
        'announcement',
        'hero',
      ])
        expect(result[key], isNull);
      expect(result['categoryNames'], isEmpty);
      expect(result['segments'], isEmpty);
      expect(result['notices'], isEmpty);
    },
  );
  test(
    'closed/paused/ordering-off notices and announcement visibility follow current Home rules',
    () {
      for (final state in ['closed', 'paused']) {
        final result = _build(menu: _menu(state: state));
        expect(result['announcement'], isNull);
        expect(result['segments'], isEmpty);
        final notices = result['notices'] as List;
        expect(notices, hasLength(1));
        expect(
          (notices.single as Map<String, dynamic>)['body'],
          isNot(contains('{')),
        );
      }
      final result = _build(menu: _menu(ordering: false));
      expect(result['notices'] as List, hasLength(1));
      expect(result['announcement'], 'Draft announcement');
      final noHours = _menu(state: 'closed');
      noHours['hours'] = {
        'opens': null,
        'closes': null,
        'next_open': '2026-11-13T10:00:00Z',
      };
      expect(
        ((_build(menu: noHours)['notices'] as List).single
            as Map<String, dynamic>)['body'],
        isNot(contains('10:00')),
      );
    },
  );
  test(
    'hero eligibility is independent of intro visibility and never guessed from editorial/missing items',
    () {
      final doc = _document();
      (doc['appearance'] as Map<String, dynamic>)['menu_intro_visible'] = false;
      final hidden = _build(document: doc, menu: _menu());
      expect(hidden['showIntro'], isFalse);
      expect(hidden['hero'], isNotNull);
      (doc['hero'] as Map<String, dynamic>)['mode'] = 'editorial';
      expect(_build(document: doc, menu: _menu())['hero'], isNull);
      (doc['hero'] as Map<String, dynamic>)['mode'] = 'item';
      (doc['hero'] as Map<String, dynamic>)['item_id'] = 'not-served';
      expect(_build(document: doc, menu: _menu())['hero'], isNull);
      final menu = _menu();
      (menu['items'] as List).first['image_url'] =
          '/storage/v1/object/authenticated/menu-images/private.jpg';
      expect(
        (_build(menu: menu)['hero'] as Map<String, dynamic>)['photo'],
        isNull,
      );
    },
  );
  test(
    'supported hero preserves scalar format/stamp/image fitting and retained modifier semantics',
    () {
      final doc = _document(), menu = _menu();
      final format = <String, dynamic>{
        'text': 'Classic Burger',
        'highlight': {'start': 8, 'end': 14},
        'break_before': 8,
      };
      doc['hero_headline'] = format['text'];
      (doc['hero'] as Map<String, dynamic>).addAll({
        'format': format,
        'stamp': 'Real draft stamp',
      });
      doc['category_presentation'] = [
        {'category_id': 'category-a', 'image_fit': 'whole-image'},
      ];
      menu['modifiers'] = [
        {
          'id': 'group-a',
          'item_id': 'item-a',
          'selection_type': 'multiple',
          'is_required': false,
          'min_select': 0,
        },
      ];
      menu['modifier_options'] = <Object?>[];
      Map hero() => _build(document: doc, menu: menu)['hero'] as Map;
      final before = jsonEncode([doc, menu]);
      expect(hero()['format'], format);
      expect(hero()['stamp'], 'Real draft stamp');
      expect(hero()['imageFit'], 'whole-image');
      expect(hero()['hasOptions'], isFalse);
      expect(jsonEncode([doc, menu]), before);
      doc['item_presentation'] = [
        {'item_id': 'item-a', 'image_fit': 'fill'},
      ];
      expect(hero()['imageFit'], 'fill');
      (menu['modifiers'] as List).first['is_required'] = true;
      expect(hero()['hasOptions'], isTrue);
      (menu['modifiers'] as List).first['is_required'] = false;
      (menu['modifiers'] as List).first['selection_type'] = 'single';
      expect(hero()['hasOptions'], isTrue);
      (menu['modifiers'] as List).first['selection_type'] = 'multiple';
      menu['modifier_options'] = [
        {'modifier_id': 'group-a'},
      ];
      expect(hero()['hasOptions'], isTrue);
      doc['hero_headline'] = 'Changed headline';
      expect(hero()['format'], isNull);
      (menu['items'] as List).first['availability'] = 'unavailable';
      expect(hero()['soldOut'], isTrue);
      (doc['appearance'] as Map<String, dynamic>)['scene_preset'] =
          'reference_dark';
      expect(
        _build(document: doc, menu: menu)['scenePreset'],
        'reference_dark',
      );
      menu['items'] = <Object?>[];
      final empty = _build(document: doc, menu: menu);
      expect(empty['empty'], isTrue);
      expect(empty['hero'], isNull);
      expect(_build()['empty'], isFalse);
    },
  );
  test(
    'font selection is a closed enum and saved theme/colors survive render-only fallback',
    () {
      final doc = _document();
      (doc['appearance'] as Map<String, dynamic>).addAll({
        'site_theme': 'light',
        'font_family': 'url(bad)',
        'text_color': '#ffffff',
        'button_text_color': '#ffffff',
      });
      final before = jsonEncode(doc);
      final result = _build(document: doc, menu: _menu());
      expect(result['fontFamily'], 'rubik');
      expect((result['colours'] as Map<String, dynamic>)['--bg'], '#ffffff');
      expect((result['colours'] as Map<String, dynamic>)['--tx'], '#202124');
      expect(jsonEncode(doc), before);
      final legacy = _build(
        sample: const StorefrontColorSample(
          background: '#ffffff',
          accent: '#ff6bad',
        ),
      );
      expect(legacy['siteTheme'], isNull);
      expect((legacy['colours'] as Map<String, dynamic>)['--bg'], '#ffffff');
    },
  );
  test('locale copy is the exact existing storefront subset', () {
    for (final locale in ['ar', 'he', 'en']) {
      final paths = [
        '../../storefront/messages/storefront.$locale.json',
        'storefront/messages/storefront.$locale.json',
      ];
      final file = paths.map(File.new).firstWhere((f) => f.existsSync());
      final source = jsonDecode(file.readAsStringSync()) as Map;
      final result = _build(menu: _menu(), locale: locale),
          copy = result['copy'] as Map;
      expect(result['menuHeading'], source['menuHeading']);
      expect(result['menuCaption'], source['menuCaption']);
      expect(result['searchText'], source['searchPh']);
      for (final key in [
        'openNow',
        'closed',
        'paused',
        'pickup',
        'pickupOff',
        'delivery',
        'deliveryOff',
        'menuLabel',
        'chefPicks',
        'findUs',
        'callRestaurant',
      ])
        expect(copy[key], source[key]);
      expect((result['hero'] as Map)['fromLabel'], source['from']);
      expect(copy['cartLabel'], source['cart']);
      expect(copy['language'], source['langLabel']);
      expect(copy['suggestLabel'], source['suggestItem']);
    }
  });
  test(
    'phone presence follows public contact grammar without exposing the number',
    () {
      for (final value in [
        '0549355685',
        '+972549355685',
        'not-a-phone',
        'tel:0549355685',
        '0549355685;ext=1',
        '0549355685\n',
      ]) {
        final profile = StorefrontProfile.fromJson({
          ..._profile.toWireFields(),
          'restaurant_id': _profile.restaurantId,
          'version': _profile.version,
          'public_phone': value,
        });
        final result = _build(profile: profile);
        expect(
          result['phoneAvailable'],
          value == '0549355685' || value == '+972549355685',
        );
        expect(result.values, isNot(contains(value)));
      }
    },
  );
  test(
    'every preview colour matches unchanged real theme derivation vectors',
    () {
      final paths = [
        'test/fixtures/storefront_banner_theme_vectors.json',
        'apps/dashboard/test/fixtures/storefront_banner_theme_vectors.json',
      ];
      final vectors =
          jsonDecode(
                paths
                    .map(File.new)
                    .firstWhere((f) => f.existsSync())
                    .readAsStringSync(),
              )
              as List;
      for (final vector in vectors.cast<Map>()) {
        final doc = _document();
        (doc['appearance'] as Map<String, dynamic>).addAll({
          'site_theme': vector['theme'],
          'scene_preset': vector['scene'],
          'text_color': vector['text'],
          'button_text_color': vector['buttonText'],
        });
        final sample = StorefrontColorSample(
          background: vector['primary'],
          accent: vector['accent'],
        );
        final actual = _build(document: doc, sample: sample)['colours'] as Map;
        for (final entry in actual.entries)
          expect(
            entry.value,
            (vector['expected'] as Map<String, dynamic>)[entry.key],
            reason: '${vector['label']} ${entry.key}',
          );
      }
    },
  );
}
