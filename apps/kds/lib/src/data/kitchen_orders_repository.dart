import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import 'kitchen_order.dart';

/// The kitchen-orders seam (RF-117). [loadOrders] maps to the future KDS read
/// (the polling `sync_pull` of orders/order_items, RF-063); kitchen status
/// actions will map to the `bump_kitchen_item` RPC (API_CONTRACT §4.4).
///
/// Implemented here ONLY by the in-memory [DemoKitchenOrdersStore]; real
/// backend + realtime wiring is DEFERRED (the existing polling path in
/// feature_kitchen/sync is the seam for that). Nothing here contacts a backend.
abstract class KitchenOrdersRepository {
  /// Loads the active kitchen order tickets, newest activity first.
  Future<List<KitchenOrderTicket>> loadOrders();
}

/// In-memory, clearly-labelled DEMO kitchen feed (RF-117). Seeds a fixed set of
/// tickets that mirror the RF-115 submitted-order payload shape (order number,
/// type, table, submitted time, items + modifiers/notes) across the kitchen
/// lifecycle, so the board shows status variety on load. Money-free
/// (SECURITY T-003). NO backend, NO persistence, NO realtime.
class DemoKitchenOrdersStore implements KitchenOrdersRepository {
  DemoKitchenOrdersStore({
    DateTime Function()? clock,
    List<KitchenOrderTicket>? seed,
  }) : _clock = clock ?? DateTime.now,
       _seed = seed;

  final DateTime Function() _clock;

  /// Optional explicit seed (e.g. an empty list to exercise the empty state).
  final List<KitchenOrderTicket>? _seed;

  @override
  Future<List<KitchenOrderTicket>> loadOrders() async {
    final override = _seed;
    if (override != null) return List.of(override);

    final now = _clock();
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    return <KitchenOrderTicket>[
      KitchenOrderTicket(
        ticketId: 'K-1001',
        orderNumber: 'K-1001',
        orderType: OrderType.dineIn,
        tableLabel: 'T3',
        stationId: 'grill',
        submittedAt: ago(2),
        status: KitchenTicketStatus.newTicket,
        items: const [
          KitchenOrderItem(
            name: 'Classic Burger',
            quantity: 2,
            modifiers: ['No pickles'],
          ),
          KitchenOrderItem(name: 'Cola', quantity: 1),
        ],
      ),
      KitchenOrderTicket(
        ticketId: 'K-1002',
        orderNumber: 'K-1002',
        orderType: OrderType.takeaway,
        tableLabel: null,
        stationId: 'oven',
        submittedAt: ago(4),
        status: KitchenTicketStatus.newTicket,
        items: const [KitchenOrderItem(name: 'Margherita Pizza', quantity: 1)],
      ),
      KitchenOrderTicket(
        ticketId: 'K-1003',
        orderNumber: 'K-1003',
        orderType: OrderType.dineIn,
        tableLabel: 'T6',
        stationId: 'fryer',
        submittedAt: ago(9),
        status: KitchenTicketStatus.inPreparation,
        items: const [
          // Product-rescue sprint: a '×N' modifier-quantity string on a ticket
          // OTHER than K-1001 (kitchen_board_test pins exactly one '×2' text
          // inside the K-1001 card) so the demo board shows Part D.
          KitchenOrderItem(
            name: 'French Fries',
            quantity: 2,
            modifiers: ['Extra cheese ×2'],
            note: 'Extra crispy',
          ),
          KitchenOrderItem(name: 'Onion Rings', quantity: 1),
        ],
      ),
      KitchenOrderTicket(
        ticketId: 'K-1004',
        orderNumber: 'K-1004',
        orderType: OrderType.takeaway,
        tableLabel: null,
        stationId: 'grill',
        submittedAt: ago(13),
        status: KitchenTicketStatus.acknowledged,
        items: const [KitchenOrderItem(name: 'Falafel Plate', quantity: 1)],
      ),
      KitchenOrderTicket(
        ticketId: 'K-1005',
        orderNumber: 'K-1005',
        orderType: OrderType.dineIn,
        tableLabel: 'T1',
        stationId: 'grill',
        submittedAt: ago(16),
        status: KitchenTicketStatus.ready,
        items: const [KitchenOrderItem(name: 'Grilled Chicken', quantity: 1)],
      ),
    ];
  }
}

/// Real-mode placeholder for the kitchen-orders seam (RF-117).
///
/// The live KDS feed does NOT flow through this repository: in real mode the
/// board is driven by the injected `KdsSyncSource` polling `sync_pull`
/// (orders/order_items/order_item_modifiers; money-free per SECURITY T-003) via
/// `KdsSyncedHome`. This [KitchenOrdersRepository] skeleton exists only so that
/// if a real-mode build ever reaches the demo-board seam it FAILS CLOSED with a
/// clear error instead of serving demo tickets under a real-mode label. It
/// contacts no backend and fabricates no data; wiring is blocked on the deferred
/// PIN/device session bridge.
class RealKitchenOrdersRepository implements KitchenOrdersRepository {
  const RealKitchenOrdersRepository();

  @override
  Future<List<KitchenOrderTicket>>
  loadOrders() async => throw const RealRepoNotWiredError(
    'kitchen-orders: real KDS data flows through the injected KdsSyncSource '
    '(sync_pull, RF-063), blocked on a PIN/device SyncSession - not wired yet',
  );
}
