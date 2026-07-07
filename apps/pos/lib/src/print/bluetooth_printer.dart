import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

// Web-safe connector selection: the stub (browsers have no Bluetooth Classic +
// no dart:io) is the default; the native plugin-backed connector is linked only
// where `dart.library.io` exists. This file itself never imports the Bluetooth
// plugin, so the POS stays importable from the web build.
import 'bluetooth_connector_stub.dart'
    if (dart.library.io) 'bluetooth_connector_native.dart';

/// A bonded/paired Bluetooth device (ANDROID-003).
class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({required this.address, required this.name});

  /// The device's Bluetooth address (MAC).
  final String address;

  /// The device's advertised name (may be empty).
  final String name;
}

/// Why a Bluetooth print/list attempt could not proceed (maps to localized UI).
enum BluetoothPrinterError {
  /// Bluetooth printing is not available on this build/platform (e.g. web).
  unsupported,

  /// The runtime BLUETOOTH_CONNECT/SCAN permission was denied.
  permissionDenied,

  /// The Bluetooth adapter is off.
  bluetoothOff,

  /// Could not connect to the printer (out of range / powered off / not bonded).
  connectFailed,

  /// Connected but writing the bytes failed.
  writeFailed,

  /// The operation timed out.
  timeout,
}

/// The result of listing paired devices — the devices OR a typed error.
class BluetoothPairedResult {
  const BluetoothPairedResult.ok(this.devices) : error = null;
  const BluetoothPairedResult.failed(this.error) : devices = const [];

  final List<BluetoothDeviceInfo> devices;
  final BluetoothPrinterError? error;

  bool get ok => error == null;
}

/// The seam over the platform Bluetooth Classic (SPP) stack (ANDROID-003).
///
/// Behind an interface so widget/unit tests inject a fake and never touch real
/// Bluetooth. The default implementation is chosen by a conditional import
/// (native plugin vs. web stub) so the web build never links native code.
abstract class BluetoothPrinterConnector {
  /// Whether Bluetooth printing is possible on this build/platform.
  bool get isSupported;

  /// Ensures the runtime BLUETOOTH_CONNECT/SCAN permissions (Android 12+).
  /// Returns whether they are granted.
  Future<bool> ensurePermissions();

  /// The bonded/paired devices (empty on failure — see [BluetoothPairedResult]).
  Future<BluetoothPairedResult> pairedDevices();

  /// Connects to [address], writes [bytes], and disconnects. Best-effort — a
  /// [pp.PrintResult] that NEVER throws and NEVER hangs (bounded by [timeout]).
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout,
  });
}

/// A [pp.PrintTransport] that delivers ESC/POS bytes to a bonded Bluetooth
/// Classic (SPP) thermal printer via a [BluetoothPrinterConnector]
/// (ANDROID-003). Web-safe: the connector's default impl fails clearly on web.
class BluetoothClassicPrintTransport implements pp.PrintTransport {
  BluetoothClassicPrintTransport({
    required this.connector,
    required this.address,
    this.timeout = const Duration(seconds: 8),
  });

  final BluetoothPrinterConnector connector;

  /// The bonded printer's Bluetooth address (MAC).
  final String address;

  /// Bound for connect + write so an unreachable printer can't hang the UI.
  final Duration timeout;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) =>
      connector.send(address: address, bytes: bytes, timeout: timeout);

  @override
  Future<void> dispose() async {}
}

/// The active Bluetooth connector. The default is platform-resolved (native
/// plugin / web stub); tests override with a fake.
final bluetoothPrinterConnectorProvider = Provider<BluetoothPrinterConnector>(
  (ref) => createBluetoothPrinterConnector(),
);
