import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show DeviceLifecycleStatus;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/setup_device_providers.dart';

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
class DashboardDeviceSummaryCard extends ConsumerWidget {
  const DashboardDeviceSummaryCard({this.onOpenDevices, super.key});

  /// The existing shell navigation callback to the Devices tab (index 2).
  final VoidCallback? onOpenDevices;

  // V2.1 — the device list is no longer fetched here.
  //
  // This card used to call `repository.loadDevices()` in `initState`, and the
  // Setup Center above it called the SAME method on the SAME repository
  // instance, so one Overview mount cost two identical requests. Both now read
  // ONE canonical provider entry, which also means the shell tearing this
  // subtree down on a tab switch no longer re-fetches anything.
  //
  // The `didUpdateWidget` identity guard that used to live here is gone with
  // it: it never fired in production anyway, because the shell holds the
  // repository in a `late final` and the instance was always identical. Scope
  // changes are now expressed by the KEY instead, which is value-based.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(
      setupDevicesProvider(ref.watch(currentSetupScopeKeyProvider)),
    );
    return Builder(
      builder: (context) {
        if (async.isLoading) {
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
        // An ERROR is treated exactly as a null result was before: the
        // repository already folds its failures to null, so this arm only
        // catches a thrown one, and both mean the same honest thing.
        final devices = async.hasError ? null : async.value;
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
            onTap: onOpenDevices,
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
          onTap: onOpenDevices,
        );
      },
    );
  }
}
