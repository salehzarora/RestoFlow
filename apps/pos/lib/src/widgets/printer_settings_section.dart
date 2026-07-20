import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_kitchen_printer_copy.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_purpose.dart';
import '../state/pos_printer_transport.dart';
import 'bluetooth_printer_section.dart';
import 'network_printer_section.dart';

/// The on-device printer setup for the native POS app (ANDROID-003 +
/// KITCHEN-MODE-001B): a PURPOSE selector (customer receipts / kitchen
/// tickets) over a per-purpose transport chooser (Wi-Fi / Bluetooth) and the
/// matching setup section. Shown only where native printing is available
/// (Android app) — on web the app keeps the print bridge path and this section
/// is not rendered.
///
/// The CUSTOMER purpose is the legacy configuration, byte-identical to
/// pre-001B. The KITCHEN purpose is PREPARATION-ONLY: an operator may store a
/// second endpoint (or copy the customer one) and run a money-free kitchen
/// test print, but NOTHING automatic prints kitchen tickets in this phase and
/// no workflow mode can be activated here (the mode stays dormant; 001C ships
/// the workflow).
class PrinterSettingsSection extends ConsumerStatefulWidget {
  const PrinterSettingsSection({super.key});

  @override
  ConsumerState<PrinterSettingsSection> createState() =>
      _PrinterSettingsSectionState();
}

class _PrinterSettingsSectionState
    extends ConsumerState<PrinterSettingsSection> {
  PosPrinterPurpose _purpose = PosPrinterPurpose.customerReceipt;
  bool _copyBusy = false;

  Future<void> _copyCustomerToKitchen(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _copyBusy = true);
    final copied = await ref.read(useCustomerPrinterForKitchenProvider)();
    if (!mounted) return;
    setState(() => _copyBusy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? l10n.posKitchenPrinterCopiedSnack
              : l10n.posKitchenPrinterNothingToCopySnack,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected =
        ref.watch(posSelectedPrinterTransportFamily(_purpose)).valueOrNull ??
        PosPrinterTransportKind.network;
    final kitchen = _purpose == PosPrinterPurpose.kitchenTicket;
    final customerHasPrinter =
        ref.watch(posNetworkPrinterConfigProvider).valueOrNull != null ||
        ref.watch(posBluetoothPrinterConfigProvider).valueOrNull != null;

    return Column(
      key: const Key('printer-settings-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KITCHEN-MODE-001B: the purpose selector (two independent slots).
        Text(
          l10n.posPrinterPurposeHeading,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PosPrinterPurpose>(
            key: const Key('printer-purpose-toggle'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            segments: [
              ButtonSegment<PosPrinterPurpose>(
                value: PosPrinterPurpose.customerReceipt,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(l10n.posPrinterPurposeCustomer),
              ),
              ButtonSegment<PosPrinterPurpose>(
                value: PosPrinterPurpose.kitchenTicket,
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: Text(l10n.posPrinterPurposeKitchen),
              ),
            ],
            selected: {_purpose},
            onSelectionChanged: (selection) =>
                setState(() => _purpose = selection.first),
          ),
        ),
        if (kitchen) ...[
          const SizedBox(height: RestoflowSpacing.sm),
          // HONEST preparation-only notice — static text, deliberately not a
          // toggle: the kitchen workflow mode stays dormant (no setter exists).
          RestoflowNoticeBanner(
            key: const Key('kitchen-printer-preparation-notice'),
            tone: RestoflowTone.info,
            icon: Icons.soup_kitchen_outlined,
            title: l10n.posKitchenPrinterPreparationTitle,
            body: l10n.posKitchenPrinterPreparationBody,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('kitchen-printer-copy-customer'),
              onPressed: (!_copyBusy && customerHasPrinter)
                  ? () => _copyCustomerToKitchen(l10n)
                  : null,
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.posKitchenPrinterUseCustomerAction),
            ),
          ),
        ],
        const SizedBox(height: RestoflowSpacing.md),
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
            key: Key(
              kitchen
                  ? 'printer-transport-toggle-kitchen'
                  : 'printer-transport-toggle',
            ),
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
                .read(posSelectedPrinterTransportFamily(_purpose).notifier)
                .select(selection.first),
          ),
        ),
        const SizedBox(height: RestoflowSpacing.md),
        // KITCHEN-MODE-001B correction (review HIGH): the transport sections
        // are STATEFUL (text controllers, in-session Bluetooth selection,
        // test status). A stable PURPOSE-SPECIFIC key forces Flutter to
        // dispose the old purpose's State and build a fresh one on every
        // purpose switch — customer values can never linger in (or be saved
        // into) the kitchen slot, and vice versa. The key is stable across
        // ordinary rebuilds (wire tokens, never translated labels) and both
        // sections additionally carry a didUpdateWidget fallback.
        switch (selected) {
          PosPrinterTransportKind.network => NetworkPrinterSection(
            key: ValueKey('network-printer-purpose-${_purpose.wire}'),
            purpose: _purpose,
          ),
          PosPrinterTransportKind.bluetooth => BluetoothPrinterSection(
            key: ValueKey('bluetooth-printer-purpose-${_purpose.wire}'),
            purpose: _purpose,
          ),
        },
      ],
    );
  }
}
