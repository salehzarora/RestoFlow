import 'package:flutter/widgets.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show FloorPreset, TableVisualPreset;

/// TABLE-119D — the shared floor-SCENE material spec.
///
/// Client-only styling (nothing persisted, nothing on the wire): a small set
/// of restaurant-safe material families, each resolving to a deterministic
/// paint palette, plus the one default mapping `preset + floor -> material`.
/// The section canvas exposes its floor preset through
/// [RestoflowFloorSceneScope], so every table resolves the same material on
/// every surface with ZERO app plumbing — and a caller may still override
/// per-tile via `RestoflowFloorTable.material` (the seam a future persisted
/// per-table choice would plug into).

/// The table-surface material families. Broad, not restaurant-specific.
enum RestoflowFloorMaterial {
  wood,
  darkWood,
  lightWood,
  plastic,
  neutralModern,
}

/// The resolved paint colors of one [RestoflowFloorMaterial]. All values are
/// compile-time constants — the painter stays a pure function of its fields.
class RestoflowMaterialPalette {
  const RestoflowMaterialPalette({
    required this.top,
    required this.topLight,
    required this.topDark,
    required this.grain,
    required this.edge,
    required this.chairSeat,
    required this.chairFrame,
    required this.labelPlate,
  });

  /// Tabletop base and its gradient stops.
  final Color top;
  final Color topLight;
  final Color topDark;

  /// Grain/plank strokes drawn over the top.
  final Color grain;

  /// The rim/bevel edge of the top.
  final Color edge;

  /// Seat cushion and frame/backrest of chairs, stools and benches.
  final Color chairSeat;
  final Color chairFrame;

  /// The light plate behind the label column when the caller's onFill is
  /// dark (a light-luminance tone per material, pinned by tests); a dark
  /// onFill flips to the shared dark plate instead.
  final Color labelPlate;

  static const _wood = RestoflowMaterialPalette(
    top: Color(0xFFC79A66),
    topLight: Color(0xFFDDB98E),
    topDark: Color(0xFFA87C4C),
    grain: Color(0xFF8F653A),
    edge: Color(0xFF77542F),
    chairSeat: Color(0xFF8C5A38),
    chairFrame: Color(0xFF5D3B22),
    labelPlate: Color(0xF2FFF8EE),
  );

  static const _darkWood = RestoflowMaterialPalette(
    top: Color(0xFF6E4B31),
    topLight: Color(0xFF876246),
    topDark: Color(0xFF553722),
    grain: Color(0xFF41291A),
    edge: Color(0xFF33200F),
    chairSeat: Color(0xFF4E332B),
    chairFrame: Color(0xFF33201B),
    labelPlate: Color(0xF2FFF4E6),
  );

  static const _lightWood = RestoflowMaterialPalette(
    top: Color(0xFFE8D5B5),
    topLight: Color(0xFFF4E7D0),
    topDark: Color(0xFFD6BC94),
    grain: Color(0xFFC0A377),
    edge: Color(0xFFA98E60),
    chairSeat: Color(0xFFB99B72),
    chairFrame: Color(0xFF8B6F4A),
    labelPlate: Color(0xE8FFFFFF),
  );

  static const _plastic = RestoflowMaterialPalette(
    top: Color(0xFFF2F5F8),
    topLight: Color(0xFFFFFFFF),
    topDark: Color(0xFFDDE4EB),
    grain: Color(0x00000000),
    edge: Color(0xFFB6C0CB),
    chairSeat: Color(0xFF6E8194),
    chairFrame: Color(0xFF48586A),
    labelPlate: Color(0xE6FFFFFF),
  );

  static const _neutralModern = RestoflowMaterialPalette(
    top: Color(0xFFDAD3C7),
    topLight: Color(0xFFEBE5DB),
    topDark: Color(0xFFC4BAAA),
    grain: Color(0xFFA99E8B),
    edge: Color(0xFF8E8574),
    chairSeat: Color(0xFF7B7263),
    chairFrame: Color(0xFF57503F),
    labelPlate: Color(0xEEFFFDF8),
  );

  static RestoflowMaterialPalette of(RestoflowFloorMaterial m) => switch (m) {
    RestoflowFloorMaterial.wood => _wood,
    RestoflowFloorMaterial.darkWood => _darkWood,
    RestoflowFloorMaterial.lightWood => _lightWood,
    RestoflowFloorMaterial.plastic => _plastic,
    RestoflowFloorMaterial.neutralModern => _neutralModern,
  };
}

/// The ONE deterministic default mapping (pinned by tests): what material a
/// table preset renders on a given floor when nothing overrides it. Barrel
/// tables are rustic everywhere; the rest follow the floor's temperature so
/// tables never disappear into their own floor (warm wood on the dark floor,
/// light wood on the white canvas, modern materials on tile/stone).
RestoflowFloorMaterial restoflowDefaultFloorMaterial(
  TableVisualPreset preset,
  FloorPreset floor,
) {
  if (preset == TableVisualPreset.tableWithBarrels) {
    return RestoflowFloorMaterial.darkWood;
  }
  if (preset == TableVisualPreset.boothTable) {
    return floor.isDark
        ? RestoflowFloorMaterial.darkWood
        : RestoflowFloorMaterial.wood;
  }
  return switch (floor) {
    FloorPreset.plainLight => RestoflowFloorMaterial.lightWood,
    FloorPreset.woodDark => RestoflowFloorMaterial.wood,
    FloorPreset.tileModern => RestoflowFloorMaterial.plastic,
    FloorPreset.stoneNeutral => RestoflowFloorMaterial.neutralModern,
  };
}

/// TABLE-119D — how the section canvas hands its floor preset down to every
/// tile it places, so [restoflowDefaultFloorMaterial] resolves identically on
/// every surface without any per-call-site plumbing. Strip tiles rendered
/// outside a canvas fall back to [FloorPreset.plainLight].
class RestoflowFloorSceneScope extends InheritedWidget {
  const RestoflowFloorSceneScope({
    super.key,
    required this.floorPreset,
    required super.child,
  });

  final FloorPreset floorPreset;

  static FloorPreset of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RestoflowFloorSceneScope>()
          ?.floorPreset ??
      FloorPreset.plainLight;

  @override
  bool updateShouldNotify(RestoflowFloorSceneScope old) =>
      old.floorPreset != floorPreset;
}
