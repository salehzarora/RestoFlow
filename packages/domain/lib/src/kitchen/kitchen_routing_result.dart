/// The deterministic, in-memory output of routing a `LocalOrder` to kitchen
/// stations (RF-033): the generated [KitchenTicket]s (one per station) plus the
/// active items that could not be routed. Pure-Dart value object with value
/// equality, so an idempotent re-route compares equal.
library;

import 'kitchen_ticket.dart';
import 'unroutable_order_item.dart';

class KitchenRoutingResult {
  KitchenRoutingResult({
    required List<KitchenTicket> tickets,
    required List<UnroutableOrderItem> unroutableItems,
  }) : tickets = List.unmodifiable(tickets),
       unroutableItems = List.unmodifiable(unroutableItems);

  /// Read-only tickets, sorted by `stationId`.
  final List<KitchenTicket> tickets;

  /// Read-only unroutable active items, sorted by `orderItemId`.
  final List<UnroutableOrderItem> unroutableItems;

  /// Number of station items across all tickets (routable active items).
  int get routableItemCount =>
      tickets.fold(0, (sum, t) => sum + t.stationItems.length);

  /// Number of active items that could not be routed.
  int get unroutableItemCount => unroutableItems.length;

  @override
  bool operator ==(Object other) =>
      other is KitchenRoutingResult &&
      _listEquals(other.tickets, tickets) &&
      _listEquals(other.unroutableItems, unroutableItems);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(tickets), Object.hashAll(unroutableItems));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
