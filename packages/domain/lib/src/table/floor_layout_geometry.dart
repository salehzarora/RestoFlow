/// TABLE-FLOOR-LAYOUT-021 / TABLE-FLOOR-MAP-POLISH-027 — the PURE floor-layout
/// geometry shared by every floor-map surface (Dashboard arrange editor, POS
/// picker, Move Table).
///
/// The wire/storage contract (mirrors the DB CHECK constraints): a placement
/// is a pair of NORMALIZED integers, each in `0..kFloorLayoutMax` (10000),
/// independent of any viewport. Coordinates describe the PHYSICAL room —
/// they are NEVER mirrored for RTL locales (text localizes; the room does
/// not flip). Both coordinates travel together or not at all.
///
/// 027 — THE SHARED FOOTPRINT CONTRACT (the Dashboard↔POS parity fix).
/// A table's footprint is defined in ROOM UNITS, not screen pixels:
///
///  * the room is a 10000×10000 logical space; x-units are 1/10000 of the
///    canvas WIDTH and y-units are 1/10000 of the canvas HEIGHT (so the
///    contract is aspect-agnostic — the aspect token lives with the canvas);
///  * every table occupies [kFloorTableW] × [kFloorTableH] room units on
///    EVERY surface, so its size RELATIVE TO THE ROOM is identical on the
///    Dashboard, the POS picker and Move Table at any viewport width —
///    two tables that clear each other on one surface clear on all of them;
///  * a stored coordinate keeps its ORIGINAL meaning: the fraction
///    (value / 10000) of the USABLE span (10000 − footprint) the tile's
///    top-left anchor sits at. No production coordinate changes meaning.
///
/// Everything here is deterministic, Flutter-free Dart so the same math is
/// unit-testable and byte-identical across apps.
library;

import 'table_section_room_frame.dart';

/// The inclusive upper bound of a normalized layout coordinate.
const int kFloorLayoutMax = 10000;

/// 027: the table footprint in ROOM UNITS — the single source of truth for
/// every surface. Width is in x-units (1/10000 of canvas width), height in
/// y-units (1/10000 of canvas height).
const int kFloorTableW = 1500;
const int kFloorTableH = 2400;

/// A normalized placement (both axes 0..[kFloorLayoutMax]).
typedef FloorPoint = ({int x, int y});

/// A rectangle in ROOM UNITS (doubles: derived values are sub-unit precise).
typedef FloorRoomRect = ({
  double left,
  double top,
  double width,
  double height,
});

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

// ---------------------------------------------------------------------------
// 027 — stored-coordinate ⇄ room-unit transforms (the parity contract).
// ---------------------------------------------------------------------------

/// The usable anchor span in room units, per axis.
const int kFloorUsableW = kFloorLayoutMax - kFloorTableW;
const int kFloorUsableH = kFloorLayoutMax - kFloorTableH;

/// TABLE-121: the table footprint's stored-unit WIDTH for [frame] (NULL =
/// the exact legacy [kFloorTableW]). Height is [kFloorTableH] in every frame.
int floorTableFootprintW(TableSectionRoomFramePreset? frame) =>
    frame?.tableFootprintXUnits ?? kFloorTableW;

/// TABLE-121: the usable horizontal span for [frame].
int floorUsableW(TableSectionRoomFramePreset? frame) =>
    kFloorLayoutMax - floorTableFootprintW(frame);

/// The room-unit LEFT edge of a table anchored at stored coordinate [x].
/// TABLE-121: the stored coordinate is a FRACTION of the frame's usable
/// span, so changing the frame reprojects — it never rewrites the data.
double floorRoomLeft(int x, {TableSectionRoomFramePreset? frame}) =>
    clampFloorCoordinate(x) / kFloorLayoutMax * floorUsableW(frame);

/// The room-unit TOP edge of a table anchored at stored coordinate [y].
double floorRoomTop(int y, {TableSectionRoomFramePreset? frame}) =>
    clampFloorCoordinate(y) / kFloorLayoutMax * kFloorUsableH;

