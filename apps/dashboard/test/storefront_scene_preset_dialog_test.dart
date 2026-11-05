import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_color_picker.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_scene_preset_dialog.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

const _bright = StorefrontColorSample(
  background: '#00ff00',
  accent: '#f030a0',
  text: '#fafafa',
  buttonText: '#112233',
);

Future<void> _open(
  WidgetTester tester, {
  required ValueChanged<StorefrontSceneChoice?> onResult,
  String locale = 'en',
  String? current,
  int dim = 15,
  bool custom = true,
  Uri? uri,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      locale: Locale(locale),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await showDialog<StorefrontSceneChoice>(
                  context: context,
                  builder: (_) => StorefrontScenePresetDialog(
                    currentPreset: current,
                    sample: _bright,
                    backgroundUrl: uri,
                    customBackground: custom,
                    dim: dim,
                    headline: 'Actual restaurant headline',
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'preset choices are local until Apply; Cancel returns no change',
    (tester) async {
      final results = <StorefrontSceneChoice?>[];
      await _open(tester, onResult: results.add);
      await _tap(tester, 'storefront-scene-legacy');
      await _tap(tester, 'storefront-scene-reference');
      expect(results, isEmpty);
      await _tap(tester, 'storefront-scene-cancel');
      expect(results, [null]);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await _tap(tester, 'storefront-scene-apply');
      expect(results.last!.preset, 'reference_dark');
    },
  );

  testWidgets('explicit inherit returns null preset through Apply', (
    tester,
  ) async {
    final results = <StorefrontSceneChoice?>[];
    await _open(tester, current: 'reference_dark', onResult: results.add);
    await _tap(tester, 'storefront-scene-legacy');
    expect(results, isEmpty);
    await _tap(tester, 'storefront-scene-apply');
    expect(results.single, isNotNull);
    expect(results.single!.preset, isNull);
  });

  for (final dim in [0, 15, 80]) {
    testWidgets(
      'same image at dim $dim compares bright brand and neutral glass',
      (tester) async {
        final uri = Uri.parse('https://example.invalid/same-owned-scene.webp');
        await _open(tester, dim: dim, uri: uri, onResult: (_) {});
        final reference = tester.widget<Image>(
          find.byKey(const Key('scene-reference-photo')),
        );
        final legacy = tester.widget<Image>(
          find.byKey(const Key('scene-legacy-photo')),
        );
        expect(
          reference.image,
          legacy.image,
          reason: 'the same exact asset in both panels',
        );
        expect((reference.image as NetworkImage).url, uri.toString());
        expect(reference.fit, BoxFit.cover);
        expect(
          tester
              .widget<ColoredBox>(find.byKey(const Key('scene-reference-dim')))
              .color,
          Colors.black.withValues(alpha: dim / 100),
        );
        expect(
          tester
              .widget<ColoredBox>(find.byKey(const Key('scene-legacy-dim')))
              .color,
          const Color(0xff00ff00).withValues(alpha: dim / 100),
        );
        expect(
          tester
              .widget<Container>(
                find.byKey(const Key('scene-reference-navigation')),
              )
              .color,
          const Color(0xff151515).withValues(alpha: .76),
        );
        expect(
          tester
              .widget<Container>(
                find.byKey(const Key('scene-legacy-navigation')),
              )
              .color,
          const Color(0xff00ff00).withValues(alpha: .94),
        );
        for (final key in ['reference', 'legacy']) {
          final panel = find.byKey(Key('scene-$key-preview'));
          expect(
            find.descendant(
              of: panel,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is ColoredBox &&
                    widget.color == const Color(0xfff030a0),
              ),
            ),
            findsOneWidget,
            reason: 'accent remains the current restaurant color',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Hero fallback illustrates legacy blur and clear reference with same image',
    (tester) async {
      await _open(
        tester,
        custom: false,
        uri: Uri.parse('https://example.invalid/independent-hero.webp'),
        onResult: (_) {},
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('scene-legacy-preview')),
          matching: find.byType(ImageFiltered),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('scene-reference-preview')),
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('scene-legacy-dim')), findsNothing);
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('scene-reference-dim')))
            .color,
        Colors.black.withValues(alpha: .15),
      );
    },
  );

  for (final locale in ['ar', 'he', 'en']) {
    for (final size in [const Size(390, 844), const Size(1024, 600)]) {
      testWidgets(
        '$locale ${size.width} large text is scrollable with visible actions',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _open(tester, locale: locale, textScale: 1.4, onResult: (_) {});
          final dialog = find.byKey(const Key('storefront-scene-dialog'));
          expect(
            Directionality.of(tester.element(dialog)),
            locale == 'en' ? TextDirection.ltr : TextDirection.rtl,
          );
          expect(
            find.byKey(const Key('storefront-scene-apply')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('storefront-scene-cancel')).hitTestable(),
            findsOneWidget,
          );
          await _tap(tester, 'storefront-scene-legacy');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
