import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';

/// POS-CASH-DRAWER-AUTO-OPEN — the per-DEVICE "open the cash drawer after a
/// cash payment" toggle.
///
/// Deliberately DEFAULT OFF: existing devices behave exactly as before until a
/// human explicitly enables the drawer on THAT till. The toggle is a local
/// device preference (which till has a drawer plugged into its receipt
/// printer is physical, per-station knowledge), so it persists in
/// `shared_preferences` under the SAME authoritative per-device namespace the
/// printer transport choice uses (`posPrinterScopeSegmentProvider`) — never a
/// tenant-wide or synced setting.
///
/// Shape mirrors [PosSelectedPrinterTransportController]
/// (pos_printer_transport.dart) field for field: prefix constant, AsyncNotifier
/// whose build awaits the resolved printer scope segment, best-effort persisted
/// setter. There is NO legacy-key adoption here — the setting is new, and
/// "unset" must read as OFF everywhere.
const String kPosCashDrawerAutoOpenKeyPrefix =
    'restoflow.printer.cash_drawer_auto_open.pos.';

/// Whether THIS device should pulse the cash drawer after a successful CASH
/// payment (default FALSE — see the note above).
final posCashDrawerAutoOpenProvider =
    AsyncNotifierProvider<PosCashDrawerAutoOpenController, bool>(
      PosCashDrawerAutoOpenController.new,
    );

class PosCashDrawerAutoOpenController extends AsyncNotifier<bool> {
  String _keyFor(String segment) => '$kPosCashDrawerAutoOpenKeyPrefix$segment';

  @override
  Future<bool> build() async {
    // PRINT-STARTUP-REPRINT-001 rule: resolve the authoritative namespace
    // first, so a cold start on a paired device never reads (or latches) a
    // value from the wrong scope.
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Absent or unreadable reads as FALSE: the drawer is a hardware cash
      // control, so any doubt fails to "do not open".
      return prefs.getBool(_keyFor(segment)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the toggle into the authoritative namespace.
  Future<void> setEnabled(bool enabled) async {
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    try {
      await future;
    } catch (_) {
      // A failed load must not block an explicit selection.
    }
    state = AsyncData(enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFor(segment), enabled);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}
