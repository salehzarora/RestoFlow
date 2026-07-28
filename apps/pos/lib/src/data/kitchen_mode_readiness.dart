import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_dispatch.dart' show resolveOrderDispatchMode;
import 'order_submission.dart' show OrderDispatchMode;
// runtimeConfigProvider + KitchenModeVerifiedKds come from restoflow_feature_auth.

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) — the typed readiness of the
/// VERIFIED kitchen workflow mode for the CURRENT scope. An order may only be
/// submitted once this is [KitchenModeReadinessResolved]; until then the POS must
/// NOT guess a KDS dispatch (which, on a real printer_only branch with no KDS,
/// would leave the order stuck at `submitted` with no way to complete or free its
/// table). Web-safe (no drift/sqlite): the offline secure-cache seed + the network
/// verification both feed this from the native spool composition.
sealed class PosKitchenModeReadiness {
  const PosKitchenModeReadiness();
}

/// The mode has not been verified/cached yet this session — block submission and
/// show a loading reason; auto-clears when a verified mode arrives.
final class KitchenModeReadinessLoading extends PosKitchenModeReadiness {
  const KitchenModeReadinessLoading();
}

/// A server-verified (or fresh secure-cached) mode is known — submission proceeds
/// with the resolved dispatch mode.
final class KitchenModeReadinessResolved extends PosKitchenModeReadiness {
  const KitchenModeReadinessResolved(this.mode);

  final KitchenModeResult mode;
}

/// Verification failed definitively AND no fresh trusted cache exists — block
/// submission and show a RETRYABLE reason (never silently create a stuck order).
final class KitchenModeReadinessUnavailable extends PosKitchenModeReadiness {
  const KitchenModeReadinessUnavailable();
}

/// Why the POS is blocking a submit while the kitchen mode is not resolved.
enum PosSubmissionBlockReason { kitchenModeLoading, kitchenModeUnavailable }

/// The ONE shared submission decision — used by BOTH the Send-button eligibility
/// and the actual submission payload (and a corrected/replayed submit), so the UI
/// and the emitted `dispatch_mode` can never disagree.
class PosSubmissionDecision {
  const PosSubmissionDecision._(
    this.canSubmit,
    this.dispatchMode,
    this.blockReason,
  );

  const PosSubmissionDecision.ready(OrderDispatchMode mode)
    : this._(true, mode, null);

  const PosSubmissionDecision.blocked(PosSubmissionBlockReason reason)
    : this._(false, OrderDispatchMode.kds, reason);

  /// True only when a verified mode is known — the ONLY state that permits submit.
  final bool canSubmit;

  /// The dispatch mode to emit (meaningful only when [canSubmit]).
  final OrderDispatchMode dispatchMode;

  /// Why submission is blocked (null when [canSubmit]).
  final PosSubmissionBlockReason? blockReason;
}

/// Maps the current [readiness] to the shared submission decision. Resolved ->
/// submit with the resolved dispatch mode; Loading/Unavailable -> block.
PosSubmissionDecision resolvePosSubmissionDecision(
  PosKitchenModeReadiness readiness,
) => switch (readiness) {
  KitchenModeReadinessResolved(:final mode) => PosSubmissionDecision.ready(
    resolveOrderDispatchMode(mode),
  ),
  KitchenModeReadinessLoading() => const PosSubmissionDecision.blocked(
    PosSubmissionBlockReason.kitchenModeLoading,
  ),
  KitchenModeReadinessUnavailable() => const PosSubmissionDecision.blocked(
    PosSubmissionBlockReason.kitchenModeUnavailable,
  ),
};

/// The authoritative readiness state. Starts [KitchenModeReadinessLoading]; the
/// native spool composition seeds it from the fresh secure cache (offline-safe)
/// and the readiness heartbeat publishes each verified network result.
class PosKitchenModeReadinessController
    extends Notifier<PosKitchenModeReadiness> {
  @override
  PosKitchenModeReadiness build() {
    // DEMO mode has no verified backend workflow and NO stuck-order risk (orders
    // are local), so it resolves to the NORMAL kds workflow immediately — Send is
    // never blocked (byte-identical to the pre-feature demo behavior). REAL mode
    // starts Loading and is resolved by the offline secure-cache seed or the
    // readiness heartbeat (native), or the lifecycle's kds seed (web/unpaired).
    if (ref.watch(runtimeConfigProvider).isDemoMode) {
      return KitchenModeReadinessResolved(
        KitchenModeVerifiedKds(verifiedAt: DateTime.now()),
      );
    }
    return const KitchenModeReadinessLoading();
  }

  /// Publish a fetched/cached mode. A TRUSTED mode (printer_only WITH a revision,
  /// or a verified kds) resolves submission; any other (revision-unavailable /
  /// invalid-session / transient / server / malformed) marks unavailable, but
  /// ONLY while still loading — a transient blip never downgrades an already
  /// verified mode (the last verified mode stays usable offline).
  void publish(KitchenModeResult mode) {
    if (mode is KitchenModePrinterOnlyWithRevision ||
        mode is KitchenModeVerifiedKds) {
      state = KitchenModeReadinessResolved(mode);
    } else {
      markUnavailable();
    }
  }

  /// A definitive verification failure with no trusted cache — block with a
  /// retryable reason. No-op once a verified mode is already resolved.
  void markUnavailable() {
    if (state is KitchenModeReadinessLoading) {
      state = const KitchenModeReadinessUnavailable();
    }
  }

  /// Return to loading so a retry (heartbeat + cache seed) can re-resolve it.
  void reset() => state = const KitchenModeReadinessLoading();

  /// The native spool composition binds the readiness heartbeat's re-verify
  /// entrypoint here so the UI can request an immediate retry WITHOUT importing
  /// the spool boundary — the runtime source-boundary proof forbids any spool
  /// reference outside `lib/src/spool` and the sanctioned lifecycle hook. Null
  /// on web/demo/unpaired, where the mode is already resolved and a retry has
  /// nothing to re-verify.
  void Function()? _resolver;

  void bindResolver(void Function()? resolver) => _resolver = resolver;

  /// User-initiated retry after an unavailable mode: reopen the gate to loading
  /// and ask the bound resolver (the heartbeat) to re-verify. A no-op when no
  /// resolver is bound (web/demo), where there is nothing to re-verify.
  void requestResolution() {
    final resolver = _resolver;
    if (resolver == null) return;
    state = const KitchenModeReadinessLoading();
    resolver();
  }
}

final posKitchenModeReadinessProvider =
    NotifierProvider<
      PosKitchenModeReadinessController,
      PosKitchenModeReadiness
    >(PosKitchenModeReadinessController.new);

/// The resolved verified mode (or null when loading/unavailable) — the input the
/// close-eligibility policy + the explicit Complete action key on. Derived from
/// the single readiness source so nothing can disagree with the submit decision.
final posVerifiedKitchenModeProvider = Provider<KitchenModeResult?>((ref) {
  final readiness = ref.watch(posKitchenModeReadinessProvider);
  return readiness is KitchenModeReadinessResolved ? readiness.mode : null;
});
