@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType, TableSectionRoomFramePreset;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-ROOM-FRAME-121 — LOCAL screenshot generator for the POS table
/// picker rendering the configured room frames (not a regression test).
/// Skipped unless run explicitly:
///   flutter test test/table_room_frame_screenshots_121_test.dart \
///     --dart-define=POS_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/table_room_frame_121/. Never
/// committed, never exercised on CI.
const bool _enabled = bool.fromEnvironment('POS_SCREENSHOTS');

Future<void> _loadRealFonts() async {
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

  await load('Rubik', [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-SemiBold.ttf',
    'Rubik-Bold.ttf',
  ]);
  await load('IBMPlexSansArabic', [
    'IBMPlexSansArabic-Regular.ttf',
    'IBMPlexSansArabic-Medium.ttf',
    'IBMPlexSansArabic-SemiBold.ttf',
  ]);
  await load('Roboto', ['Rubik-Regular.ttf', 'IBMPlexSansArabic-Regular.ttf']);

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

DemoTable _t(
  String id,
  String label, {
  String effective = 'available',
  required String sectionId,
  required String sectionName,
  required int sectionOrder,
  required int x,
  required int y,
  TableSectionRoomFramePreset? frame,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    seats: 4,
    area: sectionName,
  ),
  status: tableStatusKindFor(effective),
  effectiveState: effective,
  sectionId: sectionId,
  sectionName: sectionName,
  sectionDisplayOrder: sectionOrder,
  layoutX: x,
  layoutY: y,
  sectionRoomFramePreset: frame,
);

List<DemoTable> _floor(List<(String, TableSectionRoomFramePreset?)> frames) => [
  for (final (i, f) in frames.indexed) ...[
    _t(
      's$i-a',
      'A$i',
      sectionId: 's$i',
      sectionName: f.$1,
      sectionOrder: i,
      x: 500,
      y: 500,
      frame: f.$2,
    ),
    _t(
      's$i-b',
      'B$i',
      effective: 'occupied',
      sectionId: 's$i',
      sectionName: f.$1,
      sectionOrder: i,
      x: 5000,
      y: 5000,
      frame: f.$2,
    ),
    _t(
      's$i-c',
      'C$i',
      sectionId: 's$i',
      sectionName: f.$1,
      sectionOrder: i,
      x: 9500,
      y: 9500,
      frame: f.$2,
    ),
  ],
];

class _FakeTablesRepo extends TablesRepository {
  _FakeTablesRepo(this.rows);
  final List<DemoTable> rows;
  @override
  Future<List<DemoTable>> loadTables() async => rows;
  @override
  Future<PosFloorSnapshot> loadFloorSnapshot() async =>
      PosFloorSnapshot(tables: rows, floorElements: const []);
}

class _Launcher extends StatelessWidget {
  const _Launcher();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open-picker'),
        onPressed: () => TablePickerSheet.show(context),
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

Future<void> _shot(
  WidgetTester tester, {
  required Locale locale,
  required String name,
  required List<(String, TableSectionRoomFramePreset?)> frames,
  Size size = const Size(1280, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      tablesRepositoryProvider.overrideWithValue(
        _FakeTablesRepo(_floor(frames)),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        key: UniqueKey(),
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        debugShowCheckedModeBanner: false,
        theme: posPremiumTheme(),
        home: const _Launcher(),
      ),
    ),
  );
  container
      .read(orderSetupControllerProvider.notifier)
      .setOrderType(OrderType.dineIn);
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
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

  const setA = <(String, TableSectionRoomFramePreset?)>[
    ('Standard', null),
    ('Square', TableSectionRoomFramePreset.square),
    ('Wide', TableSectionRoomFramePreset.wide),
  ];
  const setB = <(String, TableSectionRoomFramePreset?)>[
    ('Compact', TableSectionRoomFramePreset.compact),
    ('Portrait', TableSectionRoomFramePreset.portrait),
    ('Long corridor', TableSectionRoomFramePreset.longNarrow),
  ];

  testWidgets('picker frames set A en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      locale: const Locale('en'),
      name: 'pos_frames_a_en',
      frames: setA,
    );
  });

  testWidgets('picker frames set A ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      locale: const Locale('ar'),
      name: 'pos_frames_a_ar',
      frames: setA,
    );
  });

  testWidgets('picker frames set B en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      locale: const Locale('en'),
      name: 'pos_frames_b_en',
      frames: setB,
      size: const Size(1280, 3400),
    );
  });
}
