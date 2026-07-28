import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'order_submission.dart' show OrderDispatchMode;

/// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 — the ONE dispatch-mode decision, shared
/// by the submission path and the close-eligibility UI so they can never diverge.
///
/// Returns [OrderDispatchMode.directPrint] ONLY for a VERIFIED printer_only
/// branch carrying a trusted revision ([KitchenModePrinterOnlyWithRevision]).
/// EVERY other state — a verified KDS branch, an unavailable/unknown revision, an
/// invalid session, a transient/server failure, or a not-yet-resolved (null)
/// mode — FAILS CLOSED to [OrderDispatchMode.kds]. The decision is NEVER based on
/// KDS liveness, printer connectivity, print success, or order type; only on the
/// authoritative, revision-gated kitchen workflow mode.
OrderDispatchMode resolveOrderDispatchMode(KitchenModeResult? verifiedMode) {
  return verifiedMode is KitchenModePrinterOnlyWithRevision
      ? OrderDispatchMode.directPrint
      : OrderDispatchMode.kds;
}

// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Gap A): the verified-mode signal moved to
// kitchen_mode_readiness.dart as a TYPED readiness (loading / resolved /
// unavailable) so a submit can BLOCK until the mode is verified instead of
// guessing KDS. `posVerifiedKitchenModeProvider` there is derived from it.
