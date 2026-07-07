import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';

/// A locally-saved network (Wi-Fi/Ethernet) ESC/POS printer for THIS device
/// (ANDROID-002): a printer IP/host, a TCP port (9100 by default), and an
/// optional friendly name.
///
/// This is device-LOCAL hardware config, not backend/tenant data — it never
/// leaves the device and never carries a token or secret. It is stored per
/// paired device id (so two stations sharing a machine don't share a printer)
/// via `shared_preferences`, exactly like the auto-print preference.
class PosNetworkPrinterConfig {
  const PosNetworkPrinterConfig({
    required this.host,
    this.port = 9100,
    this.name,
  });

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
  static PosNetworkPrinterConfig? fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    if (host is! String || host.trim().isEmpty) return null;
    final rawPort = json['port'];
    final port = rawPort is int
        ? rawPort
        : int.tryParse('${rawPort ?? ''}') ?? 9100;
    if (port < 1 || port > 65535) return null;
    final name = json['name'];
    return PosNetworkPrinterConfig(
      host: host.trim(),
      port: port,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
  }
}

/// The `shared_preferences` key prefix for the per-device saved network printer.
const String kPosNetworkPrinterKeyPrefix = 'restoflow.printer.network.pos.';

/// A stable fallback key segment for when no device is paired yet (demo / not
/// yet paired) so the pilot can still configure + test-print a printer.
const String kPosNetworkPrinterLocalKey = 'local';

/// The saved network printer for THIS device, or null when none is configured.
final posNetworkPrinterConfigProvider =
    AsyncNotifierProvider<
      PosNetworkPrinterConfigController,
      PosNetworkPrinterConfig?
    >(PosNetworkPrinterConfigController.new);

class PosNetworkPrinterConfigController
    extends AsyncNotifier<PosNetworkPrinterConfig?> {
  String get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    final segment = (deviceId == null || deviceId.isEmpty)
        ? kPosNetworkPrinterLocalKey
        : deviceId;
    return '$kPosNetworkPrinterKeyPrefix$segment';
  }

  @override
  Future<PosNetworkPrinterConfig?> build() async {
    // Re-read when the pairing gate (re)publishes the device.
    ref.watch(posDeviceContextProvider);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PosNetworkPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      // Unreadable/corrupt prefs degrade to "not configured", never crash.
      return null;
    }
  }

  /// Persists [config] for this device (state first, storage best-effort).
  Future<void> save(PosNetworkPrinterConfig config) async {
    state = AsyncData(config);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } catch (_) {
      // Best-effort persistence: the in-session config still applies.
    }
  }

  /// Removes this device's saved printer.
  Future<void> clear() async {
    state = const AsyncData(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Best-effort.
    }
  }
}
