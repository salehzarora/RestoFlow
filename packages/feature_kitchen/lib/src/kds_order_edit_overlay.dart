import 'package:restoflow_domain/restoflow_domain.dart';

import 'kds_order_edit.dart';
import 'kds_row_views.dart';
import 'kds_ticket_view.dart';

// ORDER-EDIT-001C (D-043 / D-044; ORDER_EDIT_DESIGN §7.2, API_CONTRACT §4.46):
// the KDS sent-order edit overlay — a PURE post-pass over the base board the
// KdsTicketMapper built. Internal to the package; tested through
// `KdsTicketMapper.map(orderEdits: …)`.
//
// It reads the edit provenance `app.edit_order` writes (20261008170100):
//   * a retired line keeps its row (status cancelled/voided) and gains
//     removed_by_edit_id + removed_kitchen_stage;
//   * every row an edit inserts carries edit_id; remainders, continuations and
//     modify replacements also carry replaces_order_item_id; "+N" deltas and
//     added lines carry none;
//   * in-place rows keep the old line's line_position and unit; rows landing
//     in the edit's round (or an add into the original Waiting ticket) get a
//     fresh line_position (max + 1);
//   * the round an edit opened carries edit_id; a round an edit emptied is
//     voided with voided_by_edit_id; an emptied ORIGINAL unit leaves no marker
//     row (the order jumps to served), so it is detected from the items.
//
// The diff is NET against the last acknowledged state: an edit that awaits
// the kitchen's "Got it" (P) is overlaid; acknowledged edits are history,
// except the permanent provenance of KDS-channel edits (K) — the round an edit
// opened ("Change N · Round M") and a REMAKE's "instead of" line. Paper-channel
// edits, voided / cancelled / draft orders and direct_print orders get nothing
// (a void supersedes every pending edit; it is governed only by the PSC-001D
// red card). Unknown edit ids (a page still draining) are tolerated: no
// overlay until the edit row arrives. Counts are never touched. Every value is
// an explicit money-free pluck (SECURITY T-003).

/// Order statuses that never get change data (§4.46: a void supersedes every
/// pending edit; cancelled and draft orders have no kitchen work).
const Set<String> _noOverlayOrderStatuses = {'voided', 'cancelled', 'draft'};

/// Item statuses that are no longer live kitchen work (the base mapper's
/// exclusion set).
const Set<String> _goneItemStatuses = {'voided', 'cancelled', 'served'};

/// Stages a standalone card can sit in (its former column).
const Set<String> _boardStages = {
  'submitted',
  'accepted',
  'preparing',
  'ready',
};

