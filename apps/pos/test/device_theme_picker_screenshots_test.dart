@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEVICE-THEME-COLOR-PICKER-032 — LOCAL screenshot generator, not a
/// regression test. Skipped everywhere unless run explicitly with
///   flutter test test/device_theme_picker_screenshots_test.dart \
///     --dart-define=POS_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/device_theme_032/ for the
/// ticket's §9 visual acceptance. Never committed (see apps/pos/.gitignore),
/// never exercised in CI — no goldens exist to compare against and the define
/// keeps every case skipped.
const bool _enabled = bool.fromEnvironment('POS_SCREENSHOTS');

/// The pilot tablet scene the ticket asks for, in Arabic.
const Size _tablet = Size(1024, 600);
const Locale _ar = Locale('ar');

Future<void> _loadRealFonts() async {
  // CI never reaches this (every case is skipped), but keep the same
  // both-working-directories probe the other generators use.
  final fontsDir = Directory('assets/fonts').existsSync()
      ? 'assets/fonts'
      : 'apps/pos/assets/fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fontsDir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Alexandria', ['Alexandria-Bold.ttf', 'Alexandria-ExtraBold.ttf']);
  // Every Material BUTTON label resolves through the design system's
  // `titleSmall`, which names no bundled family — it carries only OS
  // fallbacks (Segoe UI / Tahoma / Arial) and leans on the platform's Arabic
  // font. A real till has one; flutter_test has only Roboto and no platform
  // fallback, so without this every Arabic button label would render as tofu
  // in the shots while looking correct on the device. Registering a real
  // Arabic face as the DEFAULT family restores device behaviour; it changes
  // nothing in the app.
  await load('Roboto', ['Tajawal-Medium.ttf', 'Tajawal-Bold.ttf']);
  await load('Rubik', [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-SemiBold.ttf',
    'Rubik-Bold.ttf',
  ]);
  await load('Inter', ['Inter-Bold.ttf', 'Inter-ExtraBold.ttf']);
  await load('Tajawal', [
    'Tajawal-Medium.ttf',
    'Tajawal-Bold.ttf',
    'Tajawal-ExtraBold.ttf',
  ]);
  await load('IBMPlexSansArabic', [
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
  ]);

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      final bytes = icons.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
}

Widget _app() => ProviderScope(
  overrides: [
    posPrinterScopeSegmentProvider.overrideWith((ref) => 'shot-device'),
  ],
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: _ar,
    debugShowCheckedModeBanner: false,
    theme: posPremiumTheme(),
    home: const Scaffold(body: PosDeviceSettingsSheet()),
  ),
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('device-settings-sheet')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/device_theme_032/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('device theme visual picker — ar 1024x600', skip: !_enabled, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _tablet;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 1. Device settings → the appearance section with the custom editor open.
    await _scrollTo(tester, find.byKey(const Key('device-theme-custom')));
    await tester.tap(find.byKey(const Key('device-theme-custom')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('custom-theme-apply')));
    await _shot(tester, '1_custom_theme_editor_ar');

    // 2. The PRIMARY picker, open on the current color.
    await _tapVisible(tester, const Key('custom-theme-primary-swatch'));
    await _shot(tester, '2_primary_picker_open_ar');

    // 3. A different primary chosen visually — palette tap, then the field.
    await _tapVisible(tester, const Key('pos-color-picker-swatch-1A3D34'));
    final field = tester.getRect(
      find.byKey(const Key('pos-color-picker-sv-field')),
    );
    await tester.tapAt(
      Offset(field.left + field.width * 0.62, field.top + field.height * 0.38),
    );
    await tester.pumpAndSettle();
    await _shot(tester, '3_primary_selection_changed_ar');
    await _tapVisible(tester, const Key('pos-color-picker-confirm'));

    // 4. The SECONDARY picker, with the advanced hex section revealed so the
    //    screenshot shows that hex survives without being the way in.
    await _tapVisible(tester, const Key('custom-theme-secondary-swatch'));
    await _tapVisible(tester, const Key('pos-color-picker-swatch-D89A2B'));
    await _tapVisible(tester, const Key('pos-color-picker-advanced-toggle'));
    await _shot(tester, '4_secondary_picker_open_ar');
    await _tapVisible(tester, const Key('pos-color-picker-confirm'));

    // 5. Both halves chosen: the editor's live preview of the new pair.
    await _scrollTo(tester, find.byKey(const Key('custom-theme-preview')));
    await _shot(tester, '5_final_preview_ar');
  });
}
