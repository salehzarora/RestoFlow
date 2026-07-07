import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/pos_bluetooth_printer_config.dart';
import 'bluetooth_printer.dart';
import 'native_print_bridges.dart' show kPosNativePrintTimeout;

/// The "Test print" seam for a Bluetooth printer (ANDROID-003) — mirrors the
/// network tester. Builds the money-free ESC/POS diagnostic document, encodes it
/// for an 80mm profile, and delivers the bytes over the Bluetooth transport.
/// Behind an interface so widget tests inject a fake and never open Bluetooth.
abstract class BluetoothPrinterTester {
  Future<pp.PrintResult> testPrint(
    PosBluetoothPrinterConfig config, {
    String? deviceLabel,
  });
}

/// The default tester: real [BluetoothClassicPrintTransport] over the platform
/// connector (a stub on web / non-Android — fails clearly, never silently).
class DefaultBluetoothPrinterTester implements BluetoothPrinterTester {
  const DefaultBluetoothPrinterTester(
    this.connector, {
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
  });

  final BluetoothPrinterConnector connector;
  final pp.EscPosPrintAdapter adapter;
  final pp.PrinterProfile profile;

  @override
  Future<pp.PrintResult> testPrint(
    PosBluetoothPrinterConfig config, {
    String? deviceLabel,
  }) async {
    final document = pp.escPosNetworkTestDocument(
      printerName: config.name,
      deviceLabel: deviceLabel,
    );
    final bytes = adapter.encode(document, profile);
    final transport = BluetoothClassicPrintTransport(
      connector: connector,
      address: config.address,
      timeout: kPosNativePrintTimeout,
    );
    try {
      return await transport.send(bytes);
    } finally {
      await transport.dispose();
    }
  }
}

/// The active Bluetooth tester. Tests override with a fake.
final bluetoothPrinterTesterProvider = Provider<BluetoothPrinterTester>(
  (ref) => DefaultBluetoothPrinterTester(
    ref.watch(bluetoothPrinterConnectorProvider),
  ),
);
