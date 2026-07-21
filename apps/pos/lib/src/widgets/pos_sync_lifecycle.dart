import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class PosSyncLifecycle extends ConsumerStatefulWidget {
  const PosSyncLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PosSyncLifecycle> createState() => _PosSyncLifecycleState();
}

class _PosSyncLifecycleState extends ConsumerState<PosSyncLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // STARTUP. Deferred a frame so the device/PIN context providers have settled;
    // the coordinator itself no-ops when there is no scope yet, so an early call is
    // harmless rather than an error banner at boot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(posOrderSyncControllerProvider.notifier).syncNow();
      // PSC-001A: the ready-notification poller starts with the surface too —
      // same deferred frame, same no-scope no-op safety.
      ref.read(posReadyNotificationsControllerProvider.notifier).onResume();
      // KITCHEN-MODE-001C2B (LOCKED D4): the kitchen-spool reconciliation
      // hook — startup/resume only, never a timer. Inert on web/demo (the
      // provider is null) and a typed no-op without device scope; production
      // dispatch importing stays impossible until 001C3. Explicitly
      // fire-and-forget: the runtime converts EVERY failure into a typed
      // redacted report, so no unhandled async error can escape this hook.
      unawaited(ref.read(posKitchenSpoolRuntimeProvider)?.onStartup());
      // KITCHEN-MODE-001C3A: the READINESS-ONLY heartbeat (the one sanctioned
      // spool-layer timer — it files kitchen readiness reports and can never
      // reach the worker/drain/transport). Null on web/demo/unpaired.
      ref.read(posKitchenReadinessHeartbeatProvider)?.onStartup();
    });
  }

  @override
  void dispose() {
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
      ref.read(posReadyNotificationsControllerProvider.notifier).onPaused();
      // KITCHEN-MODE-001C3A: the readiness heartbeat pauses with the surface
      // too — a report against a backgrounded app is waste; the server row
      // simply expires (read-side, ~10 minutes).
      ref.read(posKitchenReadinessHeartbeatProvider)?.onPaused();
      return;
    }
    // RESUME. The coordinator collapses concurrent callers onto the ONE in-flight
    // sync, so a platform that fires `resumed` more than once cannot start three
    // racing pulls whose losers overwrite the winner.
    ref.read(posOrderSyncControllerProvider.notifier).onResume();
    ref.read(posReadyNotificationsControllerProvider.notifier).onResume();
    // KITCHEN-MODE-001C2B (D4): resume-time spool reconciliation (see the
    // startup hook above; same inert/no-op + typed-failure guarantees).
    unawaited(ref.read(posKitchenSpoolRuntimeProvider)?.onResume());
    // KITCHEN-MODE-001C3A: re-arm the readiness heartbeat + report now.
    ref.read(posKitchenReadinessHeartbeatProvider)?.onResume();
    // PILOT-OPERATIONS-CORRECTIONS-001: also refresh the MENU (and therefore
    // availability) on resume — a Dashboard availability change made while the POS
    // was backgrounded would otherwise stay invisible until the session changed.
    // posMenuProvider is scope-derived (it watches the PIN/device session), so the
    // re-fetch always targets the CURRENT scope and a stale old-scope result can
    // never apply. One bounded invalidation per resume (no polling loop).
    ref.invalidate(posMenuProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
