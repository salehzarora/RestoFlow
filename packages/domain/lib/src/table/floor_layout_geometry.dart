/// TABLE-FLOOR-LAYOUT-021 — the PURE floor-layout geometry shared by every
/// floor-map surface (Dashboard arrange editor, POS picker, Move Table).
///
/// The wire/storage contract (mirrors the DB CHECK constraints): a placement
/// is a pair of NORMALIZED integers, each in `0..kFloorLayoutMax` (10000),
/// independent of any viewport. Coordinates describe the PHYSICAL room —
/// they are NEVER mirrored for RTL locales (text localizes; the room does
/// not flip). Both coordinates travel together or not at all.
///
/// Everything here is deterministic, Flutter-free Dart so the same math is
/// unit-testable and byte-identical across apps.
library;

/// The inclusive upper bound of a normalized layout coordinate.
const int kFloorLayoutMax = 10000;

/// A normalized placement (both axes 0..[kFloorLayoutMax]).
typedef FloorPoint = ({int x, int y});

/// Clamps one normalized coordinate into the storable range.
int clampFloorCoordinate(int value) =>
    value < 0 ? 0 : (value > kFloorLayoutMax ? kFloorLayoutMax : value);

/// The placement as unit fractions (0..1 each), or null when the table has no
/// (complete) placement. A half-placement is treated as unplaced — the DB
/// forbids it, but a defensive client never trusts one axis alone.
({double x, double y})? floorFractionOf(int? layoutX, int? layoutY) {
  if (layoutX == null || layoutY == null) return null;
  return (
    x: clampFloorCoordinate(layoutX) / kFloorLayoutMax,
    y: clampFloorCoordinate(layoutY) / kFloorLayoutMax,
  );
}

/// Converts unit fractions (any range — a drag can overshoot the canvas) back
/// into storable normalized coordinates, clamped.
FloorPoint floorPointFromFractions(double fractionX, double fractionY) => (
  x: clampFloorCoordinate((fractionX * kFloorLayoutMax).round()),
  y: clampFloorCoordinate((fractionY * kFloorLayoutMax).round()),
);

/// Deterministic per-side chair distribution for the top-down table visual.
///
/// Returns the number of chair glyphs on each side of the rectangular table
/// surface, in the fixed order (top, bottom, start, end). At most [cap] icons
/// are DRAWN (a huge banquet table must not become a porcupine) — the exact
/// numeric seat count is always shown as text on the visual, so capping the
/// icons never hides information. Seats fill in the repeating pattern
/// [top, bottom, top, bottom, start, end], which reads naturally for the
/// common sizes: a 2-top is 1+1 across, a 4-top 2+2 across, a 6-top 2+2
/// across plus one on each end.
({int top, int bottom, int start, int end}) chairSidesFor(
  int seats, {
  int cap = 12,
}) {
  final shown = seats < 0 ? 0 : (seats > cap ? cap : seats);
  const pattern = [0, 1, 0, 1, 2, 3];
  final out = [0, 0, 0, 0];
  for (var i = 0; i < shown; i++) {
    out[pattern[i % pattern.length]] += 1;
  }
  return (top: out[0], bottom: out[1], start: out[2], end: out[3]);
}

/// Deterministic safe INITIAL placement for a table that just joined a
/// section: the first slot of a 4×3 grid of canvas anchor points whose
/// distance to every [occupied] placement is at least [minDistance]
/// (normalized units, Chebyshev — cheap and rotation-free). Falls back to the
/// canvas centre when the grid is full. Row-major walk => stable results.
FloorPoint initialFloorPlacement(
  List<FloorPoint> occupied, {
  int minDistance = 1500,
}) {
  const columns = 4;
  const rows = 3;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final candidate = (
        x: ((column + 0.5) / columns * kFloorLayoutMax).round(),
        y: ((row + 0.5) / rows * kFloorLayoutMax).round(),
      );
      final clear = occupied.every((p) {
        final dx = (p.x - candidate.x).abs();
        final dy = (p.y - candidate.y).abs();
        return (dx > dy ? dx : dy) >= minDistance;
      });
      if (clear) return candidate;
    }
  }
  return (x: kFloorLayoutMax ~/ 2, y: kFloorLayoutMax ~/ 2);
}

/// Whether two placed tables (as normalized anchor points with a tile the
/// caller says spans [tileExtent] normalized units) visually overlap — used
/// ONLY for the OPTIONAL arrange-mode warning; saved positions are never
/// auto-moved.
bool floorPlacementsOverlap(
  FloorPoint a,
  FloorPoint b, {
  int tileExtent = 1400,
}) => (a.x - b.x).abs() < tileExtent && (a.y - b.y).abs() < tileExtent;
