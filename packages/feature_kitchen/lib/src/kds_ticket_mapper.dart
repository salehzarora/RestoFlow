import 'package:restoflow_domain/restoflow_domain.dart';

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
  static const String unassignedStation = 'unassigned';

  static List<KdsTicketView> map({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> orderItems,
    required List<Map<String, dynamic>> modifiers,
    List<Map<String, dynamic>> tables = const [],
    List<Map<String, dynamic>> serviceRounds = const [],
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
        submittedAt: _parseTimestamp(r['created_at'], r['client_created_at']),
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
    final orderInfo = <String, _OrderInfo>{};
    final pendingAckOrders = <String>{};
    for (final o in orders) {
      if (o['deleted_at'] != null) continue;
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
      final tableId = o['table_id'];
      final orderType = o['order_type'];
      final notes = o['notes'];
      // ORDER-CUSTOMER-001: the OPTIONAL customer display name (money-free pluck,
      // trimmed + empty->null). Present on the kitchen wire row because
      // app.redact_money only strips *_minor/receipt keys, not this display text.
      final customerName = o['customer_name'];
      // PSC-001D: the cancellation card's honest void time + source state —
      // money-free scalar plucks, present only on a pending-ack void.
      final voidedAtRaw = o['voided_at'];
      final voidedFromRaw = o['voided_from_status'];
      orderInfo[id] = _OrderInfo(
        status: status,
        orderType: orderType is String ? orderType : null,
        tableLabel: tableId is String ? tableLabels[tableId] : null,
        notes: notes is String && notes.isNotEmpty ? notes : null,
        customerName: customerName is String && customerName.trim().isNotEmpty
            ? customerName.trim()
            : null,
        // DESIGN-001 display-only pluck: when the order was submitted, for the
        // elapsed/urgency pill. `created_at` is the stable server insert time
        // (`updated_at` bumps on every status push and would under-report
        // age); `client_created_at` is the offline-client fallback. Still a
        // money-free pluck — timestamps only.
        submittedAt: _parseTimestamp(o['created_at'], o['client_created_at']),
        voidedAt: isPendingAckVoid && voidedAtRaw is String
            ? DateTime.tryParse(voidedAtRaw)
            : null,
        voidedFromStatus: isPendingAckVoid && voidedFromRaw is String
            ? voidedFromRaw
            : null,
        roundContextOnly: isRoundContextOnly,
      );
    }

    // Modifier option names per order_item_id (skip tombstoned modifiers).
    // A modifier row carries an integer `quantity` (>=1, default 1); when it is
    // above 1 the display string gets a '×N' suffix (name first, U+00D7 — the
    // same convention as the KDS item line). Never money.
    final modsByItem = <String, List<String>>{};
    // KITCHEN-MEAT-001: each order item's meat contributions from its selected
    // options, PRE-MULTIPLIED by the modifier units (× the item quantity is
    // applied per item below). Money-free; only options carrying meat_snapshot
    // contribute (nothing is inferred from a name/price).
    final meatByItem = <String, List<KitchenMeat>>{};
    for (final m in modifiers) {
      if (m['deleted_at'] != null) continue;
      final itemId = m['order_item_id'];
      final option = m['option_name_snapshot'];
      if (itemId is! String || option is! String) continue;
      final qtyRaw = m['quantity'];
      final qty = qtyRaw is int ? qtyRaw : int.tryParse('$qtyRaw') ?? 1;
      (modsByItem[itemId] ??= <String>[]).add(
        qty > 1 ? '$option ×$qty' : option,
      );
      final meat = KitchenMeat.tryFromJson(m['meat_snapshot']);
      if (meat != null && qty > 0) {
        (meatByItem[itemId] ??= <KitchenMeat>[]).add(
          KitchenMeat(quantity: meat.quantity * qty, unit: meat.unit),
        );
      }
    }

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
    final countContribsByWorkUnit = <String, List<KitchenCountContribution>>{};
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
      final stationRaw = it['station_id'];
      final station = stationRaw is String && stationRaw.isNotEmpty
          ? stationRaw
          : unassignedStation;
      final nameRaw = it['menu_item_name_snapshot'];
      final name = nameRaw is String ? nameRaw : '';
      final qty = it['quantity'];
      final quantity = qty is int ? qty : int.tryParse('$qty') ?? 0;
      final noteRaw = it['notes'];
      final note = noteRaw is String && noteRaw.isNotEmpty ? noteRaw : null;
      // KITCHEN-PREP-001: the item's PER-UNIT prep components (money-free
      // {name,quantity,unit}) plucked from the order_items snapshot. Tolerant
      // parse — a missing/bad value yields an empty list (no prep row).
      final prepComponents = parseKitchenPrepComponents(it['prep_snapshot']);

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
              : _ticketStatusFor(round?.status ?? info.status),
          info: info,
          roundId: roundId,
          round: round,
        ),
      );
      builder.items.add(
        KdsItemView(
          name: name,
          quantity: quantity,
          // Structured modifier lines (was: flattened into the name).
          modifiers: modsByItem[itemId] ?? const <String>[],
          note: note,
          prepComponents: prepComponents,
        ),
      );
      // KDS-ALERTS-AND-KITCHEN-COUNTS-002: accumulate this item's counted-resource
      // contributions for its OWN WORK UNIT (PSC-001C Finding 3: keyed by
      // order + round, so a round ticket never inherits the original order's
      // counts) — factor = the ordered item quantity.
      // PSC-001D: a cancellation card needs no cook-prep totals (nothing is
      // being prepared any more), so pending-ack orders contribute none.
      if (!pendingAck && quantity > 0) {
        final contribs =
            countContribsByWorkUnit['$orderId|${roundId ?? ''}'] ??=
                <KitchenCountContribution>[];
        // Per-OPTION counts (already × modifier units): label = the resource the
        // owner typed as the option's count unit (e.g. "قطع لحم").
        final itemMeat = meatByItem[itemId];
        if (itemMeat != null) {
          for (final meat in itemMeat) {
            contribs.add(
              KitchenCountContribution(
                quantity: meat.quantity,
                label: meat.unit,
                factor: quantity,
              ),
            );
          }
        }
        // Per-ITEM base counts (buns, wraps, trays, …): label = the prep
        // component's resource name (+ unit when the owner set one).
        for (final prep in prepComponents) {
          contribs.add(
            KitchenCountContribution(
              quantity: prep.quantity,
              label: _countLabel(prep),
              factor: quantity,
            ),
          );
        }
      }
    }

    // KDS-ALERTS-AND-KITCHEN-COUNTS-002 + PSC-001C Finding 3: the count totals
    // per WORK UNIT (grouped by resource label), attached below to every
    // STATION ticket of that unit — and only that unit.
    final kitchenCountsByWorkUnit = <String, List<KitchenCount>>{
      for (final entry in countContribsByWorkUnit.entries)
        entry.key: aggregateKitchenCounts(entry.value),
    };

    final tickets =
        grouped.values
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
            .toList()
          // KDS-FIFO-001: oldest submitted order first (stable id tie-break) so
          // the kitchen can trust the top of each column is the next to make.
          ..sort(KdsTicketView.compareByOldestFirst);
    return tickets;
  }

  /// Parses the submit timestamp from the wire row: `created_at` first (the
  /// stable server anchor), then `client_created_at`. Non-string / unparseable
  /// values yield null — the card then shows no elapsed pill rather than a
  /// fabricated age (DESIGN-001).
  static DateTime? _parseTimestamp(Object? createdAt, Object? clientCreatedAt) {
    if (createdAt is String) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return parsed;
    }
    if (clientCreatedAt is String) return DateTime.tryParse(clientCreatedAt);
    return null;
  }

  /// The resource label for an item-base prep component: its [name], plus the
  /// [unit] when the owner set one (e.g. "خبز" / "Fish pcs"). This is the key the
  /// whole-order counts group by, so item-base counts and modifier-option counts
  /// with the same label merge into one total.
  static String _countLabel(KitchenPrepComponent component) {
    final unit = component.unit.trim();
    return unit.isEmpty ? component.name : '${component.name} $unit';
  }

  /// Minimal order-status -> kitchen-ticket-status projection.
  static KitchenTicketStatus _ticketStatusFor(String orderStatus) {
    return switch (orderStatus) {
      'submitted' => KitchenTicketStatus.newTicket,
      'accepted' => KitchenTicketStatus.acknowledged,
      'preparing' => KitchenTicketStatus.inPreparation,
      'ready' => KitchenTicketStatus.ready,
      _ => KitchenTicketStatus.newTicket,
    };
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
  final _OrderInfo info;

  /// PSC-001C: set when this ticket is an additional service round.
  final String? roundId;
  final _RoundInfo? round;
  final List<KdsItemView> items = [];
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

/// The explicit money-free pluck of one active order's display fields.
class _OrderInfo {
  const _OrderInfo({
    required this.status,
    required this.orderType,
    required this.tableLabel,
    required this.notes,
    required this.customerName,
    required this.submittedAt,
    this.voidedAt,
    this.voidedFromStatus,
    this.roundContextOnly = false,
  });

  final String status;
  final String? orderType;
  final String? tableLabel;
  final String? notes;
  final String? customerName;
  final DateTime? submittedAt;

  /// PSC-001D: set ONLY for a pending-acknowledgement void (the red card).
  final DateTime? voidedAt;
  final String? voidedFromStatus;

  /// PSC-001C: TRUE for a SERVED parent admitted only so its still-active
  /// rounds can render — its original (already bumped) items never re-appear.
  final bool roundContextOnly;
}
