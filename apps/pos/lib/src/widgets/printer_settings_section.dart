import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/pos_printer_transport.dart';
import 'bluetooth_printer_section.dart';
import 'network_printer_section.dart';

/// The on-device printer setup for the native POS app (ANDROID-003): a transport
/// chooser (Wi-Fi / Bluetooth) over the matching setup section. Shown only where
/// native printing is available (Android app) — on web the app keeps the print
/// bridge path and this section is not rendered.
class PrinterSettingsSection extends ConsumerWidget {
  const PrinterSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected =
        ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
        PosPrinterTransportKind.network;

    return Column(
      key: const Key('printer-settings-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posPrinterTransportHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PosPrinterTransportKind>(
            key: const Key('printer-transport-toggle'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            segments: [
              ButtonSegment<PosPrinterTransportKind>(
                value: PosPrinterTransportKind.network,
                icon: const Icon(Icons.wifi),
                label: Text(l10n.posPrinterTransportNetwork),
              ),
              ButtonSegment<PosPrinterTransportKind>(
                value: PosPrinterTransportKind.bluetooth,
                icon: const Icon(Icons.bluetooth),
                label: Text(l10n.posPrinterTransportBluetooth),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => ref
                .read(posSelectedPrinterTransportProvider.notifier)
                .select(selection.first),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        switch (selected) {
          PosPrinterTransportKind.network => const NetworkPrinterSection(),
          PosPrinterTransportKind.bluetooth => const BluetoothPrinterSection(),
        },
      ],
    );
  }
}