/// The full room-unit rect of a table at stored ([x], [y]).
FloorRoomRect floorTableRoomRect(
  int x,
  int y, {
  TableSectionRoomFramePreset? frame,
}) => (
  left: floorRoomLeft(x, frame: frame),
  top: floorRoomTop(y, frame: frame),
  width: floorTableFootprintW(frame).toDouble(),
  height: kFloorTableH.toDouble(),
);

/// Inverse of [floorRoomLeft]/[floorRoomTop]: the stored coordinates whose
/// anchor lands at the given room-unit top-left (clamped — a drag can push
/// past the walls).
FloorPoint floorStoredFromRoomTopLeft(
  double leftRoom,
  double topRoom, {
  TableSectionRoomFramePreset? frame,
}) => (
  x: clampFloorCoordinate(
    (leftRoom / floorUsableW(frame) * kFloorLayoutMax).round(),
  ),
  y: clampFloorCoordinate((topRoom / kFloorUsableH * kFloorLayoutMax).round()),
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
/// section: the first slot of a 4×3 grid of canvas anchor points that does
/// not overlap any [occupied] placement under the SHARED footprint contract
/// ([floorPlacementsOverlap]). Falls back to the canvas centre when the grid
/// is full. Row-major walk => stable results. 027: the grid pitch (2500 in x,
/// 3333 in y stored units → 2125×2533 room units) clears the 1500×2400
/// footprint on every surface, so default placements can never overlap.
FloorPoint initialFloorPlacement(
  List<FloorPoint> occupied, {
  TableSectionRoomFramePreset? frame,
}) {
  // TABLE-121: wide-footprint frames fit fewer columns — the column pitch in
  // ROOM units is usable/columns, which must clear the footprint width. The
  // legacy 4x3 grid stays byte-identical for NULL.
  final columns = frame == null
      ? 4
      : (floorUsableW(frame) / floorTableFootprintW(frame))
            .floor()
            .clamp(1, 4)
            .toInt();
  const rows = 3;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final candidate = (
        x: ((column + 0.5) / columns * kFloorLayoutMax).round(),
        y: ((row + 0.5) / rows * kFloorLayoutMax).round(),
      );
      final clear = occupied.every(
        (p) => !floorPlacementsOverlap(candidate, p, frame: frame),
      );
      if (clear) return candidate;
    }
  }
  return (x: kFloorLayoutMax ~/ 2, y: kFloorLayoutMax ~/ 2);
}

// ---------------------------------------------------------------------------
// 027 — visual-only floor FIXTURES (walls/doors/windows/cashier/plants).
// Same stored-coordinate semantics as tables — the anchor is the fraction of
// the USABLE span for the fixture's EFFECTIVE (rotated) footprint — so a
// fixture renders at the identical room spot on every surface.
// ---------------------------------------------------------------------------

/// The wire kinds of a floor fixture (owner decision 4 — exactly these five).
const List<String> kFloorElementKinds = [
  'wall',
  'door',
  'window',
  'cashier',
  'plant',
];

/// The per-kind DEFAULT footprint in room units (display + palette creation;
/// the server owns enforcement). Wall/window are resizable; door/cashier/plant
/// are fixed to these sizes.
({int w, int h}) floorElementDefaultSize(String kind) => switch (kind) {
  'wall' => (w: 3000, h: 150),
  'window' => (w: 2000, h: 150),
  'door' => (w: 900, h: 150),
  _ => (w: 900, h: 900), // cashier, plant
};

/// Whether a fixture kind may be resized (owner decision 4).
bool floorElementResizable(String kind) => kind == 'wall' || kind == 'window';

/// Whether a fixture kind may carry a label (owner decision 4).
bool floorElementLabelable(String kind) => kind == 'cashier' || kind == 'door';

/// TABLE-VISUAL-CONFIGURATION-120 — fixture row key carrying the persisted
/// artwork variant on every wire.
const String kFloorElementStyleWireKey = 'visual_style';

/// TABLE-VISUAL-CONFIGURATION-120 — the per-kind artwork-variant vocabulary,
/// mirrored EXACTLY by the server setter (`app.set_floor_element_style`).
/// NULL/absent = the kind's default artwork (the first-shipped 119D look).
const Map<String, List<String>> kFloorElementStyleRegistry = {
  'cashier': ['modern', 'wood', 'dark'],
  'plant': ['leafy', 'palm', 'compact_pot'],
  'door': ['wood', 'glass', 'modern'],
  'window': ['modern_glass', 'framed', 'dark_frame'],
  'wall': ['plain', 'brick', 'wood_partition'],
};

