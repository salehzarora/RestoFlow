import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPoint,
        FloorPreset,
        FloorRoomRect,
        floorClusterSeamRect,
        floorElementDefaultSize,
        floorElementLabelable,
        floorElementResizable,
        floorElementRoomRect,
        floorFractionOf,
        floorPlacementsOverlap,
        floorPointFromFractions,
        floorRectsIntersect,
        floorTableRoomRect,
        initialFloorPlacement,
        kFloorElementKinds,
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
    required this.onCreateElement,
    required this.onSaveElement,
    required this.onDeleteElement,
    required this.onSetFloorPreset,
  });

  /// TABLE-VISUAL-LAYOUT-118: persists a section's floor style (chosen from
  /// the section header picker in arrange mode).
  final void Function(DashboardTableSection section, FloorPreset preset)
  onSetFloorPreset;

  final TablesFloorSnapshot snapshot;
  final bool arrange;
  final void Function(DashboardTableSection section) onRenameSection;
  final void Function(DashboardTableSection section) onDeleteSection;

  /// 027: persists a NEW fixture (id empty — the store mints it) chosen from
  /// the per-section palette at a deterministic safe spot.
  final void Function(DashboardFloorElement element) onCreateElement;

  /// 027: persists a fixture edit (move/resize/rotate/relabel), fired on the
  /// gesture END only; resolves FALSE when the write failed (revert).
  final Future<bool> Function(DashboardFloorElement element) onSaveElement;

  /// 027: deletes a fixture (element-arrange menu action).
  final void Function(DashboardFloorElement element) onDeleteElement;

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

  /// 027: elementId -> (optimistic element, anchor fractions) — same
  /// lifecycle as [_overrides].
  final Map<String, (DashboardFloorElement, double, double)> _elementOverrides =
      {};

  /// 027: elementId -> cumulative pointer travel of the CURRENT drag, so the
  /// gesture end can tell a tap (opens the element menu) from a move (saves).
  final Map<String, double> _elementDragTravel = {};

  /// 027: the explicit arrange SUBMODE (owner decision 7) — Tables: only
  /// tables draggable; Elements: only fixtures editable.
  bool _elementsMode = false;

  @override
  void didUpdateWidget(FloorLayoutEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.snapshot, widget.snapshot)) {
      _overrides.clear();
      _elementOverrides.clear();
    }
    if (!widget.arrange) _elementsMode = false;
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
        // 027: the explicit arrange SUBMODE toggle (owner decision 7).
        if (widget.arrange)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.sm),
            child: Wrap(
              spacing: RestoflowSpacing.sm,
              children: [
                ChoiceChip(
                  key: const Key('floor-submode-tables'),
                  label: Text(l10n.tablesFloorModeTables),
                  avatar: const Icon(
                    Icons.table_restaurant_outlined,
                    size: RestoflowIconSizes.sm,
                  ),
                  selected: !_elementsMode,
                  onSelected: (_) => setState(() => _elementsMode = false),
                ),
                ChoiceChip(
                  key: const Key('floor-submode-elements'),
                  label: Text(l10n.tablesFloorModeElements),
                  avatar: const Icon(
                    Icons.chair_outlined,
                    size: RestoflowIconSizes.sm,
                  ),
                  selected: _elementsMode,
                  onSelected: (_) => setState(() => _elementsMode = true),
                ),
              ],
            ),
          ),
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
          if (widget.arrange && _elementsMode)
            // 027: the per-section fixture palette (owner decision 4 kinds).
            PopupMenuButton<String>(
              key: Key('floor-add-element-${section.id}'),
              tooltip: l10n.tablesAddElement,
              icon: const Icon(
                Icons.add_box_outlined,
                size: RestoflowIconSizes.sm,
              ),
              onSelected: (kind) => _createElement(section, kind),
              itemBuilder: (context) => [
                for (final kind in kFloorElementKinds)
                  PopupMenuItem<String>(
                    key: Key('floor-add-kind-$kind-${section.id}'),
                    value: kind,
                    child: Text(_kindLabel(l10n, kind)),
                  ),
              ],
            ),
          if (widget.arrange) ...[
            // 118: the per-section FLOOR STYLE picker (the control center of
            // the shared floor look; the POS + kiosk render the same preset).
            PopupMenuButton<FloorPreset>(
              key: Key('section-floor-preset-${section.id}'),
              tooltip: l10n.tablesFloorPreset,
              initialValue: section.floorPreset,
              icon: const Icon(
                Icons.texture_outlined,
                size: RestoflowIconSizes.sm,
              ),
              onSelected: (preset) => widget.onSetFloorPreset(section, preset),
              itemBuilder: (context) => [
                for (final preset in FloorPreset.values)
                  PopupMenuItem<FloorPreset>(
                    key: Key('floor-preset-${preset.wire}-${section.id}'),
                    value: preset,
                    child: Row(
                      children: [
                        Container(
                          width: RestoflowIconSizes.md,
                          height: RestoflowIconSizes.md,
                          decoration: BoxDecoration(
                            color: RestoflowFloorPresetPalette.of(preset).base,
                            borderRadius: BorderRadius.circular(
                              RestoflowRadii.sm,
                            ),
                            border: Border.all(
                              color: RestoflowFloorPresetPalette.of(
                                preset,
                              ).line,
                            ),
                          ),
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Text(floorPresetLabel(l10n, preset)),
                      ],
                    ),
                  ),
              ],
            ),
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

    // 027: this section's fixtures at their CURRENT (override-applied) state.
    final elements = <DashboardFloorElement>[
      for (final e in widget.snapshot.floorElements)
        if (e.sectionId == section.id) _elementOverrides[e.id]?.$1 ?? e,
    ];

    // Informational overlap check over the CURRENT on-screen placements
    // (derived positions for linked members — what is actually visible).
    var overlaps = false;
    var elementOverlaps = false;
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
      // 027: fixture-vs-table intersection is LEGAL (owner decision 6) —
      // this is a NON-blocking notice, never a gate, nothing is auto-moved.
      final tableRects = <FloorRoomRect>[
        for (final p in points) floorTableRoomRect(p.x, p.y),
      ];
      outerElements:
      for (final e in elements) {
        final rect = _elementRoomRect(e);
        for (final tr in tableRects) {
          if (floorRectsIntersect(rect, tr)) {
            elementOverlaps = true;
            break outerElements;
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
        if (elementOverlaps)
          Padding(
            padding: const EdgeInsets.only(bottom: RestoflowSpacing.xs),
            child: Row(
              key: Key('floor-element-overlap-${section.id}'),
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: RestoflowIconSizes.sm,
                  color: RestoflowTone.warning.styleOf(theme).accent,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.tablesElementOverlapWarning,
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
              // 118: the section's saved floor style (shared painter).
              floorPreset: section.floorPreset,
              // 027 z-order: fixtures under the seams, seams under the tables.
              background: [
                for (final e in elements)
                  RestoflowFloorPlacedTile(
                    room: _elementRoomRect(e),
                    child: widget.arrange && _elementsMode
                        ? _draggableElement(context, e, canvas)
                        : IgnorePointer(
                            child: RestoflowFloorFixture(
                              key: Key('floor-element-${e.id}'),
                              kind: e.kind,
                              quarterTurns: e.orientationQuarterTurns,
                              label: e.label,
                              style: e.visualStyle,
                            ),
                          ),
                  ),
                ...seams,
              ],
              placed: [
                for (final t in placed)
                  RestoflowFloorPlacedTile(
                    room: roomOf(t),
                    // 027: a LINKED member renders at its derived cluster
                    // slot and is not draggable while linked — its base
                    // position is preserved for the unlink restore. The
                    // Elements submode (owner decision 7) locks tables too.
                    child: widget.arrange && !_elementsMode && t.groupId == null
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

  // ---- 027: visual fixture editing -----------------------------------------

  static String _kindLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'wall' => l10n.floorElementWall,
        'door' => l10n.floorElementDoor,
        'window' => l10n.floorElementWindow,
        'cashier' => l10n.floorElementCashier,
        _ => l10n.floorElementPlant,
      };

  static FloorRoomRect _elementRoomRect(DashboardFloorElement e) =>
      floorElementRoomRect(
        e.layoutX,
        e.layoutY,
        width: e.widthNorm,
        height: e.heightNorm,
        quarterTurns: e.orientationQuarterTurns,
      );

  /// Palette creation: id EMPTY (the store mints), per-kind default footprint,
  /// a deterministic near-top-left spot spread by the section's fixture count.
  void _createElement(DashboardTableSection section, String kind) {
    final size = floorElementDefaultSize(kind);
    var count = 0;
    for (final e in widget.snapshot.floorElements) {
      if (e.sectionId == section.id) count++;
    }
    final x = 400 + count * 1200;
    widget.onCreateElement(
      DashboardFloorElement(
        id: '',
        sectionId: section.id,
        kind: kind,
        layoutX: x > 9600 ? 9600 : x,
        layoutY: 300,
        widthNorm: size.w,
        heightNorm: size.h,
      ),
    );
  }

  /// One optimistic fixture write: show [updated] immediately, revert to the
  /// saved snapshot state if the write fails.
  Future<void> _applyElement(DashboardFloorElement updated) async {
    setState(() {
      _elementOverrides[updated.id] = (
        updated,
        updated.layoutX / 10000.0,
        updated.layoutY / 10000.0,
      );
    });
    final saved = await widget.onSaveElement(updated);
    if (!saved && mounted) {
      setState(() => _elementOverrides.remove(updated.id));
    }
  }

  /// The elements-submode wrapper: pan moves the fixture (save on END only,
  /// optimistic + revert), while a movement-free release is a TAP that opens
  /// the element menu (rotate/resize/label/delete).
  Widget _draggableElement(
    BuildContext context,
    DashboardFloorElement element,
    Size canvas,
  ) {
    final rect = _elementRoomRect(element);

    void onUpdate(DragUpdateDetails details) {
      final entry =
          _elementOverrides[element.id] ??
          (element, element.layoutX / 10000.0, element.layoutY / 10000.0);
      // The usable anchor span in px for THIS fixture's effective footprint —
      // the same room-unit contract the tables use.
      final usableW = canvas.width * (10000 - rect.width) / 10000;
      final usableH = canvas.height * (10000 - rect.height) / 10000;
      final fx = (entry.$2 + (usableW <= 0 ? 0 : details.delta.dx / usableW))
          .clamp(0.0, 1.0);
      final fy = (entry.$3 + (usableH <= 0 ? 0 : details.delta.dy / usableH))
          .clamp(0.0, 1.0);
      _elementDragTravel[element.id] =
          (_elementDragTravel[element.id] ?? 0) + details.delta.distance;
      setState(() {
        _elementOverrides[element.id] = (
          entry.$1.copyWith(
            layoutX: (fx * 10000).round(),
            layoutY: (fy * 10000).round(),
          ),
          fx,
          fy,
        );
      });
    }

    Future<void> onEnd(DragEndDetails details) async {
      final travelled = _elementDragTravel.remove(element.id) ?? 0;
      if (travelled < 4) {
        // A movement-free press is a TAP: open the element menu.
        _showElementMenu(element);
        return;
      }
      final entry = _elementOverrides[element.id];
      if (entry == null) return;
      final saved = await widget.onSaveElement(entry.$1);
      if (!saved && mounted) {
        setState(() => _elementOverrides.remove(element.id));
      }
    }

    return RawGestureDetector(
      key: Key('floor-element-drag-${element.id}'),
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
      child: RestoflowFloorFixture(
        key: Key('floor-element-${element.id}'),
        kind: element.kind,
        quarterTurns: element.orientationQuarterTurns,
        label: element.label,
        style: element.visualStyle,
        selected: true,
      ),
    );
  }

  void _showElementMenu(DashboardFloorElement element) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          key: const Key('floor-element-menu'),
          children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(_kindLabel(l10n, element.kind)),
              subtitle: element.label == null ? null : Text(element.label!),
              enabled: false,
            ),
            ListTile(
              key: const Key('floor-element-rotate'),
              leading: const Icon(Icons.rotate_90_degrees_cw_outlined),
              title: Text(l10n.floorElementRotate),
              onTap: () {
                Navigator.of(sheetContext).pop();
                final current = _elementOverrides[element.id]?.$1 ?? element;
                _applyElement(
                  current.copyWith(
                    orientationQuarterTurns:
                        (current.orientationQuarterTurns + 1) % 4,
                  ),
                );
              },
            ),
            if (floorElementResizable(element.kind))
              ListTile(
                key: const Key('floor-element-resize'),
                leading: const Icon(Icons.open_in_full_outlined),
                title: Text(l10n.floorElementResize),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _resizeElementDialog(element);
                },
              ),
            if (floorElementLabelable(element.kind))
              ListTile(
                key: const Key('floor-element-label'),
                leading: const Icon(Icons.label_outline),
                title: Text(l10n.floorElementLabel),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _labelElementDialog(element);
                },
              ),
            ListTile(
              key: const Key('floor-element-delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.floorElementDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                // 028: never a one-tap delete — an arranged floor takes time
                // to build, so the write happens only after confirmation.
                _confirmDeleteElement(element);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 028: the fixture delete confirmation — names the kind (and the label
  /// when one exists). Cancel, the barrier and system back all close with
  /// ZERO write; only an explicit confirm runs the existing delete flow.
  Future<void> _confirmDeleteElement(DashboardFloorElement element) async {
    final l10n = AppLocalizations.of(context);
    final kind = _kindLabel(l10n, element.kind);
    final label = element.label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('floor-element-delete-confirm'),
        title: Text(l10n.floorElementDeleteConfirmTitle),
        content: Text(
          label == null || label.isEmpty
              ? l10n.floorElementDeleteConfirmBody(kind)
              : l10n.floorElementDeleteConfirmBodyLabeled(kind, label),
        ),
        actions: [
          TextButton(
            key: const Key('floor-element-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('floor-element-delete-confirm-action'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.floorElementDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onDeleteElement(element);
    }
  }

  Future<void> _resizeElementDialog(DashboardFloorElement element) async {
    final l10n = AppLocalizations.of(context);
    final current = _elementOverrides[element.id]?.$1 ?? element;
    final widthController = TextEditingController(text: '${current.widthNorm}');
    final heightController = TextEditingController(
      text: '${current.heightNorm}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.floorElementResize),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('floor-element-width'),
              controller: widthController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.floorElementWidth),
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            TextField(
              key: const Key('floor-element-height'),
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.floorElementHeight),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('floor-element-resize-save'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminSave),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    int clampSpan(String raw, int fallback) {
      final parsed = int.tryParse(raw.trim()) ?? fallback;
      return parsed < 100 ? 100 : (parsed > 10000 ? 10000 : parsed);
    }

    await _applyElement(
      current.copyWith(
        widthNorm: clampSpan(widthController.text, current.widthNorm),
        heightNorm: clampSpan(heightController.text, current.heightNorm),
      ),
    );
  }

  Future<void> _labelElementDialog(DashboardFloorElement element) async {
    final l10n = AppLocalizations.of(context);
    final current = _elementOverrides[element.id]?.$1 ?? element;
    final controller = TextEditingController(text: current.label ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.floorElementLabel),
        content: TextField(
          key: const Key('floor-element-label-field'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminCancel),
          ),
          FilledButton(
            key: const Key('floor-element-label-save'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminSave),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final text = controller.text.trim();
    await _applyElement(
      text.isEmpty
          ? current.copyWith(clearLabel: true)
          : current.copyWith(label: text),
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
        // 118: the saved shape, drawn inside the unchanged footprint.
        preset: table.visualPreset,
        material: table.visualMaterial,
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
