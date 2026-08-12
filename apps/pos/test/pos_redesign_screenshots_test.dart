@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';

/// POS-REFERENCE-REDESIGN-002 — LOCAL screenshot generator, not a regression
/// test. Skipped everywhere unless run explicitly with
///   flutter test test/pos_redesign_screenshots_test.dart \
///     --dart-define=POS_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/redesign/ for before/after visual
/// comparison. Never committed, never exercised in CI (no goldens exist to
/// compare against, and the define keeps it skipped).
const bool _enabled = bool.fromEnvironment('POS_SCREENSHOTS');

/// 'before' or 'after' — names the output files.
const String _phase = String.fromEnvironment(
  'POS_SHOT_PHASE',
  defaultValue: 'shot',
);

Future<void> _loadRealFonts() async {
  // CI runs `flutter test apps/pos` from the REPOSITORY ROOT, so a bare
  // relative path does not resolve there; probe both working directories
  // (the generator itself only ever runs locally, but setUpAll must never
  // throw on CI either way).
  final fontsDir = Directory(
    'assets/fonts',
  ).existsSync()
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

  // 004: the approved v4 pairing (Alexandria display / Rubik body / Inter
  // money) plus the previous families that remain in the fallback chain.
  await load('Alexandria', ['Alexandria-Bold.ttf', 'Alexandria-ExtraBold.ttf']);
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

  // Material icons, so glyphs render instead of tofu boxes in the PNGs.
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

Widget _app(Locale locale) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    locale: locale,
    debugShowCheckedModeBanner: false,
    theme: posPremiumTheme(),
    home: const PosMenuScreen(),
  ),
);

Future<void> _shot(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required String name,
  int addFirstItemTaps = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(locale));
  await tester.pumpAndSettle();
  for (var i = 0; i < addFirstItemTaps; i++) {
    // The FIRST add action is the plain Classic Burger one-tap add (a frozen
    // corpus fact) — no modifier sheet in the way.
    final add = find.byIcon(Icons.add_shopping_cart);
    if (add.evaluate().isNotEmpty) {
      await tester.tap(add.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/redesign/${_phase}_$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // setUpAll runs even when every test in the file is skipped — on CI (where
  // POS_SCREENSHOTS is never defined) it must be a no-op, not a font load
  // that can fail the suite (the branch's one CI red came from exactly that).
  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('1280 ar empty', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('ar'),
      name: '1280_ar_empty',
    );
  });

  testWidgets('1280 ar populated', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('ar'),
      name: '1280_ar',
      addFirstItemTaps: 3,
    );
  });

  testWidgets('834 ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(834, 1112),
      locale: const Locale('ar'),
      name: '834_ar',
      addFirstItemTaps: 1,
    );
  });

  testWidgets('430 ar phone', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(430, 932),
      locale: const Locale('ar'),
      name: '430_ar',
      addFirstItemTaps: 1,
    );
  });

  testWidgets('1280 en populated', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('en'),
      name: '1280_en',
      addFirstItemTaps: 2,
    );
  });

  testWidgets('430 he phone', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(430, 932),
      locale: const Locale('he'),
      name: '430_he',
      addFirstItemTaps: 1,
    );
  });
}
