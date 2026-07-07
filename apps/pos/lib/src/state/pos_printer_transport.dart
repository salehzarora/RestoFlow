import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';
import 'pos_network_printer_config.dart' show kPosNetworkPrinterLocalKey;

/// True when this build can print directly to a native (Wi-Fi/Bluetooth) printer
/// — the native Android app. On web the app has no `dart:io` sockets / Bluetooth
/// and keeps the print-bridge path, so the native printer UI + transports are
/// off and the bridge messaging is unchanged. Overridable in tests.
/// (Moved here from the network printer section in ANDROID-003.)
final posNativePrintingAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

/// Which local transport the POS uses for on-device printing (ANDROID-003).
///
/// On the native Android app the cashier picks one; on web there is no native
/// transport (the app keeps the print-bridge path) and this selection is inert.
enum PosPrinterTransportKind {
  /// A Wi-Fi/Ethernet RAW ESC/POS printer (TCP :9100). The ANDROID-002 default.
  network,

  /// A Bluetooth Classic (SPP) thermal printer (ANDROID-003).
  bluetooth,
}

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
