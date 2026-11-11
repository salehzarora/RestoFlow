import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_color_picker.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_contrast.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_site_theme_preview.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

class _ThemeTransport implements SyncRpcTransport {
  _ThemeTransport(this.responses);
  final List<Object?> responses;
  final calls = <({String function, Map<String, dynamic> params})>[];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function: function, params: params));
    return responses.removeAt(0);
  }
}

void main() {
  test(
    'Dashboard sample matches actual Storefront site-theme token vectors',
    () {
      final fixture = [
        File('test/fixtures/storefront_site_theme_vectors.json'),
        File('apps/dashboard/test/fixtures/storefront_site_theme_vectors.json'),
      ].firstWhere((file) => file.existsSync());
      final data = jsonDecode(fixture.readAsStringSync()) as Map;
      final vectors = data['vectors'] as List;
      expect(vectors, hasLength(32));
      for (final raw in vectors) {
        final row = raw as Map;
        final brand = row['brand'] as Map;
        final expected = row['expected'] as Map;
        final sample = StorefrontColorSample(
          background: brand['primary'] as String,
          accent: brand['accent'] as String,
          text: brand['text'] as String?,
          buttonText: brand['buttonText'] as String?,
        );
        final palette = StorefrontSiteThemePalette(
          siteTheme: row['siteTheme'] as String,
          scenePreset: row['scenePreset'] as String?,
          sample: sample,
        );
        final reason = '${row['siteTheme']} / ${row['scenePreset']} / $brand';
        for (final entry in {
          'background': palette.background,
          'text': palette.text,
          'accent': palette.accent,
          'buttonText': palette.buttonText,
          'selection': palette.selection,
        }.entries) {
          expect(
            storefrontFormatColor(entry.value),
            (expected[entry.key] as String).toLowerCase(),
            reason: '$reason / ${entry.key}',
          );
        }
        expect(sample.background, brand['primary']);
        expect(sample.accent, brand['accent']);
        expect(sample.text, brand['text']);
        expect(sample.buttonText, brand['buttonText']);
      }
    },
  );

  test(
    'site mode is negotiated through v4 and saves on unchanged branch CAS transport',
    () async {
      const org = '11111111-1111-4111-8111-111111111111';
      const restaurant = '22222222-2222-4222-8222-222222222222';
      const branch = '33333333-3333-4333-8333-333333333333';
      final saved = StorefrontContentDocument.defaults()
        ..['appearance'] = {
          'text_color': '#ffffff',
          'button_text_color': '#000000',
          'site_theme': 'light',
        };
      final transport = _ThemeTransport([
        {
          'ok': true,
          'entity': storefrontContentEntity,
          'restaurant_id': restaurant,
          'version': 3,
          'storefront_branch_id': branch,
          'document': saved,
          'warnings': [],
        },
        {
          'ok': true,
          'entity': storefrontContentEntity,
          'restaurant_id': restaurant,
          'version': 4,
          'slug': 'synthetic',
          'is_published': true,
          'idempotent_replay': false,
        },
      ]);
      final repo = SupabaseStorefrontContentRepository(
        transport: transport,
        organizationId: org,
        restaurantId: restaurant,
        nonce: () => 123,
      );
      final read = await repo.readContent();
      expect(read.isOk, isTrue);
      expect(
        transport.calls.single.function,
        'get_restaurant_storefront_content_v4',
      );
      final attempt = repo.prepareContent(
        expectedVersion: read.snapshot!.version,
        expectedBranchId: read.snapshot!.branchId,
        document: read.snapshot!.document,
      );
      final write = await repo.saveContent(attempt);
      expect(write.status, StorefrontContentWriteStatus.ok);
      expect(
        transport.calls.last.function,
        'set_restaurant_storefront_content_v1',
      );
      expect(transport.calls.last.params, {
        'p_organization_id': org,
        'p_restaurant_id': restaurant,
        'p_client_request_id': attempt.requestId,
        'p_expected_version': 3,
        'p_expected_storefront_branch_id': branch,
        'p_document': attempt.document.json,
      });
      expect(
        (attempt.document.json['appearance'] as Map)['site_theme'],
        'light',
      );
    },
  );

  test(
    'site theme is optional, closed and deeply retained without legacy reinterpretation',
    () {
      final legacy = StorefrontContentDocument.defaults();
      expect(StorefrontContentDocument.fromJson(legacy).json, legacy);
      final original = <String, Object?>{
        'text_color': '#ffffff',
        'button_text_color': '#000000',
        'font_family': 'alexandria',
        'menu_background_media_id': '66666666-6666-4666-8666-666666666666',
        'menu_background_dim': 0,
        'scene_preset': 'reference_dark',
      };
      expect(
        (StorefrontContentDocument.fromJson({
                  ...legacy,
                  'appearance': original,
                }).json['appearance']
                as Map)
            .containsKey('site_theme'),
        isFalse,
      );
      for (final theme in [null, 'light', 'dark']) {
        final decoded = StorefrontContentDocument.fromJson({
          ...legacy,
          'appearance': {...original, 'site_theme': theme},
        });
        expect(decoded.json['appearance'], {...original, 'site_theme': theme});
        expect(
          StorefrontContentDocument.fromJson(decoded.editableCopy()).json,
          decoded.json,
        );
        final copy = decoded.editableCopy();
        (copy['appearance'] as Map)['site_theme'] = 'dark';
        expect((decoded.json['appearance'] as Map)['site_theme'], theme);
      }
      for (final invalid in [
        '',
        'LIGHT',
        'dark ',
        'reference_dark',
        false,
        1,
        {},
        [],
      ]) {
        expect(
          () => StorefrontContentDocument.fromJson({
            ...legacy,
            'appearance': {...original, 'site_theme': invalid},
          }),
          throwsA(isA<StorefrontDecodeException>()),
        );
      }
      expect(contentFieldPath('appearance.site_theme'), isTrue);
      expect(
        SupabaseStorefrontContentRepository.readFunction,
        'get_restaurant_storefront_content_v4',
      );
      expect(
        SupabaseStorefrontContentRepository.writeFunction,
        'set_restaurant_storefront_content_v1',
      );
    },
  );

  test(
    'explicit modes keep tenant accent and use only readable custom ink without mutation',
    () {
      const saved = StorefrontColorSample(
        background: '#292929',
        accent: '#ff8000',
        text: '#ffffff',
        buttonText: '#000000',
      );
      final light = StorefrontSiteThemePalette(
        siteTheme: 'light',
        sample: saved,
      );
      final dark = StorefrontSiteThemePalette(siteTheme: 'dark', sample: saved);
      expect(light.background, Colors.white);
      expect(light.text, const Color(0xff202124));
      expect(light.usesTextFallback, isTrue);
      expect(dark.background, const Color(0xff292929));
      expect(dark.text, Colors.white);
      expect(dark.usesTextFallback, isFalse);
      expect(light.accent, const Color(0xffff8000));
      expect(light.buttonText, Colors.black);
      expect(saved.text, '#ffffff');
      expect(saved.background, '#292929');
      const pale = StorefrontColorSample(
        background: '#ffffff',
        accent: '#eeeeee',
        text: '#ffffff',
        buttonText: '#ffffff',
      );
      final paleDark = StorefrontSiteThemePalette(
        siteTheme: 'dark',
        sample: pale,
      );
      expect(paleDark.background, const Color(0xff151513));
      expect(paleDark.text, Colors.white);
      expect(paleDark.accent, const Color(0xffeeeeee));
      expect(paleDark.buttonText, const Color(0xff0b1512));
      expect(paleDark.usesButtonTextFallback, isTrue);
      const gray = StorefrontColorSample(
        background: '#292929',
        accent: '#777777',
      );
      for (final mode in ['light', 'dark']) {
        final grayMode = StorefrontSiteThemePalette(
          siteTheme: mode,
          sample: gray,
        );
        expect(grayMode.buttonText, Colors.black);
        expect(
          storefrontContrast(
            storefrontFormatColor(grayMode.buttonText),
            gray.accent,
          ),
          greaterThanOrEqualTo(kStorefrontContrastAa),
        );
        expect(gray.accent, '#777777');
      }

      const readable = StorefrontColorSample(text: '#222222');
      expect(
        StorefrontSiteThemePalette(siteTheme: 'light', sample: readable).text,
        const Color(0xff222222),
      );
    },
  );

  testWidgets(
    'light hides only the scene sample and dark restores same URL/dim with notice',
    (tester) async {
      var mode = 'dark';
      late StateSetter update;
      final url = Uri.parse(
        'https://example.invalid/synthetic/same-background.webp',
      );
      const sample = StorefrontColorSample(
        background: '#292929',
        accent: '#ff8000',
        text: '#ffffff',
        buttonText: '#000000',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return StorefrontSiteThemePreview(
                  siteTheme: mode,
                  scenePreset: 'reference_dark',
                  sample: sample,
                  backgroundUrl: url,
                  dim: 37,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final photo = tester.widget<Image>(
        find.byKey(const Key('content-site-theme-photo')),
      );
      expect((photo.image as NetworkImage).url, url.toString());
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('content-site-theme-dim')))
            .color
            .a,
        closeTo(.37, .005),
      );
      update(() => mode = 'light');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('content-site-theme-photo')), findsNothing);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const Key('content-site-theme-preview')),
            )
            .color,
        Colors.white,
      );
      expect(
        find.byKey(const Key('content-site-theme-contrast-notice')),
        findsOneWidget,
      );
      update(() => mode = 'dark');
      await tester.pumpAndSettle();
      final restored = tester.widget<Image>(
        find.byKey(const Key('content-site-theme-photo')),
      );
      expect((restored.image as NetworkImage).url, url.toString());
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('content-site-theme-dim')))
            .color
            .a,
        closeTo(.37, .005),
      );
      expect(
        find.byKey(const Key('content-site-theme-contrast-notice')),
        findsNothing,
      );
      expect(sample.text, '#ffffff');
      expect(tester.takeException(), isNull);
    },
  );
}
