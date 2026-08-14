import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show RestoflowFloorClusterSeam, kRestoflowFloorSectionAspect;
import 'package:restoflow_domain/restoflow_domain.dart'
    show floorTableRoomRect;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminResult;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// TABLE-FLOOR-LAYOUT-021 §I — the Dashboard floor editor responsive matrix:
/// arrange mode with two sections and eight tables (all four statuses, a
/// linked pair, an unassigned table) lays out with ZERO overflow across
/// widths and locales, and the canvas geometry stays PHYSICAL under RTL.
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

class _MatrixRepo extends InMemoryTablesStore {
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
          name: 'Terrace',
          displayOrder: 1,
          isActive: true,
          branchId: 'b',
        ),
      ],
      tables: [
        _t(
          't1',
          'طاولة ١',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 500,
          y: 500,
        ),
        _t(
          't2',
          'T2',
          status: DiningTableStatus.occupied,
          effective: 'occupied',
          active: 2,
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 5000,
          y: 500,
        ),
        _t(
          't3',
          'T3',
          status: DiningTableStatus.reserved,
          effective: 'reserved',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 9500,
          y: 500,
        ),
        _t(
          't4',
          'T4',
          status: DiningTableStatus.outOfService,
          effective: 'out_of_service',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 500,
          y: 9500,
        ),
        _t(
          't5',
          'T5',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 5000,
          y: 9500,
        ),
        _t(
          't6',
          'T6',
          group: 'g1',
          sectionId: 's1',
          sectionName: 'الصالة الرئيسية',
          sectionOrder: 0,
          x: 9500,
          y: 9500,
        ),
        _t(
          't7',
          'P1',
          sectionId: 's2',
          sectionName: 'Terrace',
          sectionOrder: 1,
          x: 2500,
          y: 5000,
        ),
        _t(
          't8',
          'P2',
          sectionId: 's2',
          sectionName: 'Terrace',
          sectionOrder: 1,
        ),
        _t('t9', 'U1'), // unassigned fallback zone
      ],
    ),
  );
}

Future<List<FlutterErrorDetails>> _pump(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  bool arrange = false,
}) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previous);

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
      home: Scaffold(body: TablesScreen(repository: _MatrixRepo())),
    ),
  );
  await tester.pumpAndSettle();
  if (arrange) {
    await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
    await tester.pumpAndSettle();
  }
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
  const sizes = [Size(800, 5200), Size(1100, 5200), Size(1500, 5200)];
  const locales = [Locale('en'), Locale('ar'), Locale('he')];

  for (final size in sizes) {
    for (final locale in locales) {
      testWidgets(
        'floor editor (arrange ON) lays out clean at ${size.width.toInt()} '
        '${locale.languageCode}',
        (tester) async {
          final errors = await _pump(
            tester,
            size: size,
            locale: locale,
            arrange: true,
          );
          _expectClean(errors, '$size $locale');
          expect(find.byKey(const Key('floor-canvas-s1')), findsOneWidget);
          expect(find.byKey(const Key('floor-canvas-s2')), findsOneWidget);
          // Drag handles exist in arrange mode; the unassigned zone survives.
          expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
          expect(find.byKey(const Key('floor-table-t9')), findsOneWidget);
        },
      );
    }
  }

  final parity = <String, List<Offset>>{};
  Future<List<Offset>> offsets(WidgetTester tester, Locale locale) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: locale,
    );
    _expectClean(errors, 'parity $locale');
    final origin = tester.getTopLeft(find.byKey(const Key('floor-canvas-s1')));
    return [
      for (final id in ['t1', 't2', 't3', 't4', 't5', 't6'])
        tester.getTopLeft(find.byKey(Key('floor-table-$id'))) - origin,
    ];
  }

  testWidgets('parity: record the LTR (en) canvas geometry', (tester) async {
    parity['en'] = await offsets(tester, const Locale('en'));
    expect(parity['en'], hasLength(6));
  });

  testWidgets('parity: the RTL (ar) canvas geometry is IDENTICAL', (
    tester,
  ) async {
    final ar = await offsets(tester, const Locale('ar'));
    expect(ar, parity['en'], reason: 'the room must not mirror under RTL');
  });

  testWidgets('027 LINKED (Dashboard, read-only): grouped members render as a '
      'seamed cluster and are NOT draggable while linked', (tester) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: const Locale('en'),
      arrange: true,
    );
    _expectClean(errors, 'dashboard linked');
    // t5+t6 share group g1 in the fixture: one seam behind them.
    expect(find.byType(RestoflowFloorClusterSeam), findsOneWidget);
    // Unlinked tables keep their drag handles; linked members do not (base
    // coordinates are preserved for the unlink restore).
    expect(find.byKey(const Key('floor-drag-t1')), findsOneWidget);
    expect(find.byKey(const Key('floor-drag-t5')), findsNothing);
    expect(find.byKey(const Key('floor-drag-t6')), findsNothing);
    // Both members still render (derived positions, same section).
    expect(find.byKey(const Key('floor-table-t5')), findsOneWidget);
    expect(find.byKey(const Key('floor-table-t6')), findsOneWidget);
    // Physically joined: the derived rects sit one seam apart.
    final r5 = tester.getRect(find.byKey(const Key('floor-table-t5')));
    final r6 = tester.getRect(find.byKey(const Key('floor-table-t6')));
    expect((r6.left - r5.right).abs(), lessThan(r5.width));
    expect((r6.top - r5.top).abs(), lessThan(1.0));
  });

  testWidgets('027 CONTRACT PARITY: the rendered tile rect equals the shared '
      'room-unit contract to <=0.5px (transitively equal to POS/Move)', (
    tester,
  ) async {
    final errors = await _pump(
      tester,
      size: const Size(1500, 5200),
      locale: const Locale('en'),
    );
    _expectClean(errors, 'contract parity');
    final canvasRect = tester.getRect(find.byKey(const Key('floor-canvas-s1')));
    // t1 is stored at (500, 500).
    final room = floorTableRoomRect(500, 500);
    final expected = Rect.fromLTWH(
      canvasRect.left + room.left * canvasRect.width / 10000,
      canvasRect.top + room.top * canvasRect.height / 10000,
      room.width * canvasRect.width / 10000,
      room.height * canvasRect.height / 10000,
    );
    final actual = tester.getRect(find.byKey(const Key('floor-table-t1')));
    expect((actual.left - expected.left).abs(), lessThanOrEqualTo(0.5));
    expect((actual.top - expected.top).abs(), lessThanOrEqualTo(0.5));
    expect((actual.width - expected.width).abs(), lessThanOrEqualTo(0.5));
    expect((actual.height - expected.height).abs(), lessThanOrEqualTo(0.5));
    // The compact aspect token holds.
    expect(
      canvasRect.width / canvasRect.height,
      closeTo(kRestoflowFloorSectionAspect, 0.01),
    );
  });
}
