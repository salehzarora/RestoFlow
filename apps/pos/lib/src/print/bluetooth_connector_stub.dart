import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';

/// Web / non-`dart:io` Bluetooth connector (ANDROID-003): Bluetooth Classic
/// printing is not available in a browser, so every call fails clearly. The
/// native (`dart:io`) connector in `bluetooth_connector_native.dart` is selected
/// by a conditional import on Android; web never links the Bluetooth plugin.
BluetoothPrinterConnector createBluetoothPrinterConnector() =>
    const _UnsupportedBluetoothConnector();

class _UnsupportedBluetoothConnector implements BluetoothPrinterConnector {
  const _UnsupportedBluetoothConnector();

  @override
  bool get isSupported => false;

  @override
  Future<bool> ensurePermissions() async => false;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.failed(BluetoothPrinterError.unsupported);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = const Duration(seconds: 8),
  }) async => const pp.PrintResult.failure(
    pp.PrinterErrorCategory.unsupported,
    'Bluetooth printing is not available on this platform.',
  );
}
