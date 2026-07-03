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
