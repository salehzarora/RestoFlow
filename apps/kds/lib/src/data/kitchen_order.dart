import 'package:restoflow_domain/restoflow_domain.dart';

/// A single line on a kitchen order ticket (RF-117). Money-free
/// (SECURITY T-003) — the kitchen never sees prices.
class KitchenOrderItem {
  const KitchenOrderItem({
    required this.name,
    required this.quantity,
    this.modifiers = const <String>[],
    this.note,
  });

  /// Item name snapshot (data, not localized chrome).
  final String name;
  final int quantity;

  /// Modifier option names (e.g. "No cheese") — data.
  final List<String> modifiers;

  /// Optional kitchen note (e.g. "Extra crispy") — data.
  final String? note;
}

/// A kitchen order ticket rendered on the KDS board (RF-117).
///
/// Mirrors the visible, MONEY-FREE subset of an RF-115 submitted order: the
/// (provisional) order number, order type, table, submitted time, item lines,
/// and a kitchen [status] using the frozen [KitchenTicketStatus] (DECISION
/// D-018). In-memory demo only — not synced.
class KitchenOrderTicket {
  const KitchenOrderTicket({
    required this.ticketId,
    required this.orderNumber,
    required this.orderType,
    required this.tableLabel,
    required this.stationId,
    required this.submittedAt,
    required this.items,
    required this.status,
  });

  final String ticketId;
  final String orderNumber;
  final OrderType orderType;

  /// The dine-in table label, or null for takeaway.
  final String? tableLabel;

  /// The routed kitchen station (data), or null if unassigned.
  final String? stationId;

  final DateTime submittedAt;
  final List<KitchenOrderItem> items;
  final KitchenTicketStatus status;

  /// Total number of physical items (sum of line quantities).
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  KitchenOrderTicket copyWith({KitchenTicketStatus? status}) =>
      KitchenOrderTicket(
        ticketId: ticketId,
        orderNumber: orderNumber,
        orderType: orderType,
        tableLabel: tableLabel,
        stationId: stationId,
        submittedAt: submittedAt,
        items: items,
        status: status ?? this.status,
      );

  /// KDS-FIFO-001: demo-board column ordering — OLDEST submitted first so the
  /// top of each column is the next ticket to handle, matching the live board.
  /// [submittedAt] is non-null here; the stable [ticketId] is the deterministic
  /// tie-break for equal times.
  static int compareByOldestFirst(KitchenOrderTicket a, KitchenOrderTicket b) {
    final byTime = a.submittedAt.compareTo(b.submittedAt);
    return byTime != 0 ? byTime : a.ticketId.compareTo(b.ticketId);
  }
}
