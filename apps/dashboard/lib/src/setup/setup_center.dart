import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminDevice, AdminRepository, DeviceLifecycleStatus;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../printers/printer_models.dart';
import '../printers/printers_repository.dart';
import '../staff/staff_models.dart';
import '../staff/staff_repository.dart';

/// A compact "is this branch ready for service?" panel shown at the top of the
/// real-mode Overview: live device / printer / staff-PIN counts (tappable, they
/// jump to the owning tab) + the next setup step as honest warnings.
///
/// Data comes from the SAME real repositories the tabs use — never invented.
/// A failed load shows a neutral unavailable value (no fake zeroes-as-success).
class DashboardSetupCenter extends StatefulWidget {
  const DashboardSetupCenter({
    required this.devicesRepository,
    required this.printersRepository,
    required this.staffRepository,
    required this.onOpenDevices,
    required this.onOpenPrinters,
    required this.onOpenStaff,
    super.key,
  });

  final AdminRepository devicesRepository;
  final PrintersRepository printersRepository;
  final StaffRepository staffRepository;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenPrinters;
  final VoidCallback onOpenStaff;

  @override
  State<DashboardSetupCenter> createState() => _DashboardSetupCenterState();
}

class _Counts {
  const _Counts({
    this.devicesTotal,
    this.devicesActive,
    this.printersTotal,
    this.printersEnabled,
    this.staffTotal,
    this.staffWithPin,
  });

  // Null => that load failed (shown as unavailable, never as a fake 0).
  final int? devicesTotal;
  final int? devicesActive;
  final int? printersTotal;
  final int? printersEnabled;
  final int? staffTotal;
  final int? staffWithPin;
}

class _DashboardSetupCenterState extends State<DashboardSetupCenter> {
  late Future<_Counts> _future = _load();

  Future<_Counts> _load() async {
    // Kick all three off concurrently, then await each (typed).
    final devicesFuture = widget.devicesRepository.loadDevices();
    final printersFuture = widget.printersRepository.load();
    final staffFuture = widget.staffRepository.load();
    List<AdminDevice>? devices;
    (await devicesFuture).fold((value) => devices = value, (_) {});
    PrintersSnapshot? printers;
    (await printersFuture).fold((value) => printers = value, (_) {});
    List<StaffMember>? staff;
    (await staffFuture).fold((value) => staff = value, (_) {});
    return _Counts(
      devicesTotal: devices?.length,
      devicesActive: devices
          ?.where((d) => d.status == DeviceLifecycleStatus.active)
          .length,
      printersTotal: printers?.printers.length,
      printersEnabled: printers?.printers.where((p) => p.isEnabled).length,
      staffTotal: staff?.length,
      staffWithPin: staff?.where((s) => s.isActive && s.hasPin).length,
    );
  }

  void refresh() {
    // Braces, not an arrow: the setState callback must not RETURN the future.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<_Counts>(
      future: _future,
      builder: (context, snap) {
        final counts = snap.data ?? const _Counts();
        final loading = !snap.hasData;
        String value(int? part, int? total) => loading || total == null
            ? l10n.setupMetricUnavailable
            : '$part/$total';
        return RestoflowSectionCard(
          title: l10n.setupTitle,
          subtitle: l10n.setupSubtitle,
          action: IconButton(
            tooltip: l10n.adminRetry,
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          children: [
            Wrap(
              spacing: RestoflowSpacing.md,
              runSpacing: RestoflowSpacing.md,
              children: [
                SizedBox(
                  width: 220,
                  child: RestoflowMetricCard(
                    label: l10n.setupDevices,
                    value: value(counts.devicesActive, counts.devicesTotal),
                    caption: l10n.setupDevicesCaption,
                    icon: Icons.devices_outlined,
                    onTap: widget.onOpenDevices,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: RestoflowMetricCard(
                    label: l10n.setupPrinters,
                    value: value(counts.printersEnabled, counts.printersTotal),
                    caption: l10n.setupPrintersCaption,
                    icon: Icons.print_outlined,
                    onTap: widget.onOpenPrinters,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: RestoflowMetricCard(
                    label: l10n.setupStaffPin,
                    value: value(counts.staffWithPin, counts.staffTotal),
                    caption: l10n.setupStaffCaption,
                    icon: Icons.badge_outlined,
                    onTap: widget.onOpenStaff,
                  ),
                ),
              ],
            ),
            ..._nextSteps(l10n, counts, loading),
          ],
        );
      },
    );
  }

  List<Widget> _nextSteps(AppLocalizations l10n, _Counts c, bool loading) {
    if (loading) return const [];
    final steps = <Widget>[];
    void add(RestoflowTone tone, IconData icon, String body) {
      steps
        ..add(const SizedBox(height: RestoflowSpacing.md))
        ..add(RestoflowNoticeBanner(tone: tone, icon: icon, body: body));
    }

    if (c.devicesTotal == 0) {
      add(RestoflowTone.info, Icons.devices_outlined, l10n.setupNoDevices);
    } else if (c.devicesTotal != null && c.devicesActive == 0) {
      add(RestoflowTone.warning, Icons.link_off, l10n.setupNoActiveDevice);
    }
    if (c.printersTotal == 0) {
      add(RestoflowTone.info, Icons.print_outlined, l10n.setupNoPrinters);
    }
    if (c.staffTotal != null && c.staffWithPin == 0) {
      add(RestoflowTone.warning, Icons.pin_outlined, l10n.setupNoStaffPin);
    }
    if (steps.isEmpty &&
        c.devicesActive != null &&
        c.devicesActive! > 0 &&
        c.staffWithPin != null &&
        c.staffWithPin! > 0) {
      add(RestoflowTone.success, Icons.check_circle_outline, l10n.setupReady);
    }
    return steps;
  }
}
