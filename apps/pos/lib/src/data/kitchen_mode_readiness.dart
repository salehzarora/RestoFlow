import 'dart:async' show Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_dispatch.dart' show resolveOrderDispatchMode;
import 'order_submission.dart' show OrderDispatchMode;
// runtimeConfigProvider + KitchenModeVerifiedKds come from restoflow_feature_auth.

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 1) — the typed scope a verified
/// kitchen mode belongs to: the effective organization, restaurant, branch, and
/// paired device. A cache/fetch/heartbeat/retry result must NEVER cross this
/// boundary — an old printer_only mode leaking into a KDS branch would emit
/// direct_print and bypass the KDS lifecycle, and an old KDS mode leaking into a
/// printer_only branch would strand the order. Derived from the paired
/// [DeviceContext] and INDEPENDENT of the PIN session: the branch's kitchen mode
/// does not depend on who is signed in (PIN handover is its own concern).
class PosKitchenModeScopeKey {
  const PosKitchenModeScopeKey({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
  });

  final String organizationId;
  final String? restaurantId;
  final String branchId;
  final String? deviceId;

  /// The scope for a PAIRED device context, or null when no device is paired
  /// (without a paired device there is no printer_only branch machinery, so the
  /// workflow is trivially the normal KDS).
  static PosKitchenModeScopeKey? fromContext(DeviceContext? ctx) {
    if (ctx == null || !ctx.isPaired) return null;
    return PosKitchenModeScopeKey(
      organizationId: ctx.organizationId,
      restaurantId: ctx.restaurantId,
      branchId: ctx.branchId,
      deviceId: ctx.deviceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PosKitchenModeScopeKey &&
      other.organizationId == organizationId &&
      other.restaurantId == restaurantId &&
      other.branchId == branchId &&
      other.deviceId == deviceId;

  @override
  int get hashCode =>
      Object.hash(organizationId, restaurantId, branchId, deviceId);

  @override
  String toString() =>
      'PosKitchenModeScopeKey($organizationId/$restaurantId/$branchId/$deviceId)';
}

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A) — the typed readiness of the
/// VERIFIED kitchen workflow mode for the CURRENT scope. An order may only be
/// submitted once this is [KitchenModeReadinessResolved]; until then the POS must
/// NOT guess a KDS dispatch (which, on a real printer_only branch with no KDS,
/// would leave the order stuck at `submitted` with no way to complete or free its
/// table). Web-safe (no drift/sqlite): the offline secure-cache seed + the network
/// verification both feed this from the native spool composition. Each variant
/// carries the [scope] it was resolved for so a delayed cross-scope result can
/// never apply (Finding 1).
sealed class PosKitchenModeReadiness {
  const PosKitchenModeReadiness(this.scope);

  /// The scope the state belongs to (null in demo / unscoped web).
  final PosKitchenModeScopeKey? scope;
}

/// The mode has not been verified/cached yet this session — block submission and
/// show a loading reason; auto-clears when a verified mode arrives.
final class KitchenModeReadinessLoading extends PosKitchenModeReadiness {
  const KitchenModeReadinessLoading([super.scope]);
}

/// A server-verified (or fresh secure-cached) mode is known — submission proceeds
/// with the resolved dispatch mode.
final class KitchenModeReadinessResolved extends PosKitchenModeReadiness {
  const KitchenModeReadinessResolved(this.mode, [super.scope]);

  final KitchenModeResult mode;
}

/// Verification failed definitively AND no fresh trusted cache exists — block
/// submission and show a RETRYABLE reason (never silently create a stuck order).
final class KitchenModeReadinessUnavailable extends PosKitchenModeReadiness {
  const KitchenModeReadinessUnavailable([super.scope]);
}

/// Why the POS is blocking a submit while the kitchen mode is not resolved.
enum PosSubmissionBlockReason { kitchenModeLoading, kitchenModeUnavailable }

/// The ONE shared submission decision — used by BOTH the Send-button eligibility
/// and the actual submission payload (and a corrected/replayed submit), so the UI
/// and the emitted `dispatch_mode` can never disagree. Carries the [scope] the
/// mode was verified for so the authoritative submit gate can re-check it against
/// the live scope at payload-construction time (Finding 1E).
class PosSubmissionDecision {
  const PosSubmissionDecision._(
    this.canSubmit,
    this.dispatchMode,
    this.blockReason,
    this.scope,
  );

  const PosSubmissionDecision.ready(
    OrderDispatchMode mode, [
    PosKitchenModeScopeKey? scope,
  ]) : this._(true, mode, null, scope);

  const PosSubmissionDecision.blocked(
    PosSubmissionBlockReason reason, [
    PosKitchenModeScopeKey? scope,
  ]) : this._(false, OrderDispatchMode.kds, reason, scope);

  /// True only when a verified mode is known — the ONLY state that permits submit.
  final bool canSubmit;

