import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/tables/table_models.dart';
import 'package:restoflow_dashboard/src/tables/tables_repository.dart';
import 'package:restoflow_dashboard/src/tables/tables_screen.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorMaterial,
        RestoflowFloorPresetPainter,
        RestoflowTableShapePainter;
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualMaterial, TableVisualPreset;
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminScope;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-VISUAL-LAYOUT-118 — the Dashboard as the CONTROL CENTER of the
/// floor look: the table dialog picks a shape with a live preview, the
/// section header (arrange mode) picks the floor style, both persist through
/// their DEDICATED setters (never the full-replace upserts), and the editor
/// canvas renders the SAME shared presets the POS/kiosk render.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

Map<String, dynamic> _listWithPresets() => {
  'ok': true,
  'entity': 'table',
  'tables': [
    {
      'id': 't-1',
      'label': 'T1',
      'seats': 4,
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
      'section_id': 's-1',
      'section_name': 'Hall',
      'section_display_order': 0,
      'layout_x': 1000,
      'layout_y': 1000,
      'visual_preset': 'round_table',
    },
    {
      // A legacy row: no preset key at all.
      'id': 't-2',
      'label': 'T2',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
    },
    {
      // A key this client does not know: the safe default, never a failure.
      'id': 't-3',
      'label': 'T3',
      'status': 'available',
      'branch_id': 'b-1',
      'is_active': true,
      'visual_preset': 'hexagon_table',
    },
  ],
  'sections': [
    {
      'id': 's-1',
      'name': 'Hall',
      'display_order': 0,
      'is_active': true,
      'branch_id': 'b-1',
      'floor_preset': 'wood_dark',
    },
    {
      'id': 's-2',
      'name': 'Terrace',
      'display_order': 1,
      'is_active': true,
      'branch_id': 'b-1',
    },
  ],
};

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

