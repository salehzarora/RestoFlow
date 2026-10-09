/// ORDER-EDIT-001F — the POS's HAND-BUILT paper change slip (design §7.3,
/// PRINTERS_AND_HARDWARE_SPEC §13.1 "hand-built, or decoded").
///
/// `app.edit_order` answers a paper edit with `kitchen_dispatch {id,
/// claim_expires_at}` only — the slip's content is NOT in the envelope. The
/// acting till therefore builds the [OrderChangeSlipView] itself, MIRRORING
/// `app.kitchen_dispatch_payload_order_edit` (20261008170100) field by field,
/// so its paper is byte-identical to the slip the spool would decode from the
/// server's stored payload (`orderChangeSlipViewFromKitchenDispatch`):
///
///  * every item is `app.kitchen_dispatch_item_projection` — `{qty, name,
///    note?, prep?, modifiers[{qty, name}]}` — taken from the authoritative
///    `pos_order_detail` row ([OrderEditSlipItem]) and turned into a
///    [KdsItemView] exactly like the dispatch adapter does ("name ×N" only
///    when N > 1, the note space-trimmed and capped at 500 characters);
///  * `edit_lines[]` follow the envelope's `changes[]` (request order): a
///    `remove` / `set_quantity` / `modify` names its retired line, whose
///    "was" projection is FROZEN from the entry baseline (the retired row
///    keeps its quantity, name, modifiers and note); `now_qty` is the
///    request's quantity; a `modify` / `add` lists the fresh detail rows of
///    its `new_order_item_ids`, in envelope order;
///  * ORDER NOW is every live line of the fresh detail, in the builder's
///    `coalesce(rank, 0)` order (category, item, line position; the detail's
///    own order breaks ties: created_at, id);
///  * the time, number and reason are the edit's (`pos_order_detail.edits[]`);
///    the customer name is space-trimmed and capped at 80, the reason text at
///    200, and the staff name is the first space-separated token, capped at
///    40 — every cap counts characters, like PostgreSQL's `left()`.
///
/// GAP G1: `pos_order_detail` carries no `orders.notes`, so the hand-built
/// slip has no order note (the server slip prints it). POS orders set none.
///
/// FAIL CLOSED: a missing line, row or edit yields NULL, never a partial slip.
///
/// PURE and MONEY-FREE (SECURITY T-003, D-007): no widgets, no providers, no
/// I/O, and no amount of any kind — no `_minor` key exists in any codec here.
/// It reaches the slip types through `restoflow_feature_kitchen` only.
library;

import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenPrepComponent;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show
        OrderChangeAdded,
        OrderChangeModified,
        OrderChangeQuantity,
        OrderChangeRemoved,
        OrderChangeSlipEntry,
        OrderChangeSlipView;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsItemView;

import 'order_detail_repository.dart';
import 'order_edit_baseline.dart';
import 'order_edit_read_model.dart' show PosOrderDetailEdit;
import 'order_edit_response.dart';

// ---------------------------------------------------------------------------
// The item projection
// ---------------------------------------------------------------------------

/// One modifier of [OrderEditSlipItem]: `{qty, name}` (the option's prep
/// contribution is a kitchen COUNT, which the slip never prints).
class OrderEditSlipModifier {
  const OrderEditSlipModifier({required this.qty, required this.name});

  final int qty;
  final String name;
}

/// The money-free kitchen projection of ONE order line — the POS mirror of
/// `app.kitchen_dispatch_item_projection`, persisted as `{qty, name, note?,
/// prep?, modifiers[{qty, name}]}`.
class OrderEditSlipItem {
  const OrderEditSlipItem({
    required this.qty,
    required this.name,
    this.note,
    this.prep = const <KitchenPrepComponent>[],
    this.modifiers = const <OrderEditSlipModifier>[],
  });

  final int qty;
  final String name;

  /// Space-trimmed, at most 500 characters; null when empty.
  final String? note;

