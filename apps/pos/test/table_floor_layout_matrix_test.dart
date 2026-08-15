import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-FLOOR-LAYOUT-021 §I — the responsive matrix for the POS floor map.
///
/// The picker with a REALISTIC sectioned floor (two sections, all four
/// statuses, a linked group, an unplaced table, legacy area tables) must lay
/// out with ZERO overflow at every supported POS width × locale, at 2×
/// accessibility text scale, and with IDENTICAL physical tile geometry under
/// LTR and RTL (the room never mirrors — only the words do).
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
    seats: 6,
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

/// Two sections + legacy: every status, a linked pair, an unplaced table.
List<DemoTable> _floor() => [
  _t(
    'a1',
    'طاولة ١',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 500,
    y: 500,
  ),
  _t(
    'a2',
    'T2',
    effective: 'occupied',
    active: 2,
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 5000,
    y: 500,
  ),
  _t(
    'a3',
    'T3',
    effective: 'reserved',
    manual: 'reserved',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 9500,
    y: 500,
  ),
  _t(
    'a4',
    'T4',
    effective: 'out_of_service',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 500,
    y: 9500,
  ),
  _t(
    'a5',
    'T5',
    group: 'g1',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 5000,
    y: 9500,
  ),
  _t(
    'a6',
    'T6',
    group: 'g1',
    sectionId: 's1',
    sectionName: 'الصالة الرئيسية',
    sectionOrder: 0,
    x: 9500,
    y: 9500,
  ),
  _t(
    'b1',
    'P1',
    sectionId: 's2',
    sectionName: 'Terrace',
    sectionOrder: 1,
    x: 2500,
    y: 5000,
  ),
  _t('b2', 'P2', sectionId: 's2', sectionName: 'Terrace', sectionOrder: 1),
  _t('l1', 'L1'),
  _t('l2', 'L2', area: 'Patio', active: 1),
];

class _FakeTablesRepo extends TablesRepository {
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

Future<List<FlutterErrorDetails>> _pumpPicker(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  double textScale = 1.0,
}) async {
  // Paint-time overflow never reaches takeException — collect through
  // FlutterError.onError and restore the handler BEFORE any expect.
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previous);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
        // A fresh Navigator per pump: without this, a SECOND pump in the same
        // test reuses the element tree and the previous locale's still-open
        // sheet keeps covering the launcher.
        key: UniqueKey(),
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const _Launcher(),
      ),
    ),
  );
  container
      .read(orderSetupControllerProvider.notifier)
      .setOrderType(OrderType.dineIn);
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
  FlutterError.onError = previous;
  return errors;
}

void _expectClean(List<FlutterErrorDetails> errors, String scene) {
  expect(
    errors.where((e) => '${e.exception}'.contains('overflowed')),
    isEmpty,
    reason: 'overflow in $scene',
  );
  expect(errors, isEmpty, reason: 'unexpected errors in $scene');
}

void main() {
  const sizes = [
    Size(430, 932),
    Size(700, 1000),
    Size(1024, 600),
    Size(1280, 800),
    Size(1600, 900),
  ];
  const locales = [Locale('en'), Locale('ar'), Locale('he')];

  for (final size in sizes) {
    for (final locale in locales) {
      testWidgets('floor picker lays out clean at ${size.width.toInt()}x'
          '${size.height.toInt()} ${locale.languageCode}', (tester) async {
        final errors = await _pumpPicker(tester, size: size, locale: locale);
        _expectClean(errors, '$size $locale');
        // Both section canvases exist; the legacy zone survives below.
        expect(
          find.byKey(const Key('table-section-canvas-s1')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('table-section-zone-s2')), findsOneWidget);
        expect(find.byKey(const Key('table-tile-l1')), findsOneWidget);
      });
    }
  }

  testWidgets('floor picker survives 2× accessibility text scale (ar)', (
    tester,
  ) async {
    final errors = await _pumpPicker(
      tester,
      size: const Size(700, 1000),
      locale: const Locale('ar'),
      textScale: 2.0,
    );
    _expectClean(errors, '2x ar');
    expect(find.byKey(const Key('table-section-canvas-s1')), findsOneWidget);
  });

  // One pump per test (a second pump in the same body leaves the replaced
  // tree's auto-dispose timer pending at teardown); the recorded en offsets
  // feed the ar comparison in the next test.
  final parity = <String, List<Offset>>{};
  Future<List<Offset>> placedOffsets(WidgetTester tester, Locale locale) async {
    final errors = await _pumpPicker(
      tester,
      size: const Size(1280, 800),
      locale: locale,
    );
    _expectClean(errors, 'parity $locale');
    final canvasOrigin = tester.getTopLeft(
      find.byKey(const Key('table-section-canvas-s1')),
    );
    return [
      for (final id in ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'])
        tester.getTopLeft(find.byKey(Key('table-floor-tile-$id'))) -
            canvasOrigin,
    ];
  }

  testWidgets('parity: record the LTR (en) physical tile geometry', (
    tester,
  ) async {
    parity['en'] = await placedOffsets(tester, const Locale('en'));
    expect(parity['en'], hasLength(6));
  });

  testWidgets('parity: the RTL (ar) tile geometry is IDENTICAL — the room '
      'never mirrors', (tester) async {
    final ar = await placedOffsets(tester, const Locale('ar'));
    expect(ar, parity['en'], reason: 'the room must not mirror under RTL');
  });
}
