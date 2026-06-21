import 'package:restoflow_domain/restoflow_domain.dart';

/// A KDS-local view model for one item line on a ticket (RF-034).
///
/// This is a SEPARATE KDS view model — RF-033's immutable `KitchenStationItem`
/// routing output is not mutated or reused here.
class KdsItemView {
  const KdsItemView({required this.name, required this.quantity});

  /// Display name snapshot (data — rendered as-is, not a localized string).
  final String name;
  final int quantity;
}

/// A KDS-local, mutable view model for one kitchen ticket (RF-034): the RF-033
/// routing data shape (id, station, items) plus a mutable [KitchenTicketStatus]
/// the KDS screen drives. In-memory only — not persisted, not synced.
class KdsTicketView {
  KdsTicketView({
    required this.kitchenTicketId,
    required this.stationId,
    required this.items,
    this.status = KitchenTicketStatus.ready,
  });

  final String kitchenTicketId;
  final String stationId;
  final List<KdsItemView> items;

  /// The current local status; mutated by bump/recall on the screen.
  KitchenTicketStatus status;
}
