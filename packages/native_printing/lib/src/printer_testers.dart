import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';
import 'printer_config.dart';

/// The "Test print" seam for a local network printer (ANDROID-002).
///
/// Builds the money-free ESC/POS diagnostic document, encodes it for an 80mm
/// profile, and sends the bytes over a raw TCP socket to the configured
/// printer. Behind an interface so widget tests inject a fake and never open a
/// real socket. Nothing here computes money (DECISION D-007/D-008); the test
/// document is a fixed English diagnostic.
abstract class NetworkPrinterTester {
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
  });
}

/// The default tester: real `NetworkTcpPrintTransport` over `dart:io` sockets
/// on native; on web the transport's stub fails clearly (no silent success).
class DefaultNetworkPrinterTester implements NetworkPrinterTester {
  const DefaultNetworkPrinterTester({
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.timeout = const Duration(seconds: 6),
  });

  final pp.EscPosPrintAdapter adapter;
  final pp.PrinterProfile profile;
  final Duration timeout;

  @override
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
  }) async {
    final document = pp.escPosNetworkTestDocument(
      printerName: config.name,
      deviceLabel: deviceLabel,
    );
    final bytes = adapter.encode(document, profile);
    final transport = pp.NetworkTcpPrintTransport(
      host: config.host,
      port: config.port,
      timeout: timeout,
    );
    try {
      return await transport.send(bytes);
    } finally {
      await transport.dispose();
    }
  }
}

/// The active tester. Tests override with a fake to capture the attempt.
final networkPrinterTesterProvider = Provider<NetworkPrinterTester>(
  (ref) => const DefaultNetworkPrinterTester(),
);

/// The "Test print" seam for a Bluetooth printer (ANDROID-003) - mirrors the
/// network tester. Builds the money-free ESC/POS diagnostic document, encodes it
/// for an 80mm profile, and delivers the bytes over the Bluetooth transport.
/// Behind an interface so widget tests inject a fake and never open Bluetooth.
abstract class BluetoothPrinterTester {
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
  });
}

/// The default tester: real [BluetoothClassicPrintTransport] over the platform
/// connector (a stub on web / non-Android - fails clearly, never silently).
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
    BluetoothPrinterConfig config, {
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
      // PRINT-BLUETOOTH-RECOVERY-001: BT connects get the Bluetooth budget
      // (a cold SPP connect regularly exceeds the 5s Wi-Fi budget).
      timeout: kBluetoothPrintTimeout,
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
