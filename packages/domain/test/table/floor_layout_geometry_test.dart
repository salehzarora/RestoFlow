import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

/// TABLE-FLOOR-LAYOUT-021 — the pure floor-layout geometry. Every floor
/// surface (Dashboard arrange editor, POS picker, Move Table) rides these
/// functions, so their determinism IS the cross-app agreement.
void main() {
  group('clampFloorCoordinate', () {
    test('clamps into 0..10000 inclusive', () {
      expect(clampFloorCoordinate(-1), 0);
      expect(clampFloorCoordinate(0), 0);
      expect(clampFloorCoordinate(4321), 4321);
      expect(clampFloorCoordinate(kFloorLayoutMax), kFloorLayoutMax);
      expect(clampFloorCoordinate(kFloorLayoutMax + 1), kFloorLayoutMax);
    });
  });

  group('floorFractionOf', () {
    test('a complete placement maps to unit fractions', () {
      final f = floorFractionOf(2500, 7500)!;
      expect(f.x, closeTo(0.25, 1e-9));
      expect(f.y, closeTo(0.75, 1e-9));
    });

    test('null and HALF placements are unplaced (defensive)', () {
      expect(floorFractionOf(null, null), isNull);
      expect(floorFractionOf(2500, null), isNull);
      expect(floorFractionOf(null, 7500), isNull);
    });

    test('out-of-range storage values are clamped, never thrown', () {
      final f = floorFractionOf(-50, 20000)!;
      expect(f.x, 0.0);
      expect(f.y, 1.0);
    });
  });

  group('floorPointFromFractions', () {
    test('rounds to normalized integers', () {
      expect(floorPointFromFractions(0.25, 0.75), (x: 2500, y: 7500));
      expect(floorPointFromFractions(0.33333, 0.5), (x: 3333, y: 5000));
    });

    test('a drag overshooting the canvas clamps into range', () {
      expect(floorPointFromFractions(-0.2, 1.4), (x: 0, y: 10000));
    });

    test('round-trips with floorFractionOf', () {
      const point = (x: 4321, y: 9876);
      final f = floorFractionOf(point.x, point.y)!;
      expect(floorPointFromFractions(f.x, f.y), point);
    });
  });

  group('chairSidesFor', () {
    test('common sizes read naturally', () {
      expect(chairSidesFor(0), (top: 0, bottom: 0, start: 0, end: 0));
      expect(chairSidesFor(2), (top: 1, bottom: 1, start: 0, end: 0));
      expect(chairSidesFor(4), (top: 2, bottom: 2, start: 0, end: 0));
      expect(chairSidesFor(6), (top: 2, bottom: 2, start: 1, end: 1));
    });

    test('negative seats draw nothing', () {
      expect(chairSidesFor(-3), (top: 0, bottom: 0, start: 0, end: 0));
    });

    test('the glyph cap bounds the DRAWN chairs only', () {
      final capped = chairSidesFor(40);
      expect(capped.top + capped.bottom + capped.start + capped.end, 12);
      final tight = chairSidesFor(40, cap: 4);
      expect(tight, (top: 2, bottom: 2, start: 0, end: 0));
    });
  });

  group('initialFloorPlacement', () {
    test('an empty canvas takes the first grid slot', () {
      expect(initialFloorPlacement(const []), (x: 1250, y: 1667));
    });

    test('skips slots the SHARED footprint would overlap (deterministic)', () {
      // The Dashboard demo-seed shape: the first three slots collide with the
      // occupied placements under the room-unit footprint; the fourth
      // (8750, 1667) clears them all and is the stable answer.
      const occupied = [
        (x: 1500, y: 2500),
        (x: 5000, y: 2500),
        (x: 8200, y: 6500),
      ];
      expect(initialFloorPlacement(occupied), (x: 8750, y: 1667));
      // Row-major walk => the same answer every call.
      expect(initialFloorPlacement(occupied), (x: 8750, y: 1667));
    });

    test('027: adjacent grid slots NEVER overlap under the shared footprint '
        '(the fix for the phone-canvas default-grid overlap)', () {
      const xSlots = [1250, 3750, 6250, 8750];
      const ySlots = [1667, 5000, 8333];
      for (final x1 in xSlots) {
        for (final y1 in ySlots) {
          for (final x2 in xSlots) {
            for (final y2 in ySlots) {
              if (x1 == x2 && y1 == y2) continue;
              expect(
                floorPlacementsOverlap((x: x1, y: y1), (x: x2, y: y2)),
                isFalse,
                reason: 'grid slots ($x1,$y1) vs ($x2,$y2) must clear',
              );
            }
          }
        }
      }
    });

    test('a full grid falls back to the canvas centre', () {
      final everywhere = [
        for (var row = 0; row < 3; row++)
          for (var column = 0; column < 4; column++)
            (
              x: ((column + 0.5) / 4 * kFloorLayoutMax).round(),
              y: ((row + 0.5) / 3 * kFloorLayoutMax).round(),
            ),
      ];
      expect(initialFloorPlacement(everywhere), (
        x: kFloorLayoutMax ~/ 2,
        y: kFloorLayoutMax ~/ 2,
      ));
    });
  });

  group('floorPlacementsOverlap (027: room-unit, per-axis)', () {
    // Stored Δx maps to room units ×(10000-kFloorTableW)/10000 = ×0.85;
    // stored Δy maps ×(10000-kFloorTableH)/10000 = ×0.76. Overlap iff the
    // room deltas are inside the 1500×2400 footprint on BOTH axes.
    test('overlap needs BOTH axes inside the shared footprint', () {
      expect(
        floorPlacementsOverlap((x: 1000, y: 1000), (x: 2000, y: 1500)),
        isTrue, // dLeft 850 < 1500, dTop 380 < 2400
      );
      expect(
        floorPlacementsOverlap((x: 1000, y: 1000), (x: 2800, y: 1000)),
        isFalse, // dLeft 1530 >= 1500 -> x clears
      );
      expect(
        floorPlacementsOverlap((x: 1000, y: 1000), (x: 1000, y: 4200)),
        isFalse, // dTop 2432 >= 2400 -> y clears
      );
    });

    test('the verdict is symmetric and viewport-independent', () {
      const a = (x: 1200, y: 3300);
      const b = (x: 2600, y: 5400);
      expect(
        floorPlacementsOverlap(a, b),
        floorPlacementsOverlap(b, a),
      );
    });
  });

  group('027 room-unit transforms', () {
    test('floorRoomLeft/Top map the usable span linearly', () {
      expect(floorRoomLeft(0), 0);
      expect(floorRoomLeft(kFloorLayoutMax), kFloorUsableW.toDouble());
      expect(floorRoomLeft(5000), closeTo(kFloorUsableW / 2, 1e-9));
      expect(floorRoomTop(kFloorLayoutMax), kFloorUsableH.toDouble());
    });

    test('floorTableRoomRect carries the SHARED footprint', () {
      final r = floorTableRoomRect(2500, 3000);
      expect(r.width, kFloorTableW.toDouble());
      expect(r.height, kFloorTableH.toDouble());
      expect(r.left, closeTo(0.25 * kFloorUsableW, 1e-9));
      expect(r.top, closeTo(0.30 * kFloorUsableH, 1e-9));
    });

    test('floorStoredFromRoomTopLeft round-trips with floorRoomLeft/Top', () {
      const point = (x: 4321, y: 9876);
      final stored = floorStoredFromRoomTopLeft(
        floorRoomLeft(point.x),
        floorRoomTop(point.y),
      );
      expect(stored, point);
    });

    test('out-of-room drags clamp into storable range', () {
      expect(
        floorStoredFromRoomTopLeft(-500, kFloorUsableH + 900),
        (x: 0, y: kFloorLayoutMax),
      );
    });
  });
}
