/// Thrown by every M7 Real* repository skeleton that has been SELECTED (real
/// mode) but is NOT YET WIRED to a verified `public.*` backend read/RPC.
///
/// This is the load-bearing honesty guarantee of the M7 demo/real seam: a Real*
/// repo never fabricates data and never silently falls back to demo - it fails
/// loudly with this error, which flows into each surface's EXISTING generic
/// error state. A surface can therefore only ever show "real" data once a true
/// backend read is implemented and verified. Carries only a short developer
/// reason - never secrets, never tenant data.
class RealRepoNotWiredError implements Exception {
  const RealRepoNotWiredError(this.message);

  final String message;

  @override
  String toString() => 'RealRepoNotWiredError: $message';
}
