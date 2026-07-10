import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';
import 'native_printer_store.dart';
import 'printer_config.dart';

/// Encodes an already-built render-neutral ESC/POS [pp.PrintDocument] and
/// delivers it over a native [pp.PrintTransport] (Wi-Fi RAW/TCP or Bluetooth
/// Classic) - the reusable ANDROID-004 send path shared by the POS receipt
/// bridge and the KDS kitchen-ticket bridge.
///
/// Money-free by construction: the caller owns the document; this only encodes
/// the bytes and maps the transport's best-effort [pp.PrintResult] to the honest
/// [pp.BridgeSubmitResult] - success = bytes delivered to the printer (NOT a
/// hardware paper-print acknowledgement).
class NativeEscPosSender {
  const NativeEscPosSender({
    required this.transportFactory,
    this.adapter = const pp.EscPosPrintAdapter(),
    this.profile = pp.PrinterProfile.escPos80mm,
  });

  /// Builds a fresh transport per submit (a socket/BT connection is not reused).
  final pp.PrintTransport Function() transportFactory;
  final pp.EscPosPrintAdapter adapter;
  final pp.PrinterProfile profile;

  /// The ESC/POS column count for [profile] (48 for 80mm) - the caller uses it
  /// to lay out fixed-width two-column lines before building the document.
  int get columns => profile == pp.PrinterProfile.escPos80mm ? 48 : 32;

  Future<pp.BridgeSubmitResult> send(pp.PrintDocument escpos) async {
    final bytes = adapter.encode(escpos, profile);
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
}

/// PRINT-RTL-001 seam: the raster text renderer for on-device Arabic/Hebrew (and
/// non-ASCII ₪/× ) printing. Null (the DEFAULT) => native prints stay ESC/POS
/// TEXT (web, and tests that don't override it). Each Android app overrides it in
/// main.dart with the real dart:ui `FlutterReceiptRasterizer` (restoflow_l10n) so
/// ar/he render as a bitmap instead of "?????". Tests inject a
/// `FakeReceiptRasterizer`. Keeping it a nullable seam here avoids a
/// native_printing -> l10n dependency (the concrete impl is injected by the app).
final nativePrintRasterizerProvider = Provider<pp.ReceiptRasterizer?>(
  (ref) => null,
);

/// The active native transport factory for THIS device (ANDROID-004 resolver),
/// or null when native printing is unavailable (web) or nothing is configured
/// for the selected transport. Reads the shared device-local config store, so an
/// app overrides the device-id/namespace seams and reuses this resolver.
///
///  * non-native (web): always null - the app keeps its print-bridge path and
///    NEVER uses a native transport.
///  * native + bluetooth selected + a saved BT printer -> a Bluetooth transport.
///  * native + network selected + a saved network printer -> a TCP transport.
///  * native but the selected transport isn't configured -> null.
final activeNativeTransportFactoryProvider =
    Provider<pp.PrintTransport Function()?>((ref) {
      if (!ref.watch(nativePrintingAvailableProvider)) return null;
      final selected =
          ref.watch(selectedPrinterTransportProvider).valueOrNull ??
          PrinterTransportKind.network;
      switch (selected) {
        case PrinterTransportKind.bluetooth:
          final bt = ref.watch(bluetoothPrinterConfigProvider).valueOrNull;
          if (bt != null) {
            final connector = ref.watch(bluetoothPrinterConnectorProvider);
            return () => BluetoothClassicPrintTransport(
              connector: connector,
              address: bt.address,
              // PRINT-BLUETOOTH-RECOVERY-001: a cold SPP connect needs more
              // than the 5s Wi-Fi budget; the native watchdog enforces this.
              timeout: kBluetoothPrintTimeout,
            );
          }
        case PrinterTransportKind.network:
          final net = ref.watch(networkPrinterConfigProvider).valueOrNull;
          if (net != null) {
            return () => pp.NetworkTcpPrintTransport(
              host: net.host,
              port: net.port,
              timeout: kNativePrintTimeout,
            );
          }
      }
      return null;
    });

/// Whether THIS device has a native printer configured for the selected
/// transport (ANDROID-004). Drives the "has a local printer" gate. Always false
/// on web (the print-bridge path is unchanged there).
final hasNativePrinterProvider = Provider<bool>((ref) {
  if (!ref.watch(nativePrintingAvailableProvider)) return false;
  final selected =
      ref.watch(selectedPrinterTransportProvider).valueOrNull ??
      PrinterTransportKind.network;
  return switch (selected) {
    PrinterTransportKind.bluetooth =>
      ref.watch(bluetoothPrinterConfigProvider).valueOrNull != null,
    PrinterTransportKind.network =>
      ref.watch(networkPrinterConfigProvider).valueOrNull != null,
  };
});
