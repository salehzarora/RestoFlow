@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// TABLE-FLOOR-LAYOUT-021 — LOCAL screenshot generator for the Dashboard
/// floor editor (not a regression test). Skipped unless run explicitly:
///   flutter test test/tables_floor_screenshots_test.dart \
///     --dart-define=DASH_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/table_floor_021/. Never committed,
/// never exercised on CI.
const bool _enabled = bool.fromEnvironment('DASH_SCREENSHOTS');

Future<void> _loadRealFonts() async {
  // The dashboard theme rides the default family + system fallbacks, so real
  // Latin + Arabic glyph files are loaded AS the default test family.
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

DashboardTable _t(
  String id,
  String label, {
  DiningTableStatus status = DiningTableStatus.available,
  String? effective,
  int active = 0,
  String? group,
  String? sectionId,
  String? sectionName,
  int? sectionOrder,
  int? x,
  int? y,
}) => DashboardTable(
  id: id,
  label: label,
  seats: 4,
  status: status,
  isActive: true,
  branchId: 'b',
  activeOrderCount: active,
  effectiveState: effective,
  groupId: group,
  sectionId: sectionId,
  sectionName: sectionName,
  sectionDisplayOrder: sectionOrder,
  layoutX: x,
  layoutY: y,
);

class _ShotRepo extends InMemoryTablesStore {
  @override
  Future<AdminResult<TablesFloorSnapshot>> load() async => Success(
    TablesFloorSnapshot(
      sections: const [
        DashboardTableSection(
          id: 's1',
          name: 'الصالة الرئيسية',
          displayOrder: 0,
          isActive: true,
          branchId: 'b',
        ),
        DashboardTableSection(
          id: 's2',
          name: 'التراس',
          displayOrder: 1,
          isActive: true,
          branchId: 'b',
        ),
      ],
      tables: [
        _t(
          't1',
          'ط١',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 800,
          y: 900,
        ),
        _t(
          't2',
          'ط٢',
          status: DiningTableStatus.occupied,
          effective: 'occupied',
          active: 2,
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 4200,
          y: 700,
        ),
        _t(
          't3',
          'ط٣',
          status: DiningTableStatus.reserved,
          effective: 'reserved',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 8600,
          y: 1200,
        ),
        _t(
          't4',
          'ط٤',
          status: DiningTableStatus.outOfService,
          effective: 'out_of_service',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 1400,
          y: 7800,
        ),
        _t(
          't5',
          'ط٥',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 5200,
          y: 8200,
        ),
        _t(
          't6',
          'ط٦',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 8800,
          y: 8200,
        ),
        _t(
          't7',
          'ت١',
          sectionId: 's2',
          sectionName: 'التراس',
          sectionOrder: 1,
          x: 2500,
          y: 4500,
        ),
        _t('t8', 'ت٢', sectionId: 's2', sectionName: 'التراس', sectionOrder: 1),
        _t('t9', 'ق١'),
      ],
    ),
  );
}

Future<void> _shot(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required String name,
  bool arrange = true,
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
  if (arrange) {
    await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/table_floor_021/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('arrange 1500 ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1500, 2600),
      locale: const Locale('ar'),
      name: 'arrange_1500_ar',
    );
  });

  testWidgets('arrange 1500 en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1500, 2600),
      locale: const Locale('en'),
      name: 'arrange_1500_en',
    );
  });

  testWidgets('view 1500 ar (read-only)', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1500, 2600),
      locale: const Locale('ar'),
      name: 'view_1500_ar',
      arrange: false,
    );
  });
}
