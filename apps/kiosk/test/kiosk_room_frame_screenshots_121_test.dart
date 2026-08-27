@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableSectionRoomFramePreset;
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-ROOM-FRAME-121 — LOCAL screenshot generator for the kiosk floor map
/// rendering the configured room frames (not a regression test). Run:
///   flutter test test/kiosk_room_frame_screenshots_121_test.dart \
///     --dart-define=KIOSK_SCREENSHOTS=true --update-goldens
/// which writes 1080×1920 PNGs under test/goldens/table_room_frame_121/.
/// Never committed, never exercised on CI.
const bool _enabled = bool.fromEnvironment('KIOSK_SCREENSHOTS');

Future<void> _loadRealFonts() async {
  final dir = Directory('assets/fonts').existsSync()
      ? 'assets/fonts'
      : 'apps/kiosk/assets/fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Anton', ['Anton-Regular.ttf']);
  await load('Rubik', [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-SemiBold.ttf',
    'Rubik-Bold.ttf',
    'Rubik-ExtraBold.ttf',
    'Rubik-Black.ttf',
  ]);
  await load('Roboto', ['Rubik-Regular.ttf']);

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

KioskFixtureZone _zone(
  String id,
  String name,
  TableSectionRoomFramePreset? frame,
  FloorPreset floor,
) => KioskFixtureZone(
  id: id,
  displayName: name,
  floorPreset: floor,
  roomFramePreset: frame,
  tables: [
    KioskFixtureTable(
      id: '$id-a',
      label: 'A',
      seats: 4,
      state: KioskTableState.available,
      layoutX: 500,
      layoutY: 500,
    ),
    KioskFixtureTable(
      id: '$id-b',
      label: 'B',
      seats: 2,
      state: KioskTableState.occupied,
      layoutX: 5000,
      layoutY: 5000,
    ),
    KioskFixtureTable(
      id: '$id-c',
      label: 'C',
      seats: 6,
      state: KioskTableState.available,
      layoutX: 9500,
      layoutY: 9500,
    ),
  ],
);

Future<void> _pumpTables(
  WidgetTester tester,
  List<KioskFixtureZone> zones, {
  String lang = 'en',
}) async {
  final container = ProviderContainer(
    overrides: [
      kioskTablesViewProvider.overrideWithValue((
        zones: zones,
        status: KioskTablesStatus.ready,
        live: true,
      )),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        key: UniqueKey(),
        locale: Locale(lang),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        debugShowCheckedModeBanner: false,
        home: const KioskShell(),
      ),
    ),
  );
  final controller = container.read(kioskFlowProvider.notifier);
  controller.startFromAttract();
  controller.pickService(KioskServiceType.dineIn);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(KioskShell),
    matchesGoldenFile('goldens/table_room_frame_121/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_enabled) await _loadRealFonts();
  });

  testWidgets('standard + compact en', skip: !_enabled, (tester) async {
    await _pumpTables(tester, [
      _zone('z1', 'Standard hall', null, FloorPreset.woodDark),
      _zone(
        'z2',
        'Compact',
        TableSectionRoomFramePreset.compact,
        FloorPreset.tileModern,
      ),
    ]);
    await _shot(tester, 'kiosk_frames_a_en');
  });

  testWidgets('square + wide en', skip: !_enabled, (tester) async {
    await _pumpTables(tester, [
      _zone(
        'z1',
        'Square',
        TableSectionRoomFramePreset.square,
        FloorPreset.stoneNeutral,
      ),
      _zone(
        'z2',
        'Wide',
        TableSectionRoomFramePreset.wide,
        FloorPreset.plainLight,
      ),
    ]);
    await _shot(tester, 'kiosk_frames_b_en');
  });

  testWidgets('portrait + long narrow en', skip: !_enabled, (tester) async {
    await _pumpTables(tester, [
      _zone(
        'z1',
        'Portrait',
        TableSectionRoomFramePreset.portrait,
        FloorPreset.woodDark,
      ),
      _zone(
        'z2',
        'Long corridor',
        TableSectionRoomFramePreset.longNarrow,
        FloorPreset.tileModern,
      ),
    ]);
    await _shot(tester, 'kiosk_frames_c_en');
  });

  testWidgets('standard + square ar', skip: !_enabled, (tester) async {
    await _pumpTables(tester, [
      _zone('z1', 'القاعة الرئيسية', null, FloorPreset.woodDark),
      _zone(
        'z2',
        'مربع',
        TableSectionRoomFramePreset.square,
        FloorPreset.stoneNeutral,
      ),
    ], lang: 'ar');
    await _shot(tester, 'kiosk_frames_a_ar');
  });
}
