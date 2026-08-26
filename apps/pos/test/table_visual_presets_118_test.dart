import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorFixture,
        RestoflowFloorMaterial,
        RestoflowFloorPresetPainter,
        RestoflowTableShapePainter;
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, FloorPreset, OrderType, TableVisualPreset;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-VISUAL-LAYOUT-118 — the POS renders the SAME saved presets the
/// Dashboard configured: the section canvas paints the section's floor
/// style, every tile draws its shape inside the unchanged footprint, and
/// nothing about assignment / selection / group semantics changes.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async =>
      _handler(function, params);
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

DemoTable _t(
  String id,
  String label, {
  String effective = 'available',
  String? sectionId,
  String? sectionName,
  int? sectionOrder,
  int? x,
  int? y,
  TableVisualPreset preset = TableVisualPreset.classicRectTable,
  FloorPreset floor = FloorPreset.plainLight,
}) => DemoTable(
  table: DiningTable(
    tableId: id,
    label: label,
    organizationId: 'o',
    restaurantId: 'r',
    branchId: 'b',
    seats: 4,
    area: 'Main',
  ),
  status: tableStatusKindFor(effective),
  effectiveState: effective,
  sectionId: sectionId,
  sectionName: sectionName,
  sectionDisplayOrder: sectionOrder,
  layoutX: x,
  layoutY: y,
  visualPreset: preset,
  sectionFloorPreset: floor,
);

class _FakeTablesRepo extends TablesRepository {
  _FakeTablesRepo(this.rows);
  final List<DemoTable> rows;
  @override
  Future<List<DemoTable>> loadTables() async => rows;
  @override
  Future<PosFloorSnapshot> loadFloorSnapshot() async => PosFloorSnapshot(
    tables: rows,
    floorElements: const [
      PosFloorElement(
        id: 'w1',
        sectionId: 's1',
        kind: 'window',
        layoutX: 0,
        layoutY: 4500,
        widthNorm: 2400,
        heightNorm: 150,
        orientationQuarterTurns: 3,
      ),
    ],
  );
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

Future<ProviderContainer> _pumpPicker(
  WidgetTester tester, {
  required List<DemoTable> tables,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      tablesRepositoryProvider.overrideWithValue(_FakeTablesRepo(tables)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
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
  return container;
}

Finder _shapePainter(TableVisualPreset preset) => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter is RestoflowTableShapePainter &&
      (w.painter! as RestoflowTableShapePainter).preset == preset,
);

Finder _floorPainter(FloorPreset preset) => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter is RestoflowFloorPresetPainter &&
      (w.painter! as RestoflowFloorPresetPainter).preset == preset,
);

List<DemoTable> _floor() => [
  _t(
    'a1',
    'Alpha',
    sectionId: 's1',
    sectionName: 'Main Hall',
    sectionOrder: 0,
    x: 1000,
    y: 1000,
    preset: TableVisualPreset.roundTable,
    floor: FloorPreset.woodDark,
  ),
  _t(
    'a2',
    'Beta',
    effective: 'occupied',
    sectionId: 's1',
    sectionName: 'Main Hall',
    sectionOrder: 0,
    x: 6000,
    y: 6000,
    preset: TableVisualPreset.boothTable,
    floor: FloorPreset.woodDark,
  ),
  _t(
    'b1',
    'Gamma',
    sectionId: 's2',
    sectionName: 'Terrace',
    sectionOrder: 1,
    x: 8000,
    y: 8000,
  ),
];

void main() {
  group('model', () {
    test('defaults, copy carry and draft restore', () {
      final plain = _t('x', 'X');
      expect(plain.visualPreset, TableVisualPreset.classicRectTable);
      expect(plain.sectionFloorPreset, FloorPreset.plainLight);
      final styled = _t(
        'y',
        'Y',
        preset: TableVisualPreset.tableWithBarrels,
        floor: FloorPreset.stoneNeutral,
      );
      // The 027 re-wrap trap: the group projection must carry both fields.
      final projected = styled.copyWithGroupState(
        effectiveState: 'occupied',
        activeOrderCount: 2,
        status: TableStatusKind.occupied,
      );
      expect(projected.visualPreset, TableVisualPreset.tableWithBarrels);
      expect(projected.sectionFloorPreset, FloorPreset.stoneNeutral);
      // A captured draft restores with the safe defaults (presets are
      // re-read with the floor, never persisted as identity).
      final restored = DemoTable.fromJson(styled.toJson());
      expect(restored.visualPreset, TableVisualPreset.classicRectTable);
      expect(restored.sectionFloorPreset, FloorPreset.plainLight);
    });

    test('RealTablesRepository decodes the two keys tolerantly', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'tables': [
            {
              'id': 't1',
              'label': 'T1',
              'status': 'available',
              'visual_preset': 'booth_table',
              'section_floor_preset': 'tile_modern',
            },
            {'id': 't2', 'label': 'T2', 'status': 'available'},
            {
              'id': 't3',
              'label': 'T3',
              'status': 'available',
              'visual_preset': 'octagon',
              'section_floor_preset': 42,
            },
          ],
        },
      );
      final rows = await RealTablesRepository(t, _session).loadTables();
      final byId = {for (final r in rows) r.tableId: r};
      expect(byId['t1']!.visualPreset, TableVisualPreset.boothTable);
      expect(byId['t1']!.sectionFloorPreset, FloorPreset.tileModern);
      expect(byId['t2']!.visualPreset, TableVisualPreset.classicRectTable);
      expect(byId['t2']!.sectionFloorPreset, FloorPreset.plainLight);
      expect(byId['t3']!.visualPreset, TableVisualPreset.classicRectTable);
      expect(byId['t3']!.sectionFloorPreset, FloorPreset.plainLight);
    });

