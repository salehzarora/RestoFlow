import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show
        FloorPoint,
        FloorPreset,
        floorClusterSeamRect,
        floorElementRoomRect,
        floorFractionOf,
        floorTableRoomRect,
        packLinkedCluster;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../state/discount_controller.dart' show staffCapabilitiesProvider;
import '../state/order_setup_controller.dart';
import 'table_group_detail_sheet.dart';
import 'table_operations_sheet.dart';

/// Modal table picker (RF-114) — a simple floor-map layout: tables grouped into
/// area "zones" (Main dining / Patio) framed as bordered regions and separated
/// by a labelled walkway, with a status legend, a clearly highlighted selected
/// table, and disabled occupied/blocked tables. Only AVAILABLE tables are
/// tappable; tapping one assigns it to the active dine-in order and closes the
/// sheet. In-memory demo only — the positions are illustrative (no real floor
/// layout, no backend, no persistence).
class TablePickerSheet extends ConsumerWidget {
  const TablePickerSheet({super.key});

  /// Opens the picker as a modal bottom sheet.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TablePickerSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tablesAsync = ref.watch(tablesProvider);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final assignedId = ref.watch(
      orderSetupControllerProvider.select((s) => s.assignedTable?.tableId),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_restaurant, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  l10n.posTablePickerTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.sm),
            // Demo-only disclaimer — REAL mode loads the branch's real tables.
            if (isDemo)
              _FootnoteRow(
                icon: Icons.info_outline,
                message: l10n.posTablesDemoNotice,
              ),
            const SizedBox(height: RestoflowSpacing.md),
            const _TableLegend(),
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: RestoflowSpacing.sm,
              ),
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            Flexible(
              child: tablesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(RestoflowSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => _PickerMessage(
                  icon: Icons.error_outline,
                  message: l10n.posTablesError,
                ),
                data: (tables) => tables.isEmpty
                    ? _PickerMessage(
                        icon: Icons.table_restaurant_outlined,
                        // Real mode says WHERE tables come from (Dashboard →
                        // Tables) instead of a bare "nothing to show".
                        message: isDemo
                            ? l10n.posTablesEmpty
                            : l10n.posTablesEmptyReal,
                      )
                    : _FloorMap(
                        tables: tables,
                        floorElements: ref.watch(floorElementsProvider),
                        assignedId: assignedId,
                        onAssign: (t) {
                          ref
                              .read(orderSetupControllerProvider.notifier)
                              .assignTable(t);
                          Navigator.of(context).pop();
                        },
                        // PSC-001B: a combined group card opens the group-detail
                        // sheet; a NEW order still requires an EXPLICIT physical
                        // member choice there — the card itself never assigns.
                        // The full table list rides along so the per-member
                        // management surface can offer honest link candidates.
                        onOpenGroup: (group) => TableGroupDetailSheet.show(
                          context,
                          group: group,
                          allTables: tables,
                          onSelectMember: (member) {
                            ref
                                .read(orderSetupControllerProvider.notifier)
                                .assignTable(member);
                            Navigator.of(context).pop();
                          },
                        ),
                        // PILOT-OPERATIONS-CORRECTIONS-001: a long-press opens the
                        // operational table sheet — ONLY for an operator the server
                        // says holds manage_table_operations. It carries the full
                        // table list so link-candidate filtering is honest.
                        onManage:
                            (ref
                                    .watch(staffCapabilitiesProvider)
                                    .valueOrNull
                                    ?.manageTableOperations ??
                                false)
                            ? (t) => TableOperationsSheet.show(
                                context,
                                table: t,
                                allTables: tables,
                              )
                            : null,
                      ),
              ),
            ),
            const SizedBox(height: RestoflowSpacing.md),
            // The illustrative-positions hint is demo-only; real tables come
            // from the dashboard and have no floor coordinates yet either,
            // but the wording ("demo-only") would be wrong in real mode.
            if (isDemo)
              _FootnoteRow(
                icon: Icons.info_outline,
                message: l10n.posTablesLayoutEditorHint,
              ),
          ],
        ),
      ),
    );
  }
}

