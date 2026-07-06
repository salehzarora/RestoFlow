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
    // LIVE-UX-001: a REVOKED device is not part of the working setup (it cannot
    // pair or run), so it must NOT satisfy "a POS/KDS exists" nor inflate the
    // device total — otherwise a branch whose only POS was revoked is never
    // prompted to create a new one. (devicesActive already excludes revoked.)
    final liveDevices = devices
        ?.where((d) => d.status != DeviceLifecycleStatus.revoked)
        .toList();
    return _Counts(
      devicesTotal: liveDevices?.length,
      devicesActive: liveDevices
          ?.where((d) => d.status == DeviceLifecycleStatus.active)
          .length,
      posDevices: liveDevices?.where((d) => d.deviceType == 'pos').length,
      kdsDevices: liveDevices?.where((d) => d.deviceType == 'kds').length,
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
        // A dimension is "ready" once at least one live thing exists in it.
        bool ready(int? part, int? total) =>
            !loading && total != null && (part ?? 0) > 0;

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
        final allReady =
            dimensions.isNotEmpty && dimensions.every((d) => d.done);

        // Dashboard "1c": the compact readiness strip. Each stat carries the SAME
        // real count and jumps to its owning tab (tap-to-navigate preserved). A
        // failed/loading count (total == null) omits that stat — never a fake 0.
        final stats = <RestoflowReadinessStat>[
          if (_menuCountable && counts.menuTotal != null)
            RestoflowReadinessStat(
              icon: Icons.restaurant_menu_outlined,
              label: l10n.dashboardNavMenu,
              done: counts.menuActive ?? 0,
              total: counts.menuTotal!,
              onTap: widget.onOpenMenu,
              tapKey: const Key('setup-stat-menu'),
            ),
          if (counts.devicesTotal != null)
            RestoflowReadinessStat(
              icon: Icons.devices_outlined,
              label: l10n.dashboardNavDevices,
              done: counts.devicesActive ?? 0,
              total: counts.devicesTotal!,
              onTap: widget.onOpenDevices,
              tapKey: const Key('setup-stat-devices'),
            ),
          if (counts.printersTotal != null)
            RestoflowReadinessStat(
              icon: Icons.print_outlined,
              label: l10n.dashboardNavPrinters,
              done: counts.printersEnabled ?? 0,
              total: counts.printersTotal!,
              onTap: widget.onOpenPrinters,
              tapKey: const Key('setup-stat-printers'),
            ),
          if (counts.staffTotal != null)
            RestoflowReadinessStat(
              icon: Icons.badge_outlined,
              label: l10n.dashboardNavStaff,
              done: counts.staffWithPin ?? 0,
              total: counts.staffTotal!,
              onTap: widget.onOpenStaff,
              tapKey: const Key('setup-stat-staff'),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RestoflowReadinessStrip(
              ready: allReady,
              readyLabel: l10n.setupReadyHeadline,
              // Pending headline keeps the "Setup" wording (the section title).
              pendingLabel: l10n.setupTitle,
              stats: stats,
              percent: (progress * 100).round(),
              trailing: IconButton(
                tooltip: l10n.adminRetry,
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                visualDensity: VisualDensity.compact,
              ),
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
    // A fully-ready branch shows no steps — the readiness strip's "Branch ready
    // for service" headline is the single ready indicator (no redundant banner).
    if (steps.isEmpty) return const [];
    return [const SizedBox(height: RestoflowSpacing.md), ...steps];
  }
}
