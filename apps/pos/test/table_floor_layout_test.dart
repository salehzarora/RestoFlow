import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show DiningTable, OrderType;
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

class _FakeTablesRepo implements TablesRepository {
  _FakeTablesRepo(this.rows);

  List<DemoTable> rows;

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

Future<ProviderContainer> _pumpPicker(
  WidgetTester tester, {
  required List<DemoTable> tables,
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
      tablesRepositoryProvider.overrideWithValue(_FakeTablesRepo(tables)),
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
