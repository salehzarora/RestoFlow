@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/quick_notes/quick_notes_repository.dart';
import 'package:restoflow_dashboard/src/quick_notes/quick_notes_section.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// POS-QUICK-NOTES-124 — LOCAL screenshot generator for the Dashboard Quick
/// notes section (§14 visual review). NOT a regression test: skipped unless run
/// explicitly with
///
///   flutter test apps/dashboard/test/pos_quick_notes_124_screenshots_test.dart \
///     --dart-define=DASH_SCREENSHOTS=true --update-goldens
///
/// which WRITES the PNGs under dist/pos-quick-notes-124a/qa-screenshots/.
/// `dist/` is untracked, nothing is committed, and CI never runs these.
const bool _enabled = bool.fromEnvironment('DASH_SCREENSHOTS');

Future<void> _loadRealFonts() async {
  final fontsDir = Directory('../pos/assets/fonts').existsSync()
      ? '../pos/assets/fonts'
      : 'apps/pos/assets/fonts';
  final loader = FontLoader('Roboto');
  for (final f in [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-Bold.ttf',
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
  ]) {
    final file = File('$fontsDir/$f');
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(
        Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
      );
      await iconLoader.load();
    }
  }
}

/// A read-only stand-in: the shots are about layout, not about writes.
class _ShotRepo implements QuickNotesRepository {
  _ShotRepo(this.presets);
  final List<QuickNotePreset> presets;
  @override
  Future<QuickNotesSnapshot> load() async => QuickNotesSnapshot.ok(presets);
  @override
  Future<QuickNoteWrite> upsert({
    String? id,
    required String label,
    required bool isActive,
  }) async => QuickNoteWrite.ok;
  @override
  Future<QuickNoteWrite> delete(String id) async => QuickNoteWrite.ok;
  @override
  Future<QuickNoteWrite> reorder(List<String> ids) async => QuickNoteWrite.ok;
}

const _english = <QuickNotePreset>[
  QuickNotePreset(id: 'a', label: 'No onions', displayOrder: 0, isActive: true),
  QuickNotePreset(
    id: 'b',
    label: 'Extra crispy',
    displayOrder: 1,
    isActive: true,
  ),
  QuickNotePreset(
    id: 'c',
    label: 'Sauce on the side',
    displayOrder: 2,
    isActive: true,
  ),
  QuickNotePreset(id: 'd', label: 'Well done', displayOrder: 3, isActive: true),
  // The switched-off row, so the visual treatment is reviewable.
  QuickNotePreset(id: 'e', label: 'No ice', displayOrder: 4, isActive: false),
];

const _arabic = <QuickNotePreset>[
  QuickNotePreset(id: 'a', label: 'بدون بصل', displayOrder: 0, isActive: true),
  QuickNotePreset(
    id: 'b',
    label: 'مقرمش جداً',
    displayOrder: 1,
    isActive: true,
  ),
  QuickNotePreset(
    id: 'c',
    label: 'الصلصة جانباً',
    displayOrder: 2,
    isActive: true,
  ),
  QuickNotePreset(id: 'd', label: 'بدون ثلج', displayOrder: 3, isActive: false),
];

Future<void> _pump(
  WidgetTester tester,
  List<QuickNotePreset> presets, {
  Locale locale = const Locale('en'),
  Size size = const Size(900, 800),
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
      theme: restoflowLightBrandTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(RestoflowSpacing.lg),
          child: SingleChildScrollView(
            child: QuickNotesSection(repository: _ShotRepo(presets)),
          ),
        ),
      ),
    ),
  );
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

  testWidgets('01 the list, with a disabled row', skip: !_enabled, (
    tester,
  ) async {
    await _pump(tester, _english);
    await _shot(tester, 'dash-01-list');
  });

  testWidgets('02 the add form', skip: !_enabled, (tester) async {
    await _pump(tester, _english);
    await tester.tap(find.byKey(const Key('quick-notes-add')));
    await tester.pumpAndSettle();
    await _shot(tester, 'dash-02-add-dialog');
  });

  testWidgets('03 the edit form, prefilled', skip: !_enabled, (tester) async {
    await _pump(tester, _english);
    await tester.tap(find.byKey(const Key('quick-note-edit-b')));
    await tester.pumpAndSettle();
    await _shot(tester, 'dash-03-edit-dialog');
  });

  testWidgets('04 the delete confirmation', skip: !_enabled, (tester) async {
    await _pump(tester, _english);
    await tester.tap(find.byKey(const Key('quick-note-delete-a')));
    await tester.pumpAndSettle();
    await _shot(tester, 'dash-04-delete-confirm');
  });

  testWidgets('05 arabic / RTL', skip: !_enabled, (tester) async {
    await _pump(tester, _arabic, locale: const Locale('ar'));
    await _shot(tester, 'dash-05-arabic-rtl');
  });

  testWidgets('06 a narrow desktop pane', skip: !_enabled, (tester) async {
    await _pump(tester, _english, size: const Size(560, 800));
    await _shot(tester, 'dash-06-narrow');
  });
}