/// Groups [tables] into ordered area zones: "Main" first, then "Patio", then
/// any other area alphabetically. A null/empty area folds into "Main" so no
/// table can ever disappear (defensive — the demo seed always sets an area).
List<({String areaKey, List<DemoTable> tables})> groupTablesByArea(
  List<DemoTable> tables,
) {
  const fallbackArea = 'Main';
  const knownOrder = <String>['Main', 'Patio'];
  final byArea = <String, List<DemoTable>>{};
  for (final t in tables) {
    final area = t.area;
    final key = (area == null || area.trim().isEmpty) ? fallbackArea : area;
    byArea.putIfAbsent(key, () => <DemoTable>[]).add(t);
  }
  final keys = byArea.keys.toList()
    ..sort((a, b) {
      final ia = knownOrder.indexOf(a);
      final ib = knownOrder.indexOf(b);
      if (ia != -1 && ib != -1) return ia.compareTo(ib);
      if (ia != -1) return -1;
      if (ib != -1) return 1;
      return a.compareTo(b);
    });
  return [for (final k in keys) (areaKey: k, tables: byArea[k]!)];
}

/// PSC-001B: one entry of the picker floor layout — either a single physical
/// table tile, or a linked group rendered as ONE combined card.
sealed class TablePickerEntry {
  const TablePickerEntry();
}

/// A plain physical table tile (ungrouped, or the fail-safe presentation of a
/// data-anomaly "group" with a single visible member — it keeps its linked
/// badge rather than pretending to be a combined card).
class TablePickerSingle extends TablePickerEntry {
  const TablePickerSingle(this.table);

  final DemoTable table;
}

/// One linked group presented as one combined card.
class TablePickerGroup extends TablePickerEntry {
  const TablePickerGroup(this.group);

  final TableGroupCardData group;
}

/// PSC-001B: the view model for ONE linked group in the picker. [members] are
/// sorted deterministically by (label, tableId) — never backend arrival order.
/// The group-wide effective state / active-order count / status are read from
/// any member: [withGroupAggregation] already projected the identical aggregate
/// onto every member (A4), so this introduces NO second precedence rule.
class TableGroupCardData {
  const TableGroupCardData({required this.groupId, required this.members});

  final String groupId;
  final List<DemoTable> members;

  DemoTable get _representative => members.first;

  /// Group-wide (projected) state — identical on every member.
  String get effectiveState => _representative.effectiveState;
  int get activeOrderCount => _representative.activeOrderCount;
  TableStatusKind get status => _representative.status;

  /// "T4 + T5" (members already label-sorted); [joiner] is localized.
  String combinedLabel(String joiner) =>
      members.map((m) => m.label).join(joiner);
}

/// PSC-001B: the complete picker floor layout. Same-area groups render inside
/// their area (at the first member's position in the area's existing order);
/// cross-zone groups render exactly once in the dedicated Linked-tables
/// section, never under an arbitrary member area and never duplicated.
class TablePickerLayout {
  const TablePickerLayout({required this.areas, required this.crossZoneGroups});

  final List<({String areaKey, List<TablePickerEntry> entries})> areas;
  final List<TableGroupCardData> crossZoneGroups;
}

/// The SAME null/empty-area fallback [groupTablesByArea] applies, so a group's
/// zone classification can never disagree with where its tiles would render.
String _normalizedAreaOf(DemoTable t) {
  final area = t.area;
  return (area == null || area.trim().isEmpty) ? 'Main' : area;
}

/// Deterministic member ordering: (label, tableId). Public so the group-detail
/// sheet re-derives live member lists with the SAME order as the picker.
int compareTablesByLabelThenId(DemoTable a, DemoTable b) {
  final byLabel = a.label.compareTo(b.label);
  return byLabel != 0 ? byLabel : a.tableId.compareTo(b.tableId);
}

/// PSC-001B: the combined-card view models, one per link group with >= 2
/// visible members. A singleton (anomaly — the backend guarantees >= 2) gets
/// no card and stays a plain tile with its linked badge, so no table can ever
/// disappear. TABLE-FLOOR-LAYOUT-021: public so the section canvases resolve
/// a placed grouped member to the SAME card the area layout would use.
Map<String, TableGroupCardData> buildTableGroupCards(List<DemoTable> tables) {
  final membersByGroup = <String, List<DemoTable>>{};
  for (final t in tables) {
    final g = t.groupId;
    if (g != null) (membersByGroup[g] ??= <DemoTable>[]).add(t);
  }
  final cards = <String, TableGroupCardData>{};
  for (final e in membersByGroup.entries) {
    if (e.value.length < 2) continue;
    final members = [...e.value]..sort(compareTablesByLabelThenId);
    cards[e.key] = TableGroupCardData(groupId: e.key, members: members);
  }
  return cards;
}

