import 'package:restoflow_domain/restoflow_domain.dart';

/// A KDS-local view model for one item line on a ticket.
///
/// Moved into `feature_kitchen` under RF-063 (was an app-local model under
/// RF-034) so the kitchen feature owns its view models, mapper, and providers
/// (ARCHITECTURE §3); the app shell only hosts them. Display data only — it
/// carries NO money field (kitchen redaction, SECURITY T-003).
class KdsItemView {
  const KdsItemView({
    required this.name,
    required this.quantity,
    this.modifiers = const <String>[],
    this.note,
    this.prepComponents = const <KitchenPrepComponent>[],
  });

  /// Display name snapshot (data — rendered as-is, not a localized string).
  final String name;

  /// Item quantity (integer; never money).
  final int quantity;

  /// Selected modifier option name snapshots (e.g. "no onion", "extra
  /// cheese") — rendered as their own lines under the item, never money.
  final List<String> modifiers;

  /// The per-item kitchen note (order_items.notes), if any.
  final String? note;

  /// KITCHEN-PREP-001: the item's configured PER-UNIT kitchen count components
  /// (from `order_items.prep_snapshot`). Non-money ({name,quantity,unit}); the
  /// mapper rolls them up × [quantity] into the ticket's whole-order
  /// [KdsTicketView.kitchenCounts]. Empty when the item has no configured count.
  final List<KitchenPrepComponent> prepComponents;
}

/// A KDS-local, mutable view model for one kitchen ticket.
///
/// Holds the routing shape (id, station, items) plus a mutable
/// [KitchenTicketStatus] the KDS screen drives via bump/recall. Built fresh from
/// each pull (RF-063) or from a local fixture (RF-034 fallback). Every field is
/// an EXPLICIT money-free pluck from the wire rows (SECURITY T-003) — never a
/// raw-row passthrough.
class KdsTicketView {
  KdsTicketView({
    required this.kitchenTicketId,
    required this.stationId,
    required this.items,
    this.status = KitchenTicketStatus.ready,
    this.orderId,
    this.orderNumber,
    this.orderType,
    this.tableLabel,
    this.customerName,
    this.notes,
    this.submittedAt,
    this.kitchenCounts = const <KitchenCount>[],
  });

  final String kitchenTicketId;
  final String stationId;
  final List<KdsItemView> items;

  /// The owning ORDER id when the ticket was built from a real `sync_pull`
  /// (RF-063 mapper) — the target of an `order.status` push. Null for local
  /// demo fixtures (no backend order exists; nothing is pushed).
  final String? orderId;

  /// The HUMAN display number for the order — the SAME `displayOrderCode`
  /// the POS shows on its confirmation/receipt (derived from [orderId]), so
  /// cashier and kitchen talk about one number. Null for demo fixtures.
  final String? orderNumber;

  /// Order type wire value ('dine_in' | 'takeaway'), when known.
  final String? orderType;

  /// The dining table's human label (resolved from the pulled `tables`
  /// entity), if the order is attached to a table.
  final String? tableLabel;

  /// ORDER-CUSTOMER-001: the OPTIONAL customer display name (orders.customer_name)
  /// plucked from the pulled order row. Non-money display text (SECURITY T-003);
  /// null when the order carried none.
  final String? customerName;

  /// The order-level kitchen note (orders.notes), if any.
  final String? notes;

  /// When the order was submitted (DESIGN-001, display only): the server's
  /// `orders.created_at` insert time, falling back to the client-reported
  /// `client_created_at`. Drives the elapsed-time/urgency signal on the ticket
  /// card. Null when the wire row carried neither (the card then simply shows
  /// no elapsed pill — never a fabricated age). NOT a money field and not used
  /// for any business decision.
  final DateTime? submittedAt;

  /// KDS-ALERTS-AND-KITCHEN-COUNTS-002: the unified WHOLE-ORDER kitchen count
  /// totals — one entry per owner-configured counted resource (patties, buns,
  /// fish pieces, …), aggregated across the ENTIRE order from BOTH the selected
  /// modifier options' counts (per-option, e.g. Double → 2 قطع لحم) AND the
  /// items' base counts (per-item, e.g. every burger → 1 خبز), grouped by
  /// resource label. Multiple totals can appear together at the top of the
  /// ticket. Non-money; empty when the order carries no configured count. The
  /// same whole-order totals are attached to every station ticket of the order.
  /// (Generalizes the earlier meat/prep summaries; only explicit owner config
  /// contributes — nothing is inferred from names or prices.)
  final List<KitchenCount> kitchenCounts;

  /// The current local status; mutated by bump/recall on the screen.
  KitchenTicketStatus status;
}