/// The variants an owner may pick for [kind] (empty for unknown kinds).
List<String> floorElementStylesFor(String kind) =>
    kFloorElementStyleRegistry[kind] ?? const [];

/// Whether [style] is a valid persisted variant for [kind]. `null` is always
/// allowed (the default artwork).
bool isFloorElementStyleAllowed(String kind, String? style) =>
    style == null || floorElementStylesFor(kind).contains(style);

/// The EFFECTIVE room-unit footprint after [quarterTurns] clockwise quarter
/// rotations (odd turns swap the axes; width/height stay stored unrotated).
({double w, double h}) floorElementEffectiveSize(
  int width,
  int height, {
  int quarterTurns = 0,
}) {
  double clampSpan(int v) => v < 100
      ? 100.0
      : (v > kFloorLayoutMax ? kFloorLayoutMax.toDouble() : v.toDouble());
  final rotated = quarterTurns.isOdd;
  return (
    w: clampSpan(rotated ? height : width),
    h: clampSpan(rotated ? width : height),
  );
}

/// The room-unit rect of a fixture at stored ([x], [y]) with the given stored
/// footprint + orientation. Same anchor semantics as [floorTableRoomRect]:
/// the stored value is the fraction of the usable span (10000 − effective
/// footprint) the top-left anchor sits at — always in-bounds by construction.
FloorRoomRect floorElementRoomRect(
  int x,
  int y, {
  required int width,
  required int height,
  int quarterTurns = 0,
}) {
  final eff = floorElementEffectiveSize(
    width,
    height,
    quarterTurns: quarterTurns,
  );
  final usableW = kFloorLayoutMax - eff.w;
  final usableH = kFloorLayoutMax - eff.h;
  return (
    left: clampFloorCoordinate(x) / kFloorLayoutMax * usableW,
    top: clampFloorCoordinate(y) / kFloorLayoutMax * usableH,
    width: eff.w,
    height: eff.h,
  );
}

/// Inverse of [floorElementRoomRect]'s anchor: the stored coordinates whose
/// anchor lands at the given room-unit top-left for the effective footprint
/// ([effW]×[effH]). A zero usable span (full-canvas fixture) stores 0.
FloorPoint floorElementStoredFromRoomTopLeft(
  double leftRoom,
  double topRoom, {
  required double effW,
  required double effH,
}) {
  final usableW = kFloorLayoutMax - effW;
  final usableH = kFloorLayoutMax - effH;
  return (
    x: usableW <= 0
        ? 0
        : clampFloorCoordinate((leftRoom / usableW * kFloorLayoutMax).round()),
    y: usableH <= 0
        ? 0
        : clampFloorCoordinate((topRoom / usableH * kFloorLayoutMax).round()),
  );
}

/// Whether a fixture rect and a table rect intersect in room units — the
/// Dashboard's NON-blocking informational warning (owner decision 6: overlap
/// is legal, never auto-corrected, never blocks saving).
bool floorRectsIntersect(FloorRoomRect a, FloorRoomRect b) =>
    a.left < b.left + b.width &&
    b.left < a.left + a.width &&
    a.top < b.top + b.height &&
    b.top < a.top + a.height;

/// Whether two placed tables overlap under the SHARED footprint contract —
/// evaluated per-axis in ROOM UNITS, so the verdict is identical on every
/// surface at every viewport width. Used for the Dashboard's informational
/// arrange-mode warning AND the initial-placement grid; saved positions are
/// never auto-moved.
bool floorPlacementsOverlap(
  FloorPoint a,
  FloorPoint b, {
  TableSectionRoomFramePreset? frame,
}) {
  final dLeft =
      (floorRoomLeft(a.x, frame: frame) - floorRoomLeft(b.x, frame: frame))
          .abs();
  final dTop = (floorRoomTop(a.y) - floorRoomTop(b.y)).abs();
  return dLeft < floorTableFootprintW(frame) && dTop < kFloorTableH;
}
