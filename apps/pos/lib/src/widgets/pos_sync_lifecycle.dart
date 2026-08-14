import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kitchen_mode_readiness.dart';
import '../data/operational_snapshot_store.dart';
import '../spool/pos_kitchen_spool_composition.dart';
import '../state/order_sync_controller.dart';
import '../state/pos_menu_provider.dart';
import '../state/pos_offline_state.dart';
import '../state/pos_orders_realtime_bridge.dart';
import '../state/ready_notifications_controller.dart';

/// POS-OPERATIONS-SYNC-001 — the app-lifecycle seam for authoritative sync.
///
/// Deliberately DUMB. It knows two facts — "the POS surface came up" and "the app
/// came back to the foreground" — and forwards both to the coordinator. It holds no
/// timers, no cursors, no merge rules and no state of its own.
///
/// The business logic lives in [PosOrderSyncController] precisely so it is testable
/// without pumping a widget tree, and so a second lifecycle callback can never
/// become a second, competing sync implementation.
///
/// POS-RUNTIME-RECOVERY-002 hardening:
///
///  1. Every startup/resume seam below is individually contained. These calls
///     were one unprotected sequence, so a synchronous throw while
///     materializing ANY earlier provider silently skipped the kitchen-mode
///     readiness startup — stranding the cashier on the kitchen-check spinner
///     with no watchdog and no Retry (the vc23 tablet failure).
///  2. The readiness heartbeat is kept LIVE through a manual listener instead
///     of one-shot reads. The provider watches the device context, but a lazy
///     provider with no listeners is only re-computed on the next read — so the
///     scope restored after startup never started its own verification. The
///     subscription makes every pairing/scope change rebuild the heartbeat
///     immediately, and the rebuilt composition starts itself (PR #197).
///
/// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] — THE RECONNECT PROBE.
///
/// The offline phase used to be a ONE-WAY LATCH. `posOfflineModeProvider` is a
/// root notifier whose build watches nothing, and its only `online` writer is
/// the `pos_menu` success path — but `posMenuProvider` is a non-autoDispose
/// FutureProvider whose offline branch RETURNS a value (the cached snapshot)
/// instead of throwing, so it settles into `AsyncData` and Riverpod never
/// retries it. The single remaining re-fetch trigger was the resume
/// invalidation below, and an Android Activity `resumed` is NOT emitted by a
/// foreground Wi-Fi toggle (there is deliberately no connectivity plugin in
/// this app). A cashier who lost the venue Wi-Fi for a minute therefore stayed
/// "offline" — banner latched, payment/discount/void/shift-close refused,
/// outbox backoff never reset — until the app was restarted.
///
/// So this widget (the app's ONE lifecycle owner, which already owns the
/// resume-time menu invalidation) now also arms a bounded PROBE while the
/// phase is `offlineCached` and the app is foregrounded. The probe is a
/// TRIGGER, never a writer: it re-invalidates the menu provider and the
/// FETCH'S OWN OUTCOME does all phase writing, exactly as before. Nothing here
/// consults a connectivity API — a completed RPC is the only evidence the POS
/// accepts, because a connectivity flag lies in both directions (captive
/// portals, LAN-without-internet). One invalidation per interval at most, an
/// in-flight check so probes cannot stack, and the timer is cancelled the
/// instant the phase leaves `offlineCached`, the app leaves the foreground, or
/// this widget is disposed.
class PosSyncLifecycle extends ConsumerStatefulWidget {
  const PosSyncLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PosSyncLifecycle> createState() => _PosSyncLifecycleState();
}

