import 'package:restoflow_domain/restoflow_domain.dart';

/// A KDS-local view model for one item line on a ticket.
///
/// Moved into `feature_kitchen` under RF-063 (was an app-local model under
/// RF-034) so the kitchen feature owns its view models, mapper, and providers
/// (ARCHITECTURE §3); the app shell only hosts them. Display data only — it
/// carries NO money field (kitchen redaction, SECURITY T-003).
class KdsItemView {
  const KdsItemView({required this.name, required this.quantity});

  /// Display name snapshot (data — rendered as-is, not a localized string).
  final String name;

  /// Item quantity (integer; never money).
  final int quantity;
}

/// A KDS-local, mutable view model for one kitchen ticket.
///
/// Holds the routing shape (id, station, items) plus a mutable
/// [KitchenTicketStatus] the KDS screen drives via bump/recall. Built fresh from
/// each pull (RF-063) or from a local fixture (RF-034 fallback). No money field.
class KdsTicketView {
  KdsTicketView({
    required this.kitchenTicketId,
    required this.stationId,
    required this.items,
    this.status = KitchenTicketStatus.ready,
    this.orderId,
  });

  final String kitchenTicketId;
  final String stationId;
  final List<KdsItemView> items;

  /// The owning ORDER id when the ticket was built from a real `sync_pull`
  /// (RF-063 mapper) — the target of an `order.status` push. Null for local
  /// demo fixtures (no backend order exists; nothing is pushed).
  final String? orderId;

  /// The current local status; mutated by bump/recall on the screen.
  KitchenTicketStatus status;
}
