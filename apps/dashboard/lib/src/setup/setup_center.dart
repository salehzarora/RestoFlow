import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show AdminDevice, AdminRepository, DeviceLifecycleStatus;
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuReadSource, MenuScope, MenuSnapshot;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../printers/printer_models.dart';
import '../printers/printers_repository.dart';
import '../staff/staff_models.dart';
import '../staff/staff_repository.dart';

/// A guided "is this branch ready for service?" checklist at the top of the
/// real-mode Overview: live menu / device / printer / staff-PIN counts
/// (tappable, they jump to the owning tab) + the concrete next step as honest
/// banners, each with a button that opens the tab that fixes it.
///
/// Data comes from the SAME real repositories the tabs use — never invented.
/// A failed load shows a neutral unavailable value (no fake zeroes-as-success).
class DashboardSetupCenter extends StatefulWidget {
  const DashboardSetupCenter({
    required this.devicesRepository,
    required this.printersRepository,
    required this.staffRepository,
    required this.onOpenMenu,
    required this.onOpenDevices,
    required this.onOpenPrinters,
    required this.onOpenStaff,
    this.menuReadSource,
    this.menuScope,
    super.key,
  });

  final AdminRepository devicesRepository;
  final PrintersRepository printersRepository;
  final StaffRepository staffRepository;

  /// The real menu read + scope (sprint). Null (e.g. the scope could not be
  /// resolved) => the menu card/step is omitted rather than showing fake data.
  final MenuReadSource? menuReadSource;
  final MenuScope? menuScope;

  final VoidCallback onOpenMenu;
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
    this.posDevices,
    this.kdsDevices,
    this.printersTotal,
    this.printersEnabled,
    this.staffTotal,
    this.staffWithPin,
    this.menuTotal,
    this.menuActive,
  });

  // Null => that load failed (shown as unavailable, never as a fake 0).
  final int? devicesTotal;
  final int? devicesActive;
  final int? posDevices;
  final int? kdsDevices;
  final int? printersTotal;
  final int? printersEnabled;
  final int? staffTotal;
  final int? staffWithPin;
  final int? menuTotal;
  final int? menuActive;
}

class _DashboardSetupCenterState extends State<DashboardSetupCenter> {
  late Future<_Counts> _future = _load();

  Future<_Counts> _load() async {
    // Kick everything off concurrently, then await each (typed).
    final devicesFuture = widget.devicesRepository.loadDevices();
    final printersFuture = widget.printersRepository.load();
    final staffFuture = widget.staffRepository.load();
    final menuSource = widget.menuReadSource;
    final menuScope = widget.menuScope;
    final menuFuture = (menuSource != null && menuScope != null)
        ? menuSource.load(menuScope)
        : null;
    List<AdminDevice>? devices;
    (await devicesFuture).fold((value) => devices = value, (_) {});
    PrintersSnapshot? printers;
    (await printersFuture).fold((value) => printers = value, (_) {});
    List<StaffMember>? staff;
    (await staffFuture).fold((value) => staff = value, (_) {});
    MenuSnapshot? menu;
    if (menuFuture != null) {
      try {
        menu = await menuFuture;
      } catch (_) {
        menu = null; // load failed -> unavailable, never a fake 0.
      }
    }
    final liveItems = menu?.items.where((i) => !i.isDeleted);
    return _Counts(
      devicesTotal: devices?.length,
      devicesActive: devices
          ?.where((d) => d.status == DeviceLifecycleStatus.active)
          .length,
      posDevices: devices?.where((d) => d.deviceType == 'pos').length,
      kdsDevices: devices?.where((d) => d.deviceType == 'kds').length,
      printersTotal: printers?.printers.length,
      printersEnabled: printers?.printers.where((p) => p.isEnabled).length,
      staffTotal: staff?.length,
      staffWithPin: staff?.where((s) => s.isActive && s.hasPin).length,
      menuTotal: liveItems?.length,
      menuActive: liveItems?.where((i) => i.isActive).length,
    );
  }

  void refresh() {
    // Braces, not an arrow: the setState callback must not RETURN the future.
    setState(() {
      _future = _load();
    });
  }

  bool get _menuCountable =>
      widget.menuReadSource != null && widget.menuScope != null;

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
        // A dimension is "ready" once at least one live thing exists in it.
        bool ready(int? part, int? total) =>
            !loading && total != null && (part ?? 0) > 0;
        // Unknown counts (loading / failed load) stay neutral — never a fake
        // green or a false alarm.
        RestoflowTone? tone(int? part, int? total) => loading || total == null
            ? null
            : (ready(part, total)
                  ? RestoflowTone.success
                  : RestoflowTone.warning);

