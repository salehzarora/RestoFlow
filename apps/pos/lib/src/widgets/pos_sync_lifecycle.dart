import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kitchen_mode_readiness.dart';
import '../data/operational_snapshot_store.dart';
import '../spool/pos_kitchen_spool_composition.dart';
import '../state/order_sync_controller.dart';
import '../state/pos_menu_provider.dart';
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

  @override
  void dispose() {
    _heartbeatSubscription?.close();
    _kitchenModeSnapshotSubscription?.close();
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
      return;
    }
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
