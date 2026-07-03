import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// The printer-assignments section (Part B): what the owner configured for
/// THIS station's branch, read through the token-proven device RPC. Safe
/// metadata only; statuses are HONEST — a configured printer shows
/// "bridge required" (this build has no physical transport), never "Ready".
class PrinterAssignmentsSection extends StatelessWidget {
  const PrinterAssignmentsSection({
    required this.l10n,
    required this.assignmentsAsync,
    this.stationNames = false,
    super.key,
  });

  final AppLocalizations l10n;
  final AsyncValue<
    Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
  >
  assignmentsAsync;

  /// KDS: show the stations routed to each kitchen printer.
  final bool stationNames;

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
        // The standing honest capability note: this build prepares/previews
        // print jobs; physical printing needs a bridge/native transport.
        RestoflowNoticeBanner(
          body: l10n.deviceSettingsCapabilityNote,
          tone: RestoflowTone.info,
        ),
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

/// One assigned printer: name, transport/paper metadata, and an honest
/// status pill (disabled in Dashboard / configured-but-bridge-required).
class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.l10n,
    required this.printer,
    this.stationNames = const [],
    super.key,
  });

  final AppLocalizations l10n;
  final AssignedPrinter printer;
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
            label: printer.isEnabled
                ? l10n.deviceSettingsBridgeRequired
                : l10n.deviceSettingsPrinterDisabled,
            tone: printer.isEnabled
                ? RestoflowTone.warning
                : RestoflowTone.neutral,
          ),
        ],
      ),
    );
  }
}
