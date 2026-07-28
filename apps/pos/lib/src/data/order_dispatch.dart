import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The LAST server-VERIFIED kitchen workflow mode for the current scope, or null
/// until it has been verified this session (fail-closed → KDS). Published by the
/// kitchen-readiness heartbeat, which fetches the revision-gated mode on
/// startup/resume/interval; the value survives offline (the last verified mode is
/// kept), so a printer_only branch keeps emitting direct_print while offline, and
/// a not-yet-verified or transiently-failed mode stays KDS. Tests override this to
/// force a mode.
final posVerifiedKitchenModeProvider = StateProvider<KitchenModeResult?>(
  (ref) => null,
);
