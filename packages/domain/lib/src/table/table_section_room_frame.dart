/// TABLE-ROOM-FRAME-121 — the per-section ROOM FRAME preset.
///
/// Server: `table_sections.room_frame_preset` — nullable text, structurally
/// CHECKed (`^[a-z][a-z0-9_]{0,39}$`) AND semantically validated by the
/// dedicated setter against exactly this vocabulary. NULL = Standard = the
/// exact legacy room (aspect 1.9, table footprint 1500 stored units wide) —
/// Standard is deliberately NOT a wire key, so every existing section keeps
/// rendering byte-identically.
///
/// THE GEOMETRY MODEL. Stored `layout_x`/`layout_y` (and fixture anchors)
/// are FRACTIONS of the room's usable span — they are never rewritten when
/// the frame changes; the room merely reprojects. Each preset carries:
///  * [aspect] — the section canvas's physical width : height;
///  * [tableFootprintXUnits] — the table footprint's stored-unit width for
///    that aspect, chosen so the TABLE TILE's physical aspect stays exactly
///    the legacy 1.1875 ((fx / 2400) * aspect == (1500 / 2400) * 1.9) —
///    furniture never squashes or stretches, and a narrower room simply
///    fits fewer, relatively larger tables (like a real narrow hall).
/// The footprint HEIGHT stays 2400 stored units in every frame.
library;

/// Section-catalog key (`list_tables` sections rows).
const String kSectionRoomFrameWireKey = 'room_frame_preset';

/// Per-table row key on wires that ship no section catalog
/// (`pos_tables` / `kiosk_tables`).
const String kSectionRoomFrameRowWireKey = 'section_room_frame_preset';

/// The legacy/Standard canvas aspect (width : height). The design_system
/// token `kRestoflowFloorSectionAspect` must equal this (pinned by tests).
const double kFloorStandardAspect = 1.9;

enum TableSectionRoomFramePreset {
  /// A smaller room, still landscape — tables read relatively larger.
  compact('compact', aspect: 1.6, tableFootprintXUnits: 1781),

  /// A square room.
  square('square', aspect: 1.0, tableFootprintXUnits: 2850),

  /// A wide banquet hall.
  wide('wide', aspect: 2.6, tableFootprintXUnits: 1096),

  /// A taller-than-wide room.
  portrait('portrait', aspect: 0.72, tableFootprintXUnits: 3958),

  /// A clearly long, deep, narrow room.
  longNarrow('long_narrow', aspect: 0.5, tableFootprintXUnits: 5700);

  const TableSectionRoomFramePreset(
    this.wire, {
    required this.aspect,
    required this.tableFootprintXUnits,
  });

  /// The stored key (`table_sections.room_frame_preset`).
  final String wire;

  /// Canvas physical width : height for this room.
  final double aspect;

  /// The table footprint's stored-unit width in this room (height is always
  /// 2400) — keeps the tile's physical aspect identical to Standard.
  final int tableFootprintXUnits;

  /// Strict decode: unknown / non-string / null => null (= Standard/legacy).
  static TableSectionRoomFramePreset? tryParse(Object? wire) {
    if (wire is! String) return null;
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

/// The canvas aspect for [frame] (NULL = the exact legacy 1.9).
double floorRoomAspect(TableSectionRoomFramePreset? frame) =>
    frame?.aspect ?? kFloorStandardAspect;
