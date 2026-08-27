import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        TableSectionRoomFramePreset,
        TableVisualPreset,
        floorRoomAspect,
        floorTableRoomRect,
        kFloorStandardAspect;

/// TABLE-ROOM-FRAME-121 — the shared canvas owns the ROOM FRAME projection.
///
/// The canvas accepts the section's optional room-frame preset and resolves
/// its own width:height from it; NULL keeps the legacy tokenized ratio
/// byte-for-byte. Because callers compute room rects through the SAME frame
/// (`floorTableRoomRect(..., frame: f)`), a table tile's ON-SCREEN physical
/// aspect stays identical in every frame — rooms resize, furniture never
/// squashes.
Widget _app(Widget child, {double width = 760}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

RestoflowFloorTable _table() => const RestoflowFloorTable(
  label: 'T1',
  seats: 4,
  fill: Colors.white,
  onFill: Colors.black,
  border: Colors.grey,
  preset: TableVisualPreset.classicRectTable,
);

void main() {
  test(
    'the tokenized canvas ratio IS the domain standard aspect (one truth)',
    () {
      expect(kRestoflowFloorSectionAspect, kFloorStandardAspect);
    },
  );

  testWidgets('NULL room frame keeps the legacy AspectRatio byte-for-byte', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RestoflowFloorSectionCanvas(
          roomFrame: null,
          placed: [
            RestoflowFloorPlacedTile(
              room: floorTableRoomRect(1000, 1000),
              child: _table(),
            ),
          ],
        ),
      ),
    );
    final ratio = tester
        .widget<AspectRatio>(
          find.descendant(
            of: find.byType(RestoflowFloorSectionCanvas),
            matching: find.byType(AspectRatio),
          ),
        )
        .aspectRatio;
    expect(ratio, kRestoflowFloorSectionAspect);
  });

  testWidgets('every preset resolves ITS aspect on the canvas', (tester) async {
    for (final frame in TableSectionRoomFramePreset.values) {
      await tester.pumpWidget(
        _app(
          RestoflowFloorSectionCanvas(
            roomFrame: frame,
            placed: [
              RestoflowFloorPlacedTile(
                room: floorTableRoomRect(1000, 1000, frame: frame),
                child: _table(),
              ),
            ],
          ),
        ),
      );
      final ratio = tester
          .widget<AspectRatio>(
            find.descendant(
              of: find.byType(RestoflowFloorSectionCanvas),
              matching: find.byType(AspectRatio),
            ),
          )
          .aspectRatio;
      expect(ratio, frame.aspect, reason: frame.wire);
      expect(ratio, floorRoomAspect(frame), reason: frame.wire);
    }
  });

  testWidgets('a table tile keeps ONE on-screen physical aspect across every '
      'room frame (rooms resize, furniture never squashes)', (tester) async {
    const legacyTileAspect = (1500 / 2400) * 1.9; // 1.1875
    for (final frame in <TableSectionRoomFramePreset?>[
      null,
      ...TableSectionRoomFramePreset.values,
    ]) {
      await tester.pumpWidget(
        _app(
          RestoflowFloorSectionCanvas(
            roomFrame: frame,
            placed: [
              RestoflowFloorPlacedTile(
                room: floorTableRoomRect(3000, 3000, frame: frame),
                child: _table(),
              ),
            ],
          ),
        ),
      );
      final size = tester.getSize(find.byType(RestoflowFloorTable));
      expect(
        (size.width / size.height - legacyTileAspect).abs() / legacyTileAspect,
        lessThan(0.01),
        reason: '${frame?.wire ?? 'standard'}: ${size.width / size.height}',
      );
    }
  });
}
