import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';
import 'pos_network_printer_config.dart' show kPosNetworkPrinterLocalKey;

/// True when this build can print directly to a native (Wi-Fi/Bluetooth) printer
/// — the native Android app. ANDROID-004 moved the definition into the shared
/// `restoflow_native_printing` package; this keeps the POS's historical name
/// pointing at the same provider instance (overrides + tests unchanged).
final posNativePrintingAvailableProvider = nativePrintingAvailableProvider;

/// Which local transport the POS uses for on-device printing (ANDROID-003).
/// ANDROID-004 moved the enum into the shared package; this alias keeps the
/// POS's historical name + persisted selection provider below unchanged.
typedef PosPrinterTransportKind = PrinterTransportKind;

/// The `shared_preferences` key prefix for the per-device selected transport.
const String kPosPrinterTransportKeyPrefix = 'restoflow.printer.selected.pos.';

/// The transport the cashier selected on THIS device (default [network]).
/// Persisted per paired device, like the printer configs.
final posSelectedPrinterTransportProvider =
    AsyncNotifierProvider<
      PosSelectedPrinterTransportController,
      PosPrinterTransportKind
    >(PosSelectedPrinterTransportController.new);

class PosSelectedPrinterTransportController
    extends AsyncNotifier<PosPrinterTransportKind> {
  String get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    final segment = (deviceId == null || deviceId.isEmpty)
        ? kPosNetworkPrinterLocalKey
        : deviceId;
    return '$kPosPrinterTransportKeyPrefix$segment';
  }

  @override
  Future<PosPrinterTransportKind> build() async {
    ref.watch(posDeviceContextProvider);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == 'bluetooth'
          ? PosPrinterTransportKind.bluetooth
          : PosPrinterTransportKind.network;
    } catch (_) {
      return PosPrinterTransportKind.network;
    }
  }

  /// Persists the selected transport (state first, storage best-effort).
  Future<void> select(PosPrinterTransportKind kind) async {
    state = AsyncData(kind);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, kind.name);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}
