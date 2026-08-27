@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableSectionRoomFramePreset;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-ROOM-FRAME-121 — LOCAL screenshot generator for the Dashboard floor
/// editor showing ALL SIX room frames at once (not a regression test).
/// Skipped unless run explicitly:
///   flutter test test/table_room_frame_screenshots_121_test.dart \
///     --dart-define=DASH_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/table_room_frame_121/. Never
/// committed, never exercised on CI.
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
    final bytes = File('$fontsDir/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      final bytes = icons.readAsBytesSync();
      iconLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await iconLoader.load();
    }
  }
}

/// One section per frame (Standard first), each with its own floor preset so
/// the matrix covers frame × floor in one capture, three tables spread to the
/// corners + centre, and a door + plant on the first two rooms.
class _ShotRepo extends InMemoryTablesStore {
  static const _frames = <(String, TableSectionRoomFramePreset?, FloorPreset)>[
    ('Standard hall', null, FloorPreset.woodDark),
    ('Compact', TableSectionRoomFramePreset.compact, FloorPreset.tileModern),
    ('Square', TableSectionRoomFramePreset.square, FloorPreset.stoneNeutral),
    ('Wide', TableSectionRoomFramePreset.wide, FloorPreset.plainLight),
    ('Portrait', TableSectionRoomFramePreset.portrait, FloorPreset.woodDark),
    (
      'Long corridor',
      TableSectionRoomFramePreset.longNarrow,
      FloorPreset.tileModern,
    ),
  ];

  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async => Success(
    TablesFloorSnapshot(
      sections: [
        for (final (i, f) in _frames.indexed)
          DashboardTableSection(
            id: 's$i',
            name: f.$1,
            displayOrder: i,
            isActive: true,
            branchId: 'b',
            floorPreset: f.$3,
            roomFramePreset: f.$2,
          ),
      ],
      floorElements: const [
        DashboardFloorElement(
          id: 'e-door',
          sectionId: 's0',
          kind: 'door',
          layoutX: 0,
          layoutY: 0,
          widthNorm: 900,
          heightNorm: 150,
        ),
        DashboardFloorElement(
          id: 'e-plant',
          sectionId: 's1',
          kind: 'plant',
          layoutX: 9800,
          layoutY: 9800,
          widthNorm: 900,
          heightNorm: 900,
        ),
      ],
      tables: [
        for (final (i, _) in _frames.indexed) ...[
          DashboardTable(
            id: 't$i-1',
            label: 'A$i',
            seats: 4,
            status: DiningTableStatus.available,
            isActive: true,
            branchId: 'b',
            sectionId: 's$i',
            sectionName: _frames[i].$1,
            sectionDisplayOrder: i,
            layoutX: 500,
            layoutY: 500,
          ),
          DashboardTable(
            id: 't$i-2',
            label: 'B$i',
            seats: 2,
            status: DiningTableStatus.occupied,
            isActive: true,
            branchId: 'b',
            effectiveState: 'occupied',
            activeOrderCount: 1,
            sectionId: 's$i',
            sectionName: _frames[i].$1,
            sectionDisplayOrder: i,
            layoutX: 5000,
            layoutY: 5000,
          ),
          DashboardTable(
            id: 't$i-3',
            label: 'C$i',
            seats: 6,
            status: DiningTableStatus.reserved,
            isActive: true,
            branchId: 'b',
            effectiveState: 'reserved',
            sectionId: 's$i',
            sectionName: _frames[i].$1,
            sectionDisplayOrder: i,
            layoutX: 9500,
            layoutY: 9500,
          ),
        ],
      ],
    ),
  );
}

Future<void> _shot(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required String name,
  bool openFramePicker = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      debugShowCheckedModeBanner: false,
      theme: restoflowLightBrandTheme(),
      home: Scaffold(body: TablesScreen(repository: _ShotRepo())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
  await tester.pumpAndSettle();
  if (openFramePicker) {
    await tester.tap(find.byKey(const Key('section-room-frame-s0')));
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/table_room_frame_121/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('all six frames en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1100, 8200),
      locale: const Locale('en'),
      name: 'dashboard_frames_en',
    );
  });

  testWidgets('all six frames ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1100, 8200),
      locale: const Locale('ar'),
      name: 'dashboard_frames_ar',
    );
  });

  testWidgets('room-frame picker menu en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1100, 2600),
      locale: const Locale('en'),
      name: 'dashboard_frame_menu_en',
      openFramePicker: true,
    );
  });
}