/// Applies the sent-order edit overlay to [base] (the unsorted base board) and
/// returns the board to sort: affected base tickets replaced by their overlaid
/// copies, unaffected ones unchanged (same instances), standalone change cards
/// appended. [modifiers] and [tableLabels] are the base mapper's own indexes,
/// so a retired line and a standalone header render exactly like the base.
List<KdsTicketView> applyKdsOrderEditOverlay({
  required List<KdsTicketView> base,
  required List<Map<String, dynamic>> orders,
  required List<Map<String, dynamic>> orderItems,
  required List<Map<String, dynamic>> serviceRounds,
  required List<Map<String, dynamic>> orderEdits,
  required KdsItemModifiers modifiers,
  required Map<String, String> tableLabels,
}) {
  // 1. The KDS-channel edits per order (explicit plucks; malformed rows and
  //    paper-channel edits are dropped here).
  final editsByOrder = <String, Map<String, KdsOrderEdit>>{};
  for (final row in orderEdits) {
    final edit = KdsOrderEdit.tryParse(row);
    if (edit == null || edit.channel != KdsEditChannel.kds) continue;
    final byId = editsByOrder.putIfAbsent(edit.orderId, () => {});
    final prior = byId[edit.id];
    // The row store keys rows by id, so a repeat is not expected; if one
    // appears, the acknowledged copy wins (the stamp is write-once).
    if (prior == null || (prior.ackAt == null && edit.ackAt != null)) {
      byId[edit.id] = edit;
    }
  }
  if (editsByOrder.isEmpty) return base;

  // 2. Scope: only orders that HAVE a KDS-channel edit, are present, not
  //    tombstoned, not voided/cancelled/draft and not direct_print. Pending
  //    edits are processed WHATEVER the order's other status (served and
  //    completed included), so a removal is never hidden (§4.46).
  final orderRows = <String, Map<String, dynamic>>{};
  for (final o in orders) {
    if (o['deleted_at'] != null) continue;
    final id = o['id'];
    final status = o['status'];
    if (id is! String || status is! String) continue;
    if (!editsByOrder.containsKey(id)) continue;
    if (_noOverlayOrderStatuses.contains(status)) continue;
    if (o['dispatch_mode'] == 'direct_print') continue;
    orderRows[id] = o;
  }
  if (orderRows.isEmpty) return base;

  // 3. Every round row of the scoped orders — ALL statuses (an emptied round
  //    is voided; a remake's round may since be served).
  final rounds = <String, _Round>{};
  for (final r in serviceRounds) {
    if (r['deleted_at'] != null) continue;
    final id = r['id'];
    final orderId = r['order_id'];
    if (id is! String || orderId is! String) continue;
    if (!orderRows.containsKey(orderId)) continue;
    final numRaw = r['round_number'];
    final editId = r['edit_id'];
    final voidedBy = r['voided_by_edit_id'];
    rounds[id] = _Round(
      number: numRaw is int ? numRaw : int.tryParse('$numRaw'),
      editId: editId is String ? editId : null,
      voidedByEditId: voidedBy is String ? voidedBy : null,
      submittedAt: parseKdsTimestamp(r['created_at'], r['client_created_at']),
    );
  }

  // 4. Every non-tombstoned item row of the scoped orders — live AND retired
  //    (the "was" text comes from the retired row).
  final rowsByOrder = <String, List<_Row>>{};
  for (final it in orderItems) {
    if (it['deleted_at'] != null) continue;
    final id = it['id'];
    final orderId = it['order_id'];
    if (id is! String || orderId is! String) continue;
    if (!orderRows.containsKey(orderId)) continue;
    (rowsByOrder[orderId] ??= <_Row>[]).add(_Row.pluck(it, id, orderId));
  }

  // 5. One pass per order, in a deterministic order.
  final baseByKey = {for (final t in base) t.kitchenTicketId: t};
  final overlaid = <String, KdsTicketView>{};
  final standalone = <KdsTicketView>[];
  for (final orderId in orderRows.keys.toList()..sort()) {
    final rows = rowsByOrder[orderId];
    if (rows == null) continue;
    final order = orderRows[orderId]!;
    _OrderPass(
      orderId: orderId,
      header: KdsOrderHeader.pluck(
        order,
        status: order['status'] as String,
        tableLabels: tableLabels,
      ),
      edits: editsByOrder[orderId]!,
      rows: rows,
      rounds: rounds,
      modifiers: modifiers,
    ).run(baseByKey: baseByKey, overlaid: overlaid, standalone: standalone);
  }
  if (overlaid.isEmpty && standalone.isEmpty) return base;
  return [
    for (final t in base) overlaid[t.kitchenTicketId] ?? t,
    ...standalone,
  ];
}

/// The overlay of ONE order: its KDS-channel edits ([edits], by id), item
/// rows (live and retired) and the shared round index.
class _OrderPass {
  _OrderPass({
    required this.orderId,
    required this.header,
    required Map<String, KdsOrderEdit> edits,
    required List<_Row> rows,
    required this.rounds,
    required this.modifiers,
  }) : kdsEdits = edits,
       pending = {
         for (final e in edits.values)
           if (e.awaitsKitchenAck) e.id: e,
       },
       rows = [...rows]..sort((a, b) => a.id.compareTo(b.id));

  final String orderId;
  final KdsOrderHeader header;

  /// K: every KDS-channel edit of the order (pending or not).
  final Map<String, KdsOrderEdit> kdsEdits;

  /// P: the edits still awaiting the kitchen's "Got it".
  final Map<String, KdsOrderEdit> pending;

  /// The order's item rows, sorted by id (determinism).
  final List<_Row> rows;
  final Map<String, _Round> rounds;
  final KdsItemModifiers modifiers;

  late final Map<String, _Row> _byId = {for (final r in rows) r.id: r};

  /// replaces_order_item_id -> the rows that replace it (sorted by id).
  late final Map<String, List<_Row>> _children = () {
    final out = <String, List<_Row>>{};
    for (final r in rows) {
      final parent = r.replaces;
      if (parent != null) (out[parent] ??= <_Row>[]).add(r);
    }
    return out;
  }();

  final Map<String, KdsItemView> _views = {};

  /// The money-free view of [r] (built once; identical to a live line).
  KdsItemView _view(_Row r) => _views[r.id] ??= kdsItemViewFromRow(
    r.raw,
    itemId: r.id,
    modifiers: modifiers,
  );

  /// written(x): the row was inserted by a PENDING edit.
  bool _written(_Row x) => x.editId != null && pending.containsKey(x.editId);

