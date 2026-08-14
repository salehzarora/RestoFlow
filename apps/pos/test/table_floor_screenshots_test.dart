@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/design/pos_theme.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-FLOOR-LAYOUT-021 — LOCAL screenshot generator for the POS floor-map
/// picker (not a regression test). Skipped everywhere unless run explicitly:
///   flutter test test/table_floor_screenshots_test.dart \
///     --dart-define=POS_SCREENSHOTS=true --update-goldens
/// which WRITES the PNGs under test/goldens/table_floor_021/. Never committed,
/// never exercised on CI.
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
  // The default family in the test env, so unthemed text renders real glyphs.
  await load('Roboto', ['Rubik-Regular.ttf', 'IBMPlexSansArabic-Regular.ttf']);

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

DemoTable _t(
  String id,
  String label, {
  String? area = 'Main',
  String effective = 'available',
  String manual = 'available',
  int active = 0,
  String? group,
  String? sectionId,
  String? sectionName,
  int? sectionOrder,
  int? x,
  int? y,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    seats: 4,
    area: area,
  ),
  status: tableStatusKindFor(effective),
  manualStatus: manual,
  effectiveState: effective,
  activeOrderCount: active,
  groupId: group,
  sectionId: sectionId,
  sectionName: sectionName,
  sectionDisplayOrder: sectionOrder,
  layoutX: x,
  layoutY: y,
);

List<DemoTable> _floor() => [
  _t(
    'a1',
    'ط١',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 800,
    y: 900,
  ),
  _t(
    'a2',
    'ط٢',
    effective: 'occupied',
    active: 2,
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 4200,
    y: 700,
  ),
  _t(
    'a3',
    'ط٣',
    effective: 'reserved',
    manual: 'reserved',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 8600,
    y: 1200,
  ),
  _t(
    'a4',
    'ط٤',
    effective: 'out_of_service',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 1400,
    y: 7800,
  ),
  _t(
    'a5',
    'ط٥',
    group: 'g1',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 5200,
    y: 8200,
  ),
  _t(
    'a6',
    'ط٦',
    group: 'g1',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 8800,
    y: 8200,
  ),
  _t(
    'b1',
    'ت١',
    sectionId: 's2',
    sectionName: 'التراس',
    sectionOrder: 1,
    x: 2500,
    y: 4500,
  ),
  _t('b2', 'ت٢', sectionId: 's2', sectionName: 'التراس', sectionOrder: 1),
  _t('l1', 'ق١'),
  _t('l2', 'ق٢', area: 'Patio', active: 1),
];

class _FakeTablesRepo implements TablesRepository {
  _FakeTablesRepo(this.rows);
  final List<DemoTable> rows;
  @override
  Future<List<DemoTable>> loadTables() async => rows;
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
  required Size size,
  required Locale locale,
  required String name,
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
      tablesRepositoryProvider.overrideWithValue(_FakeTablesRepo(_floor())),
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
    matchesGoldenFile('goldens/table_floor_021/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    await _loadRealFonts();
  });

  testWidgets('picker 1280 ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('ar'),
      name: 'picker_1280_ar',
    );
  });

  testWidgets('picker 1024x600 ar', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1024, 600),
      locale: const Locale('ar'),
      name: 'picker_1024x600_ar',
    );
  });

  testWidgets('picker 430 ar narrow', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(430, 932),
      locale: const Locale('ar'),
      name: 'picker_430_ar',
    );
  });

  testWidgets('picker 1280 en', skip: !_enabled, (tester) async {
    await _shot(
      tester,
      size: const Size(1280, 800),
      locale: const Locale('en'),
      name: 'picker_1280_en',
    );
  });
}
