import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';
import 'pos_printer_purpose.dart';

export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show NetworkPrinterConfig;

/// A locally-saved network (Wi-Fi/Ethernet) ESC/POS printer for THIS device
/// (ANDROID-002): a printer IP/host, a TCP port (9100 by default), and an
/// optional friendly name.
///
/// This is device-LOCAL hardware config, not backend/tenant data — it never
/// leaves the device and never carries a token or secret. It is stored per
/// paired device id (so two stations sharing a machine don't share a printer)
/// via `shared_preferences`, exactly like the auto-print preference.
/// ANDROID-004 moved the shape into the shared `restoflow_native_printing`
/// package (reused by POS + KDS); this alias keeps the POS's historical name +
/// per-device providers below unchanged.
typedef PosNetworkPrinterConfig = NetworkPrinterConfig;

/// The `shared_preferences` key prefix for the per-device saved network printer.
const String kPosNetworkPrinterKeyPrefix = 'restoflow.printer.network.pos.';

/// A stable fallback key segment for when no device is paired yet (demo / not
/// yet paired) so the pilot can still configure + test-print a printer.
const String kPosNetworkPrinterLocalKey = 'local';

/// KITCHEN-MODE-001B: the per-PURPOSE saved network printer family.
/// [PosPrinterPurpose.customerReceipt] reads/writes the LEGACY key (identity
/// migration — existing installations keep their receipt printer untouched);
/// [PosPrinterPurpose.kitchenTicket] uses the purpose-suffixed key and starts
/// unset. The two slots are fully independent (separate keys) — the SAME
/// endpoint may be saved in both, and writing one never touches the other.
final posNetworkPrinterConfigFamily =
    AsyncNotifierProvider.family<
      PosNetworkPrinterConfigController,
      PosNetworkPrinterConfig?,
      PosPrinterPurpose
    >(PosNetworkPrinterConfigController.new);

/// The CUSTOMER-RECEIPT slot — the POS's historical provider name. Every
/// pre-001B call site (receipt controller, bridges, settings) keeps resolving
/// exactly this slot; nothing ever prints a kitchen ticket through it.
final posNetworkPrinterConfigProvider = posNetworkPrinterConfigFamily(
  PosPrinterPurpose.customerReceipt,
);

/// The KITCHEN-TICKET slot (KITCHEN-MODE-001B; preparation-only this phase).
final posKitchenNetworkPrinterConfigProvider = posNetworkPrinterConfigFamily(
  PosPrinterPurpose.kitchenTicket,
);

class PosNetworkPrinterConfigController
    extends FamilyAsyncNotifier<PosNetworkPrinterConfig?, PosPrinterPurpose> {
  String get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    final segment = (deviceId == null || deviceId.isEmpty)
        ? kPosNetworkPrinterLocalKey
        : deviceId;
    return '$kPosNetworkPrinterKeyPrefix${arg.keySegment}$segment';
  }

  @override
  Future<PosNetworkPrinterConfig?> build(PosPrinterPurpose arg) async {
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

  /// Persists [config] for this device+purpose (state first, best-effort).
  Future<void> save(PosNetworkPrinterConfig config) async {
    state = AsyncData(config);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } catch (_) {
      // Best-effort persistence: the in-session config still applies.
    }
  }

  /// Removes this device+purpose's saved printer (other purposes untouched).
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