/// TABLE-FLOOR-LAYOUT-021: splits the branch's tables into FIRST-CLASS
/// sections (owner-ordered by display order, then name, then id) and the
/// LEGACY remainder (no section assigned). Pure and deterministic; a table
/// can never be in both.
({
  List<
    ({
      String sectionId,
      String sectionName,
      FloorPreset floorPreset,
      List<DemoTable> tables,
    })
  >
  sections,
  List<DemoTable> legacy,
})
splitTablesBySection(List<DemoTable> tables) {
  final legacy = <DemoTable>[];
  final bySection = <String, List<DemoTable>>{};
  final names = <String, String>{};
  final orders = <String, int>{};
  // 118: the section's floor style rides on each of its rows (the wire
  // ships no section catalog); the first non-default key wins, so a section
  // whose rows all carry the default paints plain light.
  final floors = <String, FloorPreset>{};
  for (final t in tables) {
    final sid = t.sectionId;
    if (sid == null) {
      legacy.add(t);
      continue;
    }
    (bySection[sid] ??= <DemoTable>[]).add(t);
    final name = t.sectionName;
    if (name != null && name.isNotEmpty) names[sid] = name;
    final order = t.sectionDisplayOrder;
    if (order != null) orders[sid] = order;
    if (t.sectionFloorPreset != FloorPreset.plainLight) {
      floors[sid] ??= t.sectionFloorPreset;
    }
  }
  final ids = bySection.keys.toList()
    ..sort((a, b) {
      final byOrder = (orders[a] ?? 1 << 30).compareTo(orders[b] ?? 1 << 30);
      if (byOrder != 0) return byOrder;
      final byName = (names[a] ?? '').compareTo(names[b] ?? '');
      return byName != 0 ? byName : a.compareTo(b);
    });
  return (
    sections: [
      for (final id in ids)
        (
          sectionId: id,
          sectionName: names[id] ?? '',
          floorPreset: floors[id] ?? FloorPreset.plainLight,
          tables: bySection[id]!,
        ),
    ],
    legacy: legacy,
  );
}

/// PSC-001B: builds the picker layout from the (already deduplicated +
/// group-projected) table list. Pure and deterministic: member order is
/// (label, tableId), cross-zone groups sort by their first member, and a
/// duplicate-free input is guaranteed upstream by [withGroupAggregation].
TablePickerLayout buildTablePickerLayout(List<DemoTable> tables) {
  final cards = buildTableGroupCards(tables);

  final sameAreaGroupIds = <String>{};
  final crossZone = <TableGroupCardData>[];
  for (final g in cards.values) {
    final areas = g.members.map(_normalizedAreaOf).toSet();
    if (areas.length > 1) {
      crossZone.add(g);
    } else {
      sameAreaGroupIds.add(g.groupId);
    }
  }
  crossZone.sort(
    (a, b) => compareTablesByLabelThenId(a.members.first, b.members.first),
  );

  // Walk the existing area layout; emit a same-area group card at its first
  // member's position, skip every other grouped member, drop areas left empty.
  final areas = <({String areaKey, List<TablePickerEntry> entries})>[];
  final emitted = <String>{};
  for (final area in groupTablesByArea(tables)) {
    final entries = <TablePickerEntry>[];
    for (final t in area.tables) {
      final g = t.groupId;
      if (g != null && cards.containsKey(g)) {
        if (sameAreaGroupIds.contains(g) && emitted.add(g)) {
          entries.add(TablePickerGroup(cards[g]!));
        }
        continue; // grouped members never render as top-level tiles
      }
      entries.add(TablePickerSingle(t));
    }
    if (entries.isNotEmpty) {
      areas.add((areaKey: area.areaKey, entries: entries));
    }
  }
  return TablePickerLayout(areas: areas, crossZoneGroups: crossZone);
}

/// Localized display name for a demo area key. Falls back to the raw key for an
/// unknown area (demo-only; the seed only uses "Main"/"Patio"). Public so the
/// group-detail sheet labels each member's zone with the same wording.
String localizedTableArea(String areaKey, AppLocalizations l10n) {
  switch (areaKey) {
    case 'Main':
      return l10n.posTableAreaMain;
    case 'Patio':
      return l10n.posTableAreaPatio;
    default:
      return areaKey;
  }
}

/// The grouped, scrollable floor map: one bordered zone per area, with a
/// labelled walkway divider between consecutive zones.
///
/// PSC-001B: linked groups render as ONE combined card each — inside their
/// area when all members share it, or exactly once in the dedicated
/// Linked-tables section (after the areas) when the members span zones.
class _FloorMap extends StatelessWidget {
  const _FloorMap({
    required this.tables,
    required this.floorElements,
    required this.assignedId,
    required this.onAssign,
    required this.onOpenGroup,
    this.onManage,
  });

  final List<DemoTable> tables;

