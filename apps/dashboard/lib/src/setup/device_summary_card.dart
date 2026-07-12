import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminDevice, AdminRepository, DeviceLifecycleStatus;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Dashboard V2 — the honest device readiness card for the Overview's lower
/// operational row: `active/configured` counts read from the SAME real devices
/// repository the Devices tab and Setup Center use (revoked devices excluded,
/// mirroring the Setup Center's LIVE-UX-001 rule). Deliberately NOT an
/// online/offline claim — RestoFlow has no device heartbeat, so the card only
/// states lifecycle readiness. A failed load renders a truthful localized
/// "device status unavailable" card (never a fake `0/0`), so the operational
/// grid keeps its full row — no ghost slot — and the Devices navigation action
/// stays available. Loading shows a static skeleton tile. Tapping opens the
/// Devices tab through the existing shell navigation callback.
class DashboardDeviceSummaryCard extends StatefulWidget {
  const DashboardDeviceSummaryCard({
    required this.repository,
    this.onOpenDevices,
    super.key,
  });

  final AdminRepository repository;

  /// The existing shell navigation callback to the Devices tab (index 2).
  final VoidCallback? onOpenDevices;

  @override
  State<DashboardDeviceSummaryCard> createState() =>
      _DashboardDeviceSummaryCardState();
}

class _DashboardDeviceSummaryCardState
    extends State<DashboardDeviceSummaryCard> {
  late Future<List<AdminDevice>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load(widget.repository);
  }

  @override
  void didUpdateWidget(DashboardDeviceSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different repository means a different data source: reload from it.
    // The FutureBuilder below keys its rendering on connectionState, so the
    // skeleton shows while the NEW source loads — the previous repository's
    // counts are never presented as the new one's.
    if (!identical(oldWidget.repository, widget.repository)) {
      _future = _load(widget.repository);
    }
  }

  Future<List<AdminDevice>?> _load(AdminRepository repository) async {
    List<AdminDevice>? devices;
    (await repository.loadDevices()).fold((value) => devices = value, (_) {});
    return devices;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<AdminDevice>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Static (pumpAndSettle-safe) skeleton while the real counts load.
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(RestoflowSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RestoflowSkeleton(width: 90, height: 14),
                  SizedBox(height: RestoflowSpacing.md),
                  RestoflowSkeleton(width: 120, height: 24),
                ],
              ),
            ),
          );
        }
        final devices = snap.data;
        if (devices == null) {
          // Load failed: an honest "status unavailable" card — never a fake
          // zero count, and never an empty ghost slot in the operational grid.
          return RestoflowMetricCard(
            key: const Key('kpi-devices-unavailable'),
            style: RestoflowMetricCardStyle.kpi,
            tone: RestoflowTone.warning,
            label: l10n.dashboardNavDevices,
            value: l10n.setupMetricUnavailable,
            caption: l10n.dashboardDevicesUnavailable,
            icon: Icons.devices_outlined,
            onTap: widget.onOpenDevices,
          );
        }
        // LIVE-UX-001: a revoked device is not part of the working setup.
        final live = devices
            .where((d) => d.status != DeviceLifecycleStatus.revoked)
            .toList();
        final active = live
            .where((d) => d.status == DeviceLifecycleStatus.active)
            .length;
        final total = live.length;
        // Tone from the REAL lifecycle counts, mirroring the Setup Center's
        // readiness semantics: success only when at least one device is
        // configured AND every configured device is active; warning while any
        // configured device is not yet active; neutral (pending) when nothing
        // is configured yet. Lifecycle only — never an online/offline claim.
        final tone = total == 0
            ? RestoflowTone.neutral
            : (active == total ? RestoflowTone.success : RestoflowTone.warning);
        return RestoflowMetricCard(
          key: const Key('kpi-devices-summary'),
          style: RestoflowMetricCardStyle.kpi,
          tone: tone,
          label: l10n.dashboardNavDevices,
          value: '$active/$total',
          caption: l10n.dashboardDevicesActiveOfConfigured,
          icon: Icons.devices_outlined,
          onTap: widget.onOpenDevices,
        );
      },
    );
  }
}
