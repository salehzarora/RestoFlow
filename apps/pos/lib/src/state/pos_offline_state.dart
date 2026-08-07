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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Which world the POS is currently operating in. See the library doc for the
/// exact meaning of each phase.
enum PosOfflinePhase { online, offlineCached, setupRequired }

/// The offline phase plus what the offline banner needs to say about it.
class PosOfflineState {
  const PosOfflineState({
    required this.phase,
    this.snapshotFetchedAt,
    this.menuFromCache = false,
    this.probing = false,
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

  /// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] True while a reconnect
  /// PROBE is in flight — a real `pos_menu` attempt started by the lifecycle's
  /// probe timer whose outcome has not landed yet. Purely presentational: the
  /// offline banner says "Reconnecting…" instead of the snapshot age.
  ///
  /// DELIBERATELY A BOOLEAN, NOT A FOURTH [PosOfflinePhase]. Every gate and
  /// every UI consumer tests `phase == PosOfflinePhase.offlineCached`
  /// (see [blockPosActionWhileOffline]); a new enum member would silently
  /// UN-GATE payment/discount/void/shift-close for the duration of every
  /// probe. The flag leaves all of those byte-identical.
  final bool probing;
}

/// The ONE writer of [PosOfflineState]. The menu fetch path calls exactly one
/// of the three records per completed attempt — via `Future.microtask`, after
/// its async work completes and guarded against scope changes, so no provider
/// is ever written during another provider's build (the vc23 root-cause class,
/// POS-RUNTIME-RECOVERY-002).
///
/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] [markProbing] is the ONE
/// exception, and it is not a phase writer: it flips a presentational flag and
/// can never move the phase in either direction. The three `record*` methods
/// remain the only writers of [PosOfflineState.phase], and each of them clears
/// `probing` by construction (the probe's own outcome ends its transient).
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

  /// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] A reconnect probe just
  /// started a real `pos_menu` attempt. PRESENTATIONAL ONLY — the phase, the
  /// snapshot age and the cache flag are carried through untouched, so every
  /// action gate keeps refusing exactly as it did a microsecond earlier. A
  /// no-op outside [PosOfflinePhase.offlineCached] (nothing else probes) and
  /// when already probing (no redundant rebuilds).
  void markProbing() {
    final current = state;
    if (current.phase != PosOfflinePhase.offlineCached) return;
    if (current.probing) return;
    state = PosOfflineState(
      phase: current.phase,
      snapshotFetchedAt: current.snapshotFetchedAt,
      menuFromCache: current.menuFromCache,
      probing: true,
    );
  }
}

/// The POS offline operating phase (root state — no autoDispose).
final posOfflineModeProvider =
    NotifierProvider<PosOfflineController, PosOfflineState>(
      PosOfflineController.new,
    );

/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] How often the POS
/// lifecycle RE-ATTEMPTS a real `pos_menu` fetch while it is operating from
/// the offline snapshot — the seam that ends the one-way offline latch.
///
/// NULL BY DEFAULT, exactly like `outboxAutoSweepIntervalProvider` and
/// `posSyncPollIntervalProvider`: `main.dart` overrides it for the real app
/// under the `includePeriodicWork` seam, and every widget test therefore stays
/// timer-free (a live periodic Timer makes `pumpAndSettle` wait forever).
///
/// This is a TRIGGER, never a writer. The probe only asks the menu provider to
/// try again; the offline PHASE is still decided exclusively by that fetch's
/// real outcome — never by a connectivity plugin, a reachability flag, or the
/// timer itself.
final posOfflineReconnectProbeIntervalProvider = Provider<Duration?>(
  (ref) => null,
);

/// The production reconnect-probe cadence (see
/// [posOfflineReconnectProbeIntervalProvider]). Matched to the outbox sweep so
/// a recovering till performs at most one extra RPC per 25s window.
const Duration kPosOfflineReconnectProbeInterval = Duration(seconds: 25);

/// [POS-OFFLINE-OPERATIONS-002] C11 — the ONE gate for server-backed actions
/// while the POS operates from the offline snapshot.
///
/// Payment, discount, void/cancel and shift close are server-authorized,
/// server-audited mutations (D-011); opening their sheets offline hands the
/// cashier a Confirm that can only fail. Each entry point calls this FIRST:
/// when the phase is [PosOfflinePhase.offlineCached] it shows the one honest
/// localized snackbar and answers true (the caller returns without opening
/// anything); every other phase answers false and changes nothing. It gates
/// ONLY at the UI entry — no payment/void/shift logic is touched — and demo
/// mode never reaches it (the demo menu cannot fail, so the phase stays
/// online).
bool blockPosActionWhileOffline(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(posOfflineModeProvider).phase !=
      PosOfflinePhase.offlineCached) {
    return false;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).posOfflineActionUnavailable),
    ),
  );
  return true;
}
