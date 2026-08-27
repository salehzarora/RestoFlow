import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show floorElementRoomRect;

/// TABLE-119B — a THIN door (the standard 900×150-room-unit strip lands at
/// roughly 5–8 px thickness on POS/kiosk canvases) must still paint the
/// door-specific artwork — frame jambs, leaf, swing cue — never the generic
/// flat strip. Orientation stays authoritative (quarterTurns), the outer
/// fixture rect never changes, RTL never mirrors the room, and the other
/// kinds keep their existing compact behaviour.
Widget _fixture(
  Size size, {
  String kind = 'door',
  int quarterTurns = 0,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: RestoflowFloorFixture(kind: kind, quarterTurns: quarterTurns),
        ),
      ),
    ),
  ),
);

Finder get _fixturePainter => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is RestoflowFixturePainter,
);

RestoflowFixturePainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_fixturePainter).painter!
        as RestoflowFixturePainter;

void main() {
  group('thin doors keep the door artwork', () {
    // Representative surfaces: POS (~580px canvas -> 52x5), kiosk (~970px ->
    // 87x8), dashboard (~1050px -> 94x8), plus the borderline 16px strip.
    for (final size in const [
      Size(52, 5),
      Size(90, 8),
      Size(60, 12),
      Size(100, 16),
    ]) {
      testWidgets('horizontal door $size mounts the door painter', (
        tester,
      ) async {
        await tester.pumpWidget(_fixture(size));
        expect(_fixturePainter, findsOneWidget, reason: '$size');
        expect(_painterOf(tester).kind, 'door');
        expect(tester.getSize(find.byType(RestoflowFloorFixture)), size);
      });
    }

    testWidgets('a ROTATED door on the pinned minimum canvas (480px wide -> '
        '~7.2x22.7) still mounts the door painter — the gate must clear both '
        'orientations despite the 1/1.9 y-scale', (tester) async {
      const size = Size(8, 23);
      await tester.pumpWidget(_fixture(size, quarterTurns: 1));
      expect(_fixturePainter, findsOneWidget);
      expect(_painterOf(tester).quarterTurns, 1);
      expect(tester.getSize(find.byType(RestoflowFloorFixture)), size);
    });

    testWidgets('an unrotated door in the 18..24px long band mounts the door '
        'painter', (tester) async {
      await tester.pumpWidget(_fixture(const Size(23, 4)));
      expect(_fixturePainter, findsOneWidget);
      expect(_painterOf(tester).kind, 'door');
    });

    testWidgets('a door below the 18px long-side floor stays the flat '
        'fallback', (tester) async {
      await tester.pumpWidget(_fixture(const Size(8, 16), quarterTurns: 1));
      expect(_fixturePainter, findsNothing);
    });

    testWidgets('vertical thin door (quarterTurns 1) mounts the door painter '
        'with the authoritative orientation', (tester) async {
      const size = Size(8, 90);
      await tester.pumpWidget(_fixture(size, quarterTurns: 1));
      expect(_fixturePainter, findsOneWidget);
      expect(_painterOf(tester).quarterTurns, 1);
      expect(tester.getSize(find.byType(RestoflowFloorFixture)), size);
    });

    for (final turns in [0, 1, 2, 3]) {
      testWidgets('quarterTurns $turns reaches the painter and never changes '
          'the outer rect', (tester) async {
        const size = Size(90, 8);
        await tester.pumpWidget(_fixture(size, quarterTurns: turns));
        expect(_painterOf(tester).quarterTurns, turns);
        expect(tester.getSize(find.byType(RestoflowFloorFixture)), size);
      });
    }

    test('the thin-vs-full door split is deterministic (local thickness '
        'against the shared threshold)', () {
      expect(RestoflowFixturePainter.kThinDoorThickness, 18.0);
      // Horizontal strips: thickness = height.
      expect(
        RestoflowFixturePainter.rendersThinDoor(const Size(90, 8), 0),
        isTrue,
      );
      expect(
        RestoflowFixturePainter.rendersThinDoor(const Size(90, 30), 0),
        isFalse,
      );
      // Odd turns swap the local frame: a vertical 8x90 strip is thin too.
      expect(
        RestoflowFixturePainter.rendersThinDoor(const Size(8, 90), 1),
        isTrue,
      );
      expect(
        RestoflowFixturePainter.rendersThinDoor(const Size(30, 90), 1),
        isFalse,
      );
    });

    testWidgets('RTL never mirrors: same painter inputs and same rect as LTR', (
      tester,
    ) async {
      const size = Size(90, 8);
      await tester.pumpWidget(_fixture(size, quarterTurns: 1));
      final ltrRect = tester.getRect(find.byType(RestoflowFloorFixture));
      final ltrTurns = _painterOf(tester).quarterTurns;
      await tester.pumpWidget(
        _fixture(size, quarterTurns: 1, direction: TextDirection.rtl),
      );
      expect(_painterOf(tester).quarterTurns, ltrTurns);
      expect(tester.getRect(find.byType(RestoflowFloorFixture)), ltrRect);
    });

    test('room geometry is untouched by any orientation', () {
      final r0 = floorElementRoomRect(0, 0, width: 900, height: 150);
      expect((r0.left, r0.top, r0.width, r0.height), (0.0, 0.0, 900.0, 150.0));
      final r1 = floorElementRoomRect(
        0,
        0,
        width: 900,
        height: 150,
        quarterTurns: 1,
      );
      expect((r1.width, r1.height), (150.0, 900.0));
    });
  });

  group('other kinds keep their existing compact behaviour', () {
    for (final kind in ['plant', 'window', 'cashier']) {
      testWidgets('$kind at a tiny size stays the flat fallback', (
        tester,
      ) async {
        await tester.pumpWidget(_fixture(const Size(14, 8), kind: kind));
        expect(_fixturePainter, findsNothing, reason: kind);
      });
    }

    testWidgets('a sliver wall still paints its joints', (tester) async {
      await tester.pumpWidget(_fixture(const Size(90, 8), kind: 'wall'));
      expect(_fixturePainter, findsOneWidget);
      expect(_painterOf(tester).kind, 'wall');
    });
  });
}
