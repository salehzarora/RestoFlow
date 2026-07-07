import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'print_bridge_status.dart';

/// The printer-assignments section (Part B): what the owner configured for
/// THIS station's branch, read through the token-proven device RPC. Safe
/// metadata only; statuses are HONEST — a configured printer shows
/// "bridge required" (no bridge configured), never "Ready".
///
/// RF-115: when a LOCAL print bridge is configured, [bridgeStatus] adds a global
/// bridge row (connected / unavailable + last job) beside the capability note,
/// reaching BOTH the POS and KDS device-settings surfaces from one place.
class PrinterAssignmentsSection extends StatelessWidget {
  const PrinterAssignmentsSection({
    required this.l10n,
    required this.assignmentsAsync,
    this.stationNames = false,
    this.bridgeStatus,
    this.nativeNetworkAvailable = false,
    super.key,
  });

  final AppLocalizations l10n;
  final AsyncValue<
    Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
  >
  assignmentsAsync;

  /// KDS: show the stations routed to each kitchen printer.
  final bool stationNames;

  /// RF-115: the local print-bridge snapshot, or null when no bridge is
  /// configured (the default — the row is then hidden, unchanged behaviour).
  final PrinterBridgeStatus? bridgeStatus;

  /// ANDROID-002: true on the native app once a direct network printer is set
  /// up on THIS device. The assigned-printer note/pill then drop the "requires
  /// print bridge" wording (a bridge is no longer the only physical path).
  /// Default false keeps the web / KDS / dashboard behaviour unchanged.
  final bool nativeNetworkAvailable;

  static String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = assignmentsAsync.valueOrNull;

    final Widget body;
    if (assignmentsAsync.isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: RestoflowSpacing.sm),
        child: RestoflowInlineSpinner(size: 18),
      );
    } else if (result == null || result is Failure) {
      // No reader wired (dormant real mode) or a load failure — a safe
      // error, never a fabricated printer list.
      body = RestoflowNoticeBanner(
        body: l10n.deviceSettingsLoadError,
        tone: RestoflowTone.warning,
      );
    } else {
      final assignments =
          (result
                  as Success<
                    DevicePrinterAssignments,
                    DevicePrinterAssignmentsFailure
                  >)
              .value;
      if (assignments.printers.isEmpty) {
        body = RestoflowNoticeBanner(
          key: const Key('no-printer-banner'),
          body: l10n.deviceSettingsNoPrinter,
          tone: RestoflowTone.info,
        );
      } else {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final printer in assignments.printers)
              _PrinterTile(
                key: Key('printer-${printer.id}'),
                l10n: l10n,
                printer: printer,
                nativeNetworkAvailable: nativeNetworkAvailable,
                stationNames: stationNames
                    ? assignments.stationNamesFor(printer)
                    : const [],
              ),
          ],
        );
      }
    }

    return Column(
      key: const Key('device-settings-printers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.deviceSettingsPrintersHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        body,
        const SizedBox(height: RestoflowSpacing.sm),
        // The standing honest capability note. On the native app with a direct
        // network printer set up, it says printing is available here with no
        // bridge (ANDROID-002); otherwise it keeps the honest "needs a
        // bridge/native transport" note.
        RestoflowNoticeBanner(
          body: nativeNetworkAvailable
              ? l10n.deviceSettingsNativeNetworkNote
              : l10n.deviceSettingsCapabilityNote,
          tone: RestoflowTone.info,
        ),
        // RF-115: the global LOCAL print-bridge row (only when a bridge is
        // configured) — connected / unavailable + the last submitted job time.
        if (bridgeStatus case final status?) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          _BridgeStatusRow(l10n: l10n, status: status),
        ],
        if (result case Success(:final value)) ...[
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            l10n.deviceSettingsLastRefresh(_formatTime(value.fetchedAt)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// RF-115: the global LOCAL print-bridge status row — connected / unavailable
/// plus the last submitted-job time. Never a printer IP or any money.
class _BridgeStatusRow extends StatelessWidget {
  const _BridgeStatusRow({required this.l10n, required this.status});

  final AppLocalizations l10n;
  final PrinterBridgeStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = status.connectivity == PrintBridgeConnectivity.connected;
    final tone = connected ? RestoflowTone.success : RestoflowTone.warning;
    final style = tone.styleOf(theme);
    final base = connected
        ? l10n.deviceSettingsBridgeConnected
        : l10n.deviceSettingsBridgeUnavailable;
    final lastJobAt = status.lastJobAt;
    final label = lastJobAt == null
        ? base
        : '$base · ${l10n.deviceSettingsBridgeLastJob(PrinterAssignmentsSection._formatTime(lastJobAt))}';
    return Row(
      key: const Key('bridge-status-row'),
      children: [
        Icon(
          connected ? Icons.link : Icons.link_off,
          size: RestoflowIconSizes.sm,
          color: style.accent,
        ),
        const SizedBox(width: RestoflowSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: style.accent),
          ),
        ),
      ],
    );
  }
}

/// One assigned printer: name, transport/paper metadata, and an honest
/// status pill (disabled in Dashboard / configured-but-bridge-required).
class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.l10n,
    required this.printer,
    this.nativeNetworkAvailable = false,
    this.stationNames = const [],
    super.key,
  });

  final AppLocalizations l10n;
  final AssignedPrinter printer;

  /// ANDROID-002: drop the "requires print bridge" pill for an enabled printer
  /// when this device can print directly to a network printer.
  final bool nativeNetworkAvailable;
  final List<String> stationNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RestoflowSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            printer.isEnabled ? Icons.print_outlined : Icons.print_disabled,
            size: RestoflowIconSizes.md,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  printer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Transport + paper are DATA (dashboard-configured values).
                Text(
                  '${printer.connectionType} · ${printer.paperWidth}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (stationNames.isNotEmpty)
                  Text(
                    l10n.deviceSettingsRouteStations(stationNames.join('، ')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RestoflowSpacing.sm),
          RestoflowStatusPill(
            label: !printer.isEnabled
                ? l10n.deviceSettingsPrinterDisabled
                : nativeNetworkAvailable
                ? l10n.deviceSettingsPrinterConfigured
                : l10n.deviceSettingsBridgeRequired,
            tone: !printer.isEnabled
                ? RestoflowTone.neutral
                : nativeNetworkAvailable
                ? RestoflowTone.info
                : RestoflowTone.warning,
          ),
        ],
      ),
    );
  }
}
