import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/demo_tables.dart';
import '../state/order_setup_controller.dart';

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
                        assignedId: assignedId,
                        onAssign: (t) {
                          ref
                              .read(orderSetupControllerProvider.notifier)
                              .assignTable(t);
                          Navigator.of(context).pop();
                        },
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

/// Localized display name for a demo area key. Falls back to the raw key for an
/// unknown area (demo-only; the seed only uses "Main"/"Patio").
String _localizedArea(String areaKey, AppLocalizations l10n) {
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
class _FloorMap extends StatelessWidget {
  const _FloorMap({
    required this.tables,
    required this.assignedId,
    required this.onAssign,
  });

  final List<DemoTable> tables;
  final String? assignedId;
  final void Function(DemoTable) onAssign;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = groupTablesByArea(tables);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const _AisleDivider(),
            _AreaZone(
              areaName: _localizedArea(groups[i].areaKey, l10n),
              edgeLabel: i == 0
                  ? l10n.posTablesEdgeEntrance
                  : (i == 1 ? l10n.posTablesEdgeCounter : null),
              tables: groups[i].tables,
              assignedId: assignedId,
              onAssign: onAssign,
            ),
          ],
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
    required this.tables,
    required this.assignedId,
    required this.onAssign,
  });

  final String areaName;
  final String? edgeLabel;
  final List<DemoTable> tables;
  final String? assignedId;
  final void Function(DemoTable) onAssign;

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
              for (final t in tables)
                _TableTile(
                  key: ValueKey('table-tile-${t.tableId}'),
                  table: t,
                  selected: t.tableId == assignedId,
                  onTap: t.isAssignable ? () => onAssign(t) : null,
                ),
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
    super.key,
  });

  final DemoTable table;
  final bool selected;
  final VoidCallback? onTap;

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
