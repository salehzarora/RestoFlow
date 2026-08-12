import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceSessionManager;
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrinterAssignmentsSection, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../print/native_print_bridges.dart' show posActivePrintBridgeProvider;
import '../print/print_bridge.dart';
import '../print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import '../state/pos_auto_print_prefs.dart';
import '../design/pos_visual_tokens.dart' show PosThemePair;
import '../state/pos_device_accent.dart';
import '../state/pos_device_context.dart';
import '../state/pos_device_theme.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_assignments.dart';
import '../state/pos_session.dart';
import '../state/pos_printer_transport.dart';
import '../state/receipt_print_controller.dart';
import 'printer_settings_section.dart';

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
    // ANDROID-002: native (Android) app can print directly to a network printer.
    final nativeAvailable = ref.watch(posNativePrintingAvailableProvider);
    final networkConfigured =
        ref.watch(posNetworkPrinterConfigProvider).valueOrNull != null;

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
                    // ANDROID-002: on the native app, set up + test a network
                    // (Wi-Fi/Ethernet) printer directly — no print bridge. Shown
                    // whatever the pairing state so a pilot can test hardware.
                    if (nativeAvailable) ...[
                      const PrinterSettingsSection(),
                      const SizedBox(height: RestoflowSpacing.sm),
                      // PRINT-STABILITY-001: reprint the last receipt through the
                      // current printer (raster path preserved). Disabled until a
                      // receipt has been built this session.
                      const _ReprintLastReceiptButton(),
                      const SizedBox(height: RestoflowSpacing.md),
                      const Divider(height: 1),
                      const SizedBox(height: RestoflowSpacing.md),
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
                      //
                      // HIDE-REDUNDANT-AUTO-PRINT-SETTINGS-014: omitted ENTIRELY
                      // on a printer_only branch — heading, both switches and
                      // the spacing. Both behaviours are mandatory there, so a
                      // toggle would be a control that cannot change anything.
                      // The section holds nothing else, so nothing is left
                      // behind; manual printing, printer setup and test print
                      // are separate sections and are untouched.
                      //
                      // POS-KITCHEN-WORKFLOW-REGRESSION-001: the KITCHEN-ticket
                      // switch is additionally omitted whenever the Dashboard
                      // workflow governs this surface — see [_AutoPrintSection].
                      // The RECEIPT switch is unaffected and keeps the 014
                      // behaviour above exactly.
                      if (!ref.watch(posPrinterOnlyAutoPrintProvider)) ...[
                        _AutoPrintSection(
                          l10n: l10n,
                          hasEnabledPrinter:
                              assignments?.hasEnabledPrinter ?? false,
                        ),
                        const SizedBox(height: RestoflowSpacing.md),
                      ],
                      // Part B: the receipt printers the Dashboard assigned
                      // to this station's branch (safe metadata only).
                      PrinterAssignmentsSection(
                        l10n: l10n,
                        assignmentsAsync: assignmentsAsync,
                        // POS-KITCHEN-WORKFLOW-REGRESSION-001: on the native
                        // app this station discovers, saves and assigns its own
                        // printers in the sections above, so the
                        // Dashboard-assignment guidance and the print-bridge
                        // capability note no longer describe how printing works
                        // here. Tied to `nativeAvailable` because that is
                        // exactly the condition under which those local
                        // sections exist — web POS has no on-device printer
                        // setup, so its Dashboard/bridge wording stays true.
                        localPrinterSetupOnDevice: nativeAvailable,
                        // RF-115: the LOCAL print-bridge status row (only when a
                        // bridge is configured — null hides it).
                        bridgeStatus: ref
                            .watch(posPrintBridgeStatusProvider)
                            .valueOrNull,
                        // ANDROID-002: once a native network printer is set up on
                        // this device, the assigned-printer note/pill drop the
                        // "requires print bridge" wording (a bridge is no longer
                        // the only physical path).
                        nativeNetworkAvailable:
                            nativeAvailable && networkConfigured,
                      ),
                      const SizedBox(height: RestoflowSpacing.md),
                      // Part G: staff-safe connection maintenance (refresh /
                      // local unpair) — no owner login, no owner/admin scope.
                      _ConnectionControls(l10n: l10n),
                    ],
                    // POS-PREMIUM-VISUAL-POLISH-001: the per-terminal secondary
                    // accent. An APPEARANCE preference (like language) available
                    // in every pairing state, demo included — placed LAST so the
                    // operational sections keep their long-standing geometry.
                    const SizedBox(height: RestoflowSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: RestoflowSpacing.md),
                    _DeviceAccentSection(l10n: l10n),
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
    // KITCHEN-PRINT-DUAL-001: the INDEPENDENT kitchen-ticket auto-print choice,
    // gated on a locally-configured KITCHEN printer (default OFF).
    //
    // POS-KITCHEN-WORKFLOW-REGRESSION-001: offered ONLY where the Dashboard
    // kitchen workflow does not govern this surface. It used to be hidden only
    // for a resolved printer_only branch, which meant a Separate-KDS branch and,
    // worse, a branch whose workflow was merely LOADING or had failed to
    // verify — presented an editable local switch that appeared to decide
    // whether the kitchen sees food. It never could: the submit path and the
    // recent-orders action both read the central decision. A control that
    // cannot change the outcome is worse than no control, because a cashier who
    // flips it believes something happened.
    //
    // Keyed on the CAPABILITY, not on the current readiness value, so an
    // unresolved workflow can never be mistaken for "no central workflow".
    final centralWorkflow = ref.watch(posCentralKitchenWorkflowProvider);
    final hasKitchenPrinter = ref.watch(posHasKitchenNativePrinterProvider);
    final storedKitchen = ref
        .watch(posAutoPrintKitchenTicketProvider)
        .valueOrNull;
    final effectiveKitchen = posAutoPrintKitchenTicketEnabled(
      stored: storedKitchen,
      hasKitchenPrinter: hasKitchenPrinter,
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
              : Text(l10n.autoPrintReceiptNoPrinterNote),
          value: effective,
          onChanged: hasEnabledPrinter
              ? (value) => ref
                    .read(posAutoPrintReceiptProvider.notifier)
                    .setEnabled(value)
              : null,
        ),
        if (!centralWorkflow)
          SwitchListTile(
            key: const Key('auto-print-kitchen-ticket-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.posAutoPrintKitchenTicketToggle),
            // KITCHEN-PRINT-DUAL-001C: with a kitchen printer configured, explain the
            // TWO workflows (on = print here + close directly, off = normal KDS);
            // without a printer, the existing "needs a printer" note.
            subtitle: hasKitchenPrinter
                ? Text(l10n.posAutoPrintKitchenTicketToggleExplanation)
                : Text(l10n.autoPrintKitchenNoPrinterNote),
            value: effectiveKitchen,
            onChanged: hasKitchenPrinter
                ? (value) => ref
                      .read(posAutoPrintKitchenTicketProvider.notifier)
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

/// PRINT-STABILITY-001: "Reprint last receipt". Re-submits the last BUILT receipt
/// document through the CURRENT selected printer (native Wi-Fi/Bluetooth, raster
/// path preserved). Never creates a new order or payment. Disabled until a
/// receipt has been built this session (nothing to reprint).
class _ReprintLastReceiptButton extends ConsumerWidget {
  const _ReprintLastReceiptButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final last = ref.watch(lastReceiptOrderKeyProvider);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('reprint-last-receipt'),
        onPressed: last == null
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final bridge = ref.read(posActivePrintBridgeProvider);
                await ref
                    .read(receiptPrintControllerProvider.notifier)
                    .reprint(
                      orderKey: last,
                      submitToBridge: bridge == null ? null : bridge.submit,
                    );
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.posReprintStartedSnack)),
                );
              },
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(l10n.posReprintLastReceiptAction),
      ),
    );
  }
}

