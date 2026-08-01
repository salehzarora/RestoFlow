import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';
import 'pos_printer_purpose.dart';

export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show BluetoothPrinterConfig;

/// A locally-saved Bluetooth Classic (SPP) ESC/POS printer for THIS device
/// (ANDROID-003): the printer's Bluetooth [address] (MAC) + an optional name.
///
/// Device-LOCAL hardware config — never sent to the backend, never a token or
/// secret. Stored per paired device via `shared_preferences`, exactly like the
/// network printer config. The address identifies a printer already BONDED in
/// Android Bluetooth settings (the MVP uses bonded/paired devices).
/// ANDROID-004 moved the shape into the shared `restoflow_native_printing`
/// package (reused by POS + KDS); this alias keeps the POS's historical name +
/// per-device providers below unchanged.
typedef PosBluetoothPrinterConfig = BluetoothPrinterConfig;

/// The `shared_preferences` key prefix for the per-device saved BT printer.
const String kPosBluetoothPrinterKeyPrefix = 'restoflow.printer.bluetooth.pos.';

/// KITCHEN-MODE-001B: the per-PURPOSE saved Bluetooth printer family
/// (customerReceipt = the LEGACY key, identity migration; kitchenTicket = the
/// purpose-suffixed key, starts unset; slots fully independent).
final posBluetoothPrinterConfigFamily =
    AsyncNotifierProvider.family<
      PosBluetoothPrinterConfigController,
      PosBluetoothPrinterConfig?,
      PosPrinterPurpose
    >(PosBluetoothPrinterConfigController.new);

/// The CUSTOMER-RECEIPT slot — the POS's historical provider name.
final posBluetoothPrinterConfigProvider = posBluetoothPrinterConfigFamily(
  PosPrinterPurpose.customerReceipt,
);

/// The KITCHEN-TICKET slot (KITCHEN-MODE-001B; preparation-only this phase).
final posKitchenBluetoothPrinterConfigProvider =
    posBluetoothPrinterConfigFamily(PosPrinterPurpose.kitchenTicket);

class PosBluetoothPrinterConfigController
    extends FamilyAsyncNotifier<PosBluetoothPrinterConfig?, PosPrinterPurpose> {
  String _keyFor(String segment) =>
      '$kPosBluetoothPrinterKeyPrefix${arg.keySegment}$segment';

  @override
  Future<PosBluetoothPrinterConfig?> build(PosPrinterPurpose arg) async {
    // PRINT-STARTUP-REPRINT-001: same authoritative-scope contract as the
    // network slot. Bluetooth and Wi-Fi remain fully separate key families.
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();
      final own = _parse(prefs.getString(_keyFor(segment)));
      if (own != null) return own;
      if (segment == kPosPrinterScopeLocalKey) return null;
      final legacyRaw = prefs.getString(_keyFor(kPosPrinterScopeLocalKey));
      final legacy = _parse(legacyRaw);
      if (legacy == null) return null;
      try {
        await prefs.setString(_keyFor(segment), legacyRaw!);
      } catch (_) {
        // Serve it this session; the legacy source is never deleted.
      }
      return legacy;
    } catch (_) {
      return null;
    }
  }

  /// Persists [config] for this device+purpose into the authoritative scope.
  Future<void> save(PosBluetoothPrinterConfig config) async {
    if (config.address.trim().isEmpty) return; // never clobber with invalid
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    await _settle();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFor(segment), jsonEncode(config.toJson()));
      state = AsyncData(config);
    } catch (_) {
      // Persistence failed: the previously saved profile stands.
    }
  }

  /// Removes this device+purpose's saved Bluetooth printer.
  Future<void> clear() async {
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    await _settle();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(segment));
      if (segment != kPosPrinterScopeLocalKey) {
        await prefs.remove(_keyFor(kPosPrinterScopeLocalKey));
      }
    } catch (_) {
      // Best-effort.
    }
    state = const AsyncData(null);
  }

  Future<void> _settle() async {
    try {
      await future;
    } catch (_) {
      // A failed load must not block an explicit action.
    }
  }

  PosBluetoothPrinterConfig? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PosBluetoothPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }
}