  /// retired(x): the row was retired by a PENDING edit.
  bool _retired(_Row x) =>
      x.removedBy != null && pending.containsKey(x.removedBy);

  /// baseline(x): the row belongs to the last ACKNOWLEDGED state — not written
  /// by a pending edit, and either still live (never retired) or retired by a
  /// pending edit (so it was there before the unconfirmed change).
  bool _baseline(_Row x) =>
      !_written(x) && (x.removedBy == null ? x.live : _retired(x));

  /// root(y): walk replaces_order_item_id (cycle-safe) to the first baseline
  /// row — intermediate rows of a chain of pending edits collapse into one
  /// "was". Null when the chain never reaches a baseline row.
  _Row? _root(_Row y) {
    final seen = <String>{y.id};
    var cur = _byId[y.replaces];
    while (cur != null && seen.add(cur.id)) {
      if (_baseline(cur)) return cur;
      cur = _byId[cur.replaces];
    }
    return null;
  }

  /// Every LIVE row that (transitively) replaces [x].
  List<_Row> _liveDescendants(_Row x) {
    final out = <_Row>[];
    final seen = <String>{x.id};
    final queue = <_Row>[x];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      for (final child in _children[node.id] ?? const <_Row>[]) {
        if (!seen.add(child.id)) continue;
        if (child.live) out.add(child);
        queue.add(child);
      }
    }
    return out;
  }

  void run({
    required Map<String, KdsTicketView> baseByKey,
    required Map<String, KdsTicketView> overlaid,
    required List<KdsTicketView> standalone,
  }) {
    final unitRows = <String, List<_Row>>{};
    for (final r in rows) {
      (unitRows[r.unitKey] ??= <_Row>[]).add(r);
    }

    // MARKS (pending only) on every live row a pending edit wrote.
    final marks = <String, _Mark>{};
    for (final y in rows) {
      if (!y.live || !_written(y)) continue;
      final number = pending[y.editId]!.editNumber;
      final root = _root(y);
      if (root != null) {
        // A remainder / continuation / replacement: CHANGED in place, or a
        // REMAKE when it landed in another unit (the edit's round).
        marks[y.id] = _Mark(
          root.unitKey == y.unitKey
              ? KdsEditLineMark.changed
              : KdsEditLineMark.remake,
          root,
          number,
        );
        continue;
      }
      if (y.linePosition > 0) {
        final samePosition = [
          for (final r in unitRows[y.unitKey]!)
            if (_baseline(r) && r.linePosition == y.linePosition) r,
        ];
        // A "+N" delta written next to the kept line it extends.
        if (samePosition.any((r) => r.removedBy == null)) {
          marks[y.id] = _Mark(KdsEditLineMark.increased, null, number);
          continue;
        }
        // A modify's excess dishes: no replaces pointer, but the old line's
        // position — grouped with the line they changed.
        final retiredSame = samePosition.where(_retired).firstOrNull;
        if (retiredSame != null) {
          marks[y.id] = _Mark(KdsEditLineMark.changed, retiredSame, number);
          continue;
        }
      }
      marks[y.id] = _Mark(KdsEditLineMark.added, null, number);
    }
    // PERMANENT provenance (K, pending or acknowledged): a live round row whose
    // replaced line sits in another unit is a REMAKE "instead of" that line.
    for (final y in rows) {
      if (!y.live || marks.containsKey(y.id) || y.roundId == null) continue;
      final edit = kdsEdits[y.editId];
      final parent = _byId[y.replaces];
      if (edit == null || parent == null || parent.unitKey == y.unitKey) {
        continue;
      }
      marks[y.id] = _Mark(KdsEditLineMark.remake, parent, edit.editNumber);
    }

    // REMOVED lines: a pending-retired row that is not already shown as the
    // "was" of a live line of its own unit, and is not an intermediate of a
    // pending chain whose live descendant shows it.
    final shownAsWas = <String>{
      for (final entry in marks.entries)
        if (entry.value.was != null &&
            entry.value.was!.unitKey == _byId[entry.key]!.unitKey)
          entry.value.was!.id,
    };
    final removedByUnit = <String, List<KdsRemovedLine>>{};
    for (final x in rows) {
      if (!_retired(x) || shownAsWas.contains(x.id)) continue;
      final live = _liveDescendants(x);
      if (_written(x) && live.isNotEmpty) continue;
      // An intermediate of a chain of pending edits whose root (the
      // acknowledged line) is in the same unit: the root already reports the
      // net change — as REMOVED, or as the "was" of a live line — so the
      // intermediate is never listed a second time.
      if (_written(x) && _root(x)?.unitKey == x.unitKey) continue;
      int? remadeIn;
      for (final d in live) {
        if (d.unitKey == x.unitKey || d.roundId == null) continue;
        final n = rounds[d.roundId]?.number;
        if (n != null && (remadeIn == null || n < remadeIn)) remadeIn = n;
      }
      (removedByUnit[x.unitKey] ??= <KdsRemovedLine>[]).add(
        KdsRemovedLine(
          line: _view(x),
          editNumber: pending[x.removedBy]!.editNumber,
          removedKitchenStage: x.removedStage,
          remadeInRoundNumber: remadeIn,
        ),
      );
    }

    // HEADER: T(k) = the pending edits that wrote, retired, opened or emptied
    // the unit.
    final touching = <String, Set<String>>{};
    for (final r in rows) {
      if (_written(r)) (touching[r.unitKey] ??= <String>{}).add(r.editId!);
      if (_retired(r)) (touching[r.unitKey] ??= <String>{}).add(r.removedBy!);
    }
    for (final entry in unitRows.entries) {
      final round = rounds[entry.value.first.roundId];
      if (round == null) continue;
      for (final id in [round.editId, round.voidedByEditId]) {
        if (id != null && pending.containsKey(id)) {
          (touching[entry.key] ??= <String>{}).add(id);
        }
      }
    }
    final orderPending = [for (final e in pending.values) e.editNumber]..sort();

    for (final unitKey in unitRows.keys.toList()..sort()) {
      final unit = unitRows[unitKey]!;
      final roundId = unit.first.roundId;
      final round = roundId == null ? null : rounds[roundId];
      final openedBy = kdsEdits[round?.editId]?.editNumber;
      final touchedBy = touching[unitKey];
      final pendingEdits = touchedBy == null
          ? const <KdsOrderEdit>[]
          : ([for (final id in touchedBy) pending[id]!]..sort(_byNumber));
      final removed = _sortRemoved(
        removedByUnit[unitKey] ?? const <KdsRemovedLine>[],
      );

      final baseTicket = baseByKey[unitKey];
      if (baseTicket != null) {
        final anyMarked = baseTicket.items.any(
          (i) => marks.containsKey(i.orderItemId),
        );
        if (pendingEdits.isEmpty && openedBy == null && !anyMarked) continue;
        overlaid[unitKey] = baseTicket.withEditOverlay(
          change: pendingEdits.isEmpty
              ? null
              : KdsTicketChange(
                  pendingEdits: pendingEdits,
                  removed: removed,
                  orderPendingEditNumbers: orderPending,
                ),
          openedByEditNumber: openedBy,
          items: _sortLines([
            for (final item in baseTicket.items) _marked(item, marks),
          ]),
        );
        continue;
      }

      // STANDALONE: a unit a pending edit touched that has no live base
      // ticket — an emptied round, an emptied original unit (served jump), or
      // an order that left the board while the change is unconfirmed.
      if (pendingEdits.isEmpty) continue;
      final retiredRows = unit.where(_retired).toList();
      // A reduce remainder or a modify continuation that the server wrote in
      // place in a served unit (the only rows it writes there) is a copy of
      // finished food, not kitchen work.
      final liveWritten = unit.any(
        (r) =>
            r.live &&
            _written(r) &&
            (_root(r) ?? _byId[r.replaces])?.removedStage != 'served',
      );
      // Finished food only (every pending removal was already served): there
      // is no kitchen work to tell about.
      if (!liveWritten &&
          retiredRows.every((r) => r.removedStage == 'served')) {
        continue;
      }
      _Row? latestRetired;
      for (final r in retiredRows) {
        if (latestRetired == null ||
            pending[r.removedBy]!.editNumber >
                pending[latestRetired.removedBy]!.editNumber) {
          latestRetired = r;
        }
      }
      final stage = latestRetired?.removedStage;
      final formerStage = stage != null && _boardStages.contains(stage)
          ? stage
          : null;
      standalone.add(
        KdsTicketView(
          kitchenTicketId: unitKey,
          stationId: unit.first.station,
          items: _sortLines([
            for (final r in unit)
              if (r.live && marks.containsKey(r.id)) _marked(_view(r), marks),
          ]),
          // Its former column; an unknown stage fails safe to New (the
          // PSC-001D red-card precedent).
          status: kdsTicketStatusFor(formerStage ?? ''),
          orderId: orderId,
          orderNumber: displayOrderCode(orderId),
          orderType: header.orderType,
          tableLabel: header.tableLabel,
          customerName: header.customerName,
          customerPhone: header.customerPhone,
          notes: header.notes,
          submittedAt: roundId == null
              ? header.submittedAt
              : round?.submittedAt,
          roundId: roundId,
          roundNumber: round?.number,
          change: KdsTicketChange(
            pendingEdits: pendingEdits,
            removed: removed,
            standalone: true,
            emptied: !unit.any((r) => r.live),
            formerStage: formerStage,
            orderPendingEditNumbers: orderPending,
          ),
          openedByEditNumber: openedBy,
        ),
      );
    }
  }

  /// [item] with its mark applied (unchanged when it carries none).
  KdsItemView _marked(KdsItemView item, Map<String, _Mark> marks) {
    final mark = marks[item.orderItemId];
    if (mark == null) return item;
    final was = mark.was;
    return item.withEdit(
      mark: mark.mark,
      was: was == null ? null : _view(was),
      editNumber: mark.editNumber,
    );
  }
}