  /// 027: the READ-ONLY visual fixture catalog (per-section decoration).
  final List<PosFloorElement> floorElements;
  final String? assignedId;
  final void Function(DemoTable) onAssign;
  final void Function(TableGroupCardData) onOpenGroup;
  final void Function(DemoTable)? onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // TABLE-FLOOR-LAYOUT-021: first-class sections render as REAL floor-map
    // canvases with the owner's saved placements; the LEGACY remainder keeps
    // the pre-existing pseudo floor map (area zones, walkway, group cards)
    // unchanged — no table can ever disappear during a gradual migration.
    final split = splitTablesBySection(tables);
    final groupCards = buildTableGroupCards(tables);
    final legacy = split.legacy;
    final layout = buildTablePickerLayout(legacy);
    final areas = layout.areas;
    // PSC-001B correction 4: the decorative Entrance/Counter captions belong to
    // the ORIGINAL first/second physical zones, not to whatever index an area
    // lands on after empty (fully-grouped) zones are filtered out. Key them by
    // the PRE-FILTER area identity so dropping an emptied zone can never shift
    // a caption onto the wrong zone.
    final originalAreaKeys = [
      for (final a in groupTablesByArea(legacy)) a.areaKey,
    ];
    String? edgeLabelFor(String areaKey) {
      if (originalAreaKeys.isNotEmpty && areaKey == originalAreaKeys[0]) {
        return l10n.posTablesEdgeEntrance;
      }
      if (originalAreaKeys.length > 1 && areaKey == originalAreaKeys[1]) {
        return l10n.posTablesEdgeCounter;
      }
      return null;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < split.sections.length; i++) ...[
            if (i > 0) const _AisleDivider(),
            _SectionZone(
              section: split.sections[i],
              elements: [
                for (final e in floorElements)
                  if (e.sectionId == split.sections[i].sectionId) e,
              ],
              groupCards: groupCards,
              assignedId: assignedId,
              onAssign: onAssign,
              onOpenGroup: onOpenGroup,
              onManage: onManage,
            ),
          ],
          for (var i = 0; i < areas.length; i++) ...[
            if (i > 0 || split.sections.isNotEmpty) const _AisleDivider(),
            _AreaZone(
              areaName: localizedTableArea(areas[i].areaKey, l10n),
              edgeLabel: edgeLabelFor(areas[i].areaKey),
              entries: areas[i].entries,
              assignedId: assignedId,
              onAssign: onAssign,
              onOpenGroup: onOpenGroup,
              onManage: onManage,
            ),
          ],
          if (layout.crossZoneGroups.isNotEmpty) ...[
            if (areas.isNotEmpty || split.sections.isNotEmpty)
              const _AisleDivider(),
            _LinkedTablesSection(
              groups: layout.crossZoneGroups,
              assignedId: assignedId,
              onOpenGroup: onOpenGroup,
            ),
          ],
        ],
      ),
    );
  }
}

/// TABLE-FLOOR-LAYOUT-021: one FIRST-CLASS section — the same bordered zone
/// chrome as a legacy area, but its body is the REAL floor-map canvas with
/// tables placed at their saved normalized coordinates. Sectioned tables the
/// owner has not placed yet auto-flow in a strip under the canvas, so nothing
/// is ever hidden. All picker semantics are unchanged: only AVAILABLE tables
/// assign; a grouped member opens the group-detail sheet (never assigns
/// directly); long-press manage stays capability-gated by the caller.
class _SectionZone extends StatelessWidget {
  const _SectionZone({
    required this.section,
    required this.elements,
    required this.groupCards,
    required this.assignedId,
    required this.onAssign,
    required this.onOpenGroup,
    this.onManage,
  });

  final ({
    String sectionId,
    String sectionName,
    FloorPreset floorPreset,
    List<DemoTable> tables,
  })
  section;

  /// 027: this section's read-only visual fixtures.
  final List<PosFloorElement> elements;
  final Map<String, TableGroupCardData> groupCards;
  final String? assignedId;
  final void Function(DemoTable) onAssign;
  final void Function(TableGroupCardData) onOpenGroup;
  final void Function(DemoTable)? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placed = <DemoTable>[];
    final unplaced = <DemoTable>[];
    for (final t in section.tables) {
      (floorFractionOf(t.layoutX, t.layoutY) == null ? unplaced : placed).add(
        t,
      );
    }

    Widget tile(DemoTable t, {bool inStrip = false}) => _SectionFloorTile(
      table: t,
      selected: t.tableId == assignedId,
      groupCard: t.groupId == null ? null : groupCards[t.groupId],
      onAssign: onAssign,
      onOpenGroup: onOpenGroup,
      onManage: onManage,
      inStrip: inStrip,
    );

