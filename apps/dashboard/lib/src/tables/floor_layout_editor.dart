import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPoint,
        floorClusterSeamRect,
        floorFractionOf,
        floorPlacementsOverlap,
        floorPointFromFractions,
        floorTableRoomRect,
        initialFloorPlacement,
        kFloorTableW,
        kFloorTableH,
        kFloorUsableW,
        kFloorUsableH,
        packLinkedCluster;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'table_models.dart';
import 'table_status_visuals.dart';

/// TABLE-FLOOR-LAYOUT-021 — the Dashboard FLOOR editor.
///
/// One white [RestoflowFloorSectionCanvas] per ACTIVE section (owner order),
/// each rendering its tables as top-down [RestoflowFloorTable]s at their SAVED
/// normalized positions. Arrange mode adds:
///  * free dragging (clamped to the canvas), with the WRITE fired on drag END
///    only — never per pointer move;
///  * optimistic movement: the tile stays where it was dropped while the RPC
///    runs; a failure reverts it to the saved position (and the screen's
///    snackbar names the failure);
///  * deterministic initial placement for section tables that have no
///    position yet ("Place on map");
///  * an informational overlap notice (nothing is ever auto-moved);
///  * per-section management (rename / reorder ▲▼ / delete).
///
/// Coordinates are PHYSICAL: the canvas never mirrors under RTL — only the
/// text localizes. Unassigned/legacy tables render in a clearly-labelled
/// auto-flow zone below the sections.
class FloorLayoutEditor extends StatefulWidget {
  const FloorLayoutEditor({
    super.key,
    required this.snapshot,
    required this.arrange,
    required this.onRenameSection,
    required this.onDeleteSection,
    required this.onReorderSections,
    required this.onMoveTable,
    required this.onSetSection,
  });

  final TablesFloorSnapshot snapshot;
  final bool arrange;
  final void Function(DashboardTableSection section) onRenameSection;
  final void Function(DashboardTableSection section) onDeleteSection;

  /// Receives the COMPLETE live section id list in the new order.
  final void Function(List<String> ids) onReorderSections;

  /// Persists a placement; resolves FALSE when the write failed (revert).
  final Future<bool> Function(String tableId, int layoutX, int layoutY)
  onMoveTable;

  /// Opens the set-section flow for an unassigned table (reuses the card menu
  /// logic on the screen).
  final void Function(DashboardTable table) onSetSection;

  @override
  State<FloorLayoutEditor> createState() => _FloorLayoutEditorState();
}

class _FloorLayoutEditorState extends State<FloorLayoutEditor> {
  /// tableId -> the CURRENT on-screen fractions while a drag is in flight or
  /// awaiting its save (the optimistic position). Cleared whenever a fresh
  /// snapshot arrives — saved truth then owns the map again.
  final Map<String, (double, double)> _overrides = {};

