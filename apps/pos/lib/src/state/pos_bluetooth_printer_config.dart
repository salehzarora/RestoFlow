import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';
import 'pos_network_printer_config.dart' show kPosNetworkPrinterLocalKey;

export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show BluetoothPrinterConfig;

/// A locally-saved Bluetooth Classic (SPP) ESC/POS printer for THIS device
/// (ANDROID-003): the printer's Bluetooth [address] (MAC) + an optional name.
///
/// Device-LOCAL hardware config — never sent to the backend, never a token or
/// secret. Stored per paired device via `shared_preferences`, exactly like the
/// network printer config. The address identifies a printer already BONDED in
/// Android Bluetooth settings (the MVP uses bonded/paired devices).
/// A locally-saved Bluetooth Classic (SPP) ESC/POS printer for THIS device
/// (ANDROID-003). ANDROID-004 moved the shape into the shared
/// `restoflow_native_printing` package (reused by POS + KDS); this alias keeps
/// the POS's historical name + per-device provider below unchanged.
typedef PosBluetoothPrinterConfig = BluetoothPrinterConfig;

/// The `shared_preferences` key prefix for the per-device saved BT printer.
const String kPosBluetoothPrinterKeyPrefix = 'restoflow.printer.bluetooth.pos.';

/// The saved Bluetooth printer for THIS device, or null when none is configured.
final posBluetoothPrinterConfigProvider =
    AsyncNotifierProvider<
      PosBluetoothPrinterConfigController,
      PosBluetoothPrinterConfig?
    >(PosBluetoothPrinterConfigController.new);

class PosBluetoothPrinterConfigController
    extends AsyncNotifier<PosBluetoothPrinterConfig?> {
  String get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    final segment = (deviceId == null || deviceId.isEmpty)
        ? kPosNetworkPrinterLocalKey
        : deviceId;
    return '$kPosBluetoothPrinterKeyPrefix$segment';
  }

  @override
  Future<PosBluetoothPrinterConfig?> build() async {
    ref.watch(posDeviceContextProvider);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PosBluetoothPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Persists [config] for this device (state first, storage best-effort).
  Future<void> save(PosBluetoothPrinterConfig config) async {
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
