import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsTicketView;

import '../state/kds_kitchen_print_controller.dart';

/// ORDER-EDIT-001D (design §7.2) — the ticket print-on-Acknowledge prints,
/// RE-DERIVED from [board] (the board after the post-push pull) instead of the
/// [tapped] card captured at tap time, so a ticket edited while unacknowledged
/// prints its fresh lines: a removed line is gone, a reduced quantity is the
/// new one.
///
/// Matches on the WORK UNIT ([KdsKitchenPrintController.keyFor] — order +
/// station + round), so the print job's idempotency key is unchanged and a
/// round never matches its order's original ticket. Returns null — print
/// nothing — when the unit left the board (the coordinator keeps rows across
/// failures, so "not found" means it is gone), when the order was voided (the
/// red card shares the unit key), when the card exists only because of a
/// change (standalone or emptied), or when no live line is left.
KdsTicketView? kdsTicketForAcknowledgePrint(
  KdsTicketView tapped,
  Iterable<KdsTicketView> board,
) {
  final key = KdsKitchenPrintController.keyFor(tapped);
  KdsTicketView? match;
  for (final ticket in board) {
    if (KdsKitchenPrintController.keyFor(ticket) != key) continue;
    if (ticket.requiresAck) return null;
    match ??= ticket;
  }
  if (match == null) return null;
  final change = match.change;
  if (change != null && (change.standalone || change.emptied)) return null;
  if (match.items.isEmpty) return null;
  return match;
}
