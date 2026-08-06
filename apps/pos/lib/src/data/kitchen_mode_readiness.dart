import 'dart:async' show Timer, scheduleMicrotask;

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
  /// [POS-OFFLINE-OPERATIONS-002] (C7): [offlineTrusted] is ADDITIVE (an
  /// optional trailing positional with a false default, so every existing
  /// call site and pattern stands unchanged; Dart forbids mixing optional
  /// positionals with named ones, hence not a named parameter). True ONLY for
  /// a mode reconstructed from the operational snapshot's server-verified
  /// capture inside its 2-hour offline trust window.
  const KitchenModeReadinessResolved(
    this.mode, [
    super.scope,
    this.offlineTrusted = false,
  ]);

  final KitchenModeResult mode;

  /// True when this resolution rests on the offline trust window rather than
  /// a live server/cache verification.
  final bool offlineTrusted;
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

/// [POS-OFFLINE-OPERATIONS-002] (C7): how long a SERVER-VERIFIED kitchen-mode
/// capture in the operational snapshot may keep resolving submission while
/// the backend is unreachable. Mirrors the secure mode-cache's stale ceiling.
const Duration kPosKitchenModeOfflineTrustWindow = Duration(hours: 2);

/// (C7) A capture claiming verification this far in the FUTURE is tolerated
/// as clock drift; anything further ahead is suspect and yields no trust —
/// the secure mode-cache's skew rule, restated here because the spool layer
/// may not be imported outside `lib/src/spool`.
const Duration kPosKitchenModeOfflineTrustSkewTolerance = Duration(minutes: 1);

