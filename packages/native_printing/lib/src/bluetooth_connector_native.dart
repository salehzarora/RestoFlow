import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import 'bluetooth_printer.dart';

/// Native (`dart:io`) Bluetooth connector (ANDROID-003 / PRINT-STABILITY-001).
/// Android drives the reliability-hardened [BluetoothThermalConnector] over the
/// plugin-backed [BluetoothThermalApi] (reconnect + chunked writes + one retry);
/// other native platforms (iOS/desktop) report unsupported for this
/// Android-focused MVP. Web never links this file.
BluetoothPrinterConnector createBluetoothPrinterConnector() =>
    defaultTargetPlatform == TargetPlatform.android
    ? BluetoothThermalConnector(api: const _PluginBluetoothThermalApi())
    : const _UnsupportedNativeConnector();

/// The `print_bluetooth_thermal` + `permission_handler` backing for
/// [BluetoothThermalApi]. Thin pass-through: NO reconnect/retry/chunking logic
/// lives here (that is the plugin-free [BluetoothThermalConnector], so it stays
/// unit-testable). Every method is best-effort and swallows plugin errors into a
/// false/typed result so control flow never depends on an exception.
class _PluginBluetoothThermalApi implements BluetoothThermalApi {
  const _PluginBluetoothThermalApi();

  @override
  Future<bool> ensurePermissions() async {
    try {
      final results = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      return results.values.every((s) => s.isGranted);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get isEnabled async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BluetoothDeviceInfo>> pairedDevices() async {
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final d in paired)
        BluetoothDeviceInfo(address: d.macAdress, name: d.name),
    ];
  }

  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);

  @override
  Future<bool> writeBytes(List<int> bytes) =>
      PrintBluetoothThermal.writeBytes(bytes);

  @override
  Future<bool> disconnect() => PrintBluetoothThermal.disconnect;
}

/// iOS / desktop native: Bluetooth Classic printing is not offered in this
/// Android-focused MVP.
class _UnsupportedNativeConnector implements BluetoothPrinterConnector {
  const _UnsupportedNativeConnector();

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
    'Bluetooth printing is only implemented on Android.',
  );
}
