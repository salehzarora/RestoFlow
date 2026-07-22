import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';

/// Per-DEVICE auto-print preference (device settings sprint, Part C): should
/// THIS POS station prepare a customer-receipt print job automatically after
/// a successful payment?
///
/// Stored locally per browser/device via `shared_preferences` (same
/// mechanism as the language choice), keyed by the paired device id so two
/// stations sharing a machine never share the setting. Stores a plain bool —
/// never tokens/secrets. `null` = the cashier never chose; the EFFECTIVE
/// default is then ON iff an enabled receipt printer is assigned (see
/// [posAutoPrintReceiptEnabled] in the sheet/trigger call sites).
const String kPosAutoPrintReceiptKeyPrefix =
    'restoflow.autoprint.pos.receiptOnPaid.';

final posAutoPrintReceiptProvider =
    AsyncNotifierProvider<PosAutoPrintReceiptController, bool?>(
      PosAutoPrintReceiptController.new,
    );

class PosAutoPrintReceiptController extends AsyncNotifier<bool?> {
  String? get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    return deviceId == null || deviceId.isEmpty
        ? null
        : '$kPosAutoPrintReceiptKeyPrefix$deviceId';
  }

  @override
  Future<bool?> build() async {
    // Re-read when the pairing gate (re)publishes the device.
    ref.watch(posDeviceContextProvider);
    final key = _key;
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key);
    } catch (_) {
      return null; // Unreadable prefs degrade to the default, never crash.
    }
  }

  /// Persists the cashier's choice (state first, storage best-effort).
  Future<void> setEnabled(bool value) async {
    final key = _key;
    if (key == null) return;
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}

/// The EFFECTIVE auto-print decision: a printer must exist and be enabled
/// (no printer = OFF and not toggleable), and the stored choice wins over
/// the configured-printer default of ON.
bool posAutoPrintReceiptEnabled({
  required bool? stored,
  required bool hasEnabledPrinter,
}) => hasEnabledPrinter && (stored ?? true);

/// KITCHEN-PRINT-DUAL-001: per-DEVICE "automatically print a KITCHEN ticket
/// after a successful order creation?" — the independent twin of
/// [posAutoPrintReceiptProvider]. Same local `shared_preferences` mechanism,
/// keyed by the paired device id, stores a plain bool. Unlike the receipt
/// default (ON), this DEFAULTS OFF: normal POS behaviour is unchanged until a
/// cashier deliberately enables it.
const String kPosAutoPrintKitchenTicketKeyPrefix =
    'restoflow.autoprint.pos.kitchenTicket.';

final posAutoPrintKitchenTicketProvider =
    AsyncNotifierProvider<PosAutoPrintKitchenTicketController, bool?>(
      PosAutoPrintKitchenTicketController.new,
    );

class PosAutoPrintKitchenTicketController extends AsyncNotifier<bool?> {
  String? get _key {
    final deviceId = ref.read(posDeviceContextProvider)?.deviceId;
    return deviceId == null || deviceId.isEmpty
        ? null
        : '$kPosAutoPrintKitchenTicketKeyPrefix$deviceId';
  }

  @override
  Future<bool?> build() async {
    ref.watch(posDeviceContextProvider);
    final key = _key;
    if (key == null) return null;
    // KITCHEN-PRINT-DUAL-001C: a genuine prefs READ FAILURE must SURFACE as
    // AsyncError, NOT silently degrade to null (OFF). CartPanel gates Send on this
    // setting being RESOLVED, so a swallowed read error would let a cold-start
    // order submit into the normal KDS workflow when the operator may expect a
    // direct kitchen print. A MISSING key is NOT an error — getBool returns null
    // (the cashier never chose), which resolves to the OFF default downstream.
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  /// Persists the cashier's choice (state first, storage best-effort). Setting the
  /// state to AsyncData FIRST also clears any prior read-error state — so toggling
  /// the option through Device Settings is the operator's escape hatch if a read
  /// ever failed and blocked Send.
  Future<void> setEnabled(bool value) async {
    final key = _key;
    if (key == null) return;
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}

/// The EFFECTIVE auto-kitchen-print decision: a KITCHEN printer must be
/// configured (no printer = OFF and not toggleable), and the DEFAULT is OFF
/// (the cashier must opt in) — `stored ?? false`, never `?? true`.
bool posAutoPrintKitchenTicketEnabled({
  required bool? stored,
  required bool hasKitchenPrinter,
}) => hasKitchenPrinter && (stored ?? false);
