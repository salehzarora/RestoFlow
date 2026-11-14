import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';

void main() {
  const id = '33333333-3333-4333-8333-333333333333';
  const fields = [
    'menu_banner_media_id',
    'menu_banner_enabled',
    'menu_intro_visible',
    'menu_banner_focal_x',
    'menu_banner_focal_y',
  ];
  test(
    'responsive optional fields keep absence, null, bounds and independent values strict',
    () {
      final base = StorefrontContentDocument.defaults()
        ..['appearance'] = {'text_color': null, 'button_text_color': null};
      final original = StorefrontContentDocument.fromJson(base);
      const responsive = {
        'menu_banner_layout': 'responsive',
        'menu_banner_desktop_media_id': id,
        'menu_banner_mobile_height_px': 520,
        'menu_banner_desktop_height_px': 400,
        'menu_banner_desktop_focal_x': 0,
        'menu_banner_desktop_focal_y': 100,
      };
      for (final key in responsive.keys) {
        expect((original.json['appearance'] as Map).containsKey(key), isFalse);
        expect(contentFieldPath('appearance.$key'), isTrue);
        expect(
          (StorefrontContentDocument.fromJson({
                ...base,
                'appearance': {...(base['appearance'] as Map), key: null},
              }).json['appearance']
              as Map)[key],
          isNull,
        );
      }
      final after = StorefrontContentDocument.fromJson({
        ...base,
        'appearance': {...(base['appearance'] as Map), ...responsive},
      });
      expect(after.editableCopy()['appearance'], {
        ...(base['appearance'] as Map),
        ...responsive,
      });
      for (final entry in {
        'menu_banner_layout': ['auto', false, 1],
        'menu_banner_desktop_media_id': [
          '',
          'https://private.invalid/x',
          false,
        ],
        'menu_banner_mobile_height_px': [319, 641, 520.5, '520', false],
        'menu_banner_desktop_height_px': [239, 561, 400.5, '400', false],
        'menu_banner_desktop_focal_x': [-1, 101, .5, '50', false],
        'menu_banner_desktop_focal_y': [-1, 101, .5, '50', false],
        'menu_banner_arbitrary': [true],
      }.entries) {
        for (final value in entry.value) {
          expect(
            () => StorefrontContentDocument.fromJson({
              ...base,
              'appearance': {...(base['appearance'] as Map), entry.key: value},
            }),
            throwsA(isA<StorefrontDecodeException>()),
            reason: '${entry.key}: $value',
          );
        }
      }
      for (final height in [320, 640]) {
        expect(
          (StorefrontContentDocument.fromJson({
                ...base,
                'appearance': {
                  ...(base['appearance'] as Map),
                  'menu_banner_mobile_height_px': height,
                },
              }).json['appearance']
              as Map)['menu_banner_mobile_height_px'],
          height,
        );
      }
      for (final height in [240, 560]) {
        expect(
          (StorefrontContentDocument.fromJson({
                ...base,
                'appearance': {
                  ...(base['appearance'] as Map),
                  'menu_banner_desktop_height_px': height,
                },
              }).json['appearance']
              as Map)['menu_banner_desktop_height_px'],
          height,
        );
      }
      expect(original.json['appearance'], base['appearance']);
    },
  );
  test(
    'banner absence stays absent; values, null and source data survive decoding',
    () {
      final legacy = StorefrontContentDocument.defaults()
        ..['appearance'] = {
          'text_color': null,
          'button_text_color': null,
          'site_theme': 'dark',
        };
      final before = StorefrontContentDocument.fromJson(legacy);
      expect(
        (before.json['appearance'] as Map).keys,
        isNot(contains('menu_banner_media_id')),
      );
      final data = {
        ...legacy,
        'appearance': {
          ...(legacy['appearance'] as Map),
          'menu_banner_media_id': id,
          'menu_banner_enabled': true,
          'menu_intro_visible': false,
          'menu_banner_focal_x': 0,
          'menu_banner_focal_y': 100,
        },
      };
      final parsed = StorefrontContentDocument.fromJson(data);
      expect(parsed.json['appearance'], data['appearance']);
      for (final field in fields) {
        expect(contentFieldPath('appearance.$field'), isTrue);
        expect(
          StorefrontContentDocument.fromJson({
            ...legacy,
            'appearance': {...(legacy['appearance'] as Map), field: null},
          }).json['appearance'],
          {...(legacy['appearance'] as Map), field: null},
        );
      }
      expect(
        () => (parsed.json['appearance'] as Map)['menu_banner_enabled'] = false,
        throwsUnsupportedError,
      );
      expect((data['appearance'] as Map)['menu_banner_enabled'], isTrue);
    },
  );
  test(
    'banner booleans/ids/focal fields retain strict types, bounds and unknown-key rejection',
    () {
      for (final entry in {
        'menu_banner_media_id': [
          false,
          '',
          'https://private.example/original.jpg',
          'ABCDEFAB-3333-4333-8333-333333333333',
        ],
        'menu_banner_enabled': ['false', 0, 1, [], {}],
        'menu_intro_visible': ['true', 0, [], {}],
        'menu_banner_focal_x': [-1, 101, 1.5, '50', false],
        'menu_banner_focal_y': [-1, 101, 1.5, '50', false],
        'arbitrary_banner': [true],
      }.entries) {
        for (final value in entry.value) {
          expect(
            () => StorefrontContentDocument.fromJson({
              ...StorefrontContentDocument.defaults(),
              'appearance': {
                'text_color': null,
                'button_text_color': null,
                entry.key: value,
              },
            }),
            throwsA(isA<StorefrontDecodeException>()),
            reason: '${entry.key}=$value',
          );
        }
      }
      expect(
        SupabaseStorefrontContentRepository.readFunction,
        'get_restaurant_storefront_content_v6',
      );
      expect(
        SupabaseStorefrontContentRepository.writeFunction,
        'set_restaurant_storefront_content_v1',
      );
    },
  );
}