  /// The item's PER-UNIT prep components (already allowlisted server-side).
  final List<KitchenPrepComponent> prep;
  final List<OrderEditSlipModifier> modifiers;

  /// The slip line, built exactly like the dispatch adapter's
  /// `_kdsItemFromDispatchItem`.
  KdsItemView toKdsItemView({int linePosition = 0}) => KdsItemView(
    name: name,
    quantity: qty,
    modifiers: [
      for (final m in modifiers) m.qty > 1 ? '${m.name} ×${m.qty}' : m.name,
    ],
    note: note,
    prepComponents: prep,
    linePosition: linePosition,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'qty': qty,
    'name': name,
    if (note != null) 'note': note,
    if (prep.isNotEmpty) 'prep': [for (final p in prep) p.toJson()],
    'modifiers': [
      for (final m in modifiers)
        <String, Object?>{'qty': m.qty, 'name': m.name},
    ],
  };

  /// STRICT: a value this build did not write throws [FormatException]
  /// naming the offending KEY (never a value).
  static OrderEditSlipItem fromJson(Object? raw) {
    final r = _Reader(raw, 'item');
    final item = OrderEditSlipItem(
      qty: r.positiveInt('qty'),
      name: r.string('name'),
      note: r.optionalString('note'),
      prep: [
        for (final p in r.optionalList('prep'))
          KitchenPrepComponent.tryFromJson(p) ??
              (throw const FormatException('order edit slip: item.prep')),
      ],
      modifiers: [for (final m in r.list('modifiers')) _modifierFromJson(m)],
    );
    r.finish();
    return item;
  }

  static OrderEditSlipModifier _modifierFromJson(Object? raw) {
    final r = _Reader(raw, 'modifier');
    final m = OrderEditSlipModifier(
      qty: r.positiveInt('qty'),
      name: r.string('name'),
    );
    r.finish();
    return m;
  }
}

/// [item] as the server projects it (`app.kitchen_dispatch_item_projection`):
/// the stored quantity and name, the note space-trimmed and capped at 500
/// characters (null when empty), the allowlisted per-unit prep and every
/// modifier in the detail's (= the projection's) order.
OrderEditSlipItem slipItemFromDetailItem(PosOrderDetailItem item) =>
    OrderEditSlipItem(
      qty: item.quantity,
      name: item.name,
      note: _pgText(item.notes, 500),
      prep: item.prepComponents,
      modifiers: [
        for (final m in item.modifiers)
          OrderEditSlipModifier(qty: m.quantity, name: m.optionName),
      ],
    );

/// [item] as a change-slip line — `_kdsItemFromDispatchItem` of its server
/// projection.
KdsItemView kdsItemFromDetailItem(
  PosOrderDetailItem item, {
  int linePosition = 0,
}) => slipItemFromDetailItem(item).toKdsItemView(linePosition: linePosition);

// ---------------------------------------------------------------------------
// The edit's lines
// ---------------------------------------------------------------------------

/// The four `edit_lines[].op` values, in wire spelling.
enum OrderEditSlipOp {
  remove('remove'),
  setQuantity('set_quantity'),
  modify('modify'),
  add('add');

  const OrderEditSlipOp(this.wire);

  final String wire;

  static OrderEditSlipOp? fromWire(Object? raw) {
    for (final op in values) {
      if (op.wire == raw) return op;
    }
    return null;
  }
}

/// One requested change of an applied edit, as the server's slip builder
/// reads it: `{kind, order_item_id, quantity, new_order_item_ids}`.
/// Money-free; persisted as `{op, order_item_id?, now_qty?, new_order_item_ids}`.
class OrderEditSlipLine {
  const OrderEditSlipLine({
    required this.op,
    this.orderItemId,
    this.nowQty,
    this.newOrderItemIds = const <String>[],
  });

  final OrderEditSlipOp op;

  /// The retired / kept line (lower-case); null on an `add`.
  final String? orderItemId;

  /// `set_quantity` only: the line's new absolute quantity.
  final int? nowQty;