Future<void> _pump(WidgetTester tester, TablesAdminRepository repo) async {
  tester.view.physicalSize = const Size(1400, 4600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(body: TablesScreen(repository: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('model defaults + wire decode', () {
    test('a table/section without a preset key decodes to the defaults', () {
      const table = DashboardTable(
        id: 't',
        label: 'T',
        status: DiningTableStatus.available,
        isActive: true,
        branchId: 'b',
      );
      const section = DashboardTableSection(
        id: 's',
        name: 'S',
        displayOrder: 0,
        isActive: true,
        branchId: 'b',
      );
      expect(table.visualPreset, TableVisualPreset.classicRectTable);
      expect(section.floorPreset, FloorPreset.plainLight);
      // Copies carry the preset (the 027 re-wrap trap).
      expect(
        table
            .copyWithGroupState(effectiveState: 'occupied', activeOrderCount: 1)
            .visualPreset,
        TableVisualPreset.classicRectTable,
      );
      expect(
        table
            .copyWith(visualPreset: TableVisualPreset.boothTable)
            .copyWithPlacement(sectionId: 's', layoutX: 1, layoutY: 2)
            .visualPreset,
        TableVisualPreset.boothTable,
      );
      expect(
        section.copyWith(floorPreset: FloorPreset.tileModern).floorPreset,
        FloorPreset.tileModern,
      );
    });

    test('load decodes visual_preset / floor_preset tolerantly', () async {
      final t = _FakeTransport((fn, p) => _listWithPresets());
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final snapshot = (await repo.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      final byId = {for (final x in snapshot.tables) x.id: x};
      expect(byId['t-1']!.visualPreset, TableVisualPreset.roundTable);
      expect(byId['t-2']!.visualPreset, TableVisualPreset.classicRectTable);
      expect(byId['t-3']!.visualPreset, TableVisualPreset.classicRectTable);
      final sections = {for (final s in snapshot.sections) s.id: s};
      expect(sections['s-1']!.floorPreset, FloorPreset.woodDark);
      expect(sections['s-2']!.floorPreset, FloorPreset.plainLight);
    });

    test('the setters call the DEDICATED RPCs with the wire keys', () async {
      final t = _FakeTransport(
        (fn, p) => {'ok': true, 'idempotent_replay': false},
      );
      final repo = SupabaseTablesRepository(
        transport: t,
        scope: AdminScope.demo,
        currentUserId: () => 'u',
      );
      final a = await repo.setTableVisualPreset(
        't-1',
        TableVisualPreset.tableWithBarrels,
      );
      final b = await repo.setSectionFloorPreset(
        's-1',
        FloorPreset.stoneNeutral,
      );
      expect(a.fold((_) => true, (_) => false), isTrue);
      expect(b.fold((_) => true, (_) => false), isTrue);
      expect(t.calls.map((c) => c.$1).toList(), [
        'set_table_visual_preset',
        'set_table_section_floor_preset',
      ]);
      expect(t.calls[0].$2['p_table_id'], 't-1');
      expect(t.calls[0].$2['p_visual_preset'], 'table_with_barrels');
      expect(t.calls[0].$2['p_client_request_id'], isA<String>());
      expect(t.calls[1].$2['p_section_id'], 's-1');
      expect(t.calls[1].$2['p_floor_preset'], 'stone_neutral');
      // Never through the full-replace upserts.
      expect(t.calls.any((c) => c.$1.startsWith('upsert_')), isFalse);
    });

    test('the in-memory demo store persists both presets', () async {
      final store = InMemoryTablesStore();
      await store.setTableVisualPreset(
        'demo-table-1',
        TableVisualPreset.roundTable,
      );
      await store.setSectionFloorPreset(
        'demo-section-2',
        FloorPreset.tileModern,
      );
      final snapshot = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        snapshot.tables.firstWhere((t) => t.id == 'demo-table-1').visualPreset,
        TableVisualPreset.roundTable,
      );
      expect(
        snapshot.sections
            .firstWhere((s) => s.id == 'demo-section-2')
            .floorPreset,
        FloorPreset.tileModern,
      );
    });
  });

  group('TablesScreen control center', () {
    testWidgets('the default floor paints NO floor-preset painter; tables '
        'paint through the shared painter (119A realism)', (tester) async {
      final store = InMemoryTablesStore();
      // 120B: give one demo table an explicit persisted material and prove
      // it reaches the shared painter (Auto keeps covering the rest).
      final demoId = ((await store.load()).fold(
        (s) => s,
        (f) => throw StateError('load'),
      )).tables.first.id;
      await store.setTableVisualMaterial(
        demoId,
        TableVisualMaterial.rusticWood,
      );
      await _pump(tester, store);
      // 119A: classic tables now render real chairs through the ONE shared
      // painter — the pre-118 "no painter" promise is deliberately
      // superseded; the floor itself stays plain by default.
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowTableShapePainter,
        ),
        findsWidgets,
      );
      // 119D: the Dashboard previews the shared MATERIAL scene too — every
      // mounted table painter carries a resolved material.
      final materials = <RestoflowFloorMaterial>{};
      for (final paint in tester.widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowTableShapePainter,
        ),
      )) {
        final m = (paint.painter! as RestoflowTableShapePainter).material;
        expect(m, isNotNull);
        materials.add(m!);
      }
      // 120B: the explicit persisted material is among the rendered ones.
      expect(materials, contains(TableVisualMaterial.rusticWood));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RestoflowFloorPresetPainter,
        ),
        findsNothing,
      );
    });

    testWidgets('the table dialog previews the chosen shape live and saves it '
        'through the dedicated setter', (tester) async {
      final store = InMemoryTablesStore();
      await _pump(tester, store);
      await tester.tap(find.byKey(const Key('table-edit-demo-table-1')));
      await tester.pumpAndSettle();
      // The picker + a preview tile showing the CURRENT (classic) shape.
      expect(
        find.byKey(const Key('table-visual-preset-field')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('table-visual-preset-preview')), findsOne);
      expect(_shapePainter(TableVisualPreset.roundTable), findsNothing);
      await tester.tap(find.byKey(const Key('table-visual-preset-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Round table').last);
      await tester.pumpAndSettle();
      // Live preview BEFORE saving. 120C: the material swatch row previews
      // the SAME chosen shape too, so several round painters are correct
      // now — the pre-120C "exactly one" is deliberately superseded.
      expect(_shapePainter(TableVisualPreset.roundTable), findsWidgets);
      await tester.tap(find.byKey(const Key('table-dialog-save')));
      await tester.pumpAndSettle();
      final saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.tables.firstWhere((t) => t.id == 'demo-table-1').visualPreset,
        TableVisualPreset.roundTable,
      );
      // The floor map tile now renders the round shape.
      expect(
        find.descendant(
          of: find.byKey(const Key('floor-table-demo-table-1')),
          matching: _shapePainter(TableVisualPreset.roundTable),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the section header picks a floor style in arrange mode and '
        'only that canvas repaints', (tester) async {
      final store = InMemoryTablesStore();
      await _pump(tester, store);
      expect(
        find.byKey(const Key('section-floor-preset-demo-section-1')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('tables-arrange-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('section-floor-preset-demo-section-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('floor-preset-wood_dark-demo-section-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('floor-canvas-demo-section-1')),
          matching: _floorPainter(FloorPreset.woodDark),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('floor-canvas-demo-section-2')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is RestoflowFloorPresetPainter,
          ),
        ),
        findsNothing,
      );
      final saved = (await store.load()).fold(
        (s) => s,
        (f) => fail('expected success'),
      );
      expect(
        saved.sections.firstWhere((s) => s.id == 'demo-section-1').floorPreset,
        FloorPreset.woodDark,
      );
    });
  });
}
