import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionManager;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrinterAssignmentsSection, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/pos_auto_print_prefs.dart';
import '../state/pos_device_context.dart';
import '../state/pos_printer_assignments.dart';
import '../state/pos_session.dart';

/// The POS operational device-settings sheet (device settings sprint).
///
/// STAFF-scope only: it shows what THIS paired station is (app type,
/// restaurant/branch, device label, pairing + staff-session status) and,
/// in later parts, the branch's receipt-printer assignments and the
/// per-device auto-print toggles. Configuration itself stays in the owner
/// Dashboard — nothing here can touch other devices, other branches, or any
/// owner/admin data. Demo mode shows an honest "no paired device" note.
class PosDeviceSettingsSheet extends ConsumerWidget {
  const PosDeviceSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const PosDeviceSettingsSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDemo = ref.watch(runtimeConfigProvider).isDemoMode;
    final device = ref.watch(posDeviceContextProvider);
    final hasStaffSession = ref.watch(posSyncSessionProvider) != null;
    final assignmentsAsync = ref.watch(posPrinterAssignmentsProvider);
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
                      DeviceInfoSection(
                        l10n: l10n,
                        appTypeValue: l10n.deviceSettingsAppTypePos,
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
                      // Part B: the receipt printers the Dashboard assigned
                      // to this station's branch (safe metadata only).
                      PrinterAssignmentsSection(
                        l10n: l10n,
                        assignmentsAsync: assignmentsAsync,
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      // Part G: staff-safe connection maintenance (refresh /
                      // local unpair) — no owner login, no owner/admin scope.
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
/// Refresh reloads the printer assignments; Unpair clears THIS device's local
/// session (best-effort server self-revoke — the existing intended
/// [DeviceSessionManager.unpair]) and returns the app to the pairing screen.
/// The Unpair control appears ONLY when a device session manager is wired
/// (real, paired mode) — never in demo, and never any owner/admin action.
class _ConnectionControls extends ConsumerWidget {
  const _ConnectionControls({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(posDeviceSessionManagerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('device-refresh-button'),
          onPressed: () {
            // Re-run the token-proven assignments read.
            ref.invalidate(posPrinterAssignmentsProvider);
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
    // Return the pairing gate to the pairing screen (it watches this).
    ref.read(posDeviceContextProvider.notifier).set(null);
    if (sheetNavigator.canPop()) sheetNavigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.deviceUnpairedSnack)));
  }
}

/// The per-device auto-print toggle (Part C): default ON when an enabled
/// receipt printer is assigned; DISABLED (with the why) when none is - a
/// toggle that could never print would be a lie. The choice persists per
/// device via shared_preferences.
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
    final stored = ref.watch(posAutoPrintReceiptProvider).valueOrNull;
    final effective = posAutoPrintReceiptEnabled(
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
          key: const Key('auto-print-receipt-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.posAutoPrintReceiptToggle),
          subtitle: hasEnabledPrinter
              ? null
              : Text(l10n.autoPrintNoPrinterNote),
          value: effective,
          onChanged: hasEnabledPrinter
              ? (value) => ref
                    .read(posAutoPrintReceiptProvider.notifier)
                    .setEnabled(value)
              : null,
        ),
      ],
    );
  }
}

/// The paired-device identity rows (shared shape for the sheet's top
/// section). Values that are not known client-side yet render as an em dash
/// — the printer-assignments read (Part B) fills the names in.
class DeviceInfoSection extends StatelessWidget {
  const DeviceInfoSection({
    required this.l10n,
    required this.appTypeValue,
    required this.hasStaffSession,
    this.deviceLabel,
    this.restaurantName,
    this.branchName,
    super.key,
  });

  final AppLocalizations l10n;
  final String appTypeValue;
  final bool hasStaffSession;
  final String? deviceLabel;
  final String? restaurantName;
  final String? branchName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeviceSettingsRow(
          label: l10n.deviceSettingsAppTypeLabel,
          value: appTypeValue,
        ),
        DeviceSettingsRow(
          label: l10n.deviceSettingsRestaurantLabel,
          value: restaurantName ?? '—',
        ),
        DeviceSettingsRow(
          label: l10n.deviceSettingsBranchLabel,
          value: branchName ?? '—',
        ),
        DeviceSettingsRow(
          label: l10n.deviceSettingsDeviceLabel,
          value: deviceLabel ?? '—',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.deviceSettingsPairingLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              RestoflowStatusPill(
                label: l10n.deviceSettingsPairingActive,
                tone: RestoflowTone.success,
                icon: Icons.link,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.deviceSettingsPinSessionLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              RestoflowStatusPill(
                label: hasStaffSession
                    ? l10n.deviceSettingsPinSessionActive
                    : l10n.deviceSettingsPinSessionNone,
                tone: hasStaffSession
                    ? RestoflowTone.success
                    : RestoflowTone.neutral,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One label/value row of the device-settings sheet.
class DeviceSettingsRow extends StatelessWidget {
  const DeviceSettingsRow({
    required this.label,
    required this.value,
    super.key,
  });

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
