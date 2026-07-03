import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// In-memory demo kitchen tickets for the KDS fallback (RF-034 / RF-103),
/// extracted in RF-105 so demo data is isolated under `src/data/` (parity with
/// POS and Dashboard).
///
/// Aligned to the shared M5 demo story (see docs/M5_DEMO_RUN_GUIDE.md): item
/// names use the POS menu vocabulary (apps/pos/lib/src/data/demo_menu.dart) and
/// tickets are seeded across the lifecycle (new / acknowledged / in_preparation
/// / ready) so the board shows status variety on load. Data only — no backend,
/// no money (kitchen redaction).
List<KdsTicketView> demoKdsTickets() => [
  KdsTicketView(
    kitchenTicketId: 'order-101:grill',
    stationId: 'grill',
    items: const [
      KdsItemView(name: 'Classic Burger', quantity: 2),
      KdsItemView(name: 'Grilled Chicken', quantity: 1),
    ],
    status: KitchenTicketStatus.newTicket,
  ),
  KdsTicketView(
    kitchenTicketId: 'order-102:grill',
    stationId: 'grill',
    items: const [KdsItemView(name: 'Margherita Pizza', quantity: 1)],
    status: KitchenTicketStatus.ready,
  ),
  KdsTicketView(
    kitchenTicketId: 'order-103:fryer',
    stationId: 'fryer',
    items: const [
      // Product-rescue sprint: showcases per-modifier QUANTITY ('×N' baked
      // into the display string, same as the real mapper) + an item note —
      // quantities and notes only, never money.
      KdsItemView(
        name: 'French Fries',
        quantity: 2,
        modifiers: ['Extra cheese ×2', 'No salt'],
        note: 'Extra crispy',
      ),
      KdsItemView(name: 'Onion Rings', quantity: 1),
    ],
    status: KitchenTicketStatus.inPreparation,
  ),
  KdsTicketView(
    kitchenTicketId: 'order-104:fryer',
    stationId: 'fryer',
    items: const [KdsItemView(name: 'Falafel Plate', quantity: 1)],
    status: KitchenTicketStatus.acknowledged,
  ),
];
