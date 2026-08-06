/// POS-OFFLINE-OPERATIONS-002 (C6) — MAY THIS SESSION SUBMIT ORDERS RIGHT NOW?
///
/// One derivation, consumed by the cart's Send gate: a session may submit when
/// it is LIVE-ONLINE (established or re-verified by a real server round-trip)
/// or RESTORED-OFFLINE and still inside its hard trust window
/// (`min(serverExpiry ?? +inf, lastOnlineVerify + 8h)` — see
/// `secure_session_store.dart`). A restored session whose window has ended
/// keeps the cached menu VISIBLE (browsing is harmless) but blocks Send with
/// its own localized reason — the deliberate C6 failure mode: never a dead
/// screen, never a submit under trust nobody granted.
///
/// The policy deliberately blocks ONLY the restored-and-expired case. Every
/// session that did not come through the offline restore (a live establish, a
/// test-injected session) is by definition not operating on borrowed offline
/// trust, and every surface consuming this sits behind the PIN gate anyway.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos_session.dart';

/// The evaluated Send-eligibility of the current session — see the library
/// doc. [now] is captured at derivation so tests can pin the boundary exactly.
class PosOfflineSessionPolicy {
  const PosOfflineSessionPolicy({
    required this.restoredOffline,
    required this.offlineValidUntil,
    required this.now,
  });

  /// True while the current session was restored without server proof.
  final bool restoredOffline;

  /// The restored session's hard trust end (null when [restoredOffline] is
  /// false — a live session carries no offline window).
  final DateTime? offlineValidUntil;

  /// The instant this policy was evaluated at.
  final DateTime now;

  /// True when submission is allowed: live-online, or restored-offline and
  /// STRICTLY inside the trust window. A restored record with no computable
  /// window fails closed.
  bool get canSubmit {
    if (!restoredOffline) return true;
    final until = offlineValidUntil;
    return until != null && now.isBefore(until);
  }
}

/// The clock the policy evaluates against (overridden in tests to pin the 8h
/// boundary deterministically).
final posOfflineSessionPolicyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The current session's Send-eligibility policy. Recomputed whenever the
/// session controller publishes a restore/verify/end transition (the reactive
/// mirror), so the cart's gate follows the session's real trust state.
final posOfflineSessionPolicyProvider = Provider<PosOfflineSessionPolicy>((
  ref,
) {
  final info = ref.watch(posSessionOfflineRestoreInfoProvider);
  return PosOfflineSessionPolicy(
    restoredOffline: info.restoredOffline,
    offlineValidUntil: info.validUntil,
    now: ref.watch(posOfflineSessionPolicyClockProvider)(),
  );
});
