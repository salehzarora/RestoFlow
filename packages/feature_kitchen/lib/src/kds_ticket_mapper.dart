import 'package:restoflow_domain/restoflow_domain.dart';

import 'kds_order_edit_overlay.dart';
import 'kds_row_views.dart';
import 'kds_ticket_view.dart';

/// Maps raw `app.sync_pull` rows (orders / order_items / order_item_modifiers)
/// to KDS ticket view models (RF-063, approved decision A4 — minimal mapping).
///
/// Deliberately MINIMAL: it groups active order items by `(order_id,
/// station_id)`, derives the ticket status from the parent order's status, and
/// attaches modifier option names to the item label. It does NOT run the full
/// `KitchenRouter`/menu/station-routing fidelity (A4) and — critically — it
/// reads NO money field (`*_minor`, totals, prices). The kitchen redaction
/// (SECURITY T-003) is therefore not relied upon for correctness here: the KDS
/// simply never needs money.
class KdsTicketMapper {
  const KdsTicketMapper._();

  /// Order statuses whose items are shown on the KDS (active kitchen work).
  /// `served`/`completed`/`cancelled`/`voided`/`draft` are excluded.
  static const Set<String> _activeOrderStatuses = {
    'submitted',
    'accepted',
    'preparing',
    'ready',
  };

  /// Item statuses excluded from a ticket (already gone / dropped).
  static const Set<String> _excludedItemStatuses = {
    'voided',
    'cancelled',
    'served',
  };

  /// Station bucket for an item with no `station_id` (routing not yet assigned).
  static const String unassignedStation = kKdsUnassignedStation;

