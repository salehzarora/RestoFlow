import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show
        RestoflowFloorFixture,
        RestoflowFloorPlacedTile,
        RestoflowFloorPresetPalette,
        RestoflowFloorSectionCanvas,
        RestoflowFloorTable;
import 'package:restoflow_domain/restoflow_domain.dart'
    show floorElementRoomRect, floorTableRoomRect;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../state/kiosk_live_runtime.dart';
import '../widgets/kiosk_chrome.dart';

/// 03 · Table picker — per-zone FLOOR MAP (TABLE-VISUAL-LAYOUT-118: the SAME
/// saved room map the Dashboard configured and the POS renders — shared
/// canvas contract, section floor preset, per-table shape, fixtures) with the
/// zone-grouped 4-column grid kept for tables that have no saved placement;
/// legend; fixed continue bar. Only AVAILABLE tables are tappable; occupied / reserved /
/// out-of-service stay visible but dimmed with their status dot and label —
/// the honest floor. Demo mode renders the fixture floor; real mode renders
/// the live `kiosk_tables` read, refreshed on entry, on demand, and again
/// before Continue whenever the data has gone stale — a selection is never
/// allowed to look guaranteed on old truth. NO hold of any kind happens here.
class KioskTablesScreen extends ConsumerStatefulWidget {
  const KioskTablesScreen({super.key});

  @override
  ConsumerState<KioskTablesScreen> createState() => _KioskTablesScreenState();
}