  @override
  void didUpdateWidget(FloorLayoutEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.snapshot, widget.snapshot)) _overrides.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sections = [
      for (final s in widget.snapshot.sections)
        if (s.isActive) s,
    ];
    final tablesBySection = <String, List<DashboardTable>>{};
    final unassigned = <DashboardTable>[];
    for (final t in widget.snapshot.tables) {
      final sid = t.sectionId;
      if (sid == null) {
        unassigned.add(t);
      } else {
        (tablesBySection[sid] ??= []).add(t);
      }
    }
    if (sections.isEmpty && unassigned.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          _sectionHeader(context, sections, i),
          _sectionCanvas(
            context,
            sections[i],
            tablesBySection[sections[i].id] ?? const [],
          ),
          const SizedBox(height: RestoflowSpacing.lg),
        ],
        if (unassigned.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: RestoflowIconSizes.sm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: RestoflowSpacing.xs),
              Text(
                l10n.tablesUnassignedZone,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Wrap(
            spacing: RestoflowSpacing.md,
            runSpacing: RestoflowSpacing.md,
            children: [
              for (final t in unassigned)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _floorTile(context, t, inStrip: true),
                    if (widget.arrange)
                      TextButton(
                        key: Key('floor-set-section-${t.id}'),
                        onPressed: () => widget.onSetSection(t),
                        child: Text(l10n.tablesSetSection),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.lg),
        ],
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    List<DashboardTableSection> sections,
    int index,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final section = sections[index];

    List<String> reordered(int from, int to) {
      final ids = [for (final s in sections) s.id];
      final id = ids.removeAt(from);
      ids.insert(to, id);
      // The RPC needs the COMPLETE live set — inactive sections included.
      final inactive = [
        for (final s in widget.snapshot.sections)
          if (!s.isActive) s.id,
      ];
      return [...ids, ...inactive];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.location_on_outlined,
            size: RestoflowIconSizes.sm,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: RestoflowSpacing.xs),
          Expanded(
            child: Text(
              section.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.arrange) ...[
            IconButton(
              key: Key('section-up-${section.id}'),
              tooltip: l10n.tablesArrange,
              onPressed: index == 0
                  ? null
                  : () => widget.onReorderSections(reordered(index, index - 1)),
              icon: const Icon(Icons.arrow_upward, size: RestoflowIconSizes.sm),
            ),
            IconButton(
              key: Key('section-down-${section.id}'),
              tooltip: l10n.tablesArrange,
              onPressed: index == sections.length - 1
                  ? null
                  : () => widget.onReorderSections(reordered(index, index + 1)),
              icon: const Icon(
                Icons.arrow_downward,
                size: RestoflowIconSizes.sm,
              ),
            ),
            IconButton(
              key: Key('section-rename-${section.id}'),
              tooltip: l10n.tablesSectionEdit,
              onPressed: () => widget.onRenameSection(section),
              icon: const Icon(
                Icons.edit_outlined,
                size: RestoflowIconSizes.sm,
              ),
            ),
            IconButton(
              key: Key('section-delete-${section.id}'),
              tooltip: l10n.tablesSectionDelete,
              style: RestoflowButtonStyles.dangerGhost(context),
              onPressed: () => widget.onDeleteSection(section),
              icon: const Icon(
                Icons.delete_outline,
                size: RestoflowIconSizes.sm,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCanvas(
    BuildContext context,
    DashboardTableSection section,
    List<DashboardTable> tables,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final placed = <DashboardTable>[];
    final unplaced = <DashboardTable>[];
    for (final t in tables) {
      (t.isPlaced ? placed : unplaced).add(t);
    }

    (double, double) fractionsOf(DashboardTable t) =>
        _overrides[t.id] ??
        (() {
          final f = floorFractionOf(t.layoutX, t.layoutY);
          return f == null ? (0.0, 0.0) : (f.x, f.y);
        })();

    // 027: DERIVED per-section clustering for operationally linked tables —
    // read-only on the Dashboard (linking is POS-owned). Base coordinates are
    // never written; unlink restores exactly by construction.
    final derived = <String, FloorPoint>{};
    final seams = <RestoflowFloorPlacedTile>[];
    final byGroup = <String, List<DashboardTable>>{};
    for (final t in placed) {
      final g = t.groupId;
      if (g != null) (byGroup[g] ??= []).add(t);
    }
    for (final members in byGroup.values) {
      if (members.length < 2) continue;
      members.sort(
        (a, b) => a.label.compareTo(b.label) != 0
            ? a.label.compareTo(b.label)
            : a.id.compareTo(b.id),
      );
      final packed = packLinkedCluster([
        for (final t in members) (id: t.id, x: t.layoutX!, y: t.layoutY!),
      ]);
      derived.addAll(packed);
      seams.add(
        RestoflowFloorPlacedTile(
          room: floorClusterSeamRect(packed.values),
          child: const RestoflowFloorClusterSeam(),
        ),
      );
    }

    FloorPoint pointOf(DashboardTable t) {
      final d = derived[t.id];
      if (d != null) return d;
      final f = fractionsOf(t);
      return floorPointFromFractions(f.$1, f.$2);
    }

    // Informational overlap check over the CURRENT on-screen placements
    // (derived positions for linked members — what is actually visible).
    var overlaps = false;
    if (widget.arrange) {
      final points = <FloorPoint>[for (final t in placed) pointOf(t)];
      outer:
      for (var a = 0; a < points.length; a++) {
        for (var b = a + 1; b < points.length; b++) {
          if (floorPlacementsOverlap(points[a], points[b])) {
            overlaps = true;
            break outer;
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overlaps)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.xs),
            child: Row(
              key: Key('floor-overlap-${section.id}'),
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: RestoflowIconSizes.sm,
                  color: RestoflowTone.warning.styleOf(theme).accent,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.tablesOverlapWarning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: RestoflowTone.warning.styleOf(theme).accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            // 027: the SHARED contract — the canvas maps room units to pixels
            // itself; drags convert through the same usable-span constants.
            final canvasWidth =
                constraints.maxWidth < kRestoflowFloorMinCanvasWidth
                ? kRestoflowFloorMinCanvasWidth
                : constraints.maxWidth;
            final canvas = Size(
              canvasWidth,
              canvasWidth / kRestoflowFloorSectionAspect,
            );
            ({double left, double top, double width, double height}) roomOf(
              DashboardTable t,
            ) {
              final d = derived[t.id];
              if (d != null) return floorTableRoomRect(d.x, d.y);
              final f = fractionsOf(t);
              return (
                left: f.$1 * kFloorUsableW,
                top: f.$2 * kFloorUsableH,
                width: kFloorTableW.toDouble(),
                height: kFloorTableH.toDouble(),
              );
            }

            return RestoflowFloorSectionCanvas(
              key: Key('floor-canvas-${section.id}'),
              background: seams,
              placed: [
                for (final t in placed)
                  RestoflowFloorPlacedTile(
                    room: roomOf(t),
                    // 027: a LINKED member renders at its derived cluster
                    // slot and is not draggable while linked — its base
                    // position is preserved for the unlink restore.
                    child: widget.arrange && t.groupId == null
                        ? _draggableTile(context, t, canvas)
                        : _floorTile(context, t),
                  ),
              ],
            );
          },
        ),
        if (unplaced.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tablesNotPlaced,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.xs),
                Wrap(
                  spacing: RestoflowSpacing.md,
                  runSpacing: RestoflowSpacing.md,
                  children: [
                    for (final t in unplaced)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _floorTile(context, t, inStrip: true),
                          if (widget.arrange)
                            TextButton(
                              key: Key('floor-place-${t.id}'),
                              onPressed: () => _placeInitial(t, placed),
                              child: Text(l10n.tablesPlaceOnMap),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Deterministic first placement for an unplaced section table, saved
  /// through the same optimistic write path a drag uses.
  Future<void> _placeInitial(
    DashboardTable table,
    List<DashboardTable> placed,
  ) async {
    final occupied = <FloorPoint>[
      for (final p in placed)
        if (p.layoutX case final x?)
          if (p.layoutY case final y?) (x: x, y: y),
    ];
    final spot = initialFloorPlacement(occupied);
    setState(() {
      _overrides[table.id] = (spot.x / 10000.0, spot.y / 10000.0);
    });
    final saved = await widget.onMoveTable(table.id, spot.x, spot.y);
    if (!saved && mounted) {
      setState(() => _overrides.remove(table.id));
    }
  }

  /// The arrange-mode draggable wrapper: pan updates the on-screen fraction
  /// (NO network); pan END persists once, optimistically, reverting on a
  /// failed write. The EAGER recognizer claims the pointer on touch-down so a
  /// tile drag always beats the surrounding vertical ListView scroll — in
  /// arrange mode a tile is a drag handle, nothing else.
  Widget _draggableTile(
    BuildContext context,
    DashboardTable table,
    Size canvas,
  ) {
    void onUpdate(DragUpdateDetails details) {
      final current =
          _overrides[table.id] ??
          (() {
            final f = floorFractionOf(table.layoutX, table.layoutY);
            return f == null ? (0.0, 0.0) : (f.x, f.y);
          })();
      // 027: the usable anchor span in PIXELS comes from the SHARED room-unit
      // contract, so a 1px pointer move maps to the same fraction on every
      // surface at this canvas size.
      final usableW = canvas.width * kFloorUsableW / 10000;
      final usableH = canvas.height * kFloorUsableH / 10000;
      setState(() {
        _overrides[table.id] = (
          (current.$1 + (usableW <= 0 ? 0 : details.delta.dx / usableW)).clamp(
            0.0,
            1.0,
          ),
          (current.$2 + (usableH <= 0 ? 0 : details.delta.dy / usableH)).clamp(
            0.0,
            1.0,
          ),
        );
      });
    }

    Future<void> onEnd(DragEndDetails details) async {
      final f = _overrides[table.id];
      if (f == null) return;
      final point = floorPointFromFractions(f.$1, f.$2);
      // Save on drag END only; optimistic (the tile stays), revert on fail.
      final saved = await widget.onMoveTable(table.id, point.x, point.y);
      if (!saved && mounted) {
        setState(() => _overrides.remove(table.id));
      }
    }

    return RawGestureDetector(
      key: Key('floor-drag-${table.id}'),
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
              _EagerPanGestureRecognizer.new,
              (recognizer) => recognizer
                ..onUpdate = onUpdate
                ..onEnd = onEnd,
            ),
      },
      child: _floorTile(context, table),
    );
  }

  Widget _floorTile(
    BuildContext context,
    DashboardTable table, {
    bool inStrip = false,
  }) {
    final theme = Theme.of(context);
    final visual = tableFloorVisual(context, table);
    final style = visual.tone.styleOf(theme);
    final l10n = AppLocalizations.of(context);
    final tile = Semantics(
      label: '${table.label}, ${visual.label}',
      child: RestoflowFloorTable(
        key: Key('floor-table-${table.id}'),
        label: table.label,
        seats: table.seats,
        fill: style.container,
        onFill: style.onContainer,
        border: style.accent,
        // 027: a linked member's glyph is the link — the seam outline plus
        // this icon mark group membership without hiding the status tint.
        statusIcon: Icon(
          table.groupId != null ? Icons.link : visual.icon,
          size: 13,
          color: style.accent,
        ),
        footnote: table.activeOrderCount > 0
            ? l10n.tablesOpenOrders(table.activeOrderCount)
            : visual.label,
      ),
    );
    // 027: outside a canvas (strips) the tile has no room to size it — give
    // it the fixed reference footprint.
    if (inStrip) {
      return SizedBox.fromSize(size: kRestoflowFloorStripTileSize, child: tile);
    }
    return tile;
  }
}

/// A pan recognizer that claims the pointer the moment it goes down, so an
/// arrange-mode tile drag ALWAYS beats the enclosing vertical scrollable.
/// Outside arrange mode the tiles are plain widgets and scrolling is normal.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