int _byNumber(KdsOrderEdit a, KdsOrderEdit b) {
  final byNumber = a.editNumber.compareTo(b.editNumber);
  return byNumber != 0 ? byNumber : a.id.compareTo(b.id);
}

/// The lines of an overlaid card in menu print order with a DETERMINISTIC
/// tie-break: in-place rows share their old line's position, so the kept line
/// comes first, then the rows by edit number, then by row id — never by the
/// wire order the rows happened to arrive in.
List<KdsItemView> _sortLines(List<KdsItemView> lines) {
  final byId = [...lines]
    ..sort((a, b) => (a.orderItemId ?? '').compareTo(b.orderItemId ?? ''));
  return sortByMenuPrintOrder(
    byId,
    (l) => [
      l.categoryDisplayOrder,
      l.itemDisplayOrder,
      l.linePosition,
      l.editNumber ?? 0,
    ],
  );
}

/// Removed lines in menu print order (same deterministic tie-break).
List<KdsRemovedLine> _sortRemoved(List<KdsRemovedLine> removed) {
  if (removed.isEmpty) return const <KdsRemovedLine>[];
  final byId = [...removed]
    ..sort(
      (a, b) => (a.line.orderItemId ?? '').compareTo(b.line.orderItemId ?? ''),
    );
  return sortByMenuPrintOrder(
    byId,
    (r) => [
      r.line.categoryDisplayOrder,
      r.line.itemDisplayOrder,
      r.line.linePosition,
      r.editNumber,
    ],
  );
}

