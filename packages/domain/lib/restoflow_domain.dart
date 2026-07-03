/// RestoFlow domain package - entity & value-object foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package will own entities, value
/// objects, the PROPOSED state enumerations (DECISION D-018), and pure domain
/// rules. RF-011 provides only a neutral base abstraction; concrete entities
/// and state enums land in later tickets (orgs/restaurants/branches in RF-014,
/// menu in RF-030, order/payment state machines in RF-032).
///
/// MONEY: the integer minor-unit money TYPE is owned by `packages/money`
/// (ticket RF-036), NOT this package (DECISION D-007; ARCHITECTURE section 3).
/// Domain entities will hold money-typed fields backed by that package.
///
/// RF-031 adds the in-memory POS cart / draft-order model (`src/cart/`): a
/// `Cart` aggregate of `CartLine`s with immutable price snapshots (D-008) and
/// integer minor-unit totals (D-007). It is not persisted, submitted, or synced.
///
/// RF-032 adds the in-memory order state machines (`src/order/`): `LocalOrder`
/// (submitted from a `Cart`) + `LocalOrderItem`, the `OrderStatus`/
/// `OrderItemStatus`/`OrderType` enumerations (D-018), and the table-driven
/// transition validators. Still in-memory only — no persistence/outbox/sync.
///
/// RF-033 adds the pure-Dart kitchen routing (`src/kitchen/`): `KitchenRouter`
/// routes a `LocalOrder`'s active items to stations per `KitchenRoutingRules`,
/// producing a deterministic in-memory `KitchenRoutingResult` (one
/// `KitchenTicket` per station + flagged `UnroutableOrderItem`s). No status/
/// state machine (RF-034), no persistence/backend.
///
/// RF-034 adds the pure-Dart kitchen STATE MACHINES (`src/kitchen/`):
/// `KitchenTicketStatus`/`KitchenStationItemStatus` (D-018), the table-driven
/// `KitchenTicketStateMachine` (incl. the audited recall action returning an
/// in-memory `RecallAuditEvent` placeholder) and `KitchenStationItemStateMachine`.
/// Still local-only — no persistence/backend/real audit write.
///
/// RF-035 adds the pure-Dart table management (`src/table/`): `DiningTable`,
/// `OrderPlacement` (dine-in-with-table / takeaway, reusing RF-032 `OrderType`),
/// `TablePolicy`, and `TableAssignmentService` (tenant-checked assignment + the
/// one-open-dine-in-per-table guard). In-memory only — no persistence/backend.
///
/// RF-037 adds the pure-Dart shift + cash-drawer-session machines (`src/shift/`):
/// `ShiftStatus`/`CashDrawerSessionStatus` (D-018), the table-driven
/// `ShiftStateMachine`/`CashDrawerSessionStateMachine`, the `Shift`/
/// `CashDrawerSession` aggregates with integer minor-unit variance
/// (`counted - expected`), and `ShiftCashDrawerBinding` (one drawer bound to one
/// shift). In-memory only — no persistence/backend/audit; no money dependency.
library;

export 'src/cart/cart.dart';
export 'src/cart/cart_exceptions.dart';
export 'src/cart/cart_line.dart';
export 'src/cart/cart_snapshots.dart';
export 'src/entity.dart';
export 'src/kitchen/kitchen_router.dart';
export 'src/kitchen/kitchen_routing_result.dart';
export 'src/kitchen/kitchen_routing_rules.dart';
export 'src/kitchen/kitchen_state_exceptions.dart';
export 'src/kitchen/kitchen_station_item.dart';
export 'src/kitchen/kitchen_station_item_state_machine.dart';
export 'src/kitchen/kitchen_station_item_status.dart';
export 'src/kitchen/kitchen_ticket.dart';
export 'src/kitchen/kitchen_ticket_state_machine.dart';
export 'src/kitchen/kitchen_ticket_status.dart';
export 'src/kitchen/recall_audit_event.dart';
export 'src/order/display_order_code.dart';
export 'src/order/local_order.dart';
export 'src/order/local_order_item.dart';
export 'src/order/order_action_authorization.dart';
export 'src/order/order_exceptions.dart';
export 'src/order/order_item_status.dart';
export 'src/order/order_state_machine.dart';
export 'src/order/order_status.dart';
export 'src/order/order_type.dart';
export 'src/shift/cash_drawer_session.dart';
export 'src/shift/cash_drawer_session_state_machine.dart';
export 'src/shift/cash_drawer_session_status.dart';
export 'src/shift/shift.dart';
export 'src/shift/shift_cash_drawer_binding.dart';
export 'src/shift/shift_exceptions.dart';
export 'src/shift/shift_state_machine.dart';
export 'src/shift/shift_status.dart';
export 'src/table/dining_table.dart';
export 'src/table/order_placement.dart';
export 'src/table/table_assignment_service.dart';
export 'src/table/table_exceptions.dart';
export 'src/table/table_policy.dart';