  /// `modify` / `add`: the rows the server wrote, in envelope order.
  final List<String> newOrderItemIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'op': op.wire,
    if (orderItemId != null) 'order_item_id': orderItemId,
    if (nowQty != null) 'now_qty': nowQty,
    'new_order_item_ids': newOrderItemIds,
  };

  /// STRICT, and closed per op: a `set_quantity` must carry its quantity, an
  /// `add` no line id, every other op a line id.
  static OrderEditSlipLine fromJson(Object? raw) {
    final r = _Reader(raw, 'edit_line');
    final op = OrderEditSlipOp.fromWire(r.string('op'));
    if (op == null) {
      throw const FormatException('order edit slip: edit_line.op');
    }
    final line = OrderEditSlipLine(
      op: op,
      orderItemId: r.optionalString('order_item_id'),
      nowQty: r.optionalPositiveInt('now_qty'),
      newOrderItemIds: [
        for (final id in r.list('new_order_item_ids'))
          id is String && id.isNotEmpty
              ? id
              : throw const FormatException(
                  'order edit slip: edit_line.new_order_item_ids',
                ),
      ],
    );
    r.finish();
    if ((op == OrderEditSlipOp.add) != (line.orderItemId == null) ||
        (op == OrderEditSlipOp.setQuantity) != (line.nowQty != null)) {
      throw const FormatException('order edit slip: edit_line shape');
    }
    return line;
  }
}

/// The edit's slip lines: the envelope's `changes[]` ZIPPED with the frozen
/// request [payload] (`now_qty` is the request's `quantity`, exactly as the
/// server builder reads it). NULL — fail closed — unless both lists have the
/// same length and every pair agrees on the op and the line.
List<OrderEditSlipLine>? orderEditSlipLines({
  required OrderEditApplied applied,
  required Map<String, Object?> payload,
}) {
  final requested = payload['changes'];
  final answered = applied.changes;
  if (requested is! List ||
      answered.isEmpty ||
      requested.length != answered.length) {
    return null;
  }
  final out = <OrderEditSlipLine>[];
  for (var i = 0; i < answered.length; i++) {
    final c = answered[i];
    final req = requested[i];
    final op = OrderEditSlipOp.fromWire(c.kind);
    if (op == null || req is! Map || req['op'] != op.wire) return null;
    final reqId = req['order_item_id'];
    final String? id;
    if (op == OrderEditSlipOp.add) {
      if (c.orderItemId != null) return null;
      id = null;
    } else {
      final answeredId = c.orderItemId?.toLowerCase();
      if (answeredId == null ||
          reqId is! String ||
          reqId.toLowerCase() != answeredId) {
        return null;
      }
      id = answeredId;
    }
    int? nowQty;
    if (op == OrderEditSlipOp.setQuantity) {
      final q = req['quantity'];
      if (q is! int || q < 1 || q > 999) return null;
      nowQty = q;
    }
    out.add(
      OrderEditSlipLine(
        op: op,
        orderItemId: id,
        nowQty: nowQty,
        newOrderItemIds: [for (final n in c.newOrderItemIds) n.toLowerCase()],
      ),
    );
  }
  return out;
}