  /// The dispatch mode to emit (meaningful only when [canSubmit]).
  final OrderDispatchMode dispatchMode;

  /// Why submission is blocked (null when [canSubmit]).
  final PosSubmissionBlockReason? blockReason;

  /// The scope the decision was verified for (null in demo / unscoped).
  final PosKitchenModeScopeKey? scope;
}

/// Maps the current [readiness] to the shared submission decision. Resolved ->
/// submit with the resolved dispatch mode; Loading/Unavailable -> block. The
/// readiness scope flows into the decision unchanged.
PosSubmissionDecision resolvePosSubmissionDecision(
  PosKitchenModeReadiness readiness,
) => switch (readiness) {
  KitchenModeReadinessResolved(:final mode, :final scope) =>
    PosSubmissionDecision.ready(resolveOrderDispatchMode(mode), scope),
  KitchenModeReadinessLoading(:final scope) => PosSubmissionDecision.blocked(
    PosSubmissionBlockReason.kitchenModeLoading,
    scope,
  ),
  KitchenModeReadinessUnavailable(:final scope) =>
    PosSubmissionDecision.blocked(
      PosSubmissionBlockReason.kitchenModeUnavailable,
      scope,
    ),
};

/// POS-KITCHEN-WORKFLOW-REGRESSION-001 — how long a SCOPED verification may sit
/// on [KitchenModeReadinessLoading] before the gate gives the operator an
/// actionable, retryable state instead of an endless spinner.
///
/// Generous on purpose: the heartbeat's own call timeout is 20s, so this only
/// fires when something upstream never reported at all. It is NOT a polling
/// interval — it is a one-shot watchdog per loading episode.
const Duration kPosKitchenModeVerificationTimeout = Duration(seconds: 30);

/// Injectable so widget tests can drive the watchdog without waiting 30s.
final posKitchenModeVerificationTimeoutProvider = Provider<Duration>(
  (_) => kPosKitchenModeVerificationTimeout,
);

/// The authoritative readiness state. Starts [KitchenModeReadinessLoading]; the
/// native spool composition binds a scope and publishes the verified mode through
/// a generation-stamped [PosKitchenModeBinding]. A delayed result from an old
/// scope/binding is IGNORED (Finding 1): every publish/retry verifies the
/// controller is not disposed and that its captured generation and scope still
/// match the active binding.
class PosKitchenModeReadinessController
    extends Notifier<PosKitchenModeReadiness> {
  int _generation = 0;
  PosKitchenModeScopeKey? _scope;
  bool _disposed = false;
  void Function()? _resolver;
  Timer? _watchdog;

  /// POS-KITCHEN-WORKFLOW-REGRESSION-001 — the ONE place readiness state is
  /// written, so the loading watchdog can never be forgotten at a call site.
  ///
  /// A SCOPED loading state arms a one-shot watchdog; every other state cancels
  /// it. When the watchdog fires while still loading the gate moves to
  /// [KitchenModeReadinessUnavailable] — which the cart already renders with a
  /// localized reason AND a Retry button. Loading therefore stops being a
  /// terminal state no matter which upstream path failed to report.
  ///
  /// An UNSCOPED loading state (no paired device yet) is not watched: it is a
  /// normal transient before the pairing gate publishes, and the composition
  /// resolves it through the unscoped-KDS path.
  void _apply(PosKitchenModeReadiness next) {
    _watchdog?.cancel();
    _watchdog = null;
    state = next;
    if (next is KitchenModeReadinessLoading && next.scope != null) {
      final generation = _generation;
      final scope = next.scope;
      _watchdog = Timer(
        ref.read(posKitchenModeVerificationTimeoutProvider),
        () {
          _markUnavailable(generation, scope);
        },
      );
    }
  }

  @override
  PosKitchenModeReadiness build() {
    ref.onDispose(() {
      _disposed = true;
      _watchdog?.cancel();
      _watchdog = null;
    });
    // DEMO mode has no verified backend workflow and NO stuck-order risk (orders
    // are local), so it resolves to the NORMAL kds workflow immediately — Send is
    // never blocked (byte-identical to the pre-feature demo behavior). REAL mode
    // starts Loading and is resolved by the offline secure-cache seed or the
    // readiness heartbeat (native), or the lifecycle's unscoped-kds seed
    // (web/unpaired).
    if (ref.watch(runtimeConfigProvider).isDemoMode) {
      _scope = null;
      return KitchenModeReadinessResolved(
        KitchenModeVerifiedKds(verifiedAt: DateTime.now()),
        null,
      );
    }
    return KitchenModeReadinessLoading(_scope);
  }

  /// The active generation token (monotonic; bumped by every bind/unbind).
  int get generation => _generation;

  /// The scope the readiness currently belongs to.
  PosKitchenModeScopeKey? get activeScope => _scope;

  /// Bind readiness to [scope] for a fresh async generation. A scope CHANGE
  /// invalidates the previous verified mode (fresh Loading for the new scope),
  /// unbinds the old resolver, and preserves nothing from the old scope; a
  /// same-scope rebind preserves the verified state but STILL bumps the
  /// generation so a previous binding's in-flight result is ignored. Returns a
  /// handle the caller stamps every async result with.
  PosKitchenModeBinding bindScope(PosKitchenModeScopeKey? scope) {
    if (_disposed) return PosKitchenModeBinding._(this, _generation, scope);
    _generation++;
    if (scope != _scope) {
      _scope = scope;
      _resolver = null;
      _apply(KitchenModeReadinessLoading(scope));
    }
    return PosKitchenModeBinding._(this, _generation, scope);
  }

  /// Web / unpaired / no-secure-spool: no printer_only machinery exists, so the
  /// workflow is the normal KDS — resolve immediately (Send never blocks). A
  /// no-op once a real device scope is being verified, or a mode is already
  /// resolved.
  void resolveUnscopedKds() {
    if (_disposed) return;
    if (_scope != null) return;
    if (state is KitchenModeReadinessResolved) return;
    _apply(
      KitchenModeReadinessResolved(
        KitchenModeVerifiedKds(verifiedAt: DateTime.now()),
        null,
      ),
    );
  }

  /// Force the gate back to [KitchenModeReadinessLoading] for the CURRENT scope
  /// without changing the scope/generation — a verified mode arriving through the
  /// active binding re-resolves it. Utility for tests and for reopening the gate
  /// on retry.
  void reset() {
    if (_disposed) return;
    _apply(KitchenModeReadinessLoading(_scope));
  }

  /// User-initiated retry after an unavailable mode: reopen the gate to loading
  /// and ask the bound resolver (the heartbeat) to re-verify. A no-op when no
  /// resolver is bound (web/demo), where there is nothing to re-verify.
  void requestResolution() {
    final resolver = _resolver;
    if (resolver == null) return;
    if (state is! KitchenModeReadinessResolved) {
      _apply(KitchenModeReadinessLoading(_scope));
    }
    resolver();
  }

  bool _isCurrent(int generation, PosKitchenModeScopeKey? scope) =>
      !_disposed && generation == _generation && scope == _scope;

  void _publish(
    int generation,
    PosKitchenModeScopeKey? scope,
    KitchenModeResult mode,
  ) {
    if (!_isCurrent(generation, scope)) return;
    // A TRUSTED mode (printer_only WITH a revision, or a verified kds) resolves
    // submission; any other (revision-unavailable / invalid-session / transient /
    // server / malformed) marks unavailable, but ONLY while still loading — a
    // transient blip never downgrades an already verified mode for the SAME scope.
    if (mode is KitchenModePrinterOnlyWithRevision ||
        mode is KitchenModeVerifiedKds) {
      _apply(KitchenModeReadinessResolved(mode, _scope));
    } else {
      _markUnavailable(generation, scope);
    }
  }

  void _markUnavailable(int generation, PosKitchenModeScopeKey? scope) {
    if (!_isCurrent(generation, scope)) return;
    if (state is KitchenModeReadinessLoading) {
      _apply(KitchenModeReadinessUnavailable(_scope));
    }
  }

  void _bindResolver(int generation, void Function()? resolver) {
    if (_disposed || generation != _generation) return;
    _resolver = resolver;
  }

  void _unbind(int generation) {
    if (_disposed) return;
    if (generation == _generation) {
      // Invalidate this (now-disposed) binding's in-flight results immediately,
      // so nothing can publish into the readiness after disposal.
      _generation++;
      _resolver = null;
    }
  }
}

/// A generation-stamped handle for ONE binding of the readiness to a scope. The
/// native composition stamps every async result (cache seed, fetch, heartbeat,
/// retry) through the handle; a result from a superseded binding is dropped.
class PosKitchenModeBinding {
  PosKitchenModeBinding._(this._controller, this._generation, this.scope);

  final PosKitchenModeReadinessController _controller;
  final int _generation;

  /// The scope this binding verifies against.
  final PosKitchenModeScopeKey? scope;

  /// Whether this binding is still the active one (scope + generation match and
  /// the controller is not disposed).
  bool get isCurrent => _controller._isCurrent(_generation, scope);

  /// Publish a fetched/cached mode. Ignored when this binding is superseded.
  void publish(KitchenModeResult mode) =>
      _controller._publish(_generation, scope, mode);

  /// Mark the mode unavailable (retryable). Ignored when superseded.
  void markUnavailable() => _controller._markUnavailable(_generation, scope);

  /// Bind the retry resolver for this scope. Ignored when superseded.
  void bindResolver(void Function()? resolver) =>
      _controller._bindResolver(_generation, resolver);

  /// Release this binding (scope change / disposal). Any later result stamped
  /// with this binding is thereafter ignored.
  void unbind() => _controller._unbind(_generation);
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
