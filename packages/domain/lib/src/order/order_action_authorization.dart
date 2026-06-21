/// PLACEHOLDER authorization for sensitive order actions (RF-032).
///
/// This is a local prototype stub only — NOT a real auth/roles/permissions
/// system. There is no JWT, no PIN session, no backend, and no audit write
/// here; real void authorization + audit are owned by RF-050/RF-051/RF-053.
/// The order machine only checks that a supplied authorization permits the
/// action (e.g. [canVoid]).
library;

class OrderActionAuthorization {
  const OrderActionAuthorization({
    required this.canVoid,
    required this.actorId,
  });

  /// Whether this (placeholder) actor is permitted to void.
  final bool canVoid;

  /// An opaque actor identifier (placeholder; not a real identity).
  final String actorId;
}