/// [POS-OFFLINE-OPERATIONS-002] (C7): reconstructs the TRUSTED offline kitchen
/// mode from the operational snapshot's server-verified capture, or null when
/// no trust may be extended. Pure and clock-injected so the window is
/// testable to the second.
///
/// The window derives ONLY from [verifiedAt] — the SERVER-verified moment the
/// snapshot stored — measured against [now]. Restarts, reconnect attempts and
/// read-back times can never move it. Rules:
///
///  * age > 2h (or a future claim beyond skew tolerance) => null;
///  * `kds` reconstructs [KitchenModeVerifiedKds] (revision carried through);
///  * `printer_only` reconstructs [KitchenModePrinterOnlyWithRevision] ONLY
///    with a positive revision — a revision-less printer_only was never
///    importable trust online and gains none offline;
///  * any other mode string => null (fail closed).
KitchenModeResult? reconstructOfflineTrustedKitchenMode({
  required String mode,
  required DateTime verifiedAt,
  required DateTime now,
  int? revision,
}) {
  final age = now.difference(verifiedAt);
  if (age.isNegative && -age > kPosKitchenModeOfflineTrustSkewTolerance) {
    return null;
  }
  if (age > kPosKitchenModeOfflineTrustWindow) return null;
  switch (mode) {
    case 'kds':
      return KitchenModeVerifiedKds(verifiedAt: verifiedAt, revision: revision);
    case 'printer_only':
      if (revision == null || revision <= 0) return null;
      return KitchenModePrinterOnlyWithRevision(
        revision: revision,
        verifiedAt: verifiedAt,
      );
    default:
      return null;
  }
}

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
  /// POS-RUNTIME-RECOVERY-002: EVERY loading state — scoped or unscoped — arms
  /// a one-shot watchdog; every other state cancels it. When the watchdog fires
  /// while still loading the gate moves to [KitchenModeReadinessUnavailable] —
  /// which the cart renders with a localized reason AND a Retry button. Loading
  /// therefore has a bounded exit no matter which upstream path failed to
  /// report. The unscoped exemption was the tablet's permanent
  /// «جارٍ التحقق من إعداد المطبخ…»: when the startup callback died before the
  /// heartbeat/seed lines ran, the INITIAL unscoped Loading had no owner, no
  /// watchdog, and no Retry affordance.
  void _apply(PosKitchenModeReadiness next) {
    _watchdog?.cancel();
    _watchdog = null;
    state = next;
    if (next is KitchenModeReadinessLoading) _armWatchdog();
  }

  /// Arms the loading watchdog for the CURRENT generation + scope. The captured
  /// generation makes a stale timer's fire a no-op; conversely, every path that
  /// bumps the generation while Loading must re-arm through here or the episode
  /// loses its bounded exit (POS-RUNTIME-RECOVERY-002 finding R2).
  void _armWatchdog() {
    _watchdog?.cancel();
    final generation = _generation;
    final scope = _scope;
    _watchdog = Timer(ref.read(posKitchenModeVerificationTimeoutProvider), () {
      _markUnavailable(generation, scope);
    });
  }

  @override
  PosKitchenModeReadiness build() {
    // POS-RUNTIME-RECOVERY-002: a provider rebuild runs the PREVIOUS build's
    // onDispose (which latched `_disposed = true`) and then this build on the
    // SAME notifier instance. Without this reset every later transition would
    // silently no-op — a zombie controller frozen on its initial state.
    _disposed = false;
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

  /// POS-RUNTIME-RECOVERY-002 (finding R1) — the LAST-RESORT bound for the
  /// initial Loading. If the state is (still) a Loading with NO armed watchdog
  /// — the frozen shape the vc23 tablet was stuck in — arm one now, so the
  /// episode ends in the retryable Unavailable state even when every normal
  /// startup path (seed, heartbeat, scope bind) failed to reach this
  /// controller. Idempotent: an already-armed episode is left untouched (its
  /// clock is never reset), and non-Loading states need no bound. Called from
  /// the lifecycle's startup hook as its final, individually-guarded step, and
  /// from the heartbeat subscription's error path; deliberately NOT armed in
  /// build() — a Timer created by mere provider materialization would leak
  /// into every widget test that touches real mode without pumping time.
  void ensureBoundedVerification() {
    if (_disposed) return;
    if (state is! KitchenModeReadinessLoading) return;
    if (_watchdog != null) return;
    _armWatchdog();
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
      // POS-RUNTIME-RECOVERY-002 — THE vc23 TABLET ROOT CAUSE. bindScope is
      // called from the heartbeat provider's BUILD, and a synchronous `state=`
      // write on another provider during a build is illegal in Riverpod: in
      // DEBUG builds the framework assertion throws mid-build, so the very
      // first real-scope bind died before arming any watchdog — the gate froze
      // on its initial Loading and the cashier was stranded on
      // «جارٍ التحقق من إعداد المطبخ…» (Release compiled the assert out, which
      // is why v20 worked). The scope/generation bookkeeping above is plain
      // field state and stays synchronous; only the OBSERVABLE transition is
      // deferred one microtask, generation-guarded so a superseded bind can
      // never apply. Until it lands, the submit path is protected by its
      // scope re-check (Finding 1E) — a stale decision can never dispatch.
      final generation = _generation;
      scheduleMicrotask(() {
        if (!_isCurrent(generation, scope)) return;
        // The binding may already have decided this generation (a fast cache
        // seed / fetch). Never downgrade a same-scope decision back to Loading.
        if (state.scope == scope && state is! KitchenModeReadinessLoading) {
          return;
        }
        _apply(KitchenModeReadinessLoading(scope));
      });
    } else if (state is KitchenModeReadinessLoading) {
      // POS-RUNTIME-RECOVERY-002 (finding R2): a SAME-scope rebind preserves
      // the state but just advanced the generation, so an already-armed
      // watchdog's captured generation went stale — its fire would no-op and
      // the loading episode would lose its bounded exit. Re-arm for the new
      // generation so exactly one live watchdog always guards a Loading state.
      _armWatchdog();
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
  /// and ask the bound resolver (the heartbeat) to re-verify.
  ///
  /// POS-RUNTIME-RECOVERY-002 (finding R4): with NO bound resolver (web/demo,
  /// or a heartbeat that failed to compose at all) the retry still visibly
  /// re-opens the gate — the re-applied Loading arms its own watchdog, so the
  /// episode stays bounded and honest instead of a dead button. An
  /// already-resolved gate with no resolver has nothing to re-verify.
  void requestResolution() {
    if (_disposed) return;
    final resolver = _resolver;
    if (resolver == null && state is KitchenModeReadinessResolved) return;
    if (state is! KitchenModeReadinessResolved) {
      _apply(KitchenModeReadinessLoading(_scope));
    }
    resolver?.call();
  }

  bool _isCurrent(int generation, PosKitchenModeScopeKey? scope) =>
      !_disposed && generation == _generation && scope == _scope;

  void _publish(
    int generation,
    PosKitchenModeScopeKey? scope,
    KitchenModeResult mode, {
    bool offlineTrusted = false,
  }) {
    if (!_isCurrent(generation, scope)) return;
    // A TRUSTED mode (printer_only WITH a revision, or a verified kds) resolves
    // submission; any other (revision-unavailable / invalid-session / transient /
    // server / malformed) marks unavailable, but ONLY while still loading — a
    // transient blip never downgrades an already verified mode for the SAME scope.
    if (mode is KitchenModePrinterOnlyWithRevision ||
        mode is KitchenModeVerifiedKds) {
      _apply(KitchenModeReadinessResolved(mode, _scope, offlineTrusted));
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
  ///
  /// [POS-OFFLINE-OPERATIONS-002] (C7): [offlineTrusted] is threaded through
  /// ADDITIVELY (default false — every existing call site publishes exactly
  /// what it always did); the composition's offline fallback passes true for
  /// a snapshot-reconstructed mode inside its 2-hour window.
  void publish(KitchenModeResult mode, {bool offlineTrusted = false}) =>
      _controller._publish(
        _generation,
        scope,
        mode,
        offlineTrusted: offlineTrusted,
      );

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