    return Container(
      key: Key('table-section-zone-${section.sectionId}'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.xs),
              Expanded(
                child: Text(
                  section.sectionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          if (placed.isNotEmpty)
            Builder(
              builder: (context) {
                // 027: linked members pack into DERIVED per-section clusters
                // (base coordinates untouched — unlink restores exactly).
                final derived = <String, FloorPoint>{};
                final seams = <RestoflowFloorPlacedTile>[];
                final byGroup = <String, List<DemoTable>>{};
                for (final t in placed) {
                  final g = t.groupId;
                  if (g != null) (byGroup[g] ??= []).add(t);
                }
                for (final members in byGroup.values) {
                  if (members.length < 2) continue;
                  members.sort(compareTablesByLabelThenId);
                  final packed = packLinkedCluster([
                    for (final t in members)
                      (id: t.tableId, x: t.layoutX!, y: t.layoutY!),
                  ]);
                  derived.addAll(packed);
                  seams.add(
                    RestoflowFloorPlacedTile(
                      room: floorClusterSeamRect(packed.values),
                      child: const RestoflowFloorClusterSeam(),
                    ),
                  );
                }
                return RestoflowFloorSectionCanvas(
                  key: Key('table-section-canvas-${section.sectionId}'),
                  // 118: the section's saved floor style (shared painter).
                  floorPreset: section.floorPreset,
                  // 027 z-order: fixtures under seams under tables; fixtures
                  // are IgnorePointer — pure decoration, never tappable.
                  background: [
                    for (final e in elements)
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
                            key: Key('pos-floor-element-${e.id}'),
                            kind: e.kind,
                            quarterTurns: e.orientationQuarterTurns,
                            label: e.label,
                          ),
                        ),
                      ),
                    ...seams,
                  ],
                  // Room-unit rects from the SHARED contract — identical
                  // relative geometry to the Dashboard editor by construction.
                  placed: [
                    for (final t in placed)
                      RestoflowFloorPlacedTile(
                        room: derived[t.tableId] != null
                            ? floorTableRoomRect(
                                derived[t.tableId]!.x,
                                derived[t.tableId]!.y,
                              )
                            : floorTableRoomRect(t.layoutX!, t.layoutY!),
                        child: tile(t),
                      ),
                  ],
                );
              },
            ),
          if (unplaced.isNotEmpty) ...[
            if (placed.isNotEmpty) const SizedBox(height: RestoflowSpacing.sm),
            Wrap(
              spacing: RestoflowSpacing.sm,
              runSpacing: RestoflowSpacing.sm,
              children: [for (final t in unplaced) tile(t, inStrip: true)],
            ),
          ],
        ],
      ),
    );
  }
}

/// One table on a section canvas: the shared top-down [RestoflowFloorTable]
/// visual, tinted by the SAME `_statusFill` mapping the legacy tiles and the
/// legend use, with the picker's exact tap semantics.
class _SectionFloorTile extends StatelessWidget {
  const _SectionFloorTile({
    required this.table,
    required this.selected,
    required this.groupCard,
    required this.onAssign,
    required this.onOpenGroup,
    this.onManage,
    this.inStrip = false,
  });

  final DemoTable table;
  final bool selected;

  /// 027: strips (not-placed lists) have no canvas to size the tile — it
  /// takes the fixed reference footprint instead.
  final bool inStrip;

  /// Non-null when this table is a member of a linked group with a combined
  /// card: tapping opens the group-detail sheet (an EXPLICIT member choice
  /// happens there — the tile itself never assigns a grouped table).
  final TableGroupCardData? groupCard;
  final void Function(DemoTable) onAssign;
  final void Function(TableGroupCardData) onOpenGroup;
  final void Function(DemoTable)? onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = _statusFill(table.status, theme);
    final fill = selected ? scheme.primaryContainer : base.fill;
    final onFill = selected ? scheme.onPrimaryContainer : base.onFill;
    final border = selected ? scheme.primary : base.border;
    final statusLabel = selected
        ? l10n.posTableStatusSelected
        : _statusLabel(table.status, l10n);

    final Widget? glyph = switch (true) {
      _ when selected => Icon(
        Icons.check_circle,
        size: 14,
        color: scheme.primary,
      ),
      _ when groupCard != null => Icon(Icons.link, size: 13, color: onFill),
      _ when table.status == TableStatusKind.occupied => Icon(
        Icons.do_not_disturb_on,
        size: 13,
        color: onFill,
      ),
      _ when table.status == TableStatusKind.reserved => Icon(
        Icons.event_seat_outlined,
        size: 13,
        color: onFill,
      ),
      _ when table.status == TableStatusKind.blocked => Icon(
        Icons.block,
        size: 13,
        color: onFill,
      ),
      _ => null,
    };

