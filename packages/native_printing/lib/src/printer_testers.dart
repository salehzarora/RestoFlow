import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';
import 'native_print_target.dart';
import 'printer_config.dart';

/// The "Test print" seam for a local network printer (ANDROID-002).
///
/// Builds the money-free ESC/POS diagnostic document, encodes it for an 80mm
/// profile, and sends the bytes over a raw TCP socket to the configured
/// printer. Behind an interface so widget tests inject a fake and never open a
/// real socket. Nothing here computes money (DECISION D-007/D-008); the test
/// document is a fixed English diagnostic.
abstract class NetworkPrinterTester {
  /// Sends a diagnostic document to [config]. With no [document] the classic
  /// money-free network diagnostic is used; KITCHEN-MODE-001B callers pass the
  /// (equally money-free) kitchen-ticket test document — the tester stays a
  /// pure TRANSPORT seam and never composes content itself.
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  });
}

/// The default tester: real `NetworkTcpPrintTransport` over `dart:io` sockets
/// on native; on web the transport's stub fails clearly (no silent success).
class DefaultNetworkPrinterTester implements NetworkPrinterTester {
  const DefaultNetworkPrinterTester({
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.rasterizer,
    this.timeout = const Duration(seconds: 6),
  });

  final pp.EscPosPrintAdapter adapter;

  /// ESC/POS capabilities/codepage for the adapter — the raster WIDTH comes from
  /// the config's media profile, never from here.
  final pp.PrinterProfile profile;

  /// PRINT-LAYOUT-001A: the raster renderer, so the Test Print renders at the
  /// SELECTED media profile through the SAME pipeline as production.
  final pp.ReceiptRasterizer? rasterizer;
  final Duration timeout;

  @override
  Future<pp.PrintResult> testPrint(
    NetworkPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    final doc =
        document ??
        pp.escPosNetworkTestDocument(
          printerName: config.name,
          deviceLabel: deviceLabel,
        );
    // PRINT-LAYOUT-001A: render at the config's media profile (exact width +
    // fixed-media pagination) — never a hardcoded 80mm/576. Continuous80 with an
    // ASCII doc stays byte-identical (rasterizeForMediaProfile is a no-op there).
    var rendered = doc;
    try {
      rendered = await pp.rasterizeForMediaProfile(
        doc,
        rasterizer: rasterizer,
        profile: config.mediaProfile,
      );
    } catch (_) {
      rendered = doc;
    }
    final bytes = adapter.encode(rendered, profile);
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
  (ref) => DefaultNetworkPrinterTester(
    rasterizer: ref.watch(nativePrintRasterizerProvider),
  ),
);

/// The "Test print" seam for a Bluetooth printer (ANDROID-003) - mirrors the
/// network tester. Builds the money-free ESC/POS diagnostic document, encodes it
/// for an 80mm profile, and delivers the bytes over the Bluetooth transport.
/// Behind an interface so widget tests inject a fake and never open Bluetooth.
abstract class BluetoothPrinterTester {
  /// Sends a diagnostic document to [config] (see [NetworkPrinterTester]).
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  });
}

/// The default tester: real [BluetoothClassicPrintTransport] over the platform
/// connector (a stub on web / non-Android - fails clearly, never silently).
class DefaultBluetoothPrinterTester implements BluetoothPrinterTester {
  const DefaultBluetoothPrinterTester(
    this.connector, {
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.rasterizer,
  });

  final BluetoothPrinterConnector connector;
  final pp.EscPosPrintAdapter adapter;
  final pp.PrinterProfile profile;

  /// PRINT-LAYOUT-001A: the raster renderer, so Test Print renders at the
  /// selected media profile (exact width + fixed-media pagination).
  final pp.ReceiptRasterizer? rasterizer;

  @override
  Future<pp.PrintResult> testPrint(
    BluetoothPrinterConfig config, {
    String? deviceLabel,
    pp.PrintDocument? document,
  }) async {
    final doc =
        document ??
        pp.escPosNetworkTestDocument(
          printerName: config.name,
          deviceLabel: deviceLabel,
        );
    var rendered = doc;
    try {
      rendered = await pp.rasterizeForMediaProfile(
        doc,
        rasterizer: rasterizer,
        profile: config.mediaProfile,
      );
    } catch (_) {
      rendered = doc;
    }
    final bytes = adapter.encode(rendered, profile);
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
    rasterizer: ref.watch(nativePrintRasterizerProvider),
  ),
);
