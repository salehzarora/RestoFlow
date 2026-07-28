import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_dispatch.dart' show resolveOrderDispatchMode;
import 'order_submission.dart' show OrderDispatchMode;

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (§14) — the ONE pure close-eligibility
/// policy used by the POS UI + controller so the "can this order be completed
/// from the POS now?" decision can never diverge from the submission dispatch
/// decision. The SERVER stays authoritative through its status-transition +
/// settlement guards; this is only the client-side affordance gate.
///
/// The typed outcomes map 1:1 to §14. Only [allowed] enables the explicit
/// "Complete order" safety net; every other value hides/disables it with an
/// honest reason (or because completion is not the POS's to drive).
enum PosOrderCloseEligibility {
  /// A served, fully-settled printer_only order the authorized actor may complete.
  allowed,

  /// Already terminal (completed/cancelled/voided) — nothing to do.
  alreadyCompleted,

  /// Not yet settled — settlement drives completion (take payment first).
  paymentRequired,

  /// A KDS-workflow order — the KDS/served-gate drives completion, never the POS.
  kdsCompletionRequired,

  /// The actor lacks the capability to complete/close the order.
  unauthorized,

  /// A non-served / not-completable state (e.g. submitted/accepted/preparing/ready).
  invalidState,

  /// A completion transition for this order is already in flight.
  transitionInFlight,

  /// The kitchen workflow mode is not verified (fail-closed) — no POS close.
  workflowUnavailable,
}

/// The set of canonical TERMINAL order statuses (D-018).
const Set<String> _kTerminalStatuses = {'completed', 'cancelled', 'voided'};

/// Evaluates whether the explicit POS "Complete order" safety net applies to an
/// order right now. Pure + total; the same [verifiedMode] the submission path
/// uses (via [resolveOrderDispatchMode]) decides printer_only vs KDS, so the two
/// never disagree. NEVER keyed on KDS liveness, printer connectivity, print
/// success, or order type — only on the authoritative inputs below.
///
/// * [status] — the order's current status.
/// * [settled] — `app.order_is_fully_settled` for the order (settlement is a
///   SEPARATE axis, D-025; the client never recomputes money — it passes the
///   server's answer in).
/// * [verifiedMode] — the last server-verified kitchen workflow mode (null =>
///   unverified => fail-closed).
/// * [actorAuthorized] — whether the signed-in actor may complete/close orders.
/// * [transitionInFlight] — whether a completion op for this order is pending.
PosOrderCloseEligibility posOrderCloseEligibility({
  required String status,
  required bool settled,
  required KitchenModeResult? verifiedMode,
  required bool actorAuthorized,
  required bool transitionInFlight,
}) {
  if (_kTerminalStatuses.contains(status)) {
    return PosOrderCloseEligibility.alreadyCompleted;
  }
  // The POS only ever completes a PRINTER_ONLY (direct_print) order. In a KDS
  // workflow, completion is the KDS/served-gated path — never a POS button.
  if (resolveOrderDispatchMode(verifiedMode) != OrderDispatchMode.directPrint) {
    // Distinguish "verified KDS" (KDS drives it) from "unverified" (fail-closed).
    return verifiedMode == null
        ? PosOrderCloseEligibility.workflowUnavailable
        : PosOrderCloseEligibility.kdsCompletionRequired;
  }
  if (!actorAuthorized) return PosOrderCloseEligibility.unauthorized;
  // A printer_only order rests at `served` after its direct_print dispatch; only
  // a served order can transition to completed (D-018 single-hop).
  if (status != 'served') return PosOrderCloseEligibility.invalidState;
  if (transitionInFlight) return PosOrderCloseEligibility.transitionInFlight;
  // Settlement is the real close: an unsettled served order is completed by
  // taking payment (auto-completion), not by the safety-net button.
  if (!settled) return PosOrderCloseEligibility.paymentRequired;
  return PosOrderCloseEligibility.allowed;
}