    final card = groupCard;
    final VoidCallback? onTap = card != null
        ? () => onOpenGroup(card)
        : table.isAssignable
        ? () => onAssign(table)
        : null;

    final Widget floorTile = RestoflowFloorTable(
      label: table.label,
      seats: table.seats,
      // 118: the saved shape, drawn inside the unchanged footprint.
      preset: table.visualPreset,
      fill: fill,
      onFill: onFill,
      border: border,
      borderWidth: selected ? 2 : 1,
      statusIcon: glyph,
      footnote: table.activeOrderCount > 0
          ? l10n.posTableOpenOrders(table.activeOrderCount)
          : statusLabel,
    );

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      selected: selected,
      label: selected
          ? l10n.posTableSelectedSemantic(table.label)
          : '${table.label}, $statusLabel',
      child: GestureDetector(
        key: Key('table-floor-tile-${table.tableId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onManage == null ? null : () => onManage!(table),
        child: inStrip
            ? SizedBox.fromSize(
                size: kRestoflowFloorStripTileSize,
                child: floorTile,
              )
            : floorTile,
      ),
    );
  }
}

/// PSC-001B: the dedicated section for CROSS-ZONE linked groups. Rendered only
/// when at least one such group exists; a same-area group never appears here.
class _LinkedTablesSection extends StatelessWidget {
  const _LinkedTablesSection({
    required this.groups,
    required this.assignedId,
    required this.onOpenGroup,
  });

  final List<TableGroupCardData> groups;
  final String? assignedId;
  final void Function(TableGroupCardData) onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      key: const Key('table-groups-section'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: RestoflowSpacing.xs),
              Expanded(
                child: Text(
                  l10n.posTableGroupSectionTitle,
                  key: const Key('table-groups-section-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Wrap(
            spacing: RestoflowSpacing.md,
            runSpacing: RestoflowSpacing.md,
            children: [
              for (final g in groups)
                _GroupTile(
                  key: ValueKey('table-group-tile-${g.groupId}'),
                  group: g,
                  assignedId: assignedId,
                  onOpen: () => onOpenGroup(g),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One area "zone": a soft bordered region with a header (area name + a spatial
/// edge label) and the area's tables laid out in a wrap.
class _AreaZone extends StatelessWidget {
  const _AreaZone({
    required this.areaName,
    required this.edgeLabel,
    required this.entries,
    required this.assignedId,
    required this.onAssign,
    required this.onOpenGroup,
    this.onManage,
  });

  final String areaName;
  final String? edgeLabel;
  final List<TablePickerEntry> entries;
  final String? assignedId;
  final void Function(DemoTable) onAssign;
  final void Function(TableGroupCardData) onOpenGroup;
  final void Function(DemoTable)? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: RestoflowSpacing.xs),
              Expanded(
                child: Text(
                  areaName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (edgeLabel != null) ...[
                const SizedBox(width: RestoflowSpacing.sm),
                _EdgeLabel(label: edgeLabel!),
              ],
            ],
          ),
          const SizedBox(height: RestoflowSpacing.md),
          Wrap(
            spacing: RestoflowSpacing.md,
            runSpacing: RestoflowSpacing.md,
            children: [
              for (final entry in entries)
                switch (entry) {
                  TablePickerSingle(:final table) => _TableTile(
                    key: ValueKey('table-tile-${table.tableId}'),
                    table: table,
                    selected: table.tableId == assignedId,
                    onTap: table.isAssignable ? () => onAssign(table) : null,
                    onLongPress: onManage == null
                        ? null
                        : () => onManage!(table),
                  ),
                  TablePickerGroup(:final group) => _GroupTile(
                    key: ValueKey('table-group-tile-${group.groupId}'),
                    group: group,
                    assignedId: assignedId,
                    onOpen: () => onOpenGroup(group),
                  ),
                },
            ],
          ),
        ],
      ),
    );
  }
}

/// A small outlined "spatial" label (Entrance / Counter) on a zone header.
class _EdgeLabel extends StatelessWidget {
  const _EdgeLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RestoflowSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RestoflowRadii.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A thin "walkway" separator between two zones: hairline — label — hairline.
class _AisleDivider extends StatelessWidget {
  const _AisleDivider();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hairlineColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.6,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.md),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: hairlineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RestoflowSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_walk,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: RestoflowSpacing.xs),
                Text(
                  l10n.posTablesAisleLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Container(height: 1, color: hairlineColor)),
        ],
      ),
    );
  }
}

