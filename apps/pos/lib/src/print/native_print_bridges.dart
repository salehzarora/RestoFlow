import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show kBluetoothPrintTimeout, nativePrintRasterizerProvider;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/pos_bluetooth_printer_config.dart';
import '../state/pos_network_printer_config.dart';
import '../state/pos_printer_transport.dart';
import 'bluetooth_printer.dart';
import 'print_bridge.dart';
import 'print_document.dart' as app;

/// The bounded timeout for a native print attempt (ANDROID-003): a Wi-Fi/BT
/// printer that is off or out of range fails fast instead of hanging the UI.
const Duration kPosNativePrintTimeout = Duration(seconds: 5);

/// A [PosPrintBridge] that encodes a receipt document and delivers it over a
/// native [pp.PrintTransport] (Wi-Fi RAW/TCP or Bluetooth Classic) — ANDROID-003.
///
/// Reuses the SAME `receiptToEscPosDocument` → [pp.EscPosPrintAdapter] pipeline
/// as the loopback bridge (no duplicated receipt/money logic); only the
/// transport differs. Maps the transport's best-effort [pp.PrintResult] to the
/// honest [pp.BridgeSubmitResult] — success = bytes delivered to the printer
/// (NOT a hardware paper-print acknowledgement).
class NativeTransportPrintBridge implements PosPrintBridge {
  const NativeTransportPrintBridge({
    required this.transportFactory,
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
    this.columns = 48,
    this.rasterizer,
    this.rasterWidthDots = pp.kNativeRasterWidthDots,
  });

  /// Builds a fresh transport per submit (a socket/BT connection is not reused).
  final pp.PrintTransport Function() transportFactory;
  final pp.EscPosPrintAdapter adapter;
  final pp.PrinterProfile profile;
  final int columns;

  /// PRINT-RTL-001: the raster renderer (null => ESC/POS text only). When set,
  /// Arabic/Hebrew (+ non-ASCII ₪/×) receipts render as a bitmap so they print
  /// correctly on printers without a Unicode codepage.
  final pp.ReceiptRasterizer? rasterizer;

  /// Raster width in dots (80mm = 576; multiple of 8).
  final int rasterWidthDots;

  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) async {
    final escpos = receiptToEscPosDocument(document, columns: columns);
    // PRINT-RTL-001: on native Android, render Arabic/Hebrew (+ ₪/×) content as a
    // raster image so it prints correctly; ASCII-only content keeps the crisp
    // text path. A rasterizer failure falls back to the text document (a receipt
    // with "?????" is still better than no print).
    pp.PrintDocument doc = escpos;
    if (rasterizer != null) {
      try {
        doc = await pp.maybeRasterizeForRtl(
          escpos,
          rasterizer: rasterizer,
          widthDots: rasterWidthDots,
        );
      } catch (_) {
        doc = escpos;
      }
    }
    final bytes = adapter.encode(doc, profile);
    final transport = transportFactory();
    try {
      final result = await transport.send(bytes);
      if (result.ok) {
        return const pp.BridgeSubmitResult.sentToPrinter(mode: 'native');
      }
      return pp.BridgeSubmitResult.failed(
        result.category ?? pp.PrinterErrorCategory.unknown,
        result.message,
      );
    } finally {
      await transport.dispose();
    }
  }

  @override
  Future<pp.BridgeHealth> health() async => pp.BridgeHealth.connected;
}

/// The active POS print target (ANDROID-003 transport resolver):
/// - non-native (web): the compiled loopback print bridge (usually null — the
///   print-bridge path is unchanged; web NEVER uses a native transport).
/// - native + bluetooth selected + a saved BT printer → Bluetooth transport.
/// - native + network selected + a saved network printer → TCP transport.
/// - native but the selected transport isn't configured → the loopback bridge
///   (usually null → the receipt stays honestly `prepared`).
final posActivePrintBridgeProvider = Provider<PosPrintBridge?>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) {
    return ref.watch(posPrintBridgeProvider);
  }
  // PRINT-RTL-001: the app injects the real raster renderer; null keeps text mode.
  final rasterizer = ref.watch(nativePrintRasterizerProvider);
  final selected =
      ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  switch (selected) {
    case PosPrinterTransportKind.bluetooth:
      final bt = ref.watch(posBluetoothPrinterConfigProvider).valueOrNull;
      if (bt != null) {
        final connector = ref.watch(bluetoothPrinterConnectorProvider);
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          transportFactory: () => BluetoothClassicPrintTransport(
            connector: connector,
            address: bt.address,
            // PRINT-BLUETOOTH-RECOVERY-001: BT gets its own budget — a cold
            // SPP connect regularly exceeds the 5s Wi-Fi budget, and the
            // native watchdog enforces the bound for real.
            timeout: kBluetoothPrintTimeout,
          ),
        );
      }
    case PosPrinterTransportKind.network:
      final net = ref.watch(posNetworkPrinterConfigProvider).valueOrNull;
      if (net != null) {
        return NativeTransportPrintBridge(
          rasterizer: rasterizer,
          transportFactory: () => pp.NetworkTcpPrintTransport(
            host: net.host,
            port: net.port,
            timeout: kPosNativePrintTimeout,
          ),
        );
      }
  }
  return ref.watch(posPrintBridgeProvider);
});

/// Whether THIS device has a native printer configured for the selected
/// transport (ANDROID-003). Drives the receipt auto-print "has a printer" gate.
/// Always false on web (the print-bridge path is unchanged there).
final posHasNativePrinterProvider = Provider<bool>((ref) {
  if (!ref.watch(posNativePrintingAvailableProvider)) return false;
  final selected =
      ref.watch(posSelectedPrinterTransportProvider).valueOrNull ??
      PosPrinterTransportKind.network;
  return switch (selected) {
    PosPrinterTransportKind.bluetooth =>
      ref.watch(posBluetoothPrinterConfigProvider).valueOrNull != null,
    PosPrinterTransportKind.network =>
      ref.watch(posNetworkPrinterConfigProvider).valueOrNull != null,
  };
});
