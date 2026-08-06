/// POS-OFFLINE-OPERATIONS-002 — the POS's OFFLINE OPERATING PHASE, as decided
/// by REAL menu-fetch outcomes.
///
/// This state is written ONLY by the menu/refresh flow's actual results —
/// never by a connectivity probe, a reachability flag, or a timer. "Online"
/// means the last menu fetch genuinely succeeded; "offline cached" means the
/// fetch genuinely failed AND the durable operational snapshot for the CURRENT
/// scope was served in its place; "setup required" means the fetch failed and
/// no usable snapshot exists, so this till has never completed its one-time
/// online bootstrap. A connectivity flag can lie in both directions (captive
/// portals, LAN-without-internet); a completed RPC cannot.
///
/// Demo mode never writes here (the demo menu is local and cannot fail), so
/// the phase stays [PosOfflinePhase.online] and no offline chrome ever shows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which world the POS is currently operating in. See the library doc for the
/// exact meaning of each phase.
enum PosOfflinePhase { online, offlineCached, setupRequired }

/// The offline phase plus what the offline banner needs to say about it.
class PosOfflineState {
  const PosOfflineState({
    required this.phase,
    this.snapshotFetchedAt,
    this.menuFromCache = false,
  });

  /// The starting state: nothing has failed, nothing is served from cache.
  static const PosOfflineState online = PosOfflineState(
    phase: PosOfflinePhase.online,
  );

  final PosOfflinePhase phase;

  /// When the snapshot currently being served was FETCHED from the server
  /// (never when it was read back) — the honest data age the offline banner
  /// shows. Null outside [PosOfflinePhase.offlineCached].
  final DateTime? snapshotFetchedAt;

  /// True when the menu the POS is selling from was reconstructed from the
  /// durable snapshot rather than parsed from a live `pos_menu` response.
  final bool menuFromCache;
}

/// The ONE writer of [PosOfflineState]. The menu fetch path calls exactly one
/// of the three records per completed attempt — via `Future.microtask`, after
/// its async work completes and guarded against scope changes, so no provider
/// is ever written during another provider's build (the vc23 root-cause class,
/// POS-RUNTIME-RECOVERY-002).
class PosOfflineController extends Notifier<PosOfflineState> {
  @override
  PosOfflineState build() => PosOfflineState.online;

  /// A real `pos_menu` fetch succeeded — the POS is online.
  void recordOnlineFetch() => state = PosOfflineState.online;

  /// The fetch failed and the durable snapshot (fetched at
  /// [snapshotFetchedAt]) was served instead.
  void recordOfflineCacheServed({required DateTime snapshotFetchedAt}) =>
      state = PosOfflineState(
        phase: PosOfflinePhase.offlineCached,
        snapshotFetchedAt: snapshotFetchedAt,
        menuFromCache: true,
      );

  /// The fetch failed and NO usable snapshot exists for the current scope.
  void recordSetupRequired() =>
      state = const PosOfflineState(phase: PosOfflinePhase.setupRequired);
}

/// The POS offline operating phase (root state — no autoDispose).
final posOfflineModeProvider =
    NotifierProvider<PosOfflineController, PosOfflineState>(
      PosOfflineController.new,
    );
