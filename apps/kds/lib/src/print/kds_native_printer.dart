import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'kds_print_bridge.dart';
import 'print_document.dart' as app;

/// ANDROID-004: wires the KDS kitchen-ticket print pipeline to the SHARED native
/// on-device printing layer (`restoflow_native_printing`) - the same Wi-Fi
/// RAW/TCP + Bluetooth Classic (SPP) transports the POS uses. MONEY-FREE: it only
/// carries the already-built kitchen [app.PrintDocument] through
/// `kitchenTicketToEscPosDocument` (T-003) to the selected local transport.

/// A [KdsPrintBridge] that encodes the kitchen ticket and delivers it over a
/// native [pp.PrintTransport] (Wi-Fi RAW/TCP or Bluetooth Classic) via the
/// shared [NativeEscPosSender]. Reuses the SAME kitchen-ticket ->
/// [pp.EscPosPrintAdapter] pipeline as the loopback bridge (no duplicated
/// ticket logic); only the transport differs. Delivery = bytes written to the
/// printer, NOT a hardware paper-print acknowledgement.
class NativeKdsPrintBridge implements KdsPrintBridge {
  const NativeKdsPrintBridge(this.sender);

  final NativeEscPosSender sender;

  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) => sender
      .send(kitchenTicketToEscPosDocument(document, columns: sender.columns));

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

/// The active KDS kitchen print bridge (ANDROID-004 transport resolver):
/// - native (Android app) + a configured local printer for the selected
///   transport -> a [NativeKdsPrintBridge] over that Wi-Fi/Bluetooth transport.
/// - otherwise -> the existing loopback [kdsPrintBridgeProvider] (usually null
///   -> the kitchen job stays honestly `prepared`; web KDS is UNCHANGED, it
///   never picks a native transport).
final kdsActivePrintBridgeProvider = Provider<KdsPrintBridge?>((ref) {
  final transportFactory = ref.watch(activeNativeTransportFactoryProvider);
  if (transportFactory != null) {
    return NativeKdsPrintBridge(
      NativeEscPosSender(transportFactory: transportFactory),
    );
  }
  return ref.watch(kdsPrintBridgeProvider);
});

/// Maps the KDS l10n into the shared printer-settings labels (ANDROID-004).
/// Reuses the generic POS printer keys where they fit and the new `kdsPrinter*`
/// keys for the KDS-specific labels. No money strings - the UI is money-free.
NativePrinterStrings kdsNativePrinterStrings(AppLocalizations l10n) =>
    NativePrinterStrings(
      transportHeading: l10n.posPrinterTransportHeading,
      transportNetwork: l10n.kdsPrinterTransportNetwork,
      transportBluetooth: l10n.kdsPrinterTransportBluetooth,
      networkHeading: l10n.posNetworkPrinterHeading,
      networkHelp: l10n.posNetworkPrinterHelp,
      networkIpLabel: l10n.kdsPrinterNetworkIp,
      networkIpHint: l10n.posNetworkPrinterIpHint,
      networkPortLabel: l10n.kdsPrinterNetworkPort,
      networkNameLabel: l10n.posNetworkPrinterNameLabel,
      invalidIp: l10n.posNetworkPrinterInvalidIp,
      invalidPort: l10n.posNetworkPrinterInvalidPort,
      saveAction: l10n.posNetworkPrinterSaveAction,
      testAction: l10n.kdsPrinterTestPrint,
      testing: l10n.posNetworkPrinterTesting,
      testSuccess: l10n.kdsPrinterTicketSent,
      testFailure: l10n.kdsPrinterPrintFailed,
      statusSaved: l10n.posNetworkPrinterStatusSaved,
      statusNotConfigured: l10n.kdsPrinterNoPrinterConfigured,
      networkSavedSnack: l10n.posNetworkPrinterSavedSnack,
      bluetoothHeading: l10n.posBluetoothPrinterHeading,
      bluetoothHelp: l10n.posBluetoothPrinterHelp,
      pairedLabel: l10n.posBluetoothPairedLabel,
      refreshAction: l10n.posBluetoothRefreshAction,
      permissionRequired: l10n.kdsPrinterBluetoothPermissionRequired,
      bluetoothOff: l10n.posBluetoothOff,
      noDevices: l10n.posBluetoothNoDevices,
      selectHint: l10n.kdsPrinterBluetoothPairHint,
      removeAction: l10n.posPrinterRemoveAction,
      removedSnack: l10n.posPrinterRemovedSnack,
      bluetoothSavedSnack: l10n.posBluetoothSavedSnack,
    );
