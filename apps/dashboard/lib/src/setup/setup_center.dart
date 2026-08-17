import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show DeviceLifecycleStatus;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../admin/branch_kitchen_workflow_repository.dart';
import '../state/setup_device_providers.dart';

/// A guided "is this branch ready for service?" checklist at the top of the
/// real-mode Overview: live menu / device / printer / staff-PIN counts
/// (tappable, they jump to the owning tab) + the concrete next step as honest
/// banners, each with a button that opens the tab that fixes it.
///
/// Data comes from the SAME real repositories the tabs use — never invented.
/// A failed load shows a neutral unavailable value (no fake zeroes-as-success).
class _Counts {
  const _Counts({
    this.devicesTotal,
    this.devicesActive,
    this.posDevices,
    this.kdsDevices,
    this.printersTotal,
    this.printersEnabled,
    this.kitchenPrintersEnabled,
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

  /// 036: enabled printers whose role actually serves KITCHEN tickets
  /// (`kitchen` or `both`). This — not "any enabled row" — is the record the
  /// printer_only workflow depends on, so it is what the printing-configuration
  /// dimension measures.
  final int? kitchenPrintersEnabled;
  final int? staffTotal;
  final int? staffWithPin;
  final int? menuTotal;
  final int? menuActive;
}

class DashboardSetupCenter extends ConsumerWidget {
  const DashboardSetupCenter({
    required this.onOpenMenu,
    required this.onOpenDevices,
    required this.onOpenPrinters,
    required this.onOpenStaff,
    super.key,
  });

  final VoidCallback onOpenMenu;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenPrinters;
  final VoidCallback onOpenStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // V2.1 — four provider entries instead of one mount-coupled Future.
    //
    // The sources stay SEPARATE because they fail separately and this panel
    // already renders each failure as its own "unavailable"; only the device
    // list is shared, with the summary card below, because that pair really was
    // asking the same repository the same question twice.
    final key = ref.watch(currentSetupScopeKeyProvider);
    final devicesAsync = ref.watch(setupDevicesProvider(key));
    final printersAsync = ref.watch(setupPrintersProvider(key));
    final staffAsync = ref.watch(setupStaffProvider(key));
    final menuAsync = ref.watch(setupMenuProvider(key));
    // 036: printing configuration is a PREREQUISITE only under printer_only,
    // where the POS prints kitchen tickets itself. An unreadable mode is NOT
    // treated as printer_only, so a transport blip cannot invent a failing
    // dimension for a branch that may run a KDS.
    final workflowAsync = ref.watch(setupKitchenWorkflowProvider(key));
    final printerOnly =
        workflowAsync.valueOrNull == KitchenWorkflowMode.printerOnly;
    final menuCountable =
        ref.watch(setupMenuSourceProvider) != null &&
        ref.watch(setupMenuScopeProvider) != null;

    final devices = devicesAsync.valueOrNull;
    final printers = printersAsync.valueOrNull;
    final staff = staffAsync.valueOrNull;
    final menu = menuAsync.valueOrNull;
    // Loading until every source the panel actually shows has answered, which
    // is what the single Future used to mean.
    final loading =
        devicesAsync.isLoading ||
        printersAsync.isLoading ||
        staffAsync.isLoading ||
        workflowAsync.isLoading ||
        (menuCountable && menuAsync.isLoading);

    final liveItems = menu?.items.where((i) => !i.isDeleted);
    // LIVE-UX-001: a REVOKED device is not part of the working setup (it cannot
    // pair or run), so it must NOT satisfy "a POS/KDS exists" nor inflate the
    // device total.
    final liveDevices = devices
        ?.where((d) => d.status != DeviceLifecycleStatus.revoked)
        .toList();
    final counts = _Counts(
      devicesTotal: liveDevices?.length,
      devicesActive: liveDevices
          ?.where((d) => d.status == DeviceLifecycleStatus.active)
          .length,
      posDevices: liveDevices?.where((d) => d.deviceType == 'pos').length,
      kdsDevices: liveDevices?.where((d) => d.deviceType == 'kds').length,
      printersTotal: printers?.printers.length,
      printersEnabled: printers?.printers.where((p) => p.isEnabled).length,
      // 036: mirrors the SERVER's kitchen qualification in
      // get_device_printer_assignments — a live row of this branch whose role
      // serves kitchen tickets (`kitchen` or `both`). `paper_width` is NOT a
      // server qualification and is deliberately not required here; adding it
      // would fail a branch whose 58mm printer_only dispatch works fine.
      kitchenPrintersEnabled: printers?.printers
          .where((p) => p.isEnabled && p.role.servesKitchenTickets)
          .length,
      staffTotal: staff?.length,
      staffWithPin: staff?.where((s) => s.isActive && s.hasPin).length,
      menuTotal: liveItems?.length,
      menuActive: liveItems?.where((i) => i.isActive).length,
    );

    return Builder(
      builder: (context) {
        // A dimension is "ready" once at least one live thing exists in it.
        bool ready(int? part, int? total) =>
            !loading && total != null && (part ?? 0) > 0;

        final dimensions = <({bool countable, bool done})>[
          (
            countable: menuCountable,
            done: ready(counts.menuActive, counts.menuTotal),
          ),
          (
            countable: true,
            done: ready(counts.devicesActive, counts.devicesTotal),
          ),
          // 036: printing CONFIGURATION counts toward readiness only where it
          // is a real prerequisite. A KDS-mode branch is not penalised for
          // having no server printer rows, and the denominator shrinks with it.
          (
            countable: printerOnly,
            done: ready(counts.kitchenPrintersEnabled, counts.printersTotal),
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
          if (menuCountable && counts.menuTotal != null)
            RestoflowReadinessStat(
              icon: Icons.restaurant_menu_outlined,
              label: l10n.dashboardNavMenu,
              done: counts.menuActive ?? 0,
              total: counts.menuTotal!,
              onTap: onOpenMenu,
              tapKey: const Key('setup-stat-menu'),
            ),
          if (counts.devicesTotal != null)
            RestoflowReadinessStat(
              icon: Icons.devices_outlined,
              label: l10n.dashboardNavDevices,
              done: counts.devicesActive ?? 0,
              total: counts.devicesTotal!,
              onTap: onOpenDevices,
              tapKey: const Key('setup-stat-devices'),
            ),
          // 036: shown ONLY under printer_only, where it is operationally
          // required, and labelled as printing CONFIGURATION — it counts live
          // kitchen-capable records, and says nothing about whether any
          // printer is powered on, paired or reachable.
          if (printerOnly && counts.printersTotal != null)
            RestoflowReadinessStat(
              icon: Icons.print_outlined,
              label: l10n.setupPrintingConfig,
              done: counts.kitchenPrintersEnabled ?? 0,
              total: counts.printersTotal!,
              onTap: onOpenPrinters,
              tapKey: const Key('setup-stat-printers'),
            ),
          if (counts.staffTotal != null)
            RestoflowReadinessStat(
              icon: Icons.badge_outlined,
              label: l10n.dashboardNavStaff,
              done: counts.staffWithPin ?? 0,
              total: counts.staffTotal!,
              onTap: onOpenStaff,
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
                // Retry re-runs the CURRENT key's four sources; it does not
                // rebuild this widget's State (there is none any more) and it
                // does not touch another branch's cached answers.
                onPressed: () => invalidateSetupSources(ref, key),
                icon: const Icon(Icons.refresh),
                visualDensity: VisualDensity.compact,
              ),
            ),
            // 036: the honesty line — say plainly that this readiness is
            // server-side CONFIGURATION and proves nothing about hardware.
            if (printerOnly && counts.printersTotal != null) ...[
              const SizedBox(height: RestoflowSpacing.xs),
              Text(
                l10n.setupPrintingConfigHelp,
                key: const Key('setup-printing-config-help'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            ..._nextSteps(
              l10n,
              counts,
              loading,
              menuCountable: menuCountable,
              printerOnly: printerOnly,
            ),
          ],
        );
      },
    );
  }

  /// The guided checklist, in the order a fresh workspace should follow:
  /// menu -> POS device -> kitchen display -> pair them -> printer -> PIN.
  /// RF-132 (Codex review): only the HIGHEST-priority pending step renders as
  /// the prominent full-width warning row; any remaining steps live in a
  /// compact expandable disclosure that names their exact count and, when
  /// opened, exposes every remaining step in its original order with its
  /// original action/callback. Conditions, order, wording, and navigation
  /// callbacks are unchanged; a single pending step shows just its warning
  /// (no disclosure); a fully ready branch shows no rows. Expanding is a
  /// purely local presentation toggle — it reads and mutates no data.
  List<Widget> _nextSteps(
    AppLocalizations l10n,
    _Counts c,
    bool loading, {
    required bool menuCountable,
    required bool printerOnly,
  }) {
    if (loading) return const [];
    final steps = <_SetupStepData>[];
    void add(
      String title, {
      String? description,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      steps.add(
        _SetupStepData(
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    }

    if (menuCountable && c.menuTotal != null && c.menuActive == 0) {
      add(
        l10n.setupNoMenu,
        actionLabel: l10n.setupAddMenuItem,
        onAction: onOpenMenu,
      );
    }
    if (c.posDevices == 0) {
      add(
        l10n.setupNoPosDevice,
        actionLabel: l10n.setupCreatePos,
        onAction: onOpenDevices,
      );
    }
    if (c.kdsDevices == 0) {
      add(
        l10n.setupNoKdsDevice,
        actionLabel: l10n.setupCreateKds,
        onAction: onOpenDevices,
      );
    }
    if (c.devicesTotal != null && c.devicesTotal! > 0 && c.devicesActive == 0) {
      // Devices exist but none is paired: say exactly HOW pairing works.
      add(
        l10n.setupNoActiveDevice,
        description: l10n.setupPairingHint,
        actionLabel: l10n.dashboardNavDevices,
        onAction: onOpenDevices,
      );
    }
    // 036: only a printer_only branch is missing something when it has no live
    // kitchen printer record. A KDS-mode branch gets NO "add printer" step —
    // its kitchen tickets go to the KDS, and server printer rows are optional.
    // The step also now names the real gap (a KITCHEN-capable record), so a
    // branch whose only printer is receipt-role is told the truth.
    if (printerOnly &&
        c.printersTotal != null &&
        (c.kitchenPrintersEnabled ?? 0) == 0) {
      add(
        l10n.setupNoKitchenPrinter,
        description: l10n.setupPrintingConfigHelp,
        actionLabel: l10n.setupAddPrinter,
        onAction: onOpenPrinters,
      );
    }
    if (c.staffTotal != null && c.staffWithPin == 0) {
      add(
        l10n.setupNoStaffPin,
        actionLabel: l10n.setupCreatePin,
        onAction: onOpenStaff,
      );
    }
    // A fully-ready branch shows no steps — the readiness strip's "Branch ready
    // for service" headline is the single ready indicator (no redundant banner).
    if (steps.isEmpty) return const [];
    final rest = steps.sublist(1);
    return [
      const SizedBox(height: RestoflowSpacing.md),
      _SetupWarningRow(step: steps.first),
      if (rest.isNotEmpty) ...[
        const SizedBox(height: RestoflowSpacing.sm),
        _MoreStepsDisclosure(steps: rest),
      ],
    ];
  }
}

/// The data of one pending setup step (RF-132): the existing message,
/// optional how-to description, and the fixing action + navigation callback.
class _SetupStepData {
  const _SetupStepData({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// RF-132 — one compact setup warning row: the warning-toned container with
/// the step message (plus its optional how-to description) and the outlined
/// action button that jumps to the fixing tab. Pure presentation over the
/// setup center's existing step data; RTL-safe (Row mirrors, directional
/// padding via the shared banner).
class _SetupWarningRow extends StatelessWidget {
  const _SetupWarningRow({required this.step});

  final _SetupStepData step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = RestoflowTone.warning.styleOf(theme);
    final label = step.actionLabel;
    final onTap = step.onAction;
    final desc = step.description;
    return RestoflowNoticeBanner(
      tone: RestoflowTone.warning,
      // With a description the message becomes the bold lead line and the
      // description the body; a description-less step is a single body line.
      title: desc == null ? null : step.title,
      body: desc ?? step.title,
      action: (label == null || onTap == null)
          ? null
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: warning.onContainer,
                side: BorderSide(color: warning.accent),
              ),
              child: Text(label),
            ),
    );
  }
}

/// RF-132 (Codex review) — the compact disclosure holding every pending step
/// beyond the first: a quiet bordered row naming the exact remaining-step
/// count that expands to the full remaining list (original order, original
/// actions). Purely local presentation state — expanding/collapsing touches
/// no repository or readiness data and needs no audit event.
class _MoreStepsDisclosure extends StatelessWidget {
  const _MoreStepsDisclosure({required this.steps});

  /// The pending steps beyond the prominent first one, in original order.
  final List<_SetupStepData> steps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final warning = RestoflowTone.warning.styleOf(theme);
    // Material (not a decorated Container) so the tile's ink renders on the
    // card surface.
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: kRestoflowHairline),
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Theme(
        // Drop the default ExpansionTile dividers so it reads as one card.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('setup-more-steps'),
          leading: Icon(
            Icons.warning_amber_outlined,
            size: RestoflowIconSizes.md,
            color: warning.accent,
          ),
          title: Text(
            l10n.setupMoreSteps(steps.length),
            style: theme.textTheme.titleSmall,
          ),
          tilePadding: const EdgeInsetsDirectional.symmetric(
            horizontal: RestoflowSpacing.md,
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.md,
            0,
            RestoflowSpacing.md,
            RestoflowSpacing.md,
          ),
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: RestoflowSpacing.sm),
              _SetupWarningRow(step: steps[i]),
            ],
          ],
        ),
      ),
    );
  }
}