class _PosSyncLifecycleState extends ConsumerState<PosSyncLifecycle>
    with WidgetsBindingObserver {
  ProviderSubscription<Object?>? _heartbeatSubscription;

  /// [POS-OFFLINE-OPERATIONS-002] keeps the durable operational snapshot's
  /// kitchen-mode capture fresh whenever a VERIFIED mode resolves.
  ProviderSubscription<Object?>? _kitchenModeSnapshotSubscription;

  /// [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] Watches the offline
  /// PHASE so the reconnect probe can be armed/cancelled on every transition,
  /// and so the recovered edge (`offlineCached -> online`) can fan out.
  ProviderSubscription<Object?>? _offlinePhaseSubscription;

  /// (Pass A) The ONE reconnect probe timer. Never more than one exists: every
  /// arm path goes through [_armReconnectProbe], which returns immediately if
  /// a timer is already live.
  Timer? _reconnectProbe;

  /// POS-OPEN-ORDERS-REALTIME-GATE-013: keeps the branch-hint bridge
  /// materialized and starts it (foreground-gated) whenever the scope-keyed
  /// provider rebuilds it.
  ProviderSubscription<PosOrdersRealtimeBridge?>? _realtimeBridgeSubscription;

  /// (Pass A) Whether the app is currently foregrounded. The probe is armed
  /// ONLY while this is true — a periodic RPC from a backgrounded till is the
  /// same waste the ready poller and the readiness heartbeat already refuse.
  /// Starts true: `didChangeAppLifecycleState` is not called for the state the
  /// app is already in when this widget mounts.
  bool _foreground = true;

  /// Runs one startup/resume seam, containing any synchronous failure so a
  /// broken seam can never cancel the seams after it. The readiness controller
  /// owns its own bounded exit (watchdog), so containment is safe: the worst a
  /// swallowed failure can produce is the RETRYABLE unavailable state, never a
  /// silent permanent spinner.
  void _guarded(void Function() step) {
    try {
      step();
    } catch (_) {
      // Contained by design — see the class doc. The failing subsystem keeps
      // its own typed error surfaces; this seam only refuses to let one
      // subsystem's failure take its siblings down.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // POS-RUNTIME-RECOVERY-002 (2): materialize the readiness heartbeat EAGERLY
    // and keep it live. The listener body is empty on purpose — the rebuilt
    // provider's own composition binds the new scope and starts itself; this
    // subscription exists so invalidation (a device-context/pairing change)
    // recomputes it IMMEDIATELY instead of at the next lifecycle read.
    _guarded(() {
      _heartbeatSubscription = ref.listenManual<Object?>(
        posKitchenReadinessHeartbeatProvider,
        (_, _) {},
        onError: (_, _) {
          // A failed composition must never take the surface down — and must
          // never leave the gate an unbounded spinner: arm the last-resort
          // watchdog so the episode ends in the retryable Unavailable state.
          _guarded(
            () => ref
                .read(posKitchenModeReadinessProvider.notifier)
                .ensureBoundedVerification(),
          );
        },
      );
    });
    // [POS-OFFLINE-OPERATIONS-002] Whenever the VERIFIED kitchen mode resolves
    // (cache seed, heartbeat, retry), refresh the durable operational
    // snapshot's kitchenMode capture via the writer's read-modify-swap. The
    // writer contains its own failures and no-ops without a snapshot/scope,
    // so this listener can never take a sibling seam down — and it is
    // individually _guarded like every other seam here anyway.
    _guarded(() {
      _kitchenModeSnapshotSubscription = ref.listenManual(
        posVerifiedKitchenModeProvider,
        (_, mode) {
          if (mode == null) return;
          _guarded(
            () => unawaited(
              ref.read(operationalSnapshotWriterProvider).refreshKitchenMode(),
            ),
          );
        },
      );
    });
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] The offline-phase
    // subscription: arms/cancels the reconnect probe and fans out the recovered
    // edge. `fireImmediately` matters — a COLD OFFLINE BOOT (the app starts
    // with no network and the menu is served from the snapshot before this
    // listener is registered) produces no later transition to react to, so
    // without it the till would come up latched exactly as before.
    _guarded(() {
      _offlinePhaseSubscription = ref.listenManual<PosOfflinePhase>(
        posOfflineModeProvider.select((s) => s.phase),
        (previous, next) {
          if (next == PosOfflinePhase.offlineCached) {
            _armReconnectProbe();
          } else {
            _cancelReconnectProbe();
          }
          // THE RECOVERED EDGE. Reached only through a real successful
          // `pos_menu` fetch (the phase has no other `online` writer), so this
          // is the app's one honest "the backend answered again" moment.
          if (previous == PosOfflinePhase.offlineCached &&
              next == PosOfflinePhase.online) {
            _onReconnected();
          }
        },
        fireImmediately: true,
      );
    });
    // POS-OPEN-ORDERS-REALTIME-GATE-013: materialize the branch-hint bridge
    // and START it whenever it (re)builds while the app is foregrounded. The
    // provider itself owns creation/disposal (scope change / re-pair / logout
    // rebuild it, disposing the old channel via ref.onDispose); this listener
    // only adds the foreground-gated start. In demo, tests, and degraded
    // boots the factory is Disabled, so start() opens no socket.
    _guarded(() {
      _realtimeBridgeSubscription = ref.listenManual(
        posOrdersRealtimeBridgeProvider,
        (previous, bridge) {
          if (bridge != null && _foreground) {
            _guarded(() => unawaited(bridge.start()));
          }
        },
        fireImmediately: true,
      );
    });
    // STARTUP. Deferred a frame so the device/PIN context providers have settled;
    // the coordinator itself no-ops when there is no scope yet, so an early call is
    // harmless rather than an error banner at boot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _guarded(
        () => ref.read(posOrderSyncControllerProvider.notifier).syncNow(),
      );
      // PSC-001A: the ready-notification poller starts with the surface too —
      // same deferred frame, same no-scope no-op safety.
      _guarded(
        () => ref
            .read(posReadyNotificationsControllerProvider.notifier)
            .onResume(),
      );
      // KITCHEN-MODE-001C2B (LOCKED D4): the kitchen-spool reconciliation
      // hook — startup/resume only, never a timer. Inert on web/demo (the
      // provider is null) and a typed no-op without device scope; production
      // dispatch importing stays impossible until 001C3. Explicitly
      // fire-and-forget: the runtime converts EVERY failure into a typed
      // redacted report, so no unhandled async error can escape this hook.
      _guarded(
        () => unawaited(ref.read(posKitchenSpoolRuntimeProvider)?.onStartup()),
      );
      // KITCHEN-MODE-001C3A: the READINESS-ONLY heartbeat (the one sanctioned
      // spool-layer timer — it files kitchen readiness reports and can never
      // reach the worker/drain/transport). Null on web/demo/unpaired.
      _guarded(
        () => ref.read(posKitchenReadinessHeartbeatProvider)?.onStartup(),
      );
      _guarded(_seedKitchenModeReadiness);
      // POS-RUNTIME-RECOVERY-002 (R1): the FINAL startup step, individually
      // guarded like the rest — whatever failed above, a still-unowned Loading
      // now gets its bounded exit instead of becoming a terminal spinner.
      _guarded(
        () => ref
            .read(posKitchenModeReadinessProvider.notifier)
            .ensureBoundedVerification(),
      );
    });
  }

  /// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): resolve the kitchen-mode
  /// readiness so a submit is never guessed as KDS before verification. On
  /// web/demo/unpaired the printer_only machinery does not exist (heartbeat null),
  /// so the workflow is the NORMAL kds — resolve it immediately (Send never
  /// blocks; byte-identical to the pre-feature behavior). On a real paired NATIVE
  /// device the readiness stays Loading (Send blocked) until the secure cache seed
  /// or the heartbeat publishes the VERIFIED mode.
  void _seedKitchenModeReadiness() {
    // Finding 1: when there is no printer_only machinery (web / unpaired /
    // no-secure-spool — heartbeat null) there is no scope to verify, so resolve
    // the normal KDS workflow through the scope-safe unscoped path. A native
    // paired device (heartbeat non-null) is left to its scope-bound heartbeat +
    // cache seed; demo is already resolved by the controller's build().
    if (ref.read(posKitchenReadinessHeartbeatProvider) == null) {
      ref.read(posKitchenModeReadinessProvider.notifier).resolveUnscopedKds();
    }
  }

  // ---------------------------------------------------------------------
  // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] The reconnect probe.
  // ---------------------------------------------------------------------

  /// Arms the probe if — and only if — it should be running: the app is
  /// foregrounded, the phase is `offlineCached`, no timer is live already, and
  /// a cadence is configured. The cadence is NULL by default (tests stay
  /// timer-free by construction); `main.dart` overrides it for the real app.
  void _armReconnectProbe() {
    if (!mounted || !_foreground) return;
    if (_reconnectProbe != null) return;
    _guarded(() {
      if (ref.read(posOfflineModeProvider).phase !=
          PosOfflinePhase.offlineCached) {
        return;
      }
      final interval = ref.read(posOfflineReconnectProbeIntervalProvider);
      if (interval == null) return;
      _reconnectProbe = Timer.periodic(interval, (_) => _probeReconnect());
    });
  }

  void _cancelReconnectProbe() {
    _reconnectProbe?.cancel();
    _reconnectProbe = null;
  }

  /// ONE probe tick: ask the menu provider to try the server again.
  ///
  /// Writes NO phase. It marks the presentational "reconnecting" transient and
  /// invalidates `posMenuProvider`; the re-run fetch records `online` on a real
  /// success and re-records `offlineCached` on a real failure, exactly as it
  /// does for a startup/resume fetch. The explicit read after the invalidation
  /// materializes the rebuilt provider even when no surface is listening,
  /// because an invalidated provider with no listeners is otherwise recomputed
  /// lazily — i.e. never, which is the latch we are here to break.
  void _probeReconnect() {
    if (!mounted) return;
    _guarded(() {
      if (ref.read(posOfflineModeProvider).phase !=
          PosOfflinePhase.offlineCached) {
        // The phase moved between ticks (the listener normally cancels first;
        // this is the belt-and-braces path).
        _cancelReconnectProbe();
        return;
      }
      // NEVER STACK PROBES. A slow/hanging fetch must not accumulate one more
      // in-flight RPC per interval.
      if (ref.read(posMenuProvider).isLoading) return;
      ref.read(posOfflineModeProvider.notifier).markProbing();
      ref.invalidate(posMenuProvider);
      ref.read(posMenuProvider);
    });
  }

  /// The recovered edge (`offlineCached -> online`): the subsystems that went
  /// quiet during the outage are woken ONCE, each individually contained.
  ///
  /// The OUTBOX is deliberately absent: it owns its own listener on this same
  /// phase transition (`outbox_controller.dart`), which resets the retry
  /// backoff and sweeps. Duplicating it here would double the push.
  void _onReconnected() {
    // The authoritative pull: single-flight, so a concurrent caller joins.
    _guarded(() => ref.read(posOrderSyncControllerProvider.notifier).syncNow());
    // KITCHEN MODE: the offline trust window (2h) may be running down on a
    // snapshot-reconstructed mode. One immediate readiness report re-verifies
    // it server-side; the verified result flows through
    // posVerifiedKitchenModeProvider into the snapshot listener above, which
    // refreshes the stored capture.
    //
    // `onResume` is the SANCTIONED on-demand entry on this seam — the web-safe
    // [PosKitchenReadinessLifecycle] surface exposes exactly three hooks, and
    // this is the one that means "re-arm the heartbeat and report NOW"
    // (`_armTimer()` + `requestImmediate('resume')` inside the coordinator).
    // Re-arming is idempotent and the report is single-flight, so a reconnect
    // that races a real resume produces one run, not two.
    _guarded(() => ref.read(posKitchenReadinessHeartbeatProvider)?.onResume());
  }

  @override
  void dispose() {
    _heartbeatSubscription?.close();
    _kitchenModeSnapshotSubscription?.close();
    _offlinePhaseSubscription?.close();
    _realtimeBridgeSubscription?.close();
    _cancelReconnectProbe();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `mounted` guards the window where the observer is still registered but the
    // element is gone — Riverpod throws on a ref read after dispose.
    if (!mounted) return;
    // PSC-001A: the ready poller PAUSES whenever the app/page leaves the
    // foreground (hidden browser tab, backgrounded app) — a ~7s tick against
    // an invisible surface is pure waste — and resumes with an immediate poll.
    if (state != AppLifecycleState.resumed) {
      _guarded(
        () => ref
            .read(posReadyNotificationsControllerProvider.notifier)
            .onPaused(),
      );
      // KITCHEN-MODE-001C3A: the readiness heartbeat pauses with the surface
      // too — a report against a backgrounded app is waste; the server row
      // simply expires (read-side, ~10 minutes).
      _guarded(
        () => ref.read(posKitchenReadinessHeartbeatProvider)?.onPaused(),
      );
      // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] The reconnect probe
      // pauses with everything else: a background till re-attempting `pos_menu`
      // every 25s is exactly the polling storm this design refuses. Resume
      // re-arms it below when the phase is still offlineCached.
      _foreground = false;
      _cancelReconnectProbe();
      // POS-OPEN-ORDERS-REALTIME-GATE-013: the realtime socket pauses with
      // the surface — stop() closes the channel; the resume path below opens
      // a FRESH authorized subscription (the bridge builds a new source per
      // start, a disposed channel is never resurrected).
      _guarded(() => ref.read(posOrdersRealtimeBridgeProvider)?.stop());
      return;
    }
    _foreground = true;
    // POS-OPEN-ORDERS-REALTIME-GATE-013: a fresh authorized subscription on
    // resume (start() is idempotent, so a platform double-resume is safe).
    _guarded(() {
      final bridge = ref.read(posOrdersRealtimeBridgeProvider);
      if (bridge != null) unawaited(bridge.start());
    });
    // RESUME. The coordinator collapses concurrent callers onto the ONE in-flight
    // sync, so a platform that fires `resumed` more than once cannot start three
    // racing pulls whose losers overwrite the winner.
    _guarded(
      () => ref.read(posOrderSyncControllerProvider.notifier).onResume(),
    );
    _guarded(
      () =>
          ref.read(posReadyNotificationsControllerProvider.notifier).onResume(),
    );
    // KITCHEN-MODE-001C2B (D4): resume-time spool reconciliation (see the
    // startup hook above; same inert/no-op + typed-failure guarantees).
    _guarded(
      () => unawaited(ref.read(posKitchenSpoolRuntimeProvider)?.onResume()),
    );
    // KITCHEN-MODE-001C3A: re-arm the readiness heartbeat + report now.
    _guarded(() => ref.read(posKitchenReadinessHeartbeatProvider)?.onResume());
    // Re-resolve the kitchen-mode readiness on resume (web/demo re-confirm kds
    // idempotently; a native device re-verifies through the heartbeat above).
    _guarded(_seedKitchenModeReadiness);
    // PILOT-OPERATIONS-CORRECTIONS-001: also refresh the MENU (and therefore
    // availability) on resume — a Dashboard availability change made while the POS
    // was backgrounded would otherwise stay invisible until the session changed.
    // posMenuProvider is scope-derived (it watches the PIN/device session), so the
    // re-fetch always targets the CURRENT scope and a stale old-scope result can
    // never apply. One bounded invalidation per resume (no polling loop).
    // [POS-OFFLINE-OPERATIONS-002] This stays ONE invalidation per resume and
    // is now SAFE offline: the menu provider's fetch-failure path serves the
    // durable operational snapshot for the current scope, so a wake with no
    // network lands on the cached menu + offline banner instead of the error
    // screen — the fetch outcome itself is what drives the offline phase.
    _guarded(() => ref.invalidate(posMenuProvider));
    // [POS-OFFLINE-RECONNECT-PAYMENT-PREBILL-001 Pass A] THE RESUME RACE. The
    // single invalidation above is fired the instant Android reports `resumed`,
    // which on a tablet waking onto venue Wi-Fi typically LOSES the race
    // against association + DHCP (2–10s). Before this ticket that one attempt
    // was all there was: it failed, re-latched `offlineCached`, and nothing
    // ever tried again. Re-arm the probe here so a resume that is still
    // offline keeps retrying on its own cadence. (The phase listener arms it
    // too; both paths funnel through the same single-timer guard.)
    _armReconnectProbe();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
