/// TABLE-VISUAL-LAYOUT-118 — the SHARED visual-preset vocabulary of the floor
/// map: how one table is DRAWN and how one section's FLOOR is painted.
///
/// This is a presentation vocabulary carried on the tenant's saved layout, not
/// a business state: no rule reads a preset, and a preset never changes the
/// table's footprint or its saved placement (the room-unit rect from
/// `floor_layout_geometry.dart` is identical for every preset — a round table
/// is drawn INSIDE the classic footprint, so switching presets never moves,
/// re-scales or re-interprets a saved `layout_x`/`layout_y`).
///
/// Wire contract (server: `tables.visual_preset`, `table_sections.floor_preset`
/// — nullable text keys validated by the DB CHECK `^[a-z][a-z0-9_]{0,39}$`;
/// the REGISTRY of meaningful keys is client-owned, exactly like the
/// `menu_categories.icon_key` precedent):
///   * a NULL / absent / unknown key decodes to the DEFAULT preset — a legacy
///     row, an older backend, or a key added by a newer client all render as
///     they did before this ticket (never a failed floor read);
///   * every consumer (Dashboard, POS, kiosk) decodes through [fromWire] so no
///     surface can drift to its own fallback.
library;

/// The DB CHECK for a preset key, mirrored client-side so a picker can never
/// send a key the server would reject.
final RegExp _kPresetKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// Whether [key] satisfies the server key CHECK (`^[a-z][a-z0-9_]{0,39}$`).
bool isValidPresetKey(String key) => _kPresetKeyPattern.hasMatch(key);

/// Per-table row key (list_tables / pos_tables / kiosk_tables rows).
const String kTableVisualPresetWireKey = 'visual_preset';

/// Section catalog key (list_tables `sections` rows).
const String kFloorPresetWireKey = 'floor_preset';

/// Per-table row key carrying the OWNING section's floor preset on the wires
/// that ship no section catalog (pos_tables / kiosk_tables rows).
const String kSectionFloorPresetWireKey = 'section_floor_preset';

/// How ONE table is drawn on the floor map. The footprint is the same for all.
enum TableVisualPreset {
  /// The pre-118 look: rounded rectangle surface with chair glyphs per side.
  classicRectTable('classic_rect_table'),

  /// A round top with chairs spread radially around it.
  roundTable('round_table'),

  /// A high standing table with a barrel at either end (no chair glyphs).
  tableWithBarrels('table_with_barrels'),

  /// A booth: the surface between two bench slabs.
  boothTable('booth_table');

  const TableVisualPreset(this.wire);

  /// The stored key (`tables.visual_preset`).
  final String wire;

  /// The look of every legacy row.
  static const TableVisualPreset defaultPreset = classicRectTable;

  /// Strict decode: the exact wire key or null.
  static TableVisualPreset? tryParse(Object? wire) {
    if (wire is! String) return null;
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }

  /// Tolerant decode: null / absent / unknown → [defaultPreset].
  static TableVisualPreset fromWire(Object? wire) =>
      tryParse(wire) ?? defaultPreset;
}

/// How ONE section's floor is painted under its tables.
enum FloorPreset {
  /// The pre-118 look: a plain light canvas.
  plainLight('plain_light', isDark: false),

  /// Dark wooden planks.
  woodDark('wood_dark', isDark: true),

  /// A light modern tile grid.
  tileModern('tile_modern', isDark: false),

  /// A neutral warm stone.
  stoneNeutral('stone_neutral', isDark: false);

  const FloorPreset(this.wire, {required this.isDark});

  /// The stored key (`table_sections.floor_preset`).
  final String wire;

  /// Whether the floor is dark — tiles pick contrasting ink from this, so a
  /// table label stays legible on every floor.
  final bool isDark;

  /// The look of every legacy section.
  static const FloorPreset defaultPreset = plainLight;

  /// Strict decode: the exact wire key or null.
  static FloorPreset? tryParse(Object? wire) {
    if (wire is! String) return null;
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }

  /// Tolerant decode: null / absent / unknown → [defaultPreset].
  static FloorPreset fromWire(Object? wire) => tryParse(wire) ?? defaultPreset;
}
