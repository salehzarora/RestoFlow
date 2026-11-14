import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_menu_banner_editor.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_banner_preview.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'helpers/storefront_content_groups.dart';
import 'storefront_content_section_test.dart' as f;

void main() {
  testWidgets(
    'banner and intro remain independent drafts across folding, save and clear',
    (tester) async {
      final repo = f.ContentRepo();
      final original = <String, Object?>{
        'text_color': '#ffffff',
        'button_text_color': '#000000',
        'font_family': 'alexandria',
        'site_theme': 'dark',
        'menu_background_media_id': f.category,
        'menu_background_dim': 23,
        'menu_banner_media_id': f.request,
        'menu_banner_enabled': true,
        'menu_intro_visible': true,
        'menu_banner_focal_x': 50,
        'menu_banner_focal_y': 50,
      };
      repo.doc = StorefrontContentDocument.fromJson(
        repo.doc.editableCopy()..['appearance'] = original,
      );
      repo.mediaRows.add(
        StorefrontContentMediaRow.fromJson({
          'id': f.request,
          'source_bucket': 'menu-images',
          'source_key': 'synthetic/banner.png',
          'variant': 'w960',
          'object_key': 'synthetic/banner.webp',
          'content_hash': 'a' * 64,
          'width': 960,
          'height': 420,
          'bytes': 123,
          'state': 'published',
          'published_at': '2026-11-11T00:00:00Z',
          'unpublished_at': null,
          'created_at': '2026-11-11T00:00:00Z',
          'in_use': [],
          'content_in_use': [],
        }),
      );
      await f.mount(tester, repo, openGroups: false);
      await setContentGroup(tester, 'menu-banner');
      final intro = find.byKey(const Key('content-menu-intro-visible'));
      await tester.ensureVisible(intro);
      await tester.tap(intro);
      await tester.pumpAndSettle();
      final x = find.byKey(const ValueKey('content-menu-banner-focal-x'));
      tester.widget<Slider>(x).onChanged!(72);
      await tester.pumpAndSettle();
      await setContentGroup(tester, 'menu-banner', expanded: false);
      await setContentGroup(tester, 'menu-banner');
      expect(tester.widget<SwitchListTile>(intro).value, isFalse);
      expect(tester.widget<Slider>(x).value, 72);
      expect(repo.calls, isEmpty);
      final save = find.byKey(const Key('content-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = repo.calls.single.document.json['appearance'] as Map;
      expect(saved['menu_intro_visible'], isFalse);
      expect(saved['menu_banner_enabled'], isTrue);
      expect(saved['menu_banner_focal_x'], 72);
      for (final key in [
        'text_color',
        'button_text_color',
        'font_family',
        'site_theme',
        'menu_background_media_id',
        'menu_background_dim',
      ]) {
        expect(saved[key], original[key], reason: key);
      }
      await setContentGroup(tester, 'menu-banner');
      final clear = find.byKey(const Key('content-menu-banner-clear'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final cleared = repo.calls.last.document.json['appearance'] as Map;
      expect(cleared['menu_banner_media_id'], isNull);
      expect(cleared['menu_background_media_id'], f.category);
      expect(cleared['menu_banner_focal_x'], 72);
      expect(cleared['menu_intro_visible'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'physical focal endpoints and midpoint save and reread without saving viewport choice',
    (tester) async {
      final repo = f.ContentRepo();
      final original = repo.doc.editableCopy();
      original['appearance'] = {
        'text_color': null,
        'button_text_color': null,
        ...?original['appearance'] as Map?,
        'menu_banner_media_id': f.request,
        'menu_banner_enabled': true,
        'menu_banner_focal_x': 50,
        'menu_banner_focal_y': 50,
      };
      repo.doc = StorefrontContentDocument.fromJson(original);
      repo.mediaRows.add(
        StorefrontContentMediaRow.fromJson({
          'id': f.request,
          'source_bucket': 'menu-images',
          'source_key': 'synthetic/banner.png',
          'variant': 'w960',
          'object_key': 'synthetic/banner.webp',
          'content_hash': 'a' * 64,
          'width': 960,
          'height': 420,
          'bytes': 123,
          'state': 'published',
          'published_at': '2026-11-11T00:00:00Z',
          'unpublished_at': null,
          'created_at': '2026-11-11T00:00:00Z',
          'in_use': [],
          'content_in_use': [],
        }),
      );
      await f.mount(tester, repo, locale: 'ar', openGroups: false);
      for (final point in [0, 50, 100]) {
        await setContentGroup(tester, 'menu-banner');
        for (final axis in ['x', 'y']) {
          final finder = find.byKey(
            ValueKey('content-menu-banner-focal-$axis'),
          );
          expect(Directionality.of(tester.element(finder)), TextDirection.ltr);
          tester.widget<Slider>(finder).onChanged!(point.toDouble());
          await tester.pumpAndSettle();
          expect(tester.widget<Slider>(finder).value, point);
        }
        final before = repo.calls.length;
        final chip = find.byKey(const ValueKey('banner-preview-width-430'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(repo.calls.length, before, reason: 'draft and width never save');
        final frame = tester.widget<StorefrontBannerPreviewFrame>(
          find.byKey(const ValueKey('banner-phone-frame')),
        );
        expect(frame.logicalWidth, 430);
        expect(frame.focalX, point);
        expect(frame.focalY, point);
        final save = find.byKey(const Key('content-save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final saved = repo.doc.json['appearance'] as Map;
        expect(saved['menu_banner_focal_x'], point);
        expect(saved['menu_banner_focal_y'], point);
        expect(
          saved.keys.any((key) => key.toString().contains('width')),
          isFalse,
        );
        // The existing parent save re-reads before unlocking the editor.
        await setContentGroup(tester, 'menu-banner');
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('content-menu-banner-focal-x')),
              )
              .value,
          point,
        );
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('content-menu-banner-focal-y')),
              )
              .value,
          point,
        );
      }
      expect(repo.calls, hasLength(3));
      expect(repo.mediaRows.single.media.sourceKey, 'synthetic/banner.png');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one public snapshot per scope and no read on focal/width changes',
    (tester) async {
      var reads = 0;
      var x = 50;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return StorefrontMenuBannerEditor(
                    appearance: {'menu_banner_focal_x': x},
                    media: const [],
                    editable: true,
                    onChanged: (_, _) {},
                    previewIdentity: 'restaurant|branch|version',
                    loadPreview: () async {
                      reads++;
                      return {'ok': true};
                    },
                    previewDataFor: (_) => const {'displayName': 'Local QA'},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      update(() => x = 100);
      await tester.pumpAndSettle();
      final width = find.byKey(const ValueKey('banner-preview-width-360'));
      await tester.ensureVisible(width);
      await tester.tap(width);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(
        tester
            .widget<StorefrontBannerPreviewFrame>(
              find.byKey(const ValueKey('banner-phone-frame')),
            )
            .logicalWidth,
        360,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late public preview read cannot repaint a newer editor scope', (
    tester,
  ) async {
    final oldRead = Completer<Map<String, dynamic>?>();
    var identity = 'A';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return StorefrontMenuBannerEditor(
                  appearance: const {},
                  media: const [],
                  editable: true,
                  onChanged: (_, _) {},
                  previewIdentity: identity,
                  loadPreview: identity == 'A'
                      ? () => oldRead.future
                      : () async => {'displayName': 'B'},
                  previewDataFor: (value) => {
                    'displayName': value?['displayName'] ?? 'unknown',
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => identity = 'B');
    await tester.pumpAndSettle();
    oldRead.complete({'displayName': 'A'});
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StorefrontBannerPreviewFrame>(
            find.byKey(const ValueKey('banner-phone-frame')),
          )
          .data['displayName'],
      'B',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'responsive opt-in keeps independent device drafts and previews; height reset and layout off preserve other settings',
    (tester) async {
      final repo = f.ContentRepo();
      final before = <String, Object?>{
        'text_color': '#ffffff',
        'button_text_color': '#000000',
        'site_theme': 'dark',
        'menu_background_media_id': null,
        'menu_background_dim': 23,
        'menu_banner_media_id': f.request,
        'menu_banner_enabled': true,
        'menu_intro_visible': false,
        'menu_banner_focal_x': 38,
        'menu_banner_focal_y': 9,
      };
      repo.doc = StorefrontContentDocument.fromJson(
        repo.doc.editableCopy()..['appearance'] = before,
      );
      StorefrontContentMediaRow media(
        String id,
        String hash,
        int width,
        int height,
      ) => StorefrontContentMediaRow.fromJson({
        'id': id,
        'source_bucket': 'menu-images',
        'source_key': 'synthetic/$hash.png',
        'variant': 'w960',
        'object_key': '${'a' * 32}/${hash * 64}.webp',
        'content_hash': hash * 64,
        'width': width,
        'height': height,
        'bytes': 123,
        'state': 'published',
        'published_at': '2026-11-11T00:00:00Z',
        'unpublished_at': null,
        'created_at': '2026-11-11T00:00:00Z',
        'in_use': [],
        'content_in_use': [],
      });
      repo.mediaRows.addAll([
        media(f.request, 'b', 960, 536),
        media(f.category, 'c', 960, 240),
      ]);
      await f.mount(
        tester,
        repo,
        openGroups: false,
        publicUrlFor: (key) => Uri.parse(
          'http://127.0.0.1:54321/storage/v1/object/public/storefront-media/$key',
        ),
      );
      await setContentGroup(tester, 'menu-banner');
      SwitchListTile layout() => tester.widget<SwitchListTile>(
        find.byKey(const Key('content-menu-banner-layout')),
      );
      StorefrontBannerPreviewFrame preview(bool phone) =>
          tester.widget<StorefrontBannerPreviewFrame>(
            find.byKey(
              ValueKey(phone ? 'banner-phone-frame' : 'banner-desktop-frame'),
            ),
          );
      expect(layout().value, isFalse);
      expect(preview(true).data['layout'], isNull);
      layout().onChanged!(true);
      await tester.pumpAndSettle();
      Future<void> editDevice(bool phone) async {
        final key = ValueKey(
          'content-menu-banner-device-${phone ? 'phone' : 'desktop'}',
        );
        tester.widget<ChoiceChip>(find.byKey(key)).onSelected!(true);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(find.byKey(key)).selected, isTrue);
      }

      void mode(String device) => tester
          .widget<DropdownButtonFormField<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<String> &&
                  w.key.toString().contains(
                    'content-menu-banner-$device-height-mode',
                  ),
            ),
          )
          .onChanged!('custom');
      mode('mobile');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('content-menu-banner-mobile-height')),
            )
            .value,
        520,
      );
      await editDevice(false);
      mode('desktop');
      await tester.pumpAndSettle();
      expect(preview(true).data['heightPx'], 520);
      expect(
        find.byKey(const ValueKey('content-menu-banner-mobile-height')),
        findsNothing,
      );
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('content-menu-banner-desktop-height')),
            )
            .value,
        400,
      );
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('content-menu-banner-desktop-height')),
          )
          .onChanged!(560);
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('content-menu-banner-desktop-media-')),
          )
          .onChanged!(f.category);
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('content-menu-banner-desktop-focal-x')),
          )
          .onChanged!(73);
      await tester.pumpAndSettle();
      expect(preview(true).data['imageUrl'], contains('${'b' * 64}.webp'));
      expect(preview(false).data['imageUrl'], contains('${'c' * 64}.webp'));
      expect(preview(true).data['heightPx'], 520);
      expect(preview(false).data['heightPx'], 560);
      expect(preview(true).focalX, 38);
      expect(preview(false).focalX, 73);
      expect(
        repo.calls,
        isEmpty,
        reason: 'All controls are unsaved draft changes',
      );
      await editDevice(true);
      expect(
        find.byKey(const ValueKey('content-menu-banner-desktop-height')),
        findsNothing,
      );
      final reset = find.byKey(
        const ValueKey('content-menu-banner-mobile-height-reset'),
      );
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(preview(true).data['heightPx'], isNull);
      expect(preview(false).data['heightPx'], 560);
      final save = find.byKey(const Key('content-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final saved = repo.calls.single.document.json['appearance'] as Map;
      expect(saved['menu_banner_layout'], 'responsive');
      expect(saved['menu_banner_mobile_height_px'], isNull);
      expect(saved['menu_banner_desktop_height_px'], 560);
      expect(saved['menu_banner_desktop_media_id'], f.category);
      expect(
        saved.keys.any((key) => key.toString().contains('editing_device')),
        isFalse,
      );
      for (final entry in before.entries)
        expect(saved[entry.key], entry.value, reason: entry.key);
      await setContentGroup(tester, 'menu-banner');
      layout().onChanged!(false);
      await tester.pumpAndSettle();
      expect(preview(true).data['layout'], isNull);
      expect(preview(false).data['imageUrl'], preview(true).data['imageUrl']);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final off = repo.calls.last.document.json['appearance'] as Map;
      expect(off['menu_banner_layout'], isNull);
      expect(off['menu_banner_desktop_height_px'], 560);
      expect(off['menu_banner_desktop_media_id'], f.category);
      await setContentGroup(tester, 'menu-banner');
      layout().onChanged!(true);
      await tester.pumpAndSettle();
      await editDevice(false);
      tester
          .widget<TextButton>(
            find.byKey(const Key('content-menu-banner-desktop-clear')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(preview(false).data['imageUrl'], preview(true).data['imageUrl']);
      expect(preview(false).data['heightPx'], 560);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('content-menu-banner-desktop-media-')),
          )
          .onChanged!(f.category);
      await tester.pumpAndSettle();
      await editDevice(true);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(ValueKey('content-menu-banner-media-${f.request}')),
          )
          .onChanged!('');
      await tester.pumpAndSettle();
      expect(preview(true).data['imageUrl'], isNull);
      expect(preview(false).data['imageUrl'], contains('${'c' * 64}.webp'));
      expect(preview(false).data['enabled'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  for (final (locale, labels) in [
    ('en', ['Low', 'Medium', 'High']),
    ('ar', ['منخفض', 'متوسط', 'مرتفع']),
    ('he', ['נמוך', 'בינוני', 'גבוה']),
  ]) {
    testWidgets(
      'localized height markers retain numerical CSS-pixel stops and change no draft: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final changes = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: StorefrontMenuBannerEditor(
                  appearance: const {
                    'menu_banner_layout': 'responsive',
                    'menu_banner_mobile_height_px': 520,
                    'menu_banner_desktop_height_px': 400,
                  },
                  media: const [],
                  editable: true,
                  onChanged: (key, _) => changes.add(key),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in labels) expect(find.text(label), findsOneWidget);
        for (final number in [320, 480, 640])
          expect(find.text('$number px'), findsOneWidget);
        expect(find.text('520 CSS px'), findsOneWidget);
        final desktop = find.byKey(
          const ValueKey('content-menu-banner-device-desktop'),
        );
        await tester.ensureVisible(desktop);
        await tester.tap(desktop);
        await tester.pumpAndSettle();
        for (final label in labels) expect(find.text(label), findsOneWidget);
        for (final number in [240, 400, 560])
          expect(find.text('$number px'), findsOneWidget);
        expect(find.text('400 CSS px'), findsOneWidget);
        expect(
          changes,
          isEmpty,
          reason: 'Localized markers and edit-device choice are display-only',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