    test('splitTablesBySection exposes each section floor preset', () {
      final split = splitTablesBySection(_floor());
      expect(split.sections.map((s) => s.sectionId).toList(), ['s1', 's2']);
      expect(split.sections[0].floorPreset, FloorPreset.woodDark);
      expect(split.sections[1].floorPreset, FloorPreset.plainLight);
    });
  });

  group('table picker rendering', () {
    testWidgets('the canvas paints the section floor and each tile its shape; '
        'assignment is unchanged', (tester) async {
      final container = await _pumpPicker(tester, tables: _floor());
      expect(
        find.descendant(
          of: find.byKey(const Key('table-section-canvas-s1')),
          matching: _floorPainter(FloorPreset.woodDark),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('table-section-canvas-s2')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is RestoflowFloorPresetPainter,
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('table-floor-tile-a1')),
          matching: _shapePainter(TableVisualPreset.roundTable),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('table-floor-tile-a2')),
          matching: _shapePainter(TableVisualPreset.boothTable),
        ),
        findsOneWidget,
      );
      // 119A: the classic tile paints through the SAME shared painter now
      // (real chairs); geometry and interaction semantics unchanged.
      expect(
        find.descendant(
          of: find.byKey(const Key('table-floor-tile-b1')),
          matching: _shapePainter(TableVisualPreset.classicRectTable),
        ),
        findsOneWidget,
      );
      // 119A: the fixture's authoritative orientation reaches the widget.
      expect(
        tester
            .widget<RestoflowFloorFixture>(
              find.byKey(const Key('pos-floor-element-w1')),
            )
            .quarterTurns,
        3,
      );
      // 119D: the POS renders the shared MATERIAL scene — the wood-dark
      // section resolves warm wood for its tables with zero app plumbing.
      final a1Painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(const Key('table-floor-tile-a1')),
                      matching: _shapePainter(TableVisualPreset.roundTable),
                    ),
                  )
                  .painter!
              as RestoflowTableShapePainter;
      expect(a1Painter.material, RestoflowFloorMaterial.wood);
      // Occupied stays non-assignable regardless of its shape.
      await tester.tap(find.byKey(const Key('table-floor-tile-a2')));
      await tester.pumpAndSettle();
      expect(
        container.read(orderSetupControllerProvider).assignedTable,
        isNull,
      );
      // An available round table assigns exactly like a classic one.
      await tester.tap(find.byKey(const Key('table-floor-tile-a1')));
      await tester.pumpAndSettle();
      expect(
        container.read(orderSetupControllerProvider).assignedTable?.tableId,
        'a1',
      );
    });
  });
}
