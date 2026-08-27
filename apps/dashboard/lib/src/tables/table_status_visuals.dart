import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPreset,
        TableSectionRoomFramePreset,
        TableVisualMaterial,
        TableVisualPreset;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'table_models.dart';

/// TABLE-VISUAL-LAYOUT-118: the localized name of a table shape preset.
String tableVisualPresetLabel(AppLocalizations l10n, TableVisualPreset p) =>
    switch (p) {
      TableVisualPreset.classicRectTable => l10n.tablesVisualPresetClassicRect,
      TableVisualPreset.roundTable => l10n.tablesVisualPresetRound,
      TableVisualPreset.tableWithBarrels => l10n.tablesVisualPresetBarrels,
      TableVisualPreset.boothTable => l10n.tablesVisualPresetBooth,
    };

/// TABLE-VISUAL-LAYOUT-118: the localized name of a floor style preset.
String floorPresetLabel(AppLocalizations l10n, FloorPreset p) => switch (p) {
  FloorPreset.plainLight => l10n.tablesFloorPresetPlainLight,
  FloorPreset.woodDark => l10n.tablesFloorPresetWoodDark,
  FloorPreset.tileModern => l10n.tablesFloorPresetTileModern,
  FloorPreset.stoneNeutral => l10n.tablesFloorPresetStoneNeutral,
};

/// TABLE-VISUAL-CONFIGURATION-120C: the localized name of a table material
/// (`null` = Auto — the floor decides).
String tableVisualMaterialLabel(
  AppLocalizations l10n,
  TableVisualMaterial? m,
) => switch (m) {
  null => l10n.tablesVisualAuto,
  TableVisualMaterial.wood => l10n.tablesVisualMaterialWood,
  TableVisualMaterial.darkWood => l10n.tablesVisualMaterialDarkWood,
  TableVisualMaterial.lightWood => l10n.tablesVisualMaterialLightWood,
  TableVisualMaterial.rusticWood => l10n.tablesVisualMaterialRusticWood,
  TableVisualMaterial.plastic => l10n.tablesVisualMaterialPlastic,
  TableVisualMaterial.neutralModern => l10n.tablesVisualMaterialNeutralModern,
};

/// TABLE-ROOM-FRAME-121: the localized name of a section room size/shape
/// (`null` = Standard — the legacy room).
String roomFramePresetLabel(
  AppLocalizations l10n,
  TableSectionRoomFramePreset? p,
) => switch (p) {
  null => l10n.tablesRoomFrameStandard,
  TableSectionRoomFramePreset.compact => l10n.tablesRoomFrameCompact,
  TableSectionRoomFramePreset.square => l10n.tablesRoomFrameSquare,
  TableSectionRoomFramePreset.wide => l10n.tablesRoomFrameWide,
  TableSectionRoomFramePreset.portrait => l10n.tablesRoomFramePortrait,
  TableSectionRoomFramePreset.longNarrow => l10n.tablesRoomFrameLongNarrow,
};

/// TABLE-VISUAL-CONFIGURATION-120C: the localized name of a fixture artwork
/// style wire key (`null` = Auto). Unknown keys fall back to Auto — the
/// picker only ever offers registry keys, so this is belt-and-braces.
String floorElementStyleLabel(AppLocalizations l10n, String? style) =>
    switch (style) {
      null => l10n.tablesVisualAuto,
      'modern' => l10n.floorElementStyleModern,
      'wood' => l10n.floorElementStyleWood,
      'dark' => l10n.floorElementStyleDark,
      'leafy' => l10n.floorElementStyleLeafy,
      'palm' => l10n.floorElementStylePalm,
      'compact_pot' => l10n.floorElementStyleCompactPot,
      'glass' => l10n.floorElementStyleGlass,
      'modern_glass' => l10n.floorElementStyleModernGlass,
      'framed' => l10n.floorElementStyleFramed,
      'dark_frame' => l10n.floorElementStyleDarkFrame,
      'plain' => l10n.floorElementStylePlain,
      'brick' => l10n.floorElementStyleBrick,
      'wood_partition' => l10n.floorElementStyleWoodPartition,
      _ => l10n.tablesVisualAuto,
    };

/// The localized label + semantic tone + icon for a table status. Tones ride
/// the shared TRUE semantic palette (success/warning/info/danger), so the
/// tiles stay themeable (no hardcoded palette). Extracted from the Tables
/// screen (TABLE-FLOOR-LAYOUT-021) so the floor editor and the classic card
/// grid can never drift apart.
({String label, RestoflowTone tone, IconData icon}) tableStatusVisual(
  BuildContext context,
  DiningTableStatus status,
) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    DiningTableStatus.available => (
      label: l10n.tablesStatusAvailable,
      tone: RestoflowTone.success,
      icon: Icons.check_circle_outline,
    ),
    DiningTableStatus.occupied => (
      label: l10n.tablesStatusOccupied,
      tone: RestoflowTone.warning,
      icon: Icons.people_alt_outlined,
    ),
    DiningTableStatus.reserved => (
      label: l10n.tablesStatusReserved,
      tone: RestoflowTone.info,
      icon: Icons.event_seat_outlined,
    ),
    DiningTableStatus.outOfService => (
      label: l10n.tablesStatusOutOfService,
      tone: RestoflowTone.danger,
      icon: Icons.block_outlined,
    ),
  };
}

/// PILOT-OPERATIONS-CORRECTIONS-001: the localized label for a server effective
/// state string, reusing the manual-status vocabulary. Finding 6: an unknown
/// state gets an HONEST localized label (never raw, never Available).
String tableEffectiveLabel(BuildContext context, String effective) {
  final status = DiningTableStatus.fromWire(effective);
  if (status == null) return AppLocalizations.of(context).tablesStatusUnknown;
  return tableStatusVisual(context, status).label;
}

/// TABLE-FLOOR-LAYOUT-021: the FLOOR tint for a table — driven by the
/// EFFECTIVE state (what the POS floor actually reads), falling back to the
/// manual status when an older backend sent none. Unknown fails closed to the
/// out-of-service (danger) visual.
({String label, RestoflowTone tone, IconData icon}) tableFloorVisual(
  BuildContext context,
  DashboardTable table,
) {
  final effective = table.effectiveState;
  final status = effective == null
      ? table.status
      : (DiningTableStatus.fromWire(effective) ??
            DiningTableStatus.outOfService);
  return tableStatusVisual(context, status);
}
