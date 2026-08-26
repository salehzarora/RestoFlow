import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/design/kiosk_theme.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-118F — a placed AVAILABLE table on the kiosk map carries the green
/// dot the legend promises; occupied / reserved / out-of-service keep their
/// customer-safe dots; the selected tile shows the accent badge instead and
/// selection never moves or resizes the tile.
KioskFixtureTable _t(
  String id,
  String label,
  KioskTableState state,
  int x,
  int y, {
  TableVisualPreset preset = TableVisualPreset.classicRectTable,
}) => KioskFixtureTable(
  id: id,
  label: label,
  seats: 4,
  state: state,
  layoutX: x,
  layoutY: y,
  visualPreset: preset,
);

List<KioskFixtureZone> _zones() => [
  KioskFixtureZone(
    id: 's1',
    displayName: 'Main Hall',
    floorPreset: FloorPreset.woodDark,
    tables: [
      _t('a1', 'A1', KioskTableState.available, 800, 900),
      _t(
        'a2',
        'A2',
        KioskTableState.occupied,
        4200,
        700,
        preset: TableVisualPreset.roundTable,
      ),
      _t('a3', 'A3', KioskTableState.reserved, 8600, 1200),
      _t('a4', 'A4', KioskTableState.outOfService, 2500, 6200),
      const KioskFixtureTable(
        id: 'a9',
        label: 'A9',
        seats: 2,
        state: KioskTableState.available,
      ),
    ],
  ),
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      kioskTablesViewProvider.overrideWithValue((
        zones: _zones(),
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

Color _dotColor(WidgetTester tester, String id) {
  final box = tester.widget<Container>(find.byKey(Key('kiosk-floor-dot-$id')));
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('an available placed table shows the legend green dot; the '
      'other states keep theirs', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('kiosk-floor-dot-a1')), findsOneWidget);
    expect(_dotColor(tester, 'a1'), KioskColors.tableFree);
    expect(_dotColor(tester, 'a2'), KioskColors.tableOccupied);
    expect(_dotColor(tester, 'a3'), KioskColors.tableReserved);
    expect(_dotColor(tester, 'a4'), KioskColors.tableOutOfService);
    // The unplaced card is not a map tile: no map dot for it.
    expect(find.byKey(const Key('kiosk-floor-dot-a9')), findsNothing);
    // Customer-safe: no counts / group / manual-status text leaks.
    expect(find.textContaining('open order'), findsNothing);
  });

  testWidgets('selecting swaps the dot for the accent badge without moving '
      'the tile; deselecting restores the dot', (tester) async {
    final container = await _pump(tester);
    final before = tester.getRect(find.byKey(const Key('kiosk-floor-tile-a1')));
    await tester.tap(find.byKey(const Key('kiosk-floor-tile-a1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(kioskFlowProvider).selectedTableId, 'a1');
    expect(find.byKey(const Key('kiosk-floor-selected-a1')), findsOneWidget);
    expect(find.byKey(const Key('kiosk-floor-dot-a1')), findsNothing);
    final after = tester.getRect(find.byKey(const Key('kiosk-floor-tile-a1')));
    expect(after, before, reason: 'selection styling never changes geometry');
    // Neighbours keep their dots.
    expect(_dotColor(tester, 'a2'), KioskColors.tableOccupied);
    await tester.tap(find.byKey(const Key('kiosk-floor-tile-a1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('kiosk-floor-selected-a1')), findsNothing);
    expect(_dotColor(tester, 'a1'), KioskColors.tableFree);
    expect(
      tester.getRect(find.byKey(const Key('kiosk-floor-tile-a1'))),
      before,
    );
  });
}