        final dimensions = <({bool countable, bool done})>[
          (
            countable: _menuCountable,
            done: ready(counts.menuActive, counts.menuTotal),
          ),
          (
            countable: true,
            done: ready(counts.devicesActive, counts.devicesTotal),
          ),
          (
            countable: true,
            done: ready(counts.printersEnabled, counts.printersTotal),
          ),
          (
            countable: true,
            done: ready(counts.staffWithPin, counts.staffTotal),
          ),
        ].where((d) => d.countable).toList();
        final progress = dimensions.isEmpty
            ? 0.0
            : dimensions.where((d) => d.done).length / dimensions.length;

        return RestoflowSectionCard(
          title: l10n.setupTitle,
          subtitle: l10n.setupSubtitle,
          action: IconButton(
            tooltip: l10n.adminRetry,
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          children: [
            const SizedBox(height: RestoflowSpacing.md),
            if (!loading) ...[
              _SetupProgressBar(value: progress),
              const SizedBox(height: RestoflowSpacing.md),
            ],
            Wrap(
              spacing: RestoflowSpacing.md,
              runSpacing: RestoflowSpacing.md,
              children: [
                if (_menuCountable)
                  SizedBox(
                    width: 220,
                    child: RestoflowMetricCard(
                      label: l10n.setupMenu,
                      value: value(counts.menuActive, counts.menuTotal),
                      caption: l10n.setupMenuCaption,
                      icon: Icons.restaurant_menu_outlined,
                      tone: tone(counts.menuActive, counts.menuTotal),
                      onTap: widget.onOpenMenu,
                    ),
                  ),
                SizedBox(
                  width: 220,
                  child: RestoflowMetricCard(
                    label: l10n.setupDevices,
                    value: value(counts.devicesActive, counts.devicesTotal),
                    caption: l10n.setupDevicesCaption,
                    icon: Icons.devices_outlined,
                    tone: tone(counts.devicesActive, counts.devicesTotal),
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
                    tone: tone(counts.printersEnabled, counts.printersTotal),
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
                    tone: tone(counts.staffWithPin, counts.staffTotal),
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

  /// The guided checklist, in the order a fresh workspace should follow:
  /// menu -> POS device -> kitchen display -> pair them -> printer -> PIN.
  /// Each pending step is a numbered tile carrying the button that opens the
  /// fixing tab; a fully ready branch shows the success banner instead.
  List<Widget> _nextSteps(AppLocalizations l10n, _Counts c, bool loading) {
    if (loading) return const [];
    final steps = <Widget>[];
    void add(
      String title, {
      String? description,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      steps.add(
        RestoflowStepTile(
          index: steps.length + 1,
          title: title,
          description: description,
          action: (actionLabel == null || onAction == null)
              ? null
              : TextButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      );
    }

    if (_menuCountable && c.menuTotal != null && c.menuActive == 0) {
      add(
        l10n.setupNoMenu,
        actionLabel: l10n.setupAddMenuItem,
        onAction: widget.onOpenMenu,
      );
    }
    if (c.posDevices == 0) {
      add(
        l10n.setupNoPosDevice,
        actionLabel: l10n.setupCreatePos,
        onAction: widget.onOpenDevices,
      );
    }
    if (c.kdsDevices == 0) {
      add(
        l10n.setupNoKdsDevice,
        actionLabel: l10n.setupCreateKds,
        onAction: widget.onOpenDevices,
      );
    }
    if (c.devicesTotal != null && c.devicesTotal! > 0 && c.devicesActive == 0) {
      // Devices exist but none is paired: say exactly HOW pairing works.
      add(
        l10n.setupNoActiveDevice,
        description: l10n.setupPairingHint,
        actionLabel: l10n.dashboardNavDevices,
        onAction: widget.onOpenDevices,
      );
    }
    if (c.printersTotal == 0) {
      add(
        l10n.setupNoPrinters,
        actionLabel: l10n.setupAddPrinter,
        onAction: widget.onOpenPrinters,
      );
    }
    if (c.staffTotal != null && c.staffWithPin == 0) {
      add(
        l10n.setupNoStaffPin,
        actionLabel: l10n.setupCreatePin,
        onAction: widget.onOpenStaff,
      );
    }
    if (steps.isEmpty) {
      if (c.devicesActive != null &&
          c.devicesActive! > 0 &&
          c.staffWithPin != null &&
          c.staffWithPin! > 0) {
        return [
          const SizedBox(height: RestoflowSpacing.md),
          RestoflowNoticeBanner(
            tone: RestoflowTone.success,
            icon: Icons.check_circle_outline,
            body: l10n.setupReady,
          ),
        ];
      }
      return const [];
    }
    return [const SizedBox(height: RestoflowSpacing.md), ...steps];
  }
}

/// A quiet, static readiness bar (finite — safe for pumpAndSettle harnesses).
class _SetupProgressBar extends StatelessWidget {
  const _SetupProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final successStyle = RestoflowTone.success.styleOf(theme);
    return ClipRRect(
      borderRadius: BorderRadius.circular(RestoflowRadii.pill),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        color: successStyle.accent,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
    );
  }
}
