import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../state/kiosk_live_runtime.dart';
import '../widgets/kiosk_chrome.dart';

/// 03 · Table picker — zone-grouped 4-column grid, legend, fixed continue
/// bar. Only AVAILABLE tables are tappable; occupied / reserved /
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
    final state = ref.watch(kioskFlowProvider);
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
                      const SizedBox(
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
