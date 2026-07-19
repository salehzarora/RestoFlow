import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos_bluetooth_printer_config.dart';
import 'pos_network_printer_config.dart';
import 'pos_printer_transport.dart';

/// KITCHEN-MODE-001B: "Use the customer printer for kitchen tickets".
///
/// An EXPLICIT user action that copies the customer slot's saved endpoint(s) +
/// selected transport into the kitchen slot. This is a one-time COPY, never a
/// hidden link: after copying, the two purpose slots remain fully independent —
/// changing either one later never changes the other. Copies whatever the
/// customer slot actually has (network and/or Bluetooth config + the selected
/// transport); returns false when the customer slot has nothing to copy.
Future<bool> useCustomerPrinterForKitchen(Ref ref) async {
  final customerNet = await ref.read(posNetworkPrinterConfigProvider.future);
  final customerBt = await ref.read(posBluetoothPrinterConfigProvider.future);
  if (customerNet == null && customerBt == null) return false;
  if (customerNet != null) {
    // Settle the slot's initial build FIRST so an in-flight build() can never
    // clobber the value we are about to save (AsyncNotifier init race).
    await ref.read(posKitchenNetworkPrinterConfigProvider.future);
    await ref
        .read(posKitchenNetworkPrinterConfigProvider.notifier)
        .save(customerNet);
  }
  if (customerBt != null) {
    await ref.read(posKitchenBluetoothPrinterConfigProvider.future);
    await ref
        .read(posKitchenBluetoothPrinterConfigProvider.notifier)
        .save(customerBt);
  }
  final transport = await ref.read(posSelectedPrinterTransportProvider.future);
  await ref.read(posKitchenSelectedPrinterTransportProvider.future);
  await ref
      .read(posKitchenSelectedPrinterTransportProvider.notifier)
      .select(transport);
  return true;
}

/// The Riverpod seam widgets call (so widget tests can override it).
final useCustomerPrinterForKitchenProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => useCustomerPrinterForKitchen(ref),
);
