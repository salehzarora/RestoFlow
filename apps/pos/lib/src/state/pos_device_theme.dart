import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/pos_visual_tokens.dart';
import 'pos_device_context.dart';

/// POS-THEME-NAVBAR-POLISH-001 — the per-DEVICE theme (primary + action pair).
///
/// A terminal-local APPEARANCE preference (like the language choice and the
/// secondary accent): each POS till picks one of the curated
/// [PosThemePair.presets]. The pair recolors the STRUCTURAL primary (navbar,
/// order-type thumb, Add buttons, phone bottom bar, theme primary roles) and
/// the ACTION family (Send CTA, prices, ×N marks, stepper plus, count
/// chips). It must NEVER carry meaning:
///  * semantic states (success/warning/danger/info) keep their own colours;
///  * availability/paid/void states never read from this;
///  * the separate per-device SECONDARY accent (focus rings, active-pill
///    tint) remains its own supporting choice.
///
/// Persistence mirrors [PosDeviceAccentController] field for field: prefix
/// constant, AsyncNotifier whose build awaits the authoritative per-device
/// namespace (`posPrinterScopeSegmentProvider`), best-effort persisted
/// setter. Unset reads as the default (Navy + Ember).
const String kPosDeviceThemeKeyPrefix = 'restoflow.pos.device_theme.';

/// This device's chosen theme pair (default [PosThemePair.navyEmber]).
final posDeviceThemeProvider =
    AsyncNotifierProvider<PosDeviceThemeController, PosThemePair>(
      PosDeviceThemeController.new,
    );

/// The resolved PAIR — what the app theme actually consumes. While the
/// preference is still loading (or the device scope is unresolved) it renders
/// the default, so first paint never flashes an arbitrary identity.
final posDeviceThemePairProvider = Provider<PosThemePair>((ref) {
  return ref.watch(posDeviceThemeProvider).valueOrNull ??
      PosThemePair.navyEmber;
});

class PosDeviceThemeController extends AsyncNotifier<PosThemePair> {
  String _keyFor(String segment) => '$kPosDeviceThemeKeyPrefix$segment';

  @override
  Future<PosThemePair> build() async {
    // Resolve the authoritative namespace first (PRINT-STARTUP-REPRINT-001
    // rule), so a cold start on a paired device never latches the wrong
    // scope's preference.
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();
      return PosThemePair.fromWire(prefs.getString(_keyFor(segment)));
    } catch (_) {
      return PosThemePair.navyEmber;
    }
  }

  /// Persists the choice into the authoritative namespace.
  Future<void> setTheme(PosThemePair pair) async {
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    try {
      await future;
    } catch (_) {
      // A failed load must not block an explicit selection.
    }
    state = AsyncData(pair);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFor(segment), pair.wire);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}