/// POS-THEME-NAVBAR-POLISH-001: «مظهر هذا الجهاز» — the per-terminal THEME.
///
/// Two rows under one section:
///  1. the THEME pair (primary + action) — recolors the structural navy and
///     the action family across the whole POS surface of this device;
///  2. the existing SECONDARY accent — the supporting highlight colour
///     (selected-category tint, focus rings, hover tints), unchanged in
///     meaning, keys and persistence.
/// Both are appearance preferences; neither may ever carry a semantic
/// meaning. Selection is communicated by a ring + check glyph + the
/// semantics selected flag — never by colour alone.
class _DeviceAccentSection extends ConsumerWidget {
  const _DeviceAccentSection({required this.l10n});

  final AppLocalizations l10n;

  String _label(PosDeviceAccent accent) => switch (accent) {
    PosDeviceAccent.mint => l10n.posDeviceAccentMint,
    PosDeviceAccent.saffron => l10n.posDeviceAccentSaffron,
    PosDeviceAccent.pomegranate => l10n.posDeviceAccentPomegranate,
    PosDeviceAccent.aubergine => l10n.posDeviceAccentAubergine,
  };

  String _themeLabel(PosThemePair pair) => switch (pair.wire) {
    'forest_charcoal' => l10n.posDeviceThemeForestCharcoal,
    'aubergine_slate' => l10n.posDeviceThemeAubergineSlate,
    'saffron_gold' => l10n.posDeviceThemeSaffronGold,
    _ => l10n.posDeviceThemeNavyEmber,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected =
        ref.watch(posDeviceAccentProvider).valueOrNull ?? PosDeviceAccent.mint;
    final selectedPair = ref.watch(posDeviceThemePairProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posDeviceThemeTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xxs),
        Text(
          l10n.posDeviceThemeHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.sm,
          children: [
            for (final pair in PosThemePair.presets)
              _ThemeSwatch(
                key: Key('device-theme-${pair.wire}'),
                pair: pair,
                label: _themeLabel(pair),
                selected: pair.wire == selectedPair.wire,
                onTap: () =>
                    ref.read(posDeviceThemeProvider.notifier).setTheme(pair),
              ),
          ],
        ),
        const SizedBox(height: RestoflowSpacing.md),
        // The SUPPORTING highlight colour — the second half of the theme.
        Text(
          l10n.posDeviceAccentTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xxs),
        Text(
          l10n.posDeviceAccentHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.sm),
        Wrap(
          spacing: RestoflowSpacing.sm,
          runSpacing: RestoflowSpacing.sm,
          children: [
            for (final accent in PosDeviceAccent.values)
              _AccentSwatch(
                key: Key('device-accent-${accent.wire}'),
                accent: accent,
                label: _label(accent),
                selected: accent == selected,
                onTap: () => ref
                    .read(posDeviceAccentProvider.notifier)
                    .setAccent(accent),
              ),
          ],
        ),
      ],
    );
  }
}

/// A theme-pair swatch: the two identity colours side by side (primary +
/// action), a name, and the standard ring/check/selected-semantics
/// treatment. ≥44dp target, same anatomy as the accent swatches.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    super.key,
    required this.pair,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final PosThemePair pair;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? pair.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.sm,
              RestoflowSpacing.xs,
              RestoflowSpacing.md,
              RestoflowSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              border: Border.all(
                color: selected ? pair.primary : kRestoflowHairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The pair, shown honestly as its two colours.
                SizedBox(
                  width: 34,
                  height: 22,
                  child: Stack(
                    children: [
                      PositionedDirectional(
                        start: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: pair.primary,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: pair.action,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const SizedBox(width: 20, height: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    super.key,
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final PosDeviceAccent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? accent.color.withValues(alpha: 0.10)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.sm,
              RestoflowSpacing.xs,
              RestoflowSpacing.md,
              RestoflowSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RestoflowRadii.md),
              border: Border.all(
                color: selected ? accent.color : kRestoflowHairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.color,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: RestoflowSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
