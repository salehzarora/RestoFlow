import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kds_device_context.dart';

/// Per-DEVICE auto-print preference (device settings sprint, Part C): should
/// THIS kitchen display prepare a kitchen-ticket print job automatically
/// when a ticket is ACKNOWLEDGED?
///
/// Stored locally per browser/device via `shared_preferences` (same
/// mechanism as the language choice), keyed by the paired device id. Stores
/// a plain bool — never tokens/secrets, never money (T-003). `null` = the
/// staff never chose; the EFFECTIVE default is then ON iff an enabled
/// kitchen printer is assigned (see [kdsAutoPrintAcknowledgeEnabled]).
/// A print-on-first-seen trigger is deliberately NOT offered: it could storm
/// the printer on every board reload, so acknowledge is the only trigger.
const String kKdsAutoPrintAcknowledgeKeyPrefix =
    'restoflow.autoprint.kds.onAcknowledge.';

final kdsAutoPrintAcknowledgeProvider =
    AsyncNotifierProvider<KdsAutoPrintAcknowledgeController, bool?>(
      KdsAutoPrintAcknowledgeController.new,
    );

class KdsAutoPrintAcknowledgeController extends AsyncNotifier<bool?> {
  String? get _key {
    final deviceId = ref.read(kdsDeviceContextProvider)?.deviceId;
    return deviceId == null || deviceId.isEmpty
        ? null
        : '$kKdsAutoPrintAcknowledgeKeyPrefix$deviceId';
  }

  @override
  Future<bool?> build() async {
    // Re-read when the pairing gate (re)publishes the device.
    ref.watch(kdsDeviceContextProvider);
    final key = _key;
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key);
    } catch (_) {
      return null; // Unreadable prefs degrade to the default, never crash.
    }
  }

  /// Persists the staff choice (state first, storage best-effort).
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

/// The EFFECTIVE auto-print decision: an enabled kitchen printer must exist
/// (no printer = OFF and not toggleable), and the stored choice wins over
/// the configured-printer default of ON.
bool kdsAutoPrintAcknowledgeEnabled({
  required bool? stored,
  required bool hasEnabledPrinter,
}) => hasEnabledPrinter && (stored ?? true);