class _KioskTablesScreenState extends ConsumerState<KioskTablesScreen> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    // Fresh floor on entry (live mode only; demo has nothing to fetch).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(kioskTablesViewProvider).live) {
        ref.read(kioskLiveProvider.notifier).refreshTables();
      }
    });
  }

  /// Continue with the stale-floor guard: live mode re-reads when the data
  /// is old, and only proceeds if the chosen table is STILL available in the
  /// fresh floor; otherwise the selection clears with an honest notice.
  Future<void> _confirm() async {
    final controller = ref.read(kioskFlowProvider.notifier);
    final view = ref.read(kioskTablesViewProvider);
    if (!view.live) {
      controller.confirmTable();
      return;
    }
    if (_confirming) return;
    final live = ref.read(kioskLiveProvider.notifier);
    if (live.tablesStale) {
      setState(() => _confirming = true);
      await live.refreshTables();
      if (!mounted) return;
      setState(() => _confirming = false);
      // 092: re-check by the AUTHORITATIVE table id (labels can repeat).
      final flow = ref.read(kioskFlowProvider);
      final label = flow.selectedTable;
      final id = flow.selectedTableId;
      final fresh = ref.read(kioskTablesViewProvider);
      final stillAvailable =
          label != null &&
          fresh.status == KioskTablesStatus.ready &&
          fresh.zones.any(
            (z) => z.tables.any(
              (t) =>
                  t.label == label &&
                  (id == null || t.id == id) &&
                  t.state == KioskTableState.available,
            ),
          );
      if (!stillAvailable) {
        controller.toggleTable(label ?? '', id: id);
        controller.showStaffToast('table-taken');
        return;
      }
    }
    controller.confirmTable();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(
      kioskFlowProvider.select(
        (s) => (
          rtl: s.rtl,
          selectedTable: s.selectedTable,
          selectedTableId: s.selectedTableId,
        ),
      ),
    );
    // 118: id-aware selection (labels can repeat across sections); the label
    // compare is only the fallback for a table without an id.
    bool isSelected(KioskFixtureTable table) =>
        table.id != null && state.selectedTableId != null
        ? table.id == state.selectedTableId
        : state.selectedTable == table.label;
    final controller = ref.read(kioskFlowProvider.notifier);
    final view = ref.watch(kioskTablesViewProvider);
    final zones = view.zones;
    final rtl = state.rtl;

    String zoneName(KioskFixtureZone zone) =>
        zone.displayName ??
        switch (zone.id) {
          'patio' => l10n.kioskZonePatio,
          'bar' => l10n.kioskZoneBar,
          _ => l10n.kioskZoneHall,
        };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(52, 52, 52, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: KioskColors.glass(.06),
                      border: Border.all(
                        color: KioskColors.glass(.14),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.kioskDineIn,
                      style: KioskType.body(
                        22,
                        FontWeight.w700,
                        color: KioskColors.accentTop,
                      ),
                    ),
                  ),
                  KioskBackPill(onTap: controller.backFromTables),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                l10n.kioskChooseTable,
                style: KioskType.display(rtl, 74, height: 1),
              ),
              const SizedBox(height: 8),
              const KioskUnderline(width: 300),
              const SizedBox(height: 26),
              Row(
                children: [
                  _LegendDot(
                    color: KioskColors.tableFree,
                    label: l10n.kioskTableAvailable,
                  ),
                  const SizedBox(width: 26),
                  _LegendDot(
                    color: KioskColors.tableOccupied,
                    label: l10n.kioskTableOccupied,
                  ),
                  const SizedBox(width: 26),
                  _LegendDot(
                    color: KioskColors.tableReserved,
                    label: l10n.kioskTableReserved,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (view.live && view.status != KioskTablesStatus.ready)
          Expanded(
            child: Center(
              child: KioskGlass(
                radius: 36,
                padding: const EdgeInsets.symmetric(
                  horizontal: 72,
                  vertical: 64,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (view.status == KioskTablesStatus.loading)
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          color: KioskColors.accentTop,
                        ),
                      )
                    else
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 84,
                        color: KioskColors.textMuted,
                      ),
                    const SizedBox(height: 34),
                    Text(
                      view.status == KioskTablesStatus.loading
                          ? l10n.kioskTablesLoadingTitle
                          : l10n.kioskTablesUnavailableTitle,
                      textAlign: TextAlign.center,
                      style: KioskType.body(34, FontWeight.w800),
                    ),
                    if (view.status != KioskTablesStatus.loading) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.kioskTablesUnavailableBody,
                        textAlign: TextAlign.center,
                        style: KioskType.body(
                          24,
                          FontWeight.w500,
                          color: KioskColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 30),
                      KioskAccentPill(
                        key: const Key('kiosk-tables-retry'),
                        onTap: () => ref
                            .read(kioskLiveProvider.notifier)
                            .refreshTables(),
                        child: Text(
                          l10n.kioskRetry.toUpperCase(),
                          style: KioskType.body(
                            26,
                            FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(52, 8, 52, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (view.live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: KioskPressable(
                          key: const Key('kiosk-tables-refresh'),
                          onTap: () => ref
                              .read(kioskLiveProvider.notifier)
                              .refreshTables(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: KioskColors.glass(.06),
                              border: Border.all(
                                color: KioskColors.glass(.14),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.refresh_rounded,
                                  size: 26,
                                  color: KioskColors.textSoft,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  l10n.kioskTablesRefresh,
                                  style: KioskType.body(
                                    21,
                                    FontWeight.w700,
                                    color: KioskColors.textSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final zone in zones) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          zoneName(zone),
                          style: KioskType.body(30, FontWeight.w800),
                        ),
                        const SizedBox(width: 16),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            l10n.kioskFreeCount(
                              zone.tables
                                  .where(
                                    (t) => t.state == KioskTableState.available,
                                  )
                                  .length,
                            ),
                            style: KioskType.body(
                              21,
                              FontWeight.w600,
                              color: KioskColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 118: placed tables render on the SHARED room map;
                    // unplaced ones keep the list card grid below it.
                    if (zone.tables.any((t) => t.isPlaced)) ...[
                      _KioskZoneMap(
                        zone: zone,
                        isSelected: isSelected,
                        onTap: (table) =>
                            controller.toggleTable(table.label, id: table.id),
                      ),
                      if (zone.tables.any((t) => !t.isPlaced))
                        const SizedBox(height: 20),
                    ],
                    if (zone.tables.any((t) => !t.isPlaced))
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 20,
                        childAspectRatio: (976 - 3 * 20) / 4 / 196,
                        children: [
                          for (final table in zone.tables)
                            if (!table.isPlaced)
                              _TableCard(
                                table: table,
                                selected: isSelected(table),
                                onTap: table.state == KioskTableState.available
                                    ? () => controller.toggleTable(
                                        table.label,
                                        id: table.id,
                                      )
                                    : null,
                              ),
                        ],
                      ),
                    const SizedBox(height: 40),
                  ],
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(52, 28, 52, 44),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .3],
              colors: [KioskColors.canvasTint(0), KioskColors.canvasBottom],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        state.selectedTable != null
                            ? '${l10n.kioskTableLabel} ${state.selectedTable}'
                            : l10n.kioskPickTableFirst,
                        style: KioskType.body(
                          24,
                          FontWeight.w600,
                          color: KioskColors.textMuted,
                        ),
                      ),
                    ),
                    if (state.selectedTable != null) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_rounded,
                        size: 26,
                        color: KioskColors.tableFree,
                      ),
                    ],
                  ],
                ),
              ),
              KioskAccentPill(
                key: const Key('kiosk-table-continue'),
                onTap: _confirm,
                enabled: state.selectedTable != null && !_confirming,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.kioskContinue.toUpperCase(),
                      style: KioskType.body(
                        30,
                        FontWeight.w900,
                        color: state.selectedTable != null
                            ? Colors.white
                            : KioskColors.textDisabled,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Icon(
                      rtl
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                      size: 34,
                      color: state.selectedTable != null
                          ? Colors.white
                          : KioskColors.textDisabled,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: KioskType.body(
          21,
          FontWeight.w600,
          color: KioskColors.textMuted,
        ),
      ),
    ],
  );
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.selected,
    required this.onTap,
  });
  final KioskFixtureTable table;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = table.state == KioskTableState.available;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dot = switch (table.state) {
      KioskTableState.available => KioskColors.tableFree,
      KioskTableState.occupied => KioskColors.tableOccupied,
      KioskTableState.reserved => KioskColors.tableReserved,
      KioskTableState.outOfService => KioskColors.tableOutOfService,
    };
    final statusLabel = switch (table.state) {
      KioskTableState.occupied => l10n.kioskTableOccupied,
      KioskTableState.reserved => l10n.kioskTableReserved,
      KioskTableState.outOfService => '—',
      KioskTableState.available => null,
    };

    return KioskPressable(
      onTap: onTap,
      enabled: onTap != null,
      pressedScale: .96,
      child: Opacity(
        opacity: available ? 1 : .55,
        child: Stack(
          clipBehavior: Clip.none,
          // The card must FILL its 229×196 grid cell (V2 wide table cards);
          // a shrink-wrapped Stack child would collapse to label width.
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: selected
                    ? KioskColors.ring.withValues(alpha: .15)
                    : KioskColors.glass(available ? .05 : .02),
                border: Border.all(
                  color: selected
                      ? KioskColors.ring
                      : KioskColors.glass(available ? .13 : .06),
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: KioskColors.ring.withValues(alpha: .3),
                          blurRadius: 40,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    table.label,
                    textDirection: TextDirection.ltr,
                    style: KioskType.display(
                      rtl,
                      52,
                      color: selected
                          ? Colors.white
                          : available
                          ? KioskColors.textPrimary
                          : KioskColors.textDisabled,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.kioskSeatsCount(table.seats),
                    style: KioskType.body(
                      20,
                      FontWeight.w600,
                      color: KioskColors.textMuted,
                    ),
                  ),
                  if (statusLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      statusLabel.toUpperCase(),
                      style: KioskType.body(
                        17,
                        FontWeight.w700,
                        color: dot,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PositionedDirectional(
              top: 16,
              end: 16,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ),
            if (selected)
              PositionedDirectional(
                top: -14,
                start: -14,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: kioskAccentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: KioskColors.ring.withValues(alpha: .5),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.check, size: 26, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// TABLE-VISUAL-LAYOUT-118: one zone's FLOOR MAP — the shared section canvas
/// (the exact room-unit → pixel contract the Dashboard editor and the POS
/// picker use, so every table sits at the same relative spot on all three
/// surfaces), painted with the section's floor preset, its visual fixtures
/// underneath, and one [_KioskFloorTile] per placed table. Wrapped in a
/// RepaintBoundary so a selection change never repaints the floor pattern
/// (PERF-110 posture).
class _KioskZoneMap extends StatelessWidget {
  const _KioskZoneMap({
    required this.zone,
    required this.isSelected,
    required this.onTap,
  });

  final KioskFixtureZone zone;
  final bool Function(KioskFixtureTable table) isSelected;
  final ValueChanged<KioskFixtureTable> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = RestoflowFloorPresetPalette.of(zone.floorPreset);
    return RepaintBoundary(
      key: Key('kiosk-floor-canvas-${zone.id}'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: KioskColors.glass(.14), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 34,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          // The kiosk reads at arm's length: scale the tile typography up
          // (the shared tile clamps at 1.4×, so labels never overflow).
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.35)),
            child: RestoflowFloorSectionCanvas(
              floorPreset: zone.floorPreset,
              // Fixtures under the tables; pure decoration, never tappable.
              background: [
                for (final e in zone.elements)
                  RestoflowFloorPlacedTile(
                    room: floorElementRoomRect(
                      e.layoutX,
                      e.layoutY,
                      width: e.widthNorm,
                      height: e.heightNorm,
                      quarterTurns: e.orientationQuarterTurns,
                    ),
                    child: IgnorePointer(
                      child: RestoflowFloorFixture(
                        key: Key('kiosk-floor-element-${e.id}'),
                        kind: e.kind,
                        label: e.label,
                      ),
                    ),
                  ),
              ],
              // Room-unit rects from the SHARED contract — identical relative
              // geometry to the Dashboard editor / POS picker by construction.
              placed: [
                for (final table in zone.tables)
                  if (table.isPlaced)
                    RestoflowFloorPlacedTile(
                      room: floorTableRoomRect(table.layoutX!, table.layoutY!),
                      child: _KioskFloorTile(
                        table: table,
                        palette: palette,
                        selected: isSelected(table),
                        onTap: table.state == KioskTableState.available
                            ? () => onTap(table)
                            : null,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One table on the kiosk map: the SHARED top-down tile (shape preset inside
/// the unchanged footprint) dressed for the customer — surface/ink picked to
/// contrast the section floor, the honest state on the border + footnote,
/// dimmed when not selectable, and an unmistakable selected state (accent
/// fill + glow + check badge). Only an AVAILABLE table gets a tap.
class _KioskFloorTile extends StatelessWidget {
  const _KioskFloorTile({
    required this.table,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final KioskFixtureTable table;
  final RestoflowFloorPresetPalette palette;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = table.state == KioskTableState.available;
    final stateColor = switch (table.state) {
      KioskTableState.available => KioskColors.tableFree,
      KioskTableState.occupied => KioskColors.tableOccupied,
      KioskTableState.reserved => KioskColors.tableReserved,
      KioskTableState.outOfService => KioskColors.tableOutOfService,
    };
    final statusLabel = switch (table.state) {
      KioskTableState.occupied => l10n.kioskTableOccupied,
      KioskTableState.reserved => l10n.kioskTableReserved,
      KioskTableState.outOfService => '—',
      KioskTableState.available => null,
    };
    final fill = selected
        ? KioskColors.ring
        : available
        ? palette.tableSurface
        : palette.tableSurface.withValues(alpha: .55);
    final onFill = selected
        ? KioskColors.onAction
        : available
        ? palette.tableOnSurface
        : palette.tableOnSurface.withValues(alpha: .7);
    final border = selected
        ? KioskColors.ring
        : available
        ? palette.tableBorder
        : stateColor.withValues(alpha: .85);
    final key = table.id ?? table.label;
    final semanticLabel = statusLabel == null
        ? '${table.label}, ${l10n.kioskSeatsCount(table.seats)}'
        : '${table.label}, $statusLabel';

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: KioskPressable(
        key: Key('kiosk-floor-tile-$key'),
        onTap: onTap,
        enabled: onTap != null,
        pressedScale: .96,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: KioskColors.ring.withValues(alpha: .45),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: RestoflowFloorTable(
                label: table.label,
                seats: table.seats,
                preset: table.visualPreset,
                fill: fill,
                onFill: onFill,
                border: border,
                borderWidth: selected ? 3 : 2,
                statusIcon: selected
                    ? Icon(Icons.check_rounded, size: 15, color: onFill)
                    : null,
                footnote: statusLabel?.toUpperCase(),
              ),
            ),
            // 118F: the customer-safe state dot the legend promises — on
            // EVERY placed tile (green = available), swapped for the accent
            // badge while selected. Decoration only: it never moves the tile.
            if (!selected)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  key: Key('kiosk-floor-dot-$key'),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.base, width: 1.5),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                top: -12,
                left: -12,
                child: Container(
                  key: Key('kiosk-floor-selected-$key'),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: kioskAccentGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: KioskColors.ring.withValues(alpha: .5),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.check, size: 20, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
