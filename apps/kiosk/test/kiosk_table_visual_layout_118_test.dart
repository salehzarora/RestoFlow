import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorFixture,
        RestoflowFloorPresetPainter,
        RestoflowFloorSectionCanvas,
        RestoflowTableShapePainter;
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset, floorTableRoomRect;
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-VISUAL-LAYOUT-118 — the kiosk renders the SAME room map the
/// Dashboard configured and the POS renders: every placed table lands at the
/// shared room-rect contract (no drift), the section paints its floor preset,
/// each table draws its shape, the selected state is unmistakable, and an
/// unplaced table keeps the list card. Occupied/reserved/out-of-service stay
/// visible but never selectable — the honest floor.
Map<String, Object?> _row(
  String id,
  String label, {
  String state = 'available',
  int? x,
  int? y,
  String? preset,
  String? floor,
  String section = 's1',
  String sectionName = 'Main Hall',
  int order = 0,
}) => {
  'id': id,
  'label': label,
  'seats': 4,
  'section_id': section,
  'section_name': sectionName,
  'section_display_order': order,
  'effective_state': state,
  'layout_x': ?x,
  'layout_y': ?y,
  'visual_preset': ?preset,
  'section_floor_preset': ?floor,
};

Map<String, Object?> _envelope() => {
  'ok': true,
  'tables': [
    _row('t1', 'T1', x: 1000, y: 1000, floor: 'wood_dark'),
    _row('t2', 'T2', state: 'occupied', x: 5000, y: 1000, floor: 'wood_dark'),
    _row(
      't3',
      'T3',
      x: 3000,
      y: 6000,
      preset: 'round_table',
      floor: 'wood_dark',
    ),
    // No placement: stays in the list strip below the map.
    _row('t9', 'T9', floor: 'wood_dark'),
    _row(
      'p1',
      'P1',
      section: 's2',
      sectionName: 'Terrace',
      order: 1,
      x: 8000,
      y: 8000,
      preset: 'table_with_barrels',
    ),
  ],
  'floor_elements': [
    {
      'id': 'e1',
      'section_id': 's1',
      'kind': 'wall',
      'layout_x': 100,
      'layout_y': 9000,
      'width_norm': 5000,
      'height_norm': 150,
      'orientation_quarter_turns': 1,
      'label': null,
    },
  ],
};

Finder _floorPainter(FloorPreset preset) => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter is RestoflowFloorPresetPainter &&
      (w.painter! as RestoflowFloorPresetPainter).preset == preset,
);

Finder _shapePainter(TableVisualPreset preset) => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter is RestoflowTableShapePainter &&
      (w.painter! as RestoflowTableShapePainter).preset == preset,
);

Future<ProviderContainer> _pumpLive(
  WidgetTester tester,
  List<KioskFixtureZone> zones,
) async {
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
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const KioskShell(),
      ),
    ),
  );
  final controller = container.read(kioskFlowProvider.notifier);
  controller.startFromAttract();
  controller.pickService(KioskServiceType.dineIn);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  return container;
}

