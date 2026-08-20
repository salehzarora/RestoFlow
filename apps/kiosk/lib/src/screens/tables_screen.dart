import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../widgets/kiosk_chrome.dart';

/// 03 · Table picker (fixture floor) — zone-grouped 4-column grid, legend,
/// fixed continue bar. Only AVAILABLE tables are tappable; occupied /
/// reserved / out-of-service stay visible but dimmed with their status dot
/// and label — the honest floor, no concurrency logic in Phase 1.
class KioskTablesScreen extends ConsumerWidget {
  const KioskTablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(kioskFlowProvider);
    final controller = ref.read(kioskFlowProvider.notifier);
    final zones = kioskFixtureZones(busy: state.busyFloor);
    final rtl = state.rtl;

    String zoneName(String id) => switch (id) {
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(52, 8, 52, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final zone in zones) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        zoneName(zone.id),
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
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: (976 - 3 * 20) / 4 / 196,
                    children: [
                      for (final table in zone.tables)
                        _TableCard(
                          table: table,
                          selected: state.selectedTable == table.label,
                          onTap: table.state == KioskTableState.available
                              ? () => controller.toggleTable(table.label)
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .3],
              colors: [Color(0x00070E1B), KioskColors.canvasBottom],
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
                onTap: controller.confirmTable,
                enabled: state.selectedTable != null,
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