  /// ORDER-EDIT-001C: [orderEdits] are the pulled `order_edits` rows. Empty
  /// (the default) returns exactly the pre-edit board; otherwise the
  /// sent-order edit overlay (change headers, line marks, removed lines and
  /// standalone change cards) is applied before the FIFO sort.
  static List<KdsTicketView> map({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> orderItems,
    required List<Map<String, dynamic>> modifiers,
    List<Map<String, dynamic>> tables = const [],
    List<Map<String, dynamic>> serviceRounds = const [],
    List<Map<String, dynamic>> orderEdits = const [],
  }) {
    // Dining-table labels (tables entity, money-free): id -> label.
    final tableLabels = <String, String>{};
    for (final t in tables) {
      if (t['deleted_at'] != null) continue;
      final id = t['id'];
      final label = t['label'];
      if (id is! String || label is! String) continue;
      tableLabels[id] = label;
    }

    // PSC-001C: ACTIVE service rounds ("Addition / Round N") — each becomes a
    // SEPARATE ticket carrying the ROUND's own status and submit time. A
    // served or voided round leaves the board exactly like a served/voided
    // order (its ready history is server-side truth, not board state). Rounds
    // are money-free rows by schema; explicit scalar plucks only (T-003).
    const activeRoundStatuses = {'submitted', 'accepted', 'preparing', 'ready'};
    final roundInfo = <String, _RoundInfo>{};
    final ordersWithActiveRounds = <String>{};
    for (final r in serviceRounds) {
      if (r['deleted_at'] != null) continue;
      final id = r['id'];
      final roundOrderId = r['order_id'];
      final roundStatus = r['status'];
      if (id is! String || roundOrderId is! String || roundStatus is! String) {
        continue;
      }
      if (!activeRoundStatuses.contains(roundStatus)) continue;
      final numRaw = r['round_number'];
      roundInfo[id] = _RoundInfo(
        orderId: roundOrderId,
        status: roundStatus,
        roundNumber: numRaw is int ? numRaw : int.tryParse('$numRaw'),
        submittedAt: parseKdsTimestamp(r['created_at'], r['client_created_at']),
      );
      ordersWithActiveRounds.add(roundOrderId);
    }

    // Active orders: not tombstoned, kitchen-relevant status. An EXPLICIT
    // money-free pluck per order (status, type, table, notes) — never the raw
    // row (T-003: money keys exist on the wire for non-kitchen roles).
    //
    // PSC-001D: a VOIDED order the kitchen must still acknowledge is the ONE
    // deliberate exception to the active-status filter — it stays on the board
    // as a red cancellation card until app.kitchen_ack_void clears it
    // (server-authoritative: voided + kitchen_ack_required + no kitchen_ack_at
    // yet). An acknowledged void, a served-source void (no acknowledgement
    // required) and every historical/ordinary voided or cancelled order remain
    // EXCLUDED exactly as before.
    final orderInfo = <String, KdsOrderHeader>{};
    final pendingAckOrders = <String>{};
    for (final o in orders) {
      if (o['deleted_at'] != null) continue;
      // KITCHEN-PRINT-DUAL-001C: a direct_print order is dispatched to the kitchen
      // via the POS printer (no KDS device). It is authoritatively routed OUT of
      // the KDS active workflow (server-side it rests at `served`); exclude it from
      // the active board REGARDLESS of status, so it never shows as an actionable
      // ticket, never accumulates an open local ticket, and never contributes to
      // the active/kitchen counts. Absent/'kds' = the normal workflow.
      if (o['dispatch_mode'] == 'direct_print') continue;
      final id = o['id'];
      final status = o['status'];
      if (id is! String || status is! String) continue;
      final isPendingAckVoid =
          status == 'voided' &&
          o['kitchen_ack_required'] == true &&
          o['kitchen_ack_at'] == null;
      // PSC-001C: a SERVED parent whose additional round is still with the
      // kitchen is admitted for ROUND TICKETS ONLY — its original items never
      // return to the board (they were already bumped with the order).
      final isRoundContextOnly =
          !_activeOrderStatuses.contains(status) &&
          !isPendingAckVoid &&
          status == 'served' &&
          ordersWithActiveRounds.contains(id);
      if (!_activeOrderStatuses.contains(status) &&
          !isPendingAckVoid &&
          !isRoundContextOnly) {
        continue;
      }
      if (isPendingAckVoid) pendingAckOrders.add(id);
      // ORDER-EDIT-001C: the explicit money-free header pluck (table, type,
      // notes, customer, submit time, PSC-001D void provenance) is shared with
      // the edit overlay — kds_row_views.dart.
      orderInfo[id] = KdsOrderHeader.pluck(
        o,
        status: status,
        tableLabels: tableLabels,
        isPendingAckVoid: isPendingAckVoid,
        roundContextOnly: isRoundContextOnly,
      );
    }

    // Modifier option names (+ meat contributions) per order_item_id, in menu
    // print order — ORDER-EDIT-001C: built by the shared kds_row_views.dart so
    // the edit overlay renders retired "was" lines with the same text.
    final itemModifiers = KdsItemModifiers.fromRows(modifiers);
    final meatByItem = itemModifiers.meatByItem;

    // Group active items into (order, station) tickets.
    final grouped = <String, _TicketBuilder>{};
    // KDS-ALERTS-AND-KITCHEN-COUNTS-002 + PSC-001C correction (Finding 3):
    // count contributions are keyed by the WORK UNIT — the initial submission
    // (order, NO round) or one service round (order, round) — unified across
    // BOTH the modifier-option counts (patties, …) AND the item-base counts
    // (buns, …). Still aggregated across ALL of the work unit's STATIONS (the
    // top-of-ticket summary is the total that unit needs), but NEVER across
    // work units: a Round-2 ticket must not display the original order's
    // counts as if they were new work. Money-free; owner config only.
    final countItemsByWorkUnit = <String, List<KitchenCountItemInput>>{};
    for (final it in orderItems) {
      if (it['deleted_at'] != null) continue;
      final itemId = it['id'];
      final orderId = it['order_id'];
      if (itemId is! String || orderId is! String) continue;
      final info = orderInfo[orderId];
      if (info == null) continue; // parent not active
      // PSC-001D: the pending-ack CANCELLATION card deliberately keeps its
      // (now voided) items visible — the kitchen must see WHAT was canceled.
      // The bypass is scoped to exactly that card; every normal ticket keeps
      // the exclusion, so ordinary voided/cancelled/served items never leak
      // back onto working cards.
      final pendingAck = pendingAckOrders.contains(orderId);
      // ORDER-EDIT-001C (§4.46 voided-order rule): the red card shows what the
      // order HAD when it was voided — a line an edit already retired was
      // never part of it, so it stays off the card. Round items and live
      // edit-written lines are kept.
      if (pendingAck && it['removed_by_edit_id'] != null) continue;
      // PSC-001C: round membership routes the item to its OWN ticket. On a
      // pending-ack cancellation the round items stay on the ORDER-level red
      // card (the kitchen sees everything that was canceled). On a live order
      // an item of a non-active (served/voided) round leaves the board, and a
      // served round-context-only parent never re-shows its original items.
      final roundIdRaw = it['service_round_id'];
      final roundId = !pendingAck && roundIdRaw is String ? roundIdRaw : null;
      _RoundInfo? round;
      if (roundId != null) {
        round = roundInfo[roundId];
        if (round == null) continue; // round served/voided/unknown -> off board
      } else if (!pendingAck && info.roundContextOnly) {
        continue; // original items of a served parent stay bumped
      }
      final itemStatus = it['status'];
      if (!pendingAck &&
          itemStatus is String &&
          _excludedItemStatuses.contains(itemStatus)) {
        continue;
      }
      final station = kdsStationOf(it);
      // ORDER-EDIT-001C: the money-free item view (name, quantity, modifiers,
      // note, prep, MENU-ORDER-001 print keys) — shared with the edit overlay
      // so a retired "was" line renders exactly like this live line.
      final view = kdsItemViewFromRow(
        it,
        itemId: itemId,
        modifiers: itemModifiers,
      );
      final quantity = view.quantity;
      final prepComponents = view.prepComponents;

      // PSC-001C: a round item builds a SEPARATE per-round ticket keyed by
      // (order, station, round); the round's OWN status drives the column.
      final key = round == null
          ? '$orderId:$station'
          : '$orderId:$station:r$roundId';
      final builder = grouped.putIfAbsent(
        key,
        () => _TicketBuilder(
          kitchenTicketId: key,
          stationId: station,
          orderId: orderId,
          // PSC-001D: a pending-ack void renders as the CANCELLED ticket (red
          // card, acknowledge-only); normal orders keep the status projection —
          // PSC-001C round tickets project from the ROUND row instead.
          status: pendingAck
              ? KitchenTicketStatus.cancelled
              : kdsTicketStatusFor(round?.status ?? info.status),
          info: info,
          roundId: roundId,
          round: round,
        ),
      );
      builder.items.add(view);
      // KDS-ALERTS-AND-KITCHEN-COUNTS-002: accumulate this item's counted-resource
      // contribution for its OWN WORK UNIT (PSC-001C Finding 3: keyed by
      // order + round, so a round ticket never inherits the original order's
      // counts). KITCHEN-PRINT-DUAL-001B: build the SHARED neutral
      // [KitchenCountItemInput] — the per-OPTION meat counts (meatByItem, already
      // × modifier units) and the per-ITEM prep counts — and let the SHARED
      // [aggregateOrderKitchenCounts] apply factor = the ordered item quantity,
      // exactly as the POS direct kitchen print does. No second aggregation.
      // PSC-001D: a cancellation card needs no cook-prep totals (nothing is
      // being prepared any more), so pending-ack orders contribute none.
      if (!pendingAck && quantity > 0) {
        (countItemsByWorkUnit['$orderId|${roundId ?? ''}'] ??=
                <KitchenCountItemInput>[])
            .add(
              KitchenCountItemInput(
                quantity: quantity,
                meats: meatByItem[itemId] ?? const <KitchenMeat>[],
                prepComponents: prepComponents,
                // 017 (Codex MEDIUM #4): the SAME menu print-order keys the
                // ticket's item lines are sorted by. The wire delivers
                // order_items in (updated_at, id) order — arbitrary within one
                // order — so without these the KDS could aggregate the same
                // totals in a different ROW order than the POS/spool.
                categoryDisplayOrder: view.categoryDisplayOrder,
                itemDisplayOrder: view.itemDisplayOrder,
                linePosition: view.linePosition,
              ),
            );
      }
    }

    // KDS-ALERTS-AND-KITCHEN-COUNTS-002 + PSC-001C Finding 3: the count totals
    // per WORK UNIT (grouped by resource label), attached below to every
    // STATION ticket of that unit — and only that unit. The SHARED aggregator is
    // the single source of truth for both the KDS and the POS direct print.
    final kitchenCountsByWorkUnit = <String, List<KitchenCount>>{
      for (final entry in countItemsByWorkUnit.entries)
        entry.key: aggregateOrderKitchenCounts(entry.value),
    };

    // MENU-ORDER-001: order each ticket's items by the shared canonical print
    // order — category display order -> item display order -> line_position ->
    // input index — so the KDS ticket + reprint print in the SAME Dashboard-
    // configured order as the cashier receipt, regardless of the (updated_at, id)
    // wire order the rows arrived in. Stable: whole items move, so each item's
    // modifiers/prep/note stay attached; legacy 0 snapshots fall back to
    // line_position + wire order (a partially-migrated order never scrambles).
    for (final b in grouped.values) {
      b.items = sortByMenuPrintOrder(
        b.items,
        (it) => [it.categoryDisplayOrder, it.itemDisplayOrder, it.linePosition],
      );
    }

    final tickets = grouped.values
        .map(
          (b) => KdsTicketView(
            kitchenTicketId: b.kitchenTicketId,
            stationId: b.stationId,
            items: b.items,
            status: b.status,
            orderId: b.orderId,
            // The SAME display code the POS shows (shared derivation).
            orderNumber: displayOrderCode(b.orderId),
            orderType: b.info.orderType,
            tableLabel: b.info.tableLabel,
            customerName: b.info.customerName,
            customerPhone: b.info.customerPhone,
            notes: b.info.notes,
            // PSC-001C: a round ticket's honest FIFO/elapsed anchor is the
            // ROUND's own submission time, not the parent order's.
            submittedAt: b.round?.submittedAt ?? b.info.submittedAt,
            // KDS-ALERTS-AND-KITCHEN-COUNTS-002 + PSC-001C Finding 3: the
            // unified count totals of THIS ticket's own work unit
            // (patties + buns + …) shown at the top. Money-free.
            kitchenCounts:
                kitchenCountsByWorkUnit['${b.orderId}|${b.roundId ?? ''}'] ??
                const <KitchenCount>[],
            // PSC-001D: cancellation provenance for the red card (null on
            // every normal ticket).
            voidedAt: b.info.voidedAt,
            voidedFromStatus: b.info.voidedFromStatus,
            // PSC-001C: round identity for "Addition · Round N" + the
            // order.round_status action target. Null on original tickets.
            roundId: b.roundId,
            roundNumber: b.round?.roundNumber,
          ),
        )
        .toList();
    // ORDER-EDIT-001C (D-044): the sent-order edit overlay — a SEPARATE pure
    // post-pass (kds_order_edit_overlay.dart). With no edit rows the base
    // board is returned untouched; otherwise affected cards get their change
    // header / line marks / removed lines, and standalone change cards are
    // appended. Grouping, counts and the one-card-per-work-unit rule are
    // unchanged; the FIFO sort below runs over the union.
    final board = orderEdits.isEmpty
        ? tickets
        : applyKdsOrderEditOverlay(
            base: tickets,
            orders: orders,
            orderItems: orderItems,
            serviceRounds: serviceRounds,
            orderEdits: orderEdits,
            modifiers: itemModifiers,
            tableLabels: tableLabels,
          );
    // KDS-FIFO-001: oldest submitted order first (stable id tie-break) so
    // the kitchen can trust the top of each column is the next to make.
    return board..sort(KdsTicketView.compareByOldestFirst);
  }
}

class _TicketBuilder {
  _TicketBuilder({
    required this.kitchenTicketId,
    required this.stationId,
    required this.orderId,
    required this.status,
    required this.info,
    this.roundId,
    this.round,
  });

  final String kitchenTicketId;
  final String stationId;
  final String orderId;
  final KitchenTicketStatus status;
  final KdsOrderHeader info;

  /// PSC-001C: set when this ticket is an additional service round.
  final String? roundId;
  final _RoundInfo? round;
  // Reassigned once, after collection, by the shared menu-print-order sort.
  List<KdsItemView> items = [];
}

/// PSC-001C: the explicit money-free pluck of one ACTIVE service round.
class _RoundInfo {
  const _RoundInfo({
    required this.orderId,
    required this.status,
    required this.roundNumber,
    required this.submittedAt,
  });

  final String orderId;
  final String status;
  final int? roundNumber;
  final DateTime? submittedAt;
}