void main() {
  group('mapKioskTablesEnvelope (118 keys)', () {
    test('reads placement, presets, the section floor and the fixtures', () {
      final zones = mapKioskTablesEnvelope(_envelope())!;
      expect(zones.map((z) => z.displayName), ['Main Hall', 'Terrace']);
      final hall = zones[0];
      expect(hall.floorPreset, FloorPreset.woodDark);
      final byLabel = {for (final t in hall.tables) t.label: t};
      expect(byLabel['T1']!.layoutX, 1000);
      expect(byLabel['T1']!.layoutY, 1000);
      expect(byLabel['T1']!.isPlaced, isTrue);
      expect(byLabel['T1']!.visualPreset, TableVisualPreset.classicRectTable);
      expect(byLabel['T3']!.visualPreset, TableVisualPreset.roundTable);
      expect(byLabel['T9']!.isPlaced, isFalse);
      expect(hall.elements.single.kind, 'wall');
      expect(hall.elements.single.widthNorm, 5000);
      final terrace = zones[1];
      expect(terrace.floorPreset, FloorPreset.plainLight);
      expect(terrace.elements, isEmpty);
      expect(
        terrace.tables.single.visualPreset,
        TableVisualPreset.tableWithBarrels,
      );
    });

    test('an older envelope (no 118 keys) decodes to unplaced defaults', () {
      final zones = mapKioskTablesEnvelope({
        'ok': true,
        'tables': [
          {'id': 'a', 'label': 'A', 'seats': 2, 'effective_state': 'available'},
        ],
      })!;
      final t = zones.single.tables.single;
      expect(t.isPlaced, isFalse);
      expect(t.visualPreset, TableVisualPreset.classicRectTable);
      expect(zones.single.floorPreset, FloorPreset.plainLight);
      expect(zones.single.elements, isEmpty);
    });

    test('a half placement or an unknown key never breaks the floor', () {
      final zones = mapKioskTablesEnvelope({
        'ok': true,
        'tables': [
          {
            'id': 'a',
            'label': 'A',
            'seats': 2,
            'effective_state': 'available',
            'layout_x': 5000,
            'visual_preset': 'hexagon',
            'section_floor_preset': 'lava',
          },
        ],
        'floor_elements': 'nope',
      })!;
      final t = zones.single.tables.single;
      expect(t.isPlaced, isFalse);
      expect(t.visualPreset, TableVisualPreset.classicRectTable);
      expect(zones.single.floorPreset, FloorPreset.plainLight);
    });
  });

  group('demo fixture floor', () {
    test('every fixture table is placed inside the room and the demo shows '
        'at least one non-classic shape', () {
      final zones = kioskFixtureZones(busy: false);
      for (final zone in zones) {
        for (final t in zone.tables) {
          expect(t.isPlaced, isTrue, reason: '${zone.id}/${t.label}');
          expect(t.layoutX, inInclusiveRange(0, 10000));
          expect(t.layoutY, inInclusiveRange(0, 10000));
        }
      }
      expect(
        zones
            .expand((z) => z.tables)
            .any((t) => t.visualPreset != TableVisualPreset.classicRectTable),
        isTrue,
      );
    });
  });

  group('kiosk floor map', () {
    testWidgets('placed tables land at the SHARED room rects (no drift), the '
        'floor paints, shapes draw, and the unplaced table keeps its card', (
      tester,
    ) async {
      await _pumpLive(tester, mapKioskTablesEnvelope(_envelope())!);
      final canvasFinder = find.byKey(const Key('kiosk-floor-canvas-s1'));
      expect(canvasFinder, findsOneWidget);
      expect(
        find.descendant(
          of: canvasFinder,
          matching: _floorPainter(FloorPreset.woodDark),
        ),
        findsOneWidget,
      );
      // The Stack inside the shared canvas is the room; every tile rect must
      // equal the contract projection of its saved coordinates.
      final room = tester.getRect(
        find
            .descendant(
              of: find.descendant(
                of: canvasFinder,
                matching: find.byType(RestoflowFloorSectionCanvas),
              ),
              matching: find.byType(Stack),
            )
            .first,
      );
      for (final (id, x, y) in [('t1', 1000, 1000), ('t2', 5000, 1000)]) {
        final tile = tester.getRect(find.byKey(Key('kiosk-floor-tile-$id')));
        final expected = RestoflowFloorSectionCanvas.pixelsForRoomRect(
          floorTableRoomRect(x, y),
          room.size,
        ).shift(room.topLeft);
        expect((tile.left - expected.left).abs(), lessThan(0.5), reason: id);
        expect((tile.top - expected.top).abs(), lessThan(0.5), reason: id);
        expect((tile.width - expected.width).abs(), lessThan(0.5), reason: id);
        expect(
          (tile.height - expected.height).abs(),
          lessThan(0.5),
          reason: id,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('kiosk-floor-tile-t3')),
          matching: _shapePainter(TableVisualPreset.roundTable),
        ),
        findsOneWidget,
      );
      // 119D: the kiosk renders the shared MATERIAL scene — every table
      // painter carries a resolved material (never the flat legacy null).
      expect(
        (tester
                    .widget<CustomPaint>(
                      find
                          .descendant(
                            of: find.byKey(const Key('kiosk-floor-tile-t3')),
                            matching: _shapePainter(
                              TableVisualPreset.roundTable,
                            ),
                          )
                          .first,
                    )
                    .painter!
                as RestoflowTableShapePainter)
            .material,
        isNotNull,
      );
      expect(find.byKey(const Key('kiosk-floor-element-e1')), findsOneWidget);
      // 119A: the AUTHORITATIVE orientation reaches the fixture widget.
      expect(
        tester
            .widget<RestoflowFloorFixture>(
              find.byKey(const Key('kiosk-floor-element-e1')),
            )
            .quarterTurns,
        1,
      );
      // The unplaced table is NOT on the map; it keeps the list card.
      expect(find.byKey(const Key('kiosk-floor-tile-t9')), findsNothing);
      expect(find.text('T9'), findsOneWidget);
      // The Terrace map paints the default floor (no painter) with barrels.
      expect(
        find.descendant(
          of: find.byKey(const Key('kiosk-floor-canvas-s2')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is RestoflowFloorPresetPainter,
          ),
        ),
        findsNothing,
      );
      expect(_shapePainter(TableVisualPreset.tableWithBarrels), findsOneWidget);
    });

    testWidgets('only an available tile selects; the selected state is '
        'explicit and id-aware; a second tap deselects', (tester) async {
      final container = await _pumpLive(
        tester,
        mapKioskTablesEnvelope(_envelope())!,
      );
      await tester.tap(find.byKey(const Key('kiosk-floor-tile-t2')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, isNull);
      expect(find.byKey(const Key('kiosk-floor-selected-t2')), findsNothing);

      await tester.tap(find.byKey(const Key('kiosk-floor-tile-t1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, 'T1');
      expect(container.read(kioskFlowProvider).selectedTableId, 't1');
      expect(find.byKey(const Key('kiosk-floor-selected-t1')), findsOneWidget);
      expect(find.byKey(const Key('kiosk-floor-selected-t3')), findsNothing);

      await tester.tap(find.byKey(const Key('kiosk-floor-tile-t1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, isNull);
      expect(find.byKey(const Key('kiosk-floor-selected-t1')), findsNothing);
    });

    testWidgets('the demo floor renders three zone maps and the classic '
        'select → continue flow still reaches the menu', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const KioskShell(),
          ),
        ),
      );
      final controller = container.read(kioskFlowProvider.notifier);
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(const Key('kiosk-floor-canvas-hall')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('kiosk-floor-tile-fixture-table-T4')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(kioskFlowProvider).selectedTable, 'T4');
      await tester.tap(find.byKey(const Key('kiosk-table-continue')));
      await tester.pump(const Duration(milliseconds: 900));
      expect(container.read(kioskFlowProvider).screen, KioskScreen.menu);
    });
  });
}
