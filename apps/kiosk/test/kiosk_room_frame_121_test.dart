import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show TableSectionRoomFramePreset, floorRoomAspect, kFloorStandardAspect;
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/data/kiosk_live_data.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_kiosk/src/state/kiosk_live_runtime.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TABLE-ROOM-FRAME-121 — the kiosk is a READ-ONLY consumer of the section
/// room frame: tolerant decode from `kiosk_tables` rows (first non-default
/// wins) and the shared canvas projects each zone at ITS aspect, so the
/// kiosk floor map matches the Dashboard/POS by construction.
Map<String, Object?> _row(
  String id,
  String label, {
  String state = 'available',
  int? x,
  int? y,
  String? frame,
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
  'section_room_frame_preset': ?frame,
};

Map<String, Object?> _envelope() => {
  'ok': true,
  'tables': [
    _row('t1', 'T1', x: 1000, y: 1000, frame: 'portrait'),
    _row('t2', 'T2', x: 5000, y: 1000, frame: 'portrait'),
    // Terrace: no key at all (legacy hosted) => Standard.
    _row(
      'p1',
      'P1',
      section: 's2',
      sectionName: 'Terrace',
      order: 1,
      x: 8000,
      y: 8000,
    ),
    // Bar: an unknown key => Standard, never a failure.
    _row(
      'b1',
      'B1',
      section: 's3',
      sectionName: 'Bar',
      order: 2,
      x: 2000,
      y: 2000,
      frame: 'hexagonal',
    ),
  ],
};

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
  test('mapKioskTablesEnvelope decodes section_room_frame_preset tolerantly '
      '(first non-default wins; unknown/absent => Standard)', () {
    final zones = mapKioskTablesEnvelope(_envelope())!;
    final byName = {for (final z in zones) z.displayName: z};
    expect(
      byName['Main Hall']!.roomFramePreset,
      TableSectionRoomFramePreset.portrait,
    );
    expect(byName['Terrace']!.roomFramePreset, isNull);
    expect(byName['Bar']!.roomFramePreset, isNull);
  });

  testWidgets('each zone canvas projects at ITS frame; Standard zones keep '
      'the legacy ratio', (tester) async {
    await _pumpLive(tester, mapKioskTablesEnvelope(_envelope())!);
    double aspectOf(String zoneId) => tester
        .widget<AspectRatio>(
          find.descendant(
            of: find.byKey(Key('kiosk-floor-canvas-$zoneId')),
            matching: find.byType(AspectRatio),
          ),
        )
        .aspectRatio;
    expect(
      aspectOf('s1'),
      floorRoomAspect(TableSectionRoomFramePreset.portrait),
    );
    expect(aspectOf('s2'), kFloorStandardAspect);
    expect(aspectOf('s3'), kFloorStandardAspect);
  });
}
