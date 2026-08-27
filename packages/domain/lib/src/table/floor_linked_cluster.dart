/// TABLE-FLOOR-MAP-POLISH-027 — DERIVED visual packing for linked tables.
///
/// Linking never writes coordinates (verified: neither link RPC touches
/// layout_x/layout_y), so the "linked tables look physically joined" visual
/// is a pure RENDER-TIME derivation: while a group exists, its placed members
/// in one section pack side-by-side around a deterministic anchor; the moment
/// the group disappears the renderer falls back to each member's unchanged
/// base coordinates — exact restore by construction, no snapshot, no RPC.
///
/// Everything is deterministic and pure so all three surfaces (Dashboard,
/// POS picker, Move Table) derive byte-identical layouts.
library;

import 'floor_layout_geometry.dart';
import 'table_section_room_frame.dart';

/// One placed member of a link group inside ONE section.
typedef FloorClusterMember = ({String id, int x, int y});

/// The seam gap between packed members, in room units.
const int kFloorClusterSeam = 120;

/// Packs the PLACED members of one link group (all in the same section) into
/// a joined cluster and returns the DERIVED stored coordinates per member id.
///
///  * [members] must be in the caller's stable display order (label, id) —
///    that order fills the cluster slots;
///  * the ANCHOR — the member whose saved base position is top-left-most
///    (smallest y, then x, then id) — keeps its base position; the others
///    pack beside it row-major with a [kFloorClusterSeam] seam, wrapping to
///    the next row when the room's right edge would be crossed;
///  * the whole cluster is then shifted left/up as needed so every member
///    stays inside the room — no member ever overlaps another by
///    construction;
///  * a group with fewer than two placed members derives nothing (identity).
///
/// TABLE-ROOM-FRAME-121: the pack projects through the SAME [frame] the
/// surfaces render with (footprint, usable span, inverse) so the derived
/// stored coordinates round-trip to the exact seam gap in every room —
/// NULL keeps the legacy pack byte-for-byte.
Map<String, FloorPoint> packLinkedCluster(
  List<FloorClusterMember> members, {
  TableSectionRoomFramePreset? frame,
}) {
  if (members.length < 2) {
    return {for (final m in members) m.id: (x: m.x, y: m.y)};
  }

  // Deterministic anchor: top-left-most SAVED base position.
  var anchor = members.first;
  for (final m in members.skip(1)) {
    final better =
        m.y < anchor.y ||
        (m.y == anchor.y &&
            (m.x < anchor.x ||
                (m.x == anchor.x && m.id.compareTo(anchor.id) < 0)));
    if (better) anchor = m;
  }

  final fx = floorTableFootprintW(frame);
  final stepX = fx + kFloorClusterSeam;
  const stepY = kFloorTableH + kFloorClusterSeam;
  // How many columns fit across the whole room (6 with the v1 Standard
  // constants; fewer in narrower frames — never below one).
  final maxCols = ((kFloorLayoutMax + kFloorClusterSeam) ~/ stepX).clamp(
    1,
    members.length,
  );
  final cols = members.length < maxCols ? members.length : maxCols;

  // Slot order: the anchor first, then the remaining members in the caller's
  // stable order.
  final ordered = <FloorClusterMember>[
    anchor,
    for (final m in members)
      if (m.id != anchor.id) m,
  ];

  final anchorLeft = floorRoomLeft(anchor.x, frame: frame);
  final anchorTop = floorRoomTop(anchor.y);
  final lefts = <String, double>{};
  final tops = <String, double>{};
  var maxRight = 0.0;
  var maxBottom = 0.0;
  for (var k = 0; k < ordered.length; k++) {
    final col = k % cols;
    final row = k ~/ cols;
    final left = anchorLeft + col * stepX;
    final top = anchorTop + row * stepY;
    lefts[ordered[k].id] = left;
    tops[ordered[k].id] = top;
    if (left + fx > maxRight) maxRight = left + fx;
    if (top + kFloorTableH > maxBottom) maxBottom = top + kFloorTableH;
  }

  // Clamp the WHOLE cluster inside the room (shift left/up; never below 0).
  var shiftX = maxRight > kFloorLayoutMax ? maxRight - kFloorLayoutMax : 0.0;
  var shiftY = maxBottom > kFloorLayoutMax ? maxBottom - kFloorLayoutMax : 0.0;
  if (shiftX > anchorLeft + 0.0 && anchorLeft - shiftX < 0) {
    shiftX = shiftX.clamp(0.0, anchorLeft);
  }
  if (shiftY > 0 && anchorTop - shiftY < 0) {
    shiftY = shiftY.clamp(0.0, anchorTop);
  }

  return {
    for (final m in ordered)
      m.id: floorStoredFromRoomTopLeft(
        lefts[m.id]! - shiftX,
        tops[m.id]! - shiftY,
        frame: frame,
      ),
  };
}

/// The room-unit bounding box of a packed cluster (for the seam outline),
/// inflated by [pad] room units on every side and clamped to the room.
FloorRoomRect floorClusterSeamRect(
  Iterable<FloorPoint> derived, {
  double pad = 70,
  TableSectionRoomFramePreset? frame,
}) {
  final fx = floorTableFootprintW(frame);
  var minL = double.infinity, minT = double.infinity;
  var maxR = 0.0, maxB = 0.0;
  for (final p in derived) {
    final l = floorRoomLeft(p.x, frame: frame);
    final t = floorRoomTop(p.y);
    if (l < minL) minL = l;
    if (t < minT) minT = t;
    if (l + fx > maxR) maxR = l + fx;
    if (t + kFloorTableH > maxB) maxB = t + kFloorTableH;
  }
  final left = (minL - pad).clamp(0.0, kFloorLayoutMax.toDouble());
  final top = (minT - pad).clamp(0.0, kFloorLayoutMax.toDouble());
  final right = (maxR + pad).clamp(0.0, kFloorLayoutMax.toDouble());
  final bottom = (maxB + pad).clamp(0.0, kFloorLayoutMax.toDouble());
  return (left: left, top: top, width: right - left, height: bottom - top);
}
