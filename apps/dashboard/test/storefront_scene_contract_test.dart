import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';

void main() {
  test(
    'scene is opt-in and null restores legacy without changing other colors',
    () {
      final legacy = StorefrontContentDocument.defaults();
      expect(StorefrontContentDocument.fromJson(legacy).json, legacy);
      for (final scene in [null, 'reference_dark']) {
        final value = {
          ...legacy,
          'appearance': {
            'text_color': '#ABCDEF',
            'button_text_color': null,
            'scene_preset': scene,
            'menu_background_dim': 0,
          },
        };
        final appearance =
            StorefrontContentDocument.fromJson(value).json['appearance'] as Map;
        expect(appearance['scene_preset'], scene);
        expect(appearance['text_color'], '#abcdef');
        expect(appearance['menu_background_dim'], 0);
      }
      final absent =
          StorefrontContentDocument.fromJson({
                ...legacy,
                'appearance': {'text_color': null, 'button_text_color': null},
              }).json['appearance']
              as Map;
      expect(absent.containsKey('scene_preset'), isFalse);
    },
  );

  test(
    'scene field accepts only its closed contract and uses versioned readiness',
    () {
      for (final scene in [
        '',
        'dark',
        'reference-dark',
        'reference_dark ',
        1,
        false,
        {},
        [],
      ]) {
        expect(
          () => StorefrontContentDocument.fromJson({
            ...StorefrontContentDocument.defaults(),
            'appearance': {
              'text_color': null,
              'button_text_color': null,
              'scene_preset': scene,
            },
          }),
          throwsA(isA<StorefrontDecodeException>()),
        );
      }
      expect(
        SupabaseStorefrontContentRepository.readFunction,
        'get_restaurant_storefront_content_v4',
      );
      expect(
        SupabaseStorefrontContentRepository.writeFunction,
        'set_restaurant_storefront_content_v1',
      );
      expect(contentFieldPath('appearance.scene_preset'), isTrue);
    },
  );
}
