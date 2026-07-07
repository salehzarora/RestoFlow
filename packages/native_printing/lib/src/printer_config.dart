import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bounded timeout for a native print attempt (ANDROID-003/004): a Wi-Fi/BT
/// printer that is off or out of range fails fast instead of hanging the UI.
const Duration kNativePrintTimeout = Duration(seconds: 5);

/// A locally-saved network (Wi-Fi/Ethernet) ESC/POS printer for THIS device
/// (ANDROID-002): a printer IP/host, a TCP port (9100 by default), and an
/// optional friendly name.
///
/// This is device-LOCAL hardware config, not backend/tenant data - it never
/// leaves the device and never carries a token or secret. It is stored per
/// paired device id (so two stations sharing a machine don't share a printer)
/// via `shared_preferences`, exactly like the auto-print preference. Money-free.
class NetworkPrinterConfig {
  const NetworkPrinterConfig({required this.host, this.port = 9100, this.name});

  /// The printer IP address (or resolvable host) on the local network.
  final String host;

  /// The TCP port; 9100 (RAW/JetDirect) by default.
  final int port;

  /// Optional friendly label shown in the UI and on the test print.
  final String? name;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    if (name != null && name!.isNotEmpty) 'name': name,
  };

  /// Parses a stored map, or null when the shape is invalid (fail-safe: a
  /// corrupt entry degrades to "not configured", never a crash).
  static NetworkPrinterConfig? fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    if (host is! String || host.trim().isEmpty) return null;
    final rawPort = json['port'];
    final port = rawPort is int
        ? rawPort
        : int.tryParse('${rawPort ?? ''}') ?? 9100;
    if (port < 1 || port > 65535) return null;
    final name = json['name'];
    return NetworkPrinterConfig(
      host: host.trim(),
      port: port,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
  }
}

/// A locally-saved Bluetooth Classic (SPP) ESC/POS printer for THIS device
/// (ANDROID-003): the printer's Bluetooth [address] (MAC) + an optional name.
///
/// Device-LOCAL hardware config - never sent to the backend, never a token or
/// secret. Stored per paired device via `shared_preferences`, exactly like the
/// network printer config. The address identifies a printer already BONDED in
/// Android Bluetooth settings (the MVP uses bonded/paired devices).
class BluetoothPrinterConfig {
  const BluetoothPrinterConfig({required this.address, this.name});

  /// The printer's Bluetooth address (MAC), e.g. `DC:0D:30:AA:BB:CC`.
  final String address;

  /// Optional friendly device name shown in the UI and on the test print.
  final String? name;

  Map<String, dynamic> toJson() => {
    'address': address,
    if (name != null && name!.isNotEmpty) 'name': name,
  };

  /// Parses a stored map, or null when the shape is invalid (fail-safe).
  static BluetoothPrinterConfig? fromJson(Map<String, dynamic> json) {
    final address = json['address'];
    if (address is! String || address.trim().isEmpty) return null;
    final name = json['name'];
    return BluetoothPrinterConfig(
      address: address.trim(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
  }
}

/// Which local transport an app uses for on-device printing (ANDROID-003).
///
/// On the native Android app the operator picks one; on web there is no native
/// transport (the app keeps the print-bridge path) and this selection is inert.
enum PrinterTransportKind {
  /// A Wi-Fi/Ethernet RAW ESC/POS printer (TCP :9100). The ANDROID-002 default.
  network,

  /// A Bluetooth Classic (SPP) thermal printer (ANDROID-003).
  bluetooth,
}

/// True when this build can print directly to a native (Wi-Fi/Bluetooth) printer
/// - the native Android app. On web the app has no `dart:io` sockets / Bluetooth
/// and keeps the print-bridge path, so the native printer UI + transports are
/// off and the bridge messaging is unchanged. Overridable in tests.
final nativePrintingAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

/// Accepts a dotted IPv4 (each octet 0-255) or a simple hostname.
bool isValidPrinterHost(String value) {
  final v = value.trim();
  if (v.isEmpty || v.contains(' ')) return false;
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  final m = ipv4.firstMatch(v);
  if (m != null) {
    for (var i = 1; i <= 4; i++) {
      if (int.parse(m.group(i)!) > 255) return false;
    }
    return true;
  }
  // Hostname: letters/digits/dots/hyphens, must contain a letter.
  return RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(v) &&
      RegExp(r'[A-Za-z]').hasMatch(v);
}
