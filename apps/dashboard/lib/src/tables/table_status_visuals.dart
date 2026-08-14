import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'table_models.dart';

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