/// The FROZEN "was" projections of the baseline lines [payload] names, keyed
/// by lower-case `order_item_id`. Taken at the attempt's freeze, so a
/// cart-free replay after a restart can still build the full slip (D2).
/// A line the baseline does not hold is simply absent — the builder then
/// fails closed.
Map<String, OrderEditSlipItem> orderEditSlipWasLines(
  OrderEditBaseline baseline,
  Map<String, Object?> payload,
) {
  final out = <String, OrderEditSlipItem>{};
  final changes = payload['changes'];
  if (changes is! List) return out;
  for (final c in changes) {
    if (c is! Map) continue;
    final id = c['order_item_id'];
    if (id is! String || id.isEmpty) continue;
    final key = id.toLowerCase();
    for (final item in baseline.detail.items) {
      if (item.orderItemId?.toLowerCase() == key) {
        out[key] = slipItemFromDetailItem(item);
        break;
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// The builders
// ---------------------------------------------------------------------------

/// The change slip of the applied edit [applied], hand-built from its frozen
/// request [payload], the frozen [was] projections and the post-apply
/// [fresh] detail. NULL (fail closed) when anything it needs is missing.
OrderChangeSlipView? buildOrderEditChangeSlip({
  required String orderCode,
  required OrderEditApplied applied,
  required Map<String, Object?> payload,
  required Map<String, OrderEditSlipItem> was,
  required PosOrderDetail fresh,
  String? staffDisplayName,
}) {
  final lines = orderEditSlipLines(applied: applied, payload: payload);
  if (lines == null) return null;
  return buildOrderEditChangeSlipFromLines(
    orderCode: orderCode,
    orderEditId: applied.orderEditId,
    editNumber: applied.editNumber,
    lines: lines,
    was: was,
    fresh: fresh,
    staffDisplayName: staffDisplayName,
  );
}

/// [buildOrderEditChangeSlip] from already-zipped [lines] — the input a
/// durable slip record keeps (it never stores the money-carrying payload).
OrderChangeSlipView? buildOrderEditChangeSlipFromLines({
  required String orderCode,
  required String orderEditId,
  required int editNumber,
  required List<OrderEditSlipLine> lines,
  required Map<String, OrderEditSlipItem> was,
  required PosOrderDetail fresh,
  String? staffDisplayName,
}) {
  if (lines.isEmpty || fresh.orderCode != orderCode) return null;
  final edit = _editOf(fresh, orderEditId);
  if (edit == null || edit.editNumber != editNumber) return null;
  final orderNow = _orderNow(fresh);
  if (orderNow.isEmpty) return null;

  final byId = <String, PosOrderDetailItem>{
    for (final item in fresh.items)
      if (item.orderItemId case final id?) id.toLowerCase(): item,
  };
  List<KdsItemView>? nowRows(List<String> ids) {
    if (ids.isEmpty) return null;
    final rows = <KdsItemView>[];
    for (final id in ids) {
      final item = byId[id.toLowerCase()];
      if (item == null) return null;
      rows.add(kdsItemFromDetailItem(item));
    }
    return rows;
  }

  final entries = <OrderChangeSlipEntry>[];
  for (final line in lines) {
    final wasItem = line.orderItemId == null
        ? null
        : was[line.orderItemId!.toLowerCase()]?.toKdsItemView();
    switch (line.op) {
      case OrderEditSlipOp.remove:
        if (wasItem == null) return null;
        entries.add(OrderChangeRemoved(wasItem));
      case OrderEditSlipOp.setQuantity:
        final nowQty = line.nowQty;
        if (wasItem == null || nowQty == null) return null;
        entries.add(OrderChangeQuantity(was: wasItem, nowQuantity: nowQty));
      case OrderEditSlipOp.modify:
        final now = nowRows(line.newOrderItemIds);
        if (wasItem == null || now == null) return null;
        entries.add(OrderChangeModified(was: wasItem, now: now));
      case OrderEditSlipOp.add:
        final now = nowRows(line.newOrderItemIds);
        if (now == null) return null;
        entries.add(OrderChangeAdded(now));
    }
  }
  return OrderChangeSlipView(
    orderCode: orderCode,
    editNumber: editNumber,
    orderType: fresh.orderType,
    tableLabel: fresh.tableLabel,
    customerName: _pgText(fresh.customerName, 80),
    editedAt: edit.createdAt?.toLocal(),
    reasonCode: edit.reasonCode,
    reasonText: _pgText(edit.reasonText, 200),
    staffFirstName: orderEditSlipStaffFirstName(staffDisplayName),
    changes: entries,
    orderNow: orderNow,
  );
}

/// The ORDER-NOW-only change slip of [detail]: no change sections, headed by
/// its LATEST edit (number, time and reason), no staff line, every live line.
/// Used where no per-change record exists (another till's newer edit, the
/// manual reprint of an edited order). NULL when no edit is known or the
/// order has no live line.
OrderChangeSlipView? orderNowSlipFromDetail(PosOrderDetail detail) {
  final orderNow = _orderNow(detail);
  if (orderNow.isEmpty) return null;
  final edits = detail.edits;
  final latest = edits == null || edits.isEmpty ? null : edits.last;
  final number = latest?.editNumber ?? detail.editCount;
  if (number < 1) return null;
  return OrderChangeSlipView(
    orderCode: detail.orderCode,
    editNumber: number,
    orderType: detail.orderType,
    tableLabel: detail.tableLabel,
    customerName: _pgText(detail.customerName, 80),
    editedAt: latest?.createdAt?.toLocal(),
    reasonCode: latest?.reasonCode,
    reasonText: _pgText(latest?.reasonText, 200),
    orderNow: orderNow,
  );
}

/// The server's `staff_name`: the first SPACE-separated token of the
/// space-trimmed display name, at most 40 characters; null when empty.
String? orderEditSlipStaffFirstName(String? displayName) {
  final first = _pgBtrim(displayName ?? '').split(' ').first;
  final capped = _pgLeft(first, 40);
  return capped.isEmpty ? null : capped;
}

PosOrderDetailEdit? _editOf(PosOrderDetail detail, String orderEditId) {
  final id = orderEditId.toLowerCase();
  for (final e in detail.edits ?? const <PosOrderDetailEdit>[]) {
    if (e.orderEditId.toLowerCase() == id) return e;
  }
  return null;
}

/// Every live line in the server builder's ORDER NOW order: a STABLE sort on
/// `(category, item, line position)` — the detail already lists them in that
/// order with created_at / id as the tie-breakers, which the stable sort
/// keeps — then numbered 1..n like the adapter.
List<KdsItemView> _orderNow(PosOrderDetail detail) {
  final indexed = [
    for (var i = 0; i < detail.items.length; i++) (i, detail.items[i]),
  ];
  indexed.sort((a, b) {
    final x = a.$2;
    final y = b.$2;
    var c = x.categoryDisplayOrder.compareTo(y.categoryDisplayOrder);
    if (c != 0) return c;
    c = x.itemDisplayOrder.compareTo(y.itemDisplayOrder);
    if (c != 0) return c;
    c = x.linePosition.compareTo(y.linePosition);
    if (c != 0) return c;
    return a.$1.compareTo(b.$1);
  });
  return [
    for (var i = 0; i < indexed.length; i++)
      kdsItemFromDetailItem(indexed[i].$2, linePosition: i + 1),
  ];
}

/// PostgreSQL `nullif(left(btrim(coalesce(v, '')), cap), '')`.
String? _pgText(String? value, int cap) {
  final out = _pgLeft(_pgBtrim(value ?? ''), cap);
  return out.isEmpty ? null : out;
}

/// PostgreSQL one-argument `btrim`: strips SPACES only (U+0020), not other
/// whitespace.
String _pgBtrim(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && s.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return s.substring(start, end);
}

/// PostgreSQL `left(s, n)`: the first [n] CHARACTERS (code points), never a
/// split surrogate pair.
String _pgLeft(String s, int n) {
  final runes = s.runes;
  return runes.length <= n ? s : String.fromCharCodes(runes.take(n));
}

// ---------------------------------------------------------------------------
// The strict money-free codec of a built slip
// ---------------------------------------------------------------------------

/// The codec's version.
const int kOrderChangeSlipCodecVersion = 1;

/// [slip] as strict, money-free JSON — what a durable slip record keeps so a
/// "Print again" reprints the SAME document. Keys avoid the money and
/// hostile-kitchen vocabulary (no `change` / `total` / `price` / `_minor`
/// token). Throws [ArgumentError] for a line carrying a field this codec does
/// not keep (a KDS overlay mark), rather than silently dropping it.
Map<String, Object?> encodeOrderChangeSlipView(OrderChangeSlipView slip) =>
    <String, Object?>{
      'v': kOrderChangeSlipCodecVersion,
      'order_code': slip.orderCode,
      'edit_number': slip.editNumber,
      if (slip.orderType != null) 'order_type': slip.orderType,
      if (slip.tableLabel != null) 'table_label': slip.tableLabel,
      if (slip.customerName != null) 'customer_name': slip.customerName,
      if (slip.orderNote != null) 'order_note': slip.orderNote,
      if (slip.editedAt != null)
        'edited_at': slip.editedAt!.toUtc().toIso8601String(),
      if (slip.reasonCode != null) 'reason_code': slip.reasonCode,
      if (slip.reasonText != null) 'reason_text': slip.reasonText,
      if (slip.staffFirstName != null) 'staff_first_name': slip.staffFirstName,
      'entries': [for (final e in slip.changes) _entryToJson(e)],
      'order_now': [for (final i in slip.orderNow) _viewToJson(i)],
    };

/// STRICT inverse of [encodeOrderChangeSlipView]: an unknown or missing key,
/// a wrong type or an unknown op throws [FormatException] naming the KEY,
/// never a value. The edit time comes back in local time.
OrderChangeSlipView decodeOrderChangeSlipView(Object? raw) {
  final r = _Reader(raw, 'slip');
  if (r.positiveInt('v') != kOrderChangeSlipCodecVersion) {
    throw const FormatException('order edit slip: slip.v');
  }
  final editedRaw = r.optionalString('edited_at');
  final editedAt = editedRaw == null ? null : DateTime.tryParse(editedRaw);
  if (editedRaw != null && editedAt == null) {
    throw const FormatException('order edit slip: slip.edited_at');
  }
  final slip = OrderChangeSlipView(
    orderCode: r.string('order_code'),
    editNumber: r.positiveInt('edit_number'),
    orderType: r.optionalString('order_type'),
    tableLabel: r.optionalString('table_label'),
    customerName: r.optionalString('customer_name'),
    orderNote: r.optionalString('order_note'),
    editedAt: editedAt?.toLocal(),
    reasonCode: r.optionalString('reason_code'),
    reasonText: r.optionalString('reason_text'),
    staffFirstName: r.optionalString('staff_first_name'),
    changes: [for (final e in r.list('entries')) _entryFromJson(e)],
    orderNow: [for (final i in r.list('order_now')) _viewFromJson(i)],
  );
  r.finish();
  return slip;
}

Map<String, Object?> _entryToJson(OrderChangeSlipEntry e) => switch (e) {
  OrderChangeRemoved(:final was) => <String, Object?>{
    'op': OrderEditSlipOp.remove.wire,
    'was': _viewToJson(was),
  },
  OrderChangeQuantity(:final was, :final nowQuantity) => <String, Object?>{
    'op': OrderEditSlipOp.setQuantity.wire,
    'was': _viewToJson(was),
    'now_qty': nowQuantity,
  },
  OrderChangeModified(:final was, :final now) => <String, Object?>{
    'op': OrderEditSlipOp.modify.wire,
    'was': _viewToJson(was),
    'now': [for (final i in now) _viewToJson(i)],
  },
  OrderChangeAdded(:final now) => <String, Object?>{
    'op': OrderEditSlipOp.add.wire,
    'now': [for (final i in now) _viewToJson(i)],
  },
};

OrderChangeSlipEntry _entryFromJson(Object? raw) {
  final r = _Reader(raw, 'entry');
  final op = OrderEditSlipOp.fromWire(r.string('op'));
  final OrderChangeSlipEntry entry;
  switch (op) {
    case OrderEditSlipOp.remove:
      entry = OrderChangeRemoved(_viewFromJson(r.take('was')));
    case OrderEditSlipOp.setQuantity:
      entry = OrderChangeQuantity(
        was: _viewFromJson(r.take('was')),
        nowQuantity: r.positiveInt('now_qty'),
      );
    case OrderEditSlipOp.modify:
      entry = OrderChangeModified(
        was: _viewFromJson(r.take('was')),
        now: [for (final i in r.nonEmptyList('now')) _viewFromJson(i)],
      );
    case OrderEditSlipOp.add:
      entry = OrderChangeAdded([
        for (final i in r.nonEmptyList('now')) _viewFromJson(i),
      ]);
    case null:
      throw const FormatException('order edit slip: entry.op');
  }
  r.finish();
  return entry;
}

Map<String, Object?> _viewToJson(KdsItemView v) {
  if (v.categoryDisplayOrder != 0 ||
      v.itemDisplayOrder != 0 ||
      v.orderItemId != null ||
      v.editMark != null ||
      v.editWas != null ||
      v.editNumber != null) {
    throw ArgumentError.value(
      v.name,
      'item',
      'a change-slip line carries no rank, identity or edit mark',
    );
  }
  return <String, Object?>{
    'qty': v.quantity,
    'name': v.name,
    'modifiers': v.modifiers,
    if (v.note != null) 'note': v.note,
    if (v.prepComponents.isNotEmpty)
      'prep': [for (final p in v.prepComponents) p.toJson()],
    if (v.linePosition != 0) 'line_position': v.linePosition,
  };
}

KdsItemView _viewFromJson(Object? raw) {
  final r = _Reader(raw, 'item');
  final view = KdsItemView(
    quantity: r.positiveInt('qty'),
    name: r.string('name'),
    modifiers: [
      for (final m in r.list('modifiers'))
        m is String && m.isNotEmpty
            ? m
            : throw const FormatException('order edit slip: item.modifiers'),
    ],
    note: r.optionalString('note'),
    prepComponents: [
      for (final p in r.optionalList('prep'))
        KitchenPrepComponent.tryFromJson(p) ??
            (throw const FormatException('order edit slip: item.prep')),
    ],
    linePosition: r.optionalPositiveInt('line_position') ?? 0,
  );
  r.finish();
  return view;
}

/// A closed JSON object reader: every key must be consumed, and every error
/// names the key — never the value.
class _Reader {
  factory _Reader(Object? raw, String context) {
    if (raw is! Map) throw FormatException('order edit slip: $context');
    return _Reader._(raw, context);
  }

  _Reader._(this._map, this._context)
    : _left = <String>{for (final k in _map.keys) k.toString()};

  final Map<dynamic, dynamic> _map;
  final String _context;
  final Set<String> _left;

  Object? take(String key) {
    _left.remove(key);
    return _map[key];
  }

  Never _bad(String key) =>
      throw FormatException('order edit slip: $_context.$key');

  String string(String key) {
    final v = take(key);
    return v is String && v.isNotEmpty ? v : _bad(key);
  }

  String? optionalString(String key) {
    final v = take(key);
    if (v == null) return null;
    return v is String && v.isNotEmpty ? v : _bad(key);
  }

  int positiveInt(String key) {
    final v = take(key);
    return v is int && v > 0 ? v : _bad(key);
  }

  int? optionalPositiveInt(String key) {
    final v = take(key);
    if (v == null) return null;
    return v is int && v > 0 ? v : _bad(key);
  }

  List<Object?> list(String key) {
    final v = take(key);
    return v is List ? v.cast<Object?>() : _bad(key);
  }

  /// A modify / add always names at least one row (the server decoder's
  /// rule too).
  List<Object?> nonEmptyList(String key) {
    final v = list(key);
    return v.isNotEmpty ? v : _bad(key);
  }

  List<Object?> optionalList(String key) {
    final v = take(key);
    if (v == null) return const <Object?>[];
    return v is List ? v.cast<Object?>() : _bad(key);
  }

  void finish() {
    if (_left.isNotEmpty) {
      final keys = _left.toList()..sort();
      throw FormatException(
        'order edit slip: unknown key(s) in $_context: ${keys.join(', ')}',
      );
    }
  }
}
