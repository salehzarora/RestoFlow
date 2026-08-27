import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorClusterSeam,
        RestoflowFloorFixture,
        RestoflowTableShapePainter,
        kRestoflowFloorSectionAspect;
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        DiningTable,
        OrderType,
        TableVisualMaterial,
        floorElementRoomRect,
        floorTableRoomRect;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/table_move_repository.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/table_move_controller.dart';
import 'package:restoflow_pos/src/widgets/move_table_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_group_detail_sheet.dart';
import 'package:restoflow_pos/src/widgets/table_picker_sheet.dart';

/// TABLE-FLOOR-LAYOUT-021 — the POS side of the saved floor layout.
///
/// First-class sections render as REAL floor-map canvases (owner order, saved
/// normalized placements, PHYSICAL coordinates — never RTL-mirrored); legacy
/// unsectioned tables keep the pre-existing area zones; reserved is a DISTINCT
/// display status that stays non-assignable; grouped members on a canvas open
/// the group-detail sheet and never assign directly. The Move Table sheet
/// renders the same saved layout with its own selection semantics.
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
  TableVisualMaterial? material,
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
  visualMaterial: material,
);

class _FakeTablesRepo extends TablesRepository {
  _FakeTablesRepo(this.rows, {this.elements = const []});

  List<DemoTable> rows;

  /// 027: the visual fixture catalog riding the same read.
  List<PosFloorElement> elements;

  @override
  Future<List<DemoTable>> loadTables() async => rows;

