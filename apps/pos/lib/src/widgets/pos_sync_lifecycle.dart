import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/order_sync_controller.dart';
import '../state/pos_menu_provider.dart';

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
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // `mounted` guards the window where the observer is still registered but the
    // element is gone — Riverpod throws on a ref read after dispose.
    if (!mounted) return;
    // RESUME. The coordinator collapses concurrent callers onto the ONE in-flight
    // sync, so a platform that fires `resumed` more than once cannot start three
    // racing pulls whose losers overwrite the winner.
    ref.read(posOrderSyncControllerProvider.notifier).onResume();
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