/// The status legend: four non-interactive swatches whose colours mirror the
/// tiles exactly, so the map is self-explanatory. Wraps to two rows on a narrow
/// sheet.
class _TableLegend extends StatelessWidget {
  const _TableLegend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = _statusFill(TableStatusKind.available, theme);
    final occupied = _statusFill(TableStatusKind.occupied, theme);
    final reserved = _statusFill(TableStatusKind.reserved, theme);
    final blocked = _statusFill(TableStatusKind.blocked, theme);
    return Wrap(
      spacing: RestoflowSpacing.lg,
      runSpacing: RestoflowSpacing.sm,
      children: [
        _LegendItem(
          color: available.fill,
          borderColor: available.border,
          label: l10n.posTableStatusAvailable,
        ),
        _LegendItem(
          color: occupied.fill,
          borderColor: occupied.border,
          label: l10n.posTableStatusOccupied,
        ),
        // TABLE-FLOOR-LAYOUT-021: reserved is self-explanatory on the map.
        _LegendItem(
          color: reserved.fill,
          borderColor: reserved.border,
          label: l10n.posTableStateReserved,
        ),
        _LegendItem(
          color: blocked.fill,
          borderColor: blocked.border,
          label: l10n.posTableStatusBlocked,
        ),
        _LegendItem(
          color: scheme.primaryContainer,
          borderColor: scheme.primary,
          borderWidth: 2,
          showCheck: true,
          label: l10n.posTableStatusSelected,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.borderColor,
    this.borderWidth = 1,
    this.showCheck = false,
  });

  final Color color;
  final String label;
  final Color? borderColor;
  final double borderWidth;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: borderWidth),
          ),
          child: showCheck
              ? Icon(Icons.check, size: 11, color: theme.colorScheme.primary)
              : null,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Fill + on-colour + border for a status, shared by BOTH the legend swatches
/// and the tile bodies so the two can never drift apart. Design-polish: the
/// fills come from the shared semantic tones — available reads as a plain
/// "empty" table, occupied as a true-amber WARNING, blocked as a red DANGER —
/// each with a matching accent border so the states survive a quick glance.
({Color fill, Color onFill, Color border}) _statusFill(
  TableStatusKind kind,
  ThemeData theme,
) {
  final scheme = theme.colorScheme;
  switch (kind) {
    case TableStatusKind.available:
      return (
        fill: scheme.surface,
        onFill: scheme.onSurface,
        border: scheme.outlineVariant,
      );
    case TableStatusKind.occupied:
      final warning = RestoflowTone.warning.styleOf(theme);
      return (
        fill: warning.container,
        onFill: warning.onContainer,
        border: warning.accent.withValues(alpha: 0.5),
      );
    // TABLE-FLOOR-LAYOUT-021: reserved is a DISTINCT visual (info tone), but
    // behaves exactly like occupied for every business rule (not assignable).
    case TableStatusKind.reserved:
      final info = RestoflowTone.info.styleOf(theme);
      return (
        fill: info.container,
        onFill: info.onContainer,
        border: info.accent.withValues(alpha: 0.5),
      );
    case TableStatusKind.blocked:
      final danger = RestoflowTone.danger.styleOf(theme);
      return (
        fill: danger.container,
        onFill: danger.onContainer,
        border: danger.accent.withValues(alpha: 0.5),
      );
  }
}

/// Localized status label for a table tile / legend item.
String _statusLabel(TableStatusKind kind, AppLocalizations l10n) {
  switch (kind) {
    case TableStatusKind.available:
      return l10n.posTableStatusAvailable;
    case TableStatusKind.occupied:
      return l10n.posTableStatusOccupied;
    case TableStatusKind.reserved:
      return l10n.posTableStateReserved;
    case TableStatusKind.blocked:
      return l10n.posTableStatusBlocked;
  }
}