/// The explicit money-free provenance pluck of one `order_items` row.
class _Row {
  _Row._({
    required this.id,
    required this.raw,
    required this.unitKey,
    required this.station,
    required this.roundId,
    required this.live,
    required this.editId,
    required this.removedBy,
    required this.replaces,
    required this.removedStage,
    required this.linePosition,
  });

  factory _Row.pluck(Map<String, dynamic> it, String id, String orderId) {
    final station = kdsStationOf(it);
    final roundRaw = it['service_round_id'];
    final roundId = roundRaw is String ? roundRaw : null;
    final status = it['status'];
    final editId = it['edit_id'];
    final removedBy = it['removed_by_edit_id'];
    final replaces = it['replaces_order_item_id'];
    final stage = it['removed_kitchen_stage'];
    return _Row._(
      id: id,
      raw: it,
      // The base mapper's ticket key: one card per (order, station[, round]).
      unitKey: roundId == null
          ? '$orderId:$station'
          : '$orderId:$station:r$roundId',
      station: station,
      roundId: roundId,
      live: !(status is String && _goneItemStatuses.contains(status)),
      editId: editId is String ? editId : null,
      removedBy: removedBy is String ? removedBy : null,
      replaces: replaces is String ? replaces : null,
      removedStage: stage is String ? stage : null,
      linePosition: menuPrintOrderInt(it['line_position']),
    );
  }

  final String id;

  /// The source row — only ever handed to [kdsItemViewFromRow] (explicit
  /// money-free plucks); never exposed.
  final Map<String, dynamic> raw;
  final String unitKey;
  final String station;
  final String? roundId;
  final bool live;
  final String? editId;
  final String? removedBy;
  final String? replaces;
  final String? removedStage;
  final int linePosition;
}

/// The explicit money-free pluck of one service round (any status).
class _Round {
  const _Round({
    required this.number,
    required this.editId,
    required this.voidedByEditId,
    required this.submittedAt,
  });

  final int? number;
  final String? editId;
  final String? voidedByEditId;
  final DateTime? submittedAt;
}

/// One live line's edit mark.
class _Mark {
  const _Mark(this.mark, this.was, this.editNumber);

  final KdsEditLineMark mark;
  final _Row? was;
  final int editNumber;
}