  @override
  Future<PosFloorSnapshot> loadFloorSnapshot() async =>
      PosFloorSnapshot(tables: rows, floorElements: elements);
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
  List<PosFloorElement> elements = const [],
  Locale locale = const Locale('en'),
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
      tablesRepositoryProvider.overrideWithValue(
        _FakeTablesRepo(tables, elements: elements),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
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
  return container;
}

/// A picker fixture: section s1 "Main Hall" (order 0) with a placed and an
/// unplaced table, section s2 "Terrace" (order 1) with one placed table, and
/// one legacy area table.
List<DemoTable> _sectionedFloor() => [
  _t(
    'a1',
    'Alpha',
    sectionId: 's1',
    sectionName: 'Main Hall',
    sectionOrder: 0,
    x: 1000,
    y: 1000,
    material: TableVisualMaterial.rusticWood,
  ),
  _t('a2', 'Beta', sectionId: 's1', sectionName: 'Main Hall', sectionOrder: 0),
  _t(
    'b1',
    'Gamma',
    sectionId: 's2',
    sectionName: 'Terrace',
    sectionOrder: 1,
    x: 8000,
    y: 8000,
  ),
  _t('l1', 'T1'),
];

void main() {
  group('splitTablesBySection (pure)', () {
    test('sections come out in owner order; the rest is legacy', () {
      final split = splitTablesBySection(_sectionedFloor());
      expect(split.sections.map((s) => s.sectionId).toList(), ['s1', 's2']);
      expect(split.sections.first.sectionName, 'Main Hall');
      expect(split.sections.first.tables.map((t) => t.tableId).toList(), [
        'a1',
        'a2',
      ]);
      expect(split.legacy.map((t) => t.tableId).toList(), ['l1']);
    });

    test('a missing display order sorts after ordered sections, by name', () {
      final split = splitTablesBySection([
        _t('z1', 'Z', sectionId: 'sz', sectionName: 'Zeta'),
        _t('y1', 'Y', sectionId: 'sy', sectionName: 'Yard'),
        _t('a1', 'A', sectionId: 'sa', sectionName: 'Annex', sectionOrder: 3),
      ]);
      expect(split.sections.map((s) => s.sectionId).toList(), [
        'sa',
        'sy',
        'sz',
      ]);
    });
  });

  group('picker: section canvases', () {
    testWidgets('sections render as canvases in owner order; unplaced tables '
        'flow in the strip; legacy keeps its area zone', (tester) async {
      await _pumpPicker(tester, tables: _sectionedFloor());
      expect(find.byKey(const Key('table-section-zone-s1')), findsOneWidget);
      expect(find.byKey(const Key('table-section-canvas-s1')), findsOneWidget);
      expect(find.byKey(const Key('table-section-zone-s2')), findsOneWidget);
      // Owner order: Main Hall above Terrace.
      expect(
        tester.getTopLeft(find.byKey(const Key('table-section-zone-s1'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('table-section-zone-s2'))).dy,
        ),
      );
      // Placed + unplaced sectioned tables both render as floor tiles.
      expect(find.byKey(const Key('table-floor-tile-a1')), findsOneWidget);
      expect(find.byKey(const Key('table-floor-tile-a2')), findsOneWidget);
      // The legacy table keeps the pre-existing area-zone tile, not a floor
      // tile.
      expect(find.byKey(const Key('table-tile-l1')), findsOneWidget);
      expect(find.byKey(const Key('table-floor-tile-l1')), findsNothing);
    });

    testWidgets('tapping an AVAILABLE canvas tile assigns it and closes the '
        'sheet', (tester) async {
      final container = await _pumpPicker(tester, tables: _sectionedFloor());
      await tester.tap(find.byKey(const Key('table-floor-tile-a1')));
      await tester.pumpAndSettle();
      expect(
        container.read(orderSetupControllerProvider).assignedTable?.tableId,
        'a1',
      );
      expect(find.byKey(const Key('table-section-canvas-s1')), findsNothing);
    });

    testWidgets('a RESERVED table is a distinct visual and is NOT assignable', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final container = await _pumpPicker(
        tester,
        tables: [
          _t(
            'r1',
            'Rho',
            effective: 'reserved',
            manual: 'reserved',
            sectionId: 's1',
            sectionName: 'Main Hall',
            sectionOrder: 0,
            x: 2000,
            y: 2000,
          ),
        ],
      );
      // Legend swatch + the tile footnote both say Reserved (never colour
      // alone; the tile also carries its own glyph).
      expect(find.text(l10n.posTableStateReserved), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('table-floor-tile-r1')));
      await tester.pumpAndSettle();
      // Nothing assigned; the sheet stays open.
      expect(
        container.read(orderSetupControllerProvider).assignedTable,
        isNull,
      );
      expect(find.byKey(const Key('table-section-canvas-s1')), findsOneWidget);
    });

    testWidgets('a grouped member on the canvas opens the group-detail sheet '
        'and never assigns directly', (tester) async {
      final container = await _pumpPicker(
        tester,
        tables: [
          for (final t in withGroupAggregation([
            _t(
              'm1',
              'M1',
              group: 'g1',
              sectionId: 's1',
              sectionName: 'Main Hall',
              sectionOrder: 0,
              x: 1000,
              y: 1000,
            ),
            _t('m2', 'M2', group: 'g1'),
          ]))
            t,
        ],
      );
      await tester.tap(find.byKey(const Key('table-floor-tile-m1')));
      await tester.pumpAndSettle();
      expect(find.byType(TableGroupDetailSheet), findsOneWidget);
      expect(
        container.read(orderSetupControllerProvider).assignedTable,
        isNull,
      );
    });

    testWidgets('027 CONTRACT PARITY: the picker tile rect equals the shared '
        'room-unit contract to <=0.5px (transitively equal to Dashboard)', (
      tester,
    ) async {
      await _pumpPicker(tester, tables: _sectionedFloor());
      final canvasRect = tester.getRect(
        find.byKey(const Key('table-section-canvas-s1')),
      );
      // a1 is stored at (1000, 1000).
      final room = floorTableRoomRect(1000, 1000);
      final expected = Rect.fromLTWH(
        canvasRect.left + room.left * canvasRect.width / 10000,
        canvasRect.top + room.top * canvasRect.height / 10000,
        room.width * canvasRect.width / 10000,
        room.height * canvasRect.height / 10000,
      );
      final actual = tester.getRect(
        find.byKey(const Key('table-floor-tile-a1')),
      );
      expect((actual.left - expected.left).abs(), lessThanOrEqualTo(0.5));
      expect((actual.top - expected.top).abs(), lessThanOrEqualTo(0.5));
      expect((actual.width - expected.width).abs(), lessThanOrEqualTo(0.5));
      expect((actual.height - expected.height).abs(), lessThanOrEqualTo(0.5));
      expect(
        canvasRect.width / canvasRect.height,
        closeTo(kRestoflowFloorSectionAspect, 0.01),
      );
    });

    testWidgets('AR: the canvas placement is PHYSICAL — the room does not '
        'mirror under RTL', (tester) async {
      await _pumpPicker(
        tester,
        tables: _sectionedFloor(),
        locale: const Locale('ar'),
      );
      final canvas = find.byKey(const Key('table-section-canvas-s1'));
      // Alpha is saved at x=1000/10000 — the physical LEFT edge. Under an RTL
      // locale it must STAY on the physical left (only text localizes).
      expect(
        tester.getCenter(find.byKey(const Key('table-floor-tile-a1'))).dx,
        lessThan(tester.getCenter(canvas).dx),
      );
    });
  });

  group('027 linked visual grouping (derived, exact restore)', () {
    List<DemoTable> fixture({String? group}) => [
      _t(
        'a1',
        'Alpha',
        sectionId: 's1',
        sectionName: 'Main Hall',
        sectionOrder: 0,
        x: 1000,
        y: 1000,
        group: group,
      ),
      _t(
        'a2',
        'Beta',
        sectionId: 's1',
        sectionName: 'Main Hall',
        sectionOrder: 0,
        x: 8000,
        y: 8000,
        group: group,
      ),
    ];

    final rects = <String, Rect>{};

    testWidgets('pre-link: record the base rendered rects', (tester) async {
      await _pumpPicker(tester, tables: fixture());
      rects['a1'] = tester.getRect(
        find.byKey(const Key('table-floor-tile-a1')),
      );
      rects['a2'] = tester.getRect(
        find.byKey(const Key('table-floor-tile-a2')),
      );
      expect(find.byType(RestoflowFloorClusterSeam), findsNothing);
    });

    testWidgets('linked: members pack together with a seam; derived rects '
        'differ from base', (tester) async {
      await _pumpPicker(tester, tables: fixture(group: 'g1'));
      final a1 = tester.getRect(find.byKey(const Key('table-floor-tile-a1')));
      final a2 = tester.getRect(find.byKey(const Key('table-floor-tile-a2')));
      // The anchor (top-left-most base = a1) keeps its spot; the peer moved
      // beside it.
      expect(a1, rects['a1']);
      expect(a2, isNot(rects['a2']));
      // Physically joined: the peer's gap to the anchor is the small seam,
      // not the original half-room separation.
      expect((a2.left - a1.right).abs(), lessThan(a1.width));
      expect((a2.top - a1.top).abs(), lessThan(1.0));
      expect(find.byType(RestoflowFloorClusterSeam), findsOneWidget);
    });

    testWidgets('unlink: EXACT return to the base rects (no snapshot, no '
        'write — pure renderer fallback)', (tester) async {
      await _pumpPicker(tester, tables: fixture());
      expect(
        tester.getRect(find.byKey(const Key('table-floor-tile-a1'))),
        rects['a1'],
      );
      expect(
        tester.getRect(find.byKey(const Key('table-floor-tile-a2'))),
        rects['a2'],
      );
      expect(find.byType(RestoflowFloorClusterSeam), findsNothing);
    });

    testWidgets('cross-section link: per-section sub-clusters — a lone member '
        'in a section stays at its base with the link cue, never relocated', (
      tester,
    ) async {
      final container = await _pumpPicker(
        tester,
        tables: [
          _t(
            'a1',
            'Alpha',
            sectionId: 's1',
            sectionName: 'Main Hall',
            sectionOrder: 0,
            x: 1000,
            y: 1000,
            group: 'g1',
          ),
          _t(
            'b1',
            'Gamma',
            sectionId: 's2',
            sectionName: 'Terrace',
            sectionOrder: 1,
            x: 8000,
            y: 8000,
            group: 'g1',
          ),
        ],
      );
      // Each member renders in ITS OWN section at its base position: a
      // singleton per section derives nothing and draws no seam.
      expect(find.byType(RestoflowFloorClusterSeam), findsNothing);
      final s1 = tester.getRect(
        find.byKey(const Key('table-section-canvas-s1')),
      );
      final a1 = tester.getRect(find.byKey(const Key('table-floor-tile-a1')));
      final room = floorTableRoomRect(1000, 1000);
      expect(
        (a1.left - (s1.left + room.left * s1.width / 10000)).abs(),
        lessThanOrEqualTo(0.5),
      );
      // The linked cue still opens the group-detail sheet (never assigns).
      await tester.tap(find.byKey(const Key('table-floor-tile-a1')));
      await tester.pumpAndSettle();
      expect(find.byType(TableGroupDetailSheet), findsOneWidget);
      expect(
        container.read(orderSetupControllerProvider).assignedTable,
        isNull,
      );
    });
  });

  group('027 fixtures (read-only decoration)', () {
    const wall = PosFloorElement(
      id: 'fe1',
      sectionId: 's1',
      kind: 'wall',
      layoutX: 5000,
      layoutY: 30,
      widthNorm: 3000,
      heightNorm: 150,
      // 120C LOW follow-up: the persisted style must reach the move sheet.
      visualStyle: 'wood_partition',
    );
    const cashier = PosFloorElement(
      id: 'fe2',
      sectionId: 's1',
      kind: 'cashier',
      layoutX: 9000,
      layoutY: 9000,
      widthNorm: 900,
      heightNorm: 900,
      label: 'POS',
    );

    testWidgets('picker: fixtures render UNDER the tables at the shared '
        'contract rect and are never tappable', (tester) async {
      await _pumpPicker(
        tester,
        tables: _sectionedFloor(),
        elements: const [wall, cashier],
      );
      expect(find.byKey(const Key('pos-floor-element-fe1')), findsOneWidget);
      expect(find.byKey(const Key('pos-floor-element-fe2')), findsOneWidget);
      // The wall sits at the shared room-unit contract rect (<=0.5px).
      final canvas = tester.getRect(
        find.byKey(const Key('table-section-canvas-s1')),
      );
      final room = floorElementRoomRect(
        wall.layoutX,
        wall.layoutY,
        width: wall.widthNorm,
        height: wall.heightNorm,
      );
      final actual = tester.getRect(
        find.byKey(const Key('pos-floor-element-fe1')),
      );
      expect(
        (actual.left - (canvas.left + room.left * canvas.width / 10000)).abs(),
        lessThanOrEqualTo(0.5),
      );
      expect(
        (actual.top - (canvas.top + room.top * canvas.height / 10000)).abs(),
        lessThanOrEqualTo(0.5),
      );
      expect(
        (actual.width - room.width * canvas.width / 10000).abs(),
        lessThanOrEqualTo(0.5),
      );
      // Decoration is IGNORED by the pointer: tapping the labelled cashier
      // fixture assigns nothing and the picker stays open.
      await tester.tap(
        find.byKey(const Key('pos-floor-element-fe2')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('table-section-canvas-s1')), findsOneWidget);
    });

    testWidgets('move sheet: the same fixtures render read-only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: true),
            ),
            posMoveTableRepositoryProvider.overrideWithValue(
              _NeverCalledMoves(),
            ),
            tablesRepositoryProvider.overrideWithValue(
              _FakeTablesRepo(_sectionedFloor(), elements: const [wall]),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open-move-sheet'),
                    onPressed: () => MoveTableSheet.show(
                      context,
                      order: PosRecentOrder.discovered(
                        PosOrderSnapshot(
                          orderId: 'o-9',
                          orderCode: '#00O009',
                          revision: 1,
                          status: 'preparing',
                          settlement: PosSettlement.unpaid,
                          subtotalMinor: 1000,
                          discountTotalMinor: 0,
                          taxTotalMinor: 0,
                          grandTotalMinor: 1000,
                          createdAt: DateTime.utc(2026, 7, 14, 12),
                          updatedAt: DateTime.utc(2026, 7, 14, 12),
                          syncAt: DateTime.utc(2026, 7, 14, 12),
                          orderType: 'dine_in',
                          tableLabel: 'T1',
                          currencyCode: 'ILS',
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-move-sheet')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('move-table-section-canvas-s1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('move-floor-element-fe1')), findsOneWidget);
      // 120C LOW follow-up: the persisted visual values reach the SHARED
      // renderers through the move sheet too.
      expect(
        tester
            .widget<RestoflowFloorFixture>(
              find.byKey(const Key('move-floor-element-fe1')),
            )
            .style,
        'wood_partition',
      );
      final movePainter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(const Key('move-table-tile-a1')),
                      matching: find.byWidgetPredicate(
                        (w) =>
                            w is CustomPaint &&
                            w.painter is RestoflowTableShapePainter,
                      ),
                    ),
                  )
                  .painter!
              as RestoflowTableShapePainter;
      expect(movePainter.material, TableVisualMaterial.rusticWood);
    });
  });

  group('move sheet: section canvases', () {
    PosRecentOrder order() => PosRecentOrder.discovered(
      PosOrderSnapshot(
        orderId: 'o-1',
        orderCode: '#00O001',
        revision: 2,
        status: 'preparing',
        settlement: PosSettlement.unpaid,
        subtotalMinor: 2500,
        discountTotalMinor: 0,
        taxTotalMinor: 0,
        grandTotalMinor: 2500,
        createdAt: DateTime.utc(2026, 7, 14, 12),
        updatedAt: DateTime.utc(2026, 7, 14, 12),
        syncAt: DateTime.utc(2026, 7, 14, 12),
        orderType: 'dine_in',
        tableLabel: 'T1',
        currencyCode: 'ILS',
      ),
    );

    testWidgets('sectioned tables render on the saved canvas; a canvas tile '
        'selects; reserved keeps its cue', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posMoveTableRepositoryProvider.overrideWithValue(
              _NeverCalledMoves(),
            ),
            tablesProvider.overrideWith(
              (ref) async => [
                _t('t1', 'T1'), // the CURRENT table (legacy, disabled)
                _t(
                  't2',
                  'T2',
                  sectionId: 's1',
                  sectionName: 'Main Hall',
                  sectionOrder: 0,
                  x: 1000,
                  y: 1000,
                ),
                _t(
                  't3',
                  'T3',
                  effective: 'reserved',
                  manual: 'reserved',
                  sectionId: 's1',
                  sectionName: 'Main Hall',
                  sectionOrder: 0,
                  x: 8000,
                  y: 1000,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open-move-sheet'),
                    onPressed: () =>
                        MoveTableSheet.show(context, order: order()),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-move-sheet')));
      await tester.pumpAndSettle();

      // The section renders as a canvas with both placed tiles.
      expect(
        find.byKey(const Key('move-table-section-canvas-s1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('move-table-tile-t2')), findsOneWidget);
      // Reserved cue is words, not colour alone.
      expect(find.text(l10n.posTableStateReserved), findsOneWidget);
      // Confirm is disabled until a target is picked from the canvas.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('move-table-confirm-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('move-table-tile-t2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('move-table-confirm-button')),
            )
            .onPressed,
        isNotNull,
      );
    });
  });
}

class _NeverCalledMoves implements MoveTableRepository {
  @override
  Future<MoveTableResult> moveTable({
    required String orderId,
    required String tableId,
    required String tableLabel,
    int? expectedRevision,
  }) => throw UnimplementedError('the selection test never submits');
}