/// One table on the floor map. Available tiles are tappable; occupied/blocked
/// carry a distinct status-tinted fill + icon and a null tap (not assignable).
/// The selected tile is filled + ringed + checked + labelled "Selected".
class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final DemoTable table;
  final bool selected;
  final VoidCallback? onTap;

  /// PILOT-OPERATIONS-CORRECTIONS-001: deliberate operational management gesture
  /// (capability-gated by the caller; null = hidden). Independent of [onTap] so an
  /// occupied/blocked table can still be managed.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = _statusFill(table.status, theme);
    final Color fill = selected ? scheme.primaryContainer : base.fill;
    final Color onFill = selected ? scheme.onPrimaryContainer : base.onFill;
    final Color borderColor = selected ? scheme.primary : base.border;
    final double borderWidth = selected ? 2 : 1;
    final String statusLabel = selected
        ? l10n.posTableStatusSelected
        : _statusLabel(table.status, l10n);

    final Widget? glyph = switch (true) {
      _ when selected => Icon(
        Icons.check_circle,
        size: 20,
        color: scheme.primary,
      ),
      _ when table.status == TableStatusKind.occupied => Icon(
        Icons.do_not_disturb_on,
        size: 18,
        color: onFill,
      ),
      // TABLE-FLOOR-LAYOUT-021: reserved carries its own glyph — never a
      // colour-alone distinction.
      _ when table.status == TableStatusKind.reserved => Icon(
        Icons.event_seat_outlined,
        size: 18,
        color: onFill,
      ),
      _ when table.status == TableStatusKind.blocked => Icon(
        Icons.block,
        size: 18,
        color: onFill,
      ),
      _ => null,
    };

    return Semantics(
      button: table.isAssignable,
      enabled: table.isAssignable,
      selected: selected,
      label: selected ? l10n.posTableSelectedSemantic(table.label) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 132, maxWidth: 168),
        // Subtle interaction polish: selection fill/border fades (finite
        // implicit animation; ink rides a transparent Material on top).
        child: AnimatedContainer(
          duration: RestoflowDurations.fast,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              child: Padding(
                padding: const EdgeInsets.all(RestoflowSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_seat, size: 18, color: onFill),
                        const SizedBox(width: RestoflowSpacing.xs),
                        Text(
                          table.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onFill,
                          ),
                        ),
                        if (glyph != null) ...[const Spacer(), glyph],
                      ],
                    ),
                    if (table.seats != null) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Text(
                        l10n.posTableSeats(table.seats!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onFill.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    // RESTAURANT-OPERATIONS-V1-001: honest DERIVED occupancy —
                    // live active orders the SERVER counted on this table.
                    // Display truth only; it never gates selection by itself
                    // (second-round ordering on a seated table is valid).
                    if (table.activeOrderCount > 0) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Text(
                        l10n.posTableOpenOrders(table.activeOrderCount),
                        key: Key('table-open-orders-${table.tableId}'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: onFill.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    // PILOT-OPERATIONS-CORRECTIONS-001: a table in a link group is
                    // shown as linked (icon + label, not colour alone).
                    // PSC-001B: the label is Flexible + ellipsized — a long
                    // translation must truncate, never overflow the tile.
                    if (table.isGrouped) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Row(
                        key: Key('table-linked-${table.tableId}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link, size: 14, color: onFill),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              l10n.posTableLinked,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: onFill.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: RestoflowSpacing.sm),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onFill,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PSC-001B: ONE combined card for a linked group. Shows every member label
/// (deterministic order), a linked indicator, the group-wide effective state
/// (most restrictive — fail-closed on unknown), and the group-wide active-order
/// total. ALWAYS tappable — it opens the group-detail sheet for inspection and
/// explicit physical-member selection, even when no member is assignable. It
/// never assigns a table by itself.
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.assignedId,
    required this.onOpen,
    super.key,
  });

  final TableGroupCardData group;
  final String? assignedId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = group.members.any((m) => m.tableId == assignedId);
    final base = _statusFill(group.status, theme);
    final Color fill = selected ? scheme.primaryContainer : base.fill;
    final Color onFill = selected ? scheme.onPrimaryContainer : base.onFill;
    final Color borderColor = selected ? scheme.primary : base.border;
    final double borderWidth = selected ? 2 : 1;
    final String statusLabel = selected
        ? l10n.posTableStatusSelected
        : _statusLabel(group.status, l10n);
    final combinedLabel = group.combinedLabel(l10n.posTableGroupJoiner);

    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
        child: AnimatedContainer(
          duration: RestoflowDurations.fast,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              child: Padding(
                padding: const EdgeInsets.all(RestoflowSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.link, size: 18, color: onFill),
                        const SizedBox(width: RestoflowSpacing.xs),
                        Expanded(
                          child: Text(
                            combinedLabel,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: onFill,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: RestoflowSpacing.xs),
                          Icon(
                            Icons.check_circle,
                            size: 20,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    Row(
                      key: Key('table-group-linked-${group.groupId}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link, size: 14, color: onFill),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            l10n.posTableLinked,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: onFill.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (group.activeOrderCount > 0) ...[
                      const SizedBox(height: RestoflowSpacing.xs),
                      Text(
                        l10n.posTableOpenOrders(group.activeOrderCount),
                        key: Key('group-open-orders-${group.groupId}'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: onFill.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    const SizedBox(height: RestoflowSpacing.sm),
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onFill,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A muted single-line footnote (info icon + message). Used for both the demo
/// notice and the future-layout-editor hint; no border/background so it can
/// never read as a broken card.
class _FootnoteRow extends StatelessWidget {
  const _FootnoteRow({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: RestoflowSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
