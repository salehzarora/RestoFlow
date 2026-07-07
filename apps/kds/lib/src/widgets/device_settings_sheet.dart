import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionManager;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrinterAssignmentsSection, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show NativePrinterSettingsSection, nativePrintingAvailableProvider;

import '../print/kds_native_printer.dart' show kdsNativePrinterStrings;
import '../print/kds_print_bridge.dart';
import '../state/kds_auto_print_prefs.dart';
import '../state/kds_device_context.dart';
import '../state/kds_printer_assignments.dart';
import '../state/kds_session.dart';

/// The KDS operational device-settings sheet (device settings sprint).
///
/// STAFF-scope only and MONEY-FREE (T-003): it shows what THIS paired
/// kitchen display is (app type, restaurant/branch, device label, pairing +
/// staff-session status) and, in later parts, the branch's kitchen-printer
/// assignments and the per-device auto-print toggles. Configuration itself
/// stays in the owner Dashboard — nothing here can touch other devices,
/// other branches, or any owner/admin/payment data. Demo mode shows an
/// honest "no paired device" note.
class KdsDeviceSettingsSheet extends ConsumerWidget {
  const KdsDeviceSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const KdsDeviceSettingsSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final device = ref.watch(kdsDeviceContextProvider);
    final hasStaffSession = ref.watch(kdsSyncSessionProvider) != null;
    final assignmentsAsync = ref.watch(kdsPrinterAssignmentsProvider);
    final assignments = switch (assignmentsAsync.valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            key: const Key('device-settings-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: theme.colorScheme.primary),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.deviceSettingsTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.md),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // ANDROID-004: the on-device local kitchen printer setup
                    // (Wi-Fi/Bluetooth). Shown only on the native Android app
                    // (independent of demo/real — it configures THIS display's
                    // local printer); hidden on web, where the KDS keeps the
                    // print-bridge path unchanged. Money-free (T-003).
                    if (ref.watch(nativePrintingAvailableProvider)) ...[
                      Text(
                        l10n.kdsPrinterSettingsTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: RestoflowSpacing.sm),
                      NativePrinterSettingsSection(
                        strings: kdsNativePrinterStrings(l10n),
                        deviceLabel: device?.displayName,
                      ),
                      const Divider(height: RestoflowSpacing.xl),
                    ],
                    if (isDemo)
                      RestoflowNoticeBanner(
                        body: l10n.deviceSettingsDemoNote,
                        tone: RestoflowTone.info,
                      )
                    else if (device == null)
                      RestoflowNoticeBanner(
                        body: l10n.deviceSettingsUnavailable,
                        tone: RestoflowTone.warning,
                      )
                    else ...[
                      _DeviceInfoSection(
                        l10n: l10n,
                        deviceLabel:
                            assignments?.deviceLabel ?? device.displayName,
                        restaurantName: assignments?.restaurantName,
                        branchName: assignments?.branchName,
                        hasStaffSession: hasStaffSession,
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      // Part C: the per-device auto-print choice (local,
                      // per browser/device, no owner login involved).
                      _AutoPrintSection(
                        l10n: l10n,
                        hasEnabledPrinter:
                            assignments?.hasEnabledPrinter ?? false,
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      // Part B: the KITCHEN printers the Dashboard assigned
                      // to this display's branch (safe metadata only; the
                      // station routes say where each printer serves).
                      PrinterAssignmentsSection(
                        l10n: l10n,
                        assignmentsAsync: assignmentsAsync,
                        stationNames: true,
                        // RF-115: the LOCAL print-bridge status row (only when a
                        // bridge is configured — null hides it).
                        bridgeStatus: ref
                            .watch(kdsPrintBridgeStatusProvider)
                            .valueOrNull,
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      // Part G: staff-safe connection maintenance (refresh /
                      // local unpair) — no owner login, no owner/admin scope,
                      // money-free like everything on this surface.
                      _ConnectionControls(l10n: l10n),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staff-safe connection maintenance (device settings sprint, Part G):
/// Refresh reloads the kitchen-printer assignments; Unpair clears THIS
/// display's local session (best-effort server self-revoke — the existing
/// intended [DeviceSessionManager.unpair]) AND ends the staff session so the
/// LIVE board falls back to the pairing flow (the board renders without the
/// gate in its tree). Unpair appears ONLY when a device session manager is
/// wired (real, paired mode) — never in demo, never any owner/admin action.
class _ConnectionControls extends ConsumerWidget {
  const _ConnectionControls({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(kdsDeviceSessionManagerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('device-refresh-button'),
          onPressed: () {
            ref.invalidate(kdsPrinterAssignmentsProvider);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.deviceRefreshedSnack)));
          },
          icon: const Icon(Icons.refresh),
          label: Text(l10n.deviceRefreshAction),
        ),
        if (manager != null) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          OutlinedButton.icon(
            key: const Key('device-unpair-button'),
            style: RestoflowButtonStyles.dangerGhost(context),
            onPressed: () => _confirmUnpair(context, ref, manager),
            icon: const Icon(Icons.link_off),
            label: Text(l10n.deviceUnpairAction),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmUnpair(
    BuildContext context,
    WidgetRef ref,
    DeviceSessionManager manager,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final sheetNavigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deviceUnpairAction),
        content: Text(l10n.deviceUnpairWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.deviceUnpairCancel),
          ),
          FilledButton(
            key: const Key('device-unpair-confirm'),
            style: RestoflowButtonStyles.danger(context),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deviceUnpairConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Clear the local device session (best-effort server self-revoke).
    await manager.unpair();
    // End the staff session so the LIVE board falls back to pairing, and
    // clear the published context so the gate (once mounted) shows pairing.
    ref.read(kdsSessionControllerProvider.notifier).endSession();
    ref.read(kdsDeviceContextProvider.notifier).set(null);
    if (sheetNavigator.canPop()) sheetNavigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.deviceUnpairedSnack)));
  }
}

/// The per-device auto-print toggle (Part C): default ON when an enabled
/// kitchen printer is assigned; DISABLED (with the why) when none is. The
/// choice persists per device via shared_preferences. Print-on-first-seen is
/// deliberately not offered (reload print storms).
class _AutoPrintSection extends ConsumerWidget {
  const _AutoPrintSection({
    required this.l10n,
    required this.hasEnabledPrinter,
  });

  final AppLocalizations l10n;
  final bool hasEnabledPrinter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stored = ref.watch(kdsAutoPrintAcknowledgeProvider).valueOrNull;
    final effective = kdsAutoPrintAcknowledgeEnabled(
      stored: stored,
      hasEnabledPrinter: hasEnabledPrinter,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.deviceSettingsAutoPrintHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        SwitchListTile(
          key: const Key('auto-print-acknowledge-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.kdsAutoPrintAcknowledgeToggle),
          subtitle: hasEnabledPrinter
              ? null
              : Text(l10n.autoPrintNoPrinterNote),
          value: effective,
          onChanged: hasEnabledPrinter
              ? (value) => ref
                    .read(kdsAutoPrintAcknowledgeProvider.notifier)
                    .setEnabled(value)
              : null,
        ),
      ],
    );
  }
}

/// The paired-device identity rows. Values not known client-side yet render
/// as an em dash — the printer-assignments read (Part B) fills the names in.
class _DeviceInfoSection extends StatelessWidget {
  const _DeviceInfoSection({
    required this.l10n,
    required this.hasStaffSession,
    this.deviceLabel,
    this.restaurantName,
    this.branchName,
  });

  final AppLocalizations l10n;
  final bool hasStaffSession;
  final String? deviceLabel;
  final String? restaurantName;
  final String? branchName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: l10n.deviceSettingsAppTypeLabel,
          value: l10n.deviceSettingsAppTypeKds,
        ),
        _Row(
          label: l10n.deviceSettingsRestaurantLabel,
          value: restaurantName ?? '—',
        ),
        _Row(label: l10n.deviceSettingsBranchLabel, value: branchName ?? '—'),
        _Row(label: l10n.deviceSettingsDeviceLabel, value: deviceLabel ?? '—'),
        _PillRow(
          label: l10n.deviceSettingsPairingLabel,
          pill: RestoflowStatusPill(
            label: l10n.deviceSettingsPairingActive,
            tone: RestoflowTone.success,
            icon: Icons.link,
          ),
        ),
        _PillRow(
          label: l10n.deviceSettingsPinSessionLabel,
          pill: RestoflowStatusPill(
            label: hasStaffSession
                ? l10n.deviceSettingsPinSessionActive
                : l10n.deviceSettingsPinSessionNone,
            tone: hasStaffSession
                ? RestoflowTone.success
                : RestoflowTone.neutral,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillRow extends StatelessWidget {
  const _PillRow({required this.label, required this.pill});

  final String label;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          pill,
        ],
      ),
    );
  }
}
