import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/pos_visual_tokens.dart';
import 'pos_device_context.dart';

/// POS-PREMIUM-VISUAL-POLISH-001 — the per-DEVICE secondary accent.
///
/// A terminal-local APPEARANCE preference (like the language choice): each POS
/// till may pick one of four curated accents. The accent colours ONLY
/// non-critical highlights — the selected-category marker, focus rings, hover
/// tints, the cart count badge. It must NEVER carry meaning:
///  * semantic states (success/warning/danger/info) keep their own colours;
///  * the primary action stays brand navy;
///  * availability/paid/void states never read from this.
///
/// Persistence mirrors [PosCashDrawerAutoOpenController] field for field:
/// prefix constant, AsyncNotifier whose build awaits the authoritative
/// per-device namespace (`posPrinterScopeSegmentProvider`), best-effort
/// persisted setter. Unset reads as the default (Mint Leaf).
const String kPosDeviceAccentKeyPrefix = 'restoflow.pos.device_accent.';

/// The curated accent choices. Wire names are persisted — never rename a
/// value without an adoption path.
enum PosDeviceAccent {
  mint('mint', kPosDefaultSecondaryAccent),
  saffron('saffron', Color(0xFFD89A2B)),
  pomegranate('pomegranate', Color(0xFFC65A4B)),
  aubergine('aubergine', Color(0xFF6E5BD3));

  const PosDeviceAccent(this.wire, this.color);

  final String wire;
  final Color color;

  /// Unknown/absent tokens fall back to the default accent — a bad stored
  /// value must never break the till's rendering.
  static PosDeviceAccent fromWire(String? wire) => PosDeviceAccent.values
      .firstWhere((a) => a.wire == wire, orElse: () => PosDeviceAccent.mint);
}

/// This device's chosen secondary accent (default [PosDeviceAccent.mint]).
final posDeviceAccentProvider =
    AsyncNotifierProvider<PosDeviceAccentController, PosDeviceAccent>(
      PosDeviceAccentController.new,
    );

/// The resolved accent COLOR — what widgets actually consume. While the
/// preference is still loading (or the device scope is unresolved) it renders
/// the default, so first paint never flashes an arbitrary colour.
final posDeviceAccentColorProvider = Provider<Color>((ref) {
  final accent = ref.watch(posDeviceAccentProvider).valueOrNull;
  return (accent ?? PosDeviceAccent.mint).color;
});

class PosDeviceAccentController extends AsyncNotifier<PosDeviceAccent> {
  String _keyFor(String segment) => '$kPosDeviceAccentKeyPrefix$segment';

  @override
  Future<PosDeviceAccent> build() async {
    // Resolve the authoritative namespace first (PRINT-STARTUP-REPRINT-001
    // rule), so a cold start on a paired device never latches the wrong
    // scope's preference.
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();
      return PosDeviceAccent.fromWire(prefs.getString(_keyFor(segment)));
    } catch (_) {
      return PosDeviceAccent.mint;
    }
  }

  /// Persists the choice into the authoritative namespace.
  Future<void> setAccent(PosDeviceAccent accent) async {
    final segment = await ref.read(posPrinterScopeSegmentProvider.future);
    try {
      await future;
    } catch (_) {
      // A failed load must not block an explicit selection.
    }
    state = AsyncData(accent);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFor(segment), accent.wire);
    } catch (_) {
      // Best-effort persistence: the in-session choice still applies.
    }
  }
}
