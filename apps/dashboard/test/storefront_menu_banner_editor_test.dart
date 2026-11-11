import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_content_models.dart';

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
}
