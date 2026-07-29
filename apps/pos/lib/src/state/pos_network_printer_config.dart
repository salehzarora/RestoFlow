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
///
/// PRINT-STARTUP-REPRINT-001: this is now the ONE shared constant
/// [kPosPrinterScopeLocalKey]; the alias is kept so existing imports of this
/// name keep compiling.
const String kPosNetworkPrinterLocalKey = kPosPrinterScopeLocalKey;

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

/// True when [config] is safe to persist. An invalid profile must NEVER
/// overwrite the last valid one (PRINT-STARTUP-REPRINT-001).
bool isValidNetworkPrinterConfig(PosNetworkPrinterConfig config) =>
    config.host.trim().isNotEmpty && config.port > 0 && config.port <= 65535;

class PosNetworkPrinterConfigController
    extends FamilyAsyncNotifier<PosNetworkPrinterConfig?, PosPrinterPurpose> {
  String _keyFor(String segment) =>
      '$kPosNetworkPrinterKeyPrefix${arg.keySegment}$segment';

  @override
  Future<PosNetworkPrinterConfig?> build(PosPrinterPurpose arg) async {
    // PRINT-STARTUP-REPRINT-001: WAIT for the authoritative scope. While a
    // device-session restore is pending this suspends (stays loading) instead
    // of reading the legacy `local` namespace and latching the wrong answer.
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. The CURRENT device-scoped key always wins.
      final own = _parse(prefs.getString(_keyFor(segment)));
      if (own != null) return own;

      // 2. Only when it is empty, fall back to the LEGACY local key of this
      //    SAME app installation. Never another device id — there is no
      //    device -> local -> other-device chain anywhere in this class.
      if (segment == kPosPrinterScopeLocalKey) return null;
      final legacyRaw = prefs.getString(_keyFor(kPosPrinterScopeLocalKey));
      final legacy = _parse(legacyRaw);
      if (legacy == null) return null;

      // 3. Adopt it ONCE into the current device namespace, and verify the
      //    write landed before treating the migration as done. The legacy
      //    source is deliberately KEPT: losing a working printer profile to a
      //    half-finished migration is far worse than a stale duplicate key.
      await _writeVerified(prefs, _keyFor(segment), legacyRaw!);
      return legacy;
    } catch (_) {
      // Unreadable/corrupt prefs degrade to "not configured", never crash.
      return null;
    }
  }

  /// Persists [config] for this device+purpose.
  ///
  /// Waits for the authoritative scope and settles any in-flight load first, so
  /// a save issued during cold startup can never land in the legacy namespace.
  /// Exposed state is updated only after the write is verified; a failed or
  /// invalid save leaves the previously saved profile untouched.
  Future<void> save(PosNetworkPrinterConfig config) async {
    if (!isValidNetworkPrinterConfig(config)) return; // keep the last valid one
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    await _settle();
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await _writeVerified(
        prefs,
        _keyFor(segment),
        jsonEncode(config.toJson()),
      );
      if (ok) state = AsyncData(config);
    } catch (_) {
      // Persistence failed: the previously saved profile stands.
    }
  }

  /// Removes this device+purpose's saved printer (other purposes untouched).
  ///
  /// The ONLY path that deletes a profile. It also clears the legacy local key
  /// for this slot so an explicit removal is not silently undone by the
  /// adoption fallback on the next cold start.
  Future<void> clear() async {
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    await _settle();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(segment));
      if (segment != kPosPrinterScopeLocalKey) {
        await prefs.remove(_keyFor(kPosPrinterScopeLocalKey));
      }
      state = const AsyncData(null);
    } catch (_) {
      state = const AsyncData(null);
    }
  }

  /// Settles the in-flight build so a save never races the initial load.
  Future<void> _settle() async {
    try {
      await future;
    } catch (_) {
      // A failed load must not block an explicit save.
    }
  }

  PosNetworkPrinterConfig? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PosNetworkPrinterConfig.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes and RE-READS the key; returns true only when the value is durably
  /// present. Used for both adoption and save so neither reports success on a
  /// storage backend that silently dropped the write.
  Future<bool> _writeVerified(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    try {
      await prefs.setString(key, value);
      return prefs.getString(key) == value;
    } catch (_) {
      return false;
    }
  }
}
