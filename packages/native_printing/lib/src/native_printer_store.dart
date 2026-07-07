import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';

/// The app-provided device id that scopes the saved printer config to THIS
/// paired device (ANDROID-004 seam). Null/empty => a stable `local` fallback so
/// an unpaired device (demo / not yet paired) can still configure + test-print.
///
/// Each app overrides this with its own device-context device id (POS reads
/// `posDeviceContextProvider`, KDS reads the KDS device context), so the shared
/// store re-reads when the pairing gate (re)publishes the device.
final nativePrinterDeviceIdProvider = Provider<String?>((ref) => null);

/// The app namespace segment in the `shared_preferences` key so the POS and KDS
/// on one machine never share a printer selection (ANDROID-004 seam). Apps
/// override it (`pos` / `kds`); the POS keys keep their historical `pos`
/// namespace (`restoflow.printer.network.pos.*`) so existing saved printers and
/// tests resolve unchanged.
final nativePrinterNamespaceProvider = Provider<String>((ref) => 'app');

/// A stable fallback key segment for when no device is paired yet.
const String kNativePrinterLocalKey = 'local';

String _prefsKey(Ref ref, String kind) {
  final deviceId = ref.watch(nativePrinterDeviceIdProvider);
  final namespace = ref.watch(nativePrinterNamespaceProvider);
  final segment = (deviceId == null || deviceId.isEmpty)
      ? kNativePrinterLocalKey
      : deviceId;
  return 'restoflow.printer.$kind.$namespace.$segment';
}

/// The saved network printer for THIS device, or null when none is configured.
final networkPrinterConfigProvider =
    AsyncNotifierProvider<
      NetworkPrinterConfigController,
      NetworkPrinterConfig?
    >(NetworkPrinterConfigController.new);

class NetworkPrinterConfigController
    extends AsyncNotifier<NetworkPrinterConfig?> {
  String get _key => _prefsKey(ref, 'network');

  @override
  Future<NetworkPrinterConfig?> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? NetworkPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      // Unreadable/corrupt prefs degrade to "not configured", never crash.
      return null;
    }
  }

  /// Persists [config] for this device (state first, storage best-effort).
  Future<void> save(NetworkPrinterConfig config) async {
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

/// The saved Bluetooth printer for THIS device, or null when none is configured.
final bluetoothPrinterConfigProvider =
    AsyncNotifierProvider<
      BluetoothPrinterConfigController,
      BluetoothPrinterConfig?
    >(BluetoothPrinterConfigController.new);

class BluetoothPrinterConfigController
    extends AsyncNotifier<BluetoothPrinterConfig?> {
  String get _key => _prefsKey(ref, 'bluetooth');

  @override
  Future<BluetoothPrinterConfig?> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? BluetoothPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Persists [config] for this device (state first, storage best-effort).
  Future<void> save(BluetoothPrinterConfig config) async {
    state = AsyncData(config);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } catch (_) {
      // Best-effort persistence: the in-session config still applies.
    }
  }

  /// Removes this device's saved Bluetooth printer.
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

/// The transport the operator selected on THIS device (default [network]).
/// Persisted per paired device, like the printer configs.
final selectedPrinterTransportProvider =
    AsyncNotifierProvider<
      SelectedPrinterTransportController,
      PrinterTransportKind
    >(SelectedPrinterTransportController.new);

class SelectedPrinterTransportController
    extends AsyncNotifier<PrinterTransportKind> {
  String get _key => _prefsKey(ref, 'selected');

  @override
  Future<PrinterTransportKind> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == 'bluetooth'
          ? PrinterTransportKind.bluetooth
          : PrinterTransportKind.network;
    } catch (_) {
      return PrinterTransportKind.network;
    }
  }

  /// Persists the selected transport (state first, storage best-effort).
  Future<void> select(PrinterTransportKind kind) async {
    state = AsyncData(kind);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, kind.name);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}
