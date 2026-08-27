/// TABLE-VISUAL-CONFIGURATION-120 — the owner-configurable table-surface
/// MATERIAL vocabulary.
///
/// Server: `tables.visual_material` — a nullable text key, structurally
/// CHECKed (`^[a-z][a-z0-9_]{0,39}$`) AND semantically validated by the
/// dedicated setter (`app.set_table_visual_material`) against exactly this
/// vocabulary. NULL means AUTO: the client's deterministic preset+floor
/// mapping (TABLE-119D) — Auto is deliberately NOT a wire key, so an
/// unconfigured table keeps following mapping improvements.
///
/// This is the ONE authoritative vocabulary (the `TableVisualPreset`
/// precedent): the design_system palettes and every app decode from here —
/// no surface may invent its own material enum.
library;

/// Per-table row key on `list_tables` / `pos_tables` / `kiosk_tables`.
const String kTableVisualMaterialWireKey = 'visual_material';

/// The persisted material families. Wire keys are stable snake_case.
enum TableVisualMaterial {
  /// Warm oak.
  wood('wood'),

  /// Dark walnut.
  darkWood('dark_wood'),

  /// Pale ash/birch.
  lightWood('light_wood'),

  /// Weathered, heavy-grain rustic oak.
  rusticWood('rustic_wood'),

  /// Clean casual plastic / laminate.
  plastic('plastic'),

  /// Warm-gray contemporary stone/laminate.
  neutralModern('neutral_modern');

  const TableVisualMaterial(this.wire);

  /// The stored key (`tables.visual_material`).
  final String wire;

  /// Strict decode: an unknown / non-string / null wire is `null` — which the
  /// renderer treats as AUTO (the deterministic 119D mapping). There is no
  /// tolerant "default material": Auto IS the default.
  static TableVisualMaterial? tryParse(Object? wire) {
    if (wire is! String) return null;
    for (final m in values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
}
