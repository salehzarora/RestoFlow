@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';

/// POS-QUICK-NOTES-124 — LOCAL screenshot generator for the §14 visual review.
/// NOT a regression test: every case is skipped unless run explicitly with
///
///   flutter test apps/pos/test/pos_quick_notes_124_screenshots_test.dart \
///     --dart-define=POS_SCREENSHOTS=true --update-goldens
///
/// which WRITES the PNGs under dist/pos-quick-notes-124a/qa-screenshots/.
/// `dist/` is not tracked, no goldens are committed, and CI never runs these —
/// they are QA evidence, deliberately not a brittle pixel gate.
const bool _enabled = bool.fromEnvironment('POS_SCREENSHOTS');

const Size _tablet = Size(1024, 700);
const Size _compact = Size(360, 780);

Future<void> _loadRealFonts() async {
  final fontsDir = Directory('assets/fonts').existsSync()
      ? 'assets/fonts'
      : 'apps/pos/assets/fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$fontsDir/$f');
      if (!file.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
    await loader.load();
  }

  await load('Alexandria', ['Alexandria-Bold.ttf', 'Alexandria-ExtraBold.ttf']);
  // flutter_test has no platform Arabic fallback, so a real Arabic face is
  // registered as the DEFAULT family — otherwise every Arabic label in the
  // shots is tofu while the device renders it correctly. App code is unchanged.
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

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
      );
      await loader.load();
    }
  }
}

const _item = DemoMenuItem(
  id: 'item-a',
  name: 'Classic burger',
  priceMinor: 4200,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);

List<PosModifierGroup> _groups() => const [
  PosModifierGroup(
    id: 'g-0',
    menuItemId: 'item-a',
    name: 'Extras',
    options: [
      PosModifierOption(id: 'opt-0', name: 'Cheddar', priceDeltaMinor: 300),
      PosModifierOption(id: 'opt-1', name: 'Bacon', priceDeltaMinor: 500),
    ],
  ),
];

/// The English demo phrases; ten of them, so the "more" affordance is real.
List<PosQuickNotePreset> _presets(int n) =>
    kDemoQuickNotePresets.take(n).toList();

const _arabicPresets = <PosQuickNotePreset>[
  PosQuickNotePreset(id: 'a1', label: 'بدون بصل', displayOrder: 0),
  PosQuickNotePreset(id: 'a2', label: 'بدون ملح', displayOrder: 1),
  PosQuickNotePreset(id: 'a3', label: 'مقرمش جداً', displayOrder: 2),
  PosQuickNotePreset(id: 'a4', label: 'حار', displayOrder: 3),
  PosQuickNotePreset(id: 'a5', label: 'الصلصة جانباً', displayOrder: 4),
];

Future<void> _open(
  WidgetTester tester, {
  required List<PosQuickNotePreset> quickNotes,
  Size size = _tablet,
  Locale locale = const Locale('en'),
  String? initialNote,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      debugShowCheckedModeBanner: false,
      theme: posPremiumTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open-sheet'),
              onPressed: () => ModifierSelectionSheet.show(
                context,
                item: _item,
                groups: _groups(),
                currencyCode: 'ILS',
                quickNotes: quickNotes,
                initialNote: initialNote,
                onConfirm: (_, _, _) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  await _reveal(tester, find.byKey(const Key('modifier-quick-notes')));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile(
    '../../../dist/pos-quick-notes-124a/qa-screenshots/$name.png',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('01 four presets', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _presets(4));
    await _shot(tester, 'pos-01-four-presets');
  });

  testWidgets('02 ten presets, collapsed', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _presets(10));
    await _shot(tester, 'pos-02-ten-collapsed');
  });

  testWidgets('03 expanded via More', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _presets(10));
    await tester.tap(find.byKey(const Key('quick-note-more')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('modifier-quick-notes')));
    await _shot(tester, 'pos-03-expanded');
  });

  testWidgets('04 arabic / RTL', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _arabicPresets, locale: const Locale('ar'));
    await _shot(tester, 'pos-04-arabic-rtl');
  });

  testWidgets('05 note after two chips', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _presets(6));
    for (final id in ['qn-no-onions', 'qn-extra-crispy']) {
      final chip = find.byKey(Key('quick-note-chip-$id'));
      await _reveal(tester, chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    await _reveal(tester, find.byKey(const Key('modifier-item-note')));
    await _shot(tester, 'pos-05-note-after-two-chips');
  });

  testWidgets('06 the 140-character refusal', skip: !_enabled, (tester) async {
    await _open(tester, quickNotes: _presets(6), initialNote: 'x' * 138);
    final chip = find.byKey(const Key('quick-note-chip-qn-no-onions'));
    await _reveal(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('quick-note-limit-warning')));
    await _shot(tester, 'pos-06-limit-refusal');
  });

  testWidgets('07 compact width with the keyboard up', skip: !_enabled, (
    tester,
  ) async {
    await _open(tester, quickNotes: _presets(10), size: _compact);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('modifier-quick-notes')));
    await _shot(tester, 'pos-07-compact-keyboard');
  });
}
