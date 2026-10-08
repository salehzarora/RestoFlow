import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

/// ORDER-EDIT-001C — the KDS sent-order edit overlay (D-043 / D-044;
/// ORDER_EDIT_DESIGN §7.2, API_CONTRACT §4.46), driven through
/// `KdsTicketMapper.map(orderEdits: …)`.
///
/// Every fixture mirrors a REAL kitchen `sync_pull` row: the column names of
/// public.orders / order_items / order_item_modifiers / order_service_rounds /
/// order_edits (migrations 20260621130000, 20260722090000, 20261008170000),
/// with the kitchen money redaction applied (no `*_minor` key at all) and the
/// unredacted staff / session / device columns an `order_edits` row really
/// carries. The rows an edit writes follow `app.edit_order`
/// (20261008170100): retired lines keep their row with removed_by_edit_id +
/// removed_kitchen_stage (cancelled in a Waiting unit, voided otherwise);
/// in-place rows keep the old line_position; round rows get max + 1.

// ---------------------------------------------------------------------------
// Ids (uuid-shaped so the display code and ticket keys look real).
// ---------------------------------------------------------------------------
const _org = '00000000-0000-4000-8000-00000000000a';
const _rest = '00000000-0000-4000-8000-00000000000b';
const _branch = '00000000-0000-4000-8000-00000000000c';
const _o1 = '11111111-0000-4000-8000-0000000000a1';
const _o2 = '22222222-0000-4000-8000-0000000000a2';
const _o3 = '33333333-0000-4000-8000-0000000000a3';
const _r2 = '44444444-0000-4000-8000-0000000000b2';
const _r3 = '44444444-0000-4000-8000-0000000000b3';
const _e1 = '55555555-0000-4000-8000-0000000000e1';
const _e2 = '55555555-0000-4000-8000-0000000000e2';
const _e9 = '55555555-0000-4000-8000-0000000000e9';
const _table = '66666666-0000-4000-8000-0000000000t1';

String _original(String orderId) => '$orderId:unassigned';
String _roundKey(String orderId, String roundId) =>
    '$orderId:unassigned:r$roundId';

const _t0 = '2026-10-08T10:00:00Z';
const _tEdit1 = '2026-10-08T10:20:00Z';
const _tEdit2 = '2026-10-08T10:25:00Z';
const _tAck = '2026-10-08T10:30:00Z';

// ---------------------------------------------------------------------------
// Server-shaped row builders.
// ---------------------------------------------------------------------------
Map<String, dynamic> _order(
  String id, {
  String status = 'preparing',
  String createdAt = _t0,
  String dispatchMode = 'kds',
  int editCount = 0,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'organization_id': _org,
  'restaurant_id': _rest,
  'branch_id': _branch,
  'status': status,
  'order_type': 'dine_in',
  'table_id': _table,
  'notes': 'Allergy: nuts',
  'customer_name': 'Dana',
  'customer_phone': null,
  'dispatch_mode': dispatchMode,
  'kitchen_ack_required': false,
  'kitchen_ack_at': null,
  'voided_at': null,
  'voided_from_status': null,
  'edit_count': editCount,
  'revision': 1 + editCount,
  'device_id': 'pos-device-1',
  'local_operation_id': 'submit-$id',
  'client_created_at': createdAt,
  'created_at': createdAt,
  'updated_at': createdAt,
  'deleted_at': null,
  ...extra,
};

Map<String, dynamic> _item(
  String id,
  String orderId, {
  required String name,
  int qty = 1,
  String status = 'pending',
  int linePosition = 1,
  int category = 1,
  int itemOrder = 1,
  String? round,
  String? editId,
  String? replaces,
  String? notes,
  List<Map<String, dynamic>>? prep,
  String createdAt = _t0,
}) => {
  'id': id,
  'organization_id': _org,
  'restaurant_id': _rest,
  'branch_id': _branch,
  'order_id': orderId,
  'menu_item_id': 'menu-$name',
  'station_id': null,
  'status': status,
  'quantity': qty,
  'menu_item_name_snapshot': name,
  'item_size_snapshot': null,
  'item_variant_snapshot': null,
  'notes': notes,
  'prep_snapshot': prep,
  'service_round_id': round,
  'line_position': linePosition,
  'category_display_order_snapshot': category,
  'item_display_order_snapshot': itemOrder,
  'edit_id': editId,
  'removed_by_edit_id': null,
  'replaces_order_item_id': replaces,
  'removed_kitchen_stage': null,
  'void_reason': null,
  'created_at': createdAt,
  'updated_at': createdAt,
  'deleted_at': null,
};

/// The row as `app.edit_order` step 14 leaves it after retiring it: cancelled
/// while its unit is Waiting on the KDS channel, voided otherwise.
Map<String, dynamic> _retired(
  Map<String, dynamic> row, {
  required String by,
  required String stage,
}) => {
  ...row,
  'status': stage == 'submitted' ? 'cancelled' : 'voided',
  'void_reason': 'order_edit:customer_changed_mind',
  'removed_by_edit_id': by,
  'removed_kitchen_stage': stage,
  'updated_at': _tEdit1,
};

Map<String, dynamic> _mod(
  String id,
  String itemId,
  String option, {
  int qty = 1,
  int group = 1,
  int optionOrder = 1,
}) => {
  'id': id,
  'organization_id': _org,
  'restaurant_id': _rest,
  'branch_id': _branch,
  'order_item_id': itemId,
  'modifier_option_id': 'opt-$option',
  'modifier_name_snapshot': 'Extras',
  'option_name_snapshot': option,
  'quantity': qty,
  'meat_snapshot': null,
  'line_position': 1,
  'modifier_group_display_order_snapshot': group,
  'modifier_option_display_order_snapshot': optionOrder,
  'created_at': _t0,
  'updated_at': _t0,
  'deleted_at': null,
};

Map<String, dynamic> _round(
  String id,
  String orderId, {
  int number = 2,
  String status = 'submitted',
  String createdAt = _tEdit1,
  String? editId,
  String? voidedBy,
}) => {
  'id': id,
  'organization_id': _org,
  'restaurant_id': _rest,
  'branch_id': _branch,
  'order_id': orderId,
  'round_number': number,
  'status': status,
  'ready_at': status == 'ready' || status == 'served' ? createdAt : null,
  'void_reason': voidedBy == null ? null : 'order_edit:customer_changed_mind',
  'device_id': 'pos-device-1',
  'opened_by_employee_profile_id': 'emp-cashier',
  'local_operation_id': null,
  'revision': 1,
  'client_created_at': createdAt,
  'created_at': createdAt,
  'updated_at': createdAt,
  'deleted_at': null,
  'edit_id': editId,
  'voided_by_edit_id': voidedBy,
};

/// A raw `order_edits` row — the KDS receives it UNREDACTED except for money
/// (it has none): staff, PIN session, device and replay key included.
Map<String, dynamic> _edit(
  String id,
  String orderId,
  int number, {
  String channel = 'kds',
  bool ackRequired = true,
  String? ackAt,
  String? reasonCode = 'customer_changed_mind',
  String? reasonText,
  String createdAt = _tEdit1,
}) => {
  'id': id,
  'organization_id': _org,
  'restaurant_id': _rest,
  'branch_id': _branch,
  'order_id': orderId,
  'edit_number': number,
  'device_id': 'pos-device-1',
  'local_operation_id': 'edit-op-$number',
  'pin_session_id': 'pin-session-cashier',
  'employee_profile_id': 'emp-cashier',
  'membership_id': 'membership-cashier',
  'reason_code': reasonCode,
  'reason_text': reasonText,
  'kitchen_channel': channel,
  'kitchen_ack_required': ackRequired,
  'kitchen_ack_at': ackAt,
  'kitchen_ack_by_employee_profile_id': ackAt == null ? null : 'emp-cook',
  'kitchen_ack_device_id': ackAt == null ? null : 'kds-device-1',
  'bill_presented_at': null,
  'client_created_at': createdAt,
  'created_at': createdAt,
  'updated_at': ackAt ?? createdAt,
  'deleted_at': null,
};

final _tables = <Map<String, dynamic>>[
  {'id': _table, 'organization_id': _org, 'label': 'T7', 'deleted_at': null},
];

/// One pull's rows.
class _Rows {
  _Rows({
    required this.orders,
    required this.items,
    this.mods = const [],
    this.rounds = const [],
    this.edits = const [],
  });

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> mods;
  final List<Map<String, dynamic>> rounds;
  final List<Map<String, dynamic>> edits;

  _Rows withEdits(List<Map<String, dynamic>> next) => _Rows(
    orders: orders,
    items: items,
    mods: mods,
    rounds: rounds,
    edits: next,
  );

  _Rows operator +(_Rows other) => _Rows(
    orders: [...orders, ...other.orders],
    items: [...items, ...other.items],
    mods: [...mods, ...other.mods],
    rounds: [...rounds, ...other.rounds],
    edits: [...edits, ...other.edits],
  );

  List<KdsTicketView> map({bool withEdits = true}) => KdsTicketMapper.map(
    orders: orders,
    orderItems: items,
    modifiers: mods,
    tables: _tables,
    serviceRounds: rounds,
    orderEdits: withEdits ? edits : const [],
  );
}

// ---------------------------------------------------------------------------
// A canonical, field-complete description of a board (deep-comparable).
// ---------------------------------------------------------------------------
Object? _describeItem(KdsItemView? i) => i == null
    ? null
    : {
        'id': i.orderItemId,
        'name': i.name,
        'qty': i.quantity,
        'mods': i.modifiers,
        'note': i.note,
        'prep': [
          for (final p in i.prepComponents) '${p.name}|${p.quantity}|${p.unit}',
        ],
        'keys': [i.categoryDisplayOrder, i.itemDisplayOrder, i.linePosition],
        'mark': i.editMark?.name,
        'was': _describeItem(i.editWas),
        'editNumber': i.editNumber,
      };

Object? _describeEdit(KdsOrderEdit e) => {
  'id': e.id,
  'order': e.orderId,
  'number': e.editNumber,
  'channel': e.channel.name,
  'ackRequired': e.ackRequired,
  'ackAt': e.ackAt?.toIso8601String(),
  'createdAt': e.createdAt?.toIso8601String(),
  'reason': e.reasonCode,
  'text': e.reasonText,
};

Object? _describeChange(KdsTicketChange? c) => c == null
    ? null
    : {
        'pending': [for (final e in c.pendingEdits) _describeEdit(e)],
        'removed': [
          for (final r in c.removed)
            {
              'line': _describeItem(r.line),
              'edit': r.editNumber,
              'stage': r.removedKitchenStage,
              'remadeIn': r.remadeInRoundNumber,
            },
        ],
        'standalone': c.standalone,
        'emptied': c.emptied,
        'formerStage': c.formerStage,
        'orderPending': c.orderPendingEditNumbers,
        'upTo': c.upToEditNumber,
        'also': c.alsoAcknowledges,
      };

List<Object?> _describe(List<KdsTicketView> board) => [
  for (final t in board)
    {
      'id': t.kitchenTicketId,
      'station': t.stationId,
      'status': t.status.name,
      'order': t.orderId,
      'number': t.orderNumber,
      'type': t.orderType,
      'table': t.tableLabel,
      'customer': t.customerName,
      'phone': t.customerPhone,
      'notes': t.notes,
      'submittedAt': t.submittedAt?.toIso8601String(),
      'counts': [
        for (final c in t.kitchenCounts)
          '${c.label}|${c.quantity}|${c.classifier}',
      ],
      'voidedAt': t.voidedAt?.toIso8601String(),
      'voidedFrom': t.voidedFromStatus,
      'roundId': t.roundId,
      'roundNumber': t.roundNumber,
      'items': [for (final i in t.items) _describeItem(i)],
      'change': _describeChange(t.change),
      'openedBy': t.openedByEditNumber,
      'alertKey': t.changeAlertKey,
    },
];

KdsTicketView _ticket(List<KdsTicketView> board, String id) =>
    board.singleWhere((t) => t.kitchenTicketId == id);

/// A prep snapshot (per-unit, money-free) so counts are exercised.
List<Map<String, dynamic>> _patty(int n) => [
  {'name': 'Patty', 'quantity': n, 'unit': 'pcs'},
];

// ---------------------------------------------------------------------------
// Scenario fixtures (each reused by the shuffle test).
// ---------------------------------------------------------------------------

/// 5. Modify "just 1 of 3" in an In-kitchen unit: the old 3× line is retired;
/// a 2× continuation and a 1× changed replacement land in place.
_Rows _modifyOneOfThree(String orderId, {String? edit1AckAt}) {
  final x = _item(
    'x-$orderId',
    orderId,
    name: 'Burger',
    qty: 3,
    prep: _patty(1),
  );
  return _Rows(
    orders: [_order(orderId, editCount: 1)],
    items: [
      _retired(x, by: _e1, stage: 'preparing'),
      _item(
        'xc-$orderId',
        orderId,
        name: 'Burger',
        qty: 2,
        editId: _e1,
        replaces: 'x-$orderId',
        prep: _patty(1),
      ),
      _item(
        'xr-$orderId',
        orderId,
        name: 'Burger',
        editId: _e1,
        replaces: 'x-$orderId',
        prep: _patty(1),
      ),
      _item('f-$orderId', orderId, name: 'Fries', linePosition: 2),
    ],
    mods: [
      _mod('m-x-$orderId', 'x-$orderId', 'Tomato'),
      _mod('m-xc-$orderId', 'xc-$orderId', 'Tomato'),
    ],
    edits: [_edit(_e1, orderId, 1, ackAt: edit1AckAt)],
  );
}

/// 9. Modify a line of a READY unit: the changed replacement is a REMAKE in
/// the edit's round (Round 2, opened by the edit).
_Rows _remakeOnReady(String orderId, {String? ackAt, String roundId = _r2}) {
  final a = _item('a-$orderId', orderId, name: 'Burger');
  return _Rows(
    orders: [_order(orderId, status: 'ready', editCount: 1)],
    items: [
      _retired(a, by: _e1, stage: 'ready'),
      _item('b-$orderId', orderId, name: 'Fries', linePosition: 2),
      _item(
        'a2-$orderId',
        orderId,
        name: 'Burger',
        linePosition: 3,
        round: roundId,
        editId: _e1,
        replaces: 'a-$orderId',
        createdAt: _tEdit1,
      ),
    ],
    mods: [_mod('m-a-$orderId', 'a-$orderId', 'Tomato')],
    rounds: [_round(roundId, orderId, editId: _e1)],
    edits: [_edit(_e1, orderId, 1, ackAt: ackAt)],
  );
}

/// 10. Emptied round: an add-items Round 2 (preparing) loses its only line;
/// app.edit_order voids the round with voided_by_edit_id.
_Rows _emptiedRound(String orderId, {String roundId = _r3}) {
  final b = _item(
    'b-$orderId',
    orderId,
    name: 'Fries',
    linePosition: 2,
    round: roundId,
    prep: _patty(2),
  );
  return _Rows(
    orders: [_order(orderId, editCount: 1)],
    items: [
      _item('a-$orderId', orderId, name: 'Burger', prep: _patty(1)),
      _retired(b, by: _e2, stage: 'preparing'),
    ],
    rounds: [
      _round(
        roundId,
        orderId,
        status: 'voided',
        createdAt: '2026-10-08T10:10:00Z',
        voidedBy: _e2,
      ),
    ],
    edits: [_edit(_e2, orderId, 1)],
  );
}

/// 21. Two pending edits on two cards of one order: E1 removes from the
/// original unit, E2 removes from an add-items round.
_Rows _crossCard(String orderId, {String roundId = _r2}) {
  return _Rows(
    orders: [_order(orderId, editCount: 2)],
    items: [
      _retired(
        _item('a-$orderId', orderId, name: 'Burger'),
        by: _e1,
        stage: 'preparing',
      ),
      _item('b-$orderId', orderId, name: 'Fries', linePosition: 2),
      _retired(
        _item(
          'c-$orderId',
          orderId,
          name: 'Soup',
          linePosition: 3,
          round: roundId,
        ),
        by: _e2,
        stage: 'preparing',
      ),
      _item(
        'd-$orderId',
        orderId,
        name: 'Salad',
        linePosition: 4,
        round: roundId,
      ),
    ],
    rounds: [
      _round(
        roundId,
        orderId,
        status: 'preparing',
        createdAt: '2026-10-08T10:10:00Z',
      ),
    ],
    edits: [
      _edit(_e1, orderId, 1),
      _edit(_e2, orderId, 2, createdAt: _tEdit2),
    ],
  );
}

void main() {
  group('baseline and the four basic changes', () {
    test(
      '1. no edits: the board is identical (rounds, a red card, counts)',
      () {
        final rows = _Rows(
          orders: [
            _order(_o1),
            _order(
              _o2,
              status: 'voided',
              extra: {
                'kitchen_ack_required': true,
                'voided_at': '2026-10-08T10:40:00Z',
                'voided_from_status': 'preparing',
              },
            ),
          ],
          items: [
            _item('a1', _o1, name: 'Burger', qty: 2, prep: _patty(1)),
            _item(
              'a2',
              _o1,
              name: 'Fries',
              linePosition: 2,
              round: _r2,
              prep: _patty(3),
            ),
            _item('v1', _o2, name: 'Soup', status: 'voided'),
          ],
          mods: [_mod('m1', 'a1', 'Cheese', qty: 2)],
          rounds: [_round(_r2, _o1, status: 'accepted')],
        );
        final base = rows.map(withEdits: false);
        expect(base, hasLength(3));
        // The default argument and an explicit empty list are the same board…
        final explicitEmpty = KdsTicketMapper.map(
          orders: rows.orders,
          orderItems: rows.items,
          modifiers: rows.mods,
          tables: _tables,
          serviceRounds: rows.rounds,
        );
        expect(_describe(explicitEmpty), _describe(base));
        // …and edit rows that touch nothing on this board change nothing.
        final unrelated = rows.withEdits([
          _edit(_e9, _o3, 1),
          _edit(_e1, _o1, 1, channel: 'paper'),
        ]).map();
        expect(_describe(unrelated), _describe(base));
        for (final t in base) {
          expect(t.change, isNull);
          expect(t.requiresChangeAck, isFalse);
          expect(t.changeAlertKey, isNull);
          expect(t.openedByEditNumber, isNull);
          for (final i in t.items) {
            expect(i.editMark, isNull);
            expect(i.editWas, isNull);
            expect(i.editNumber, isNull);
            expect(i.orderItemId, isNotNull, reason: 'the base fills the id');
          }
        }
        final original = _ticket(base, _original(_o1));
        expect(original.kitchenCounts.single.quantity, 2);
        expect(original.items.single.modifiers, ['Cheese ×2']);
        expect(
          _ticket(base, _roundKey(_o1, _r2)).kitchenCounts.single.quantity,
          3,
        );
        expect(
          _ticket(base, _original(_o2)).status,
          KitchenTicketStatus.cancelled,
        );
      },
    );

    test('2. remove in a WAITING unit: REMOVED with the exact "was" text, the '
        'header and the alert key', () {
      final a = _item(
        'a1',
        _o1,
        name: 'Burger',
        qty: 2,
        notes: 'well done',
        prep: _patty(1),
      );
      final rows = _Rows(
        orders: [_order(_o1, status: 'submitted', editCount: 1)],
        items: [
          _retired(a, by: _e1, stage: 'submitted'),
          _item('b1', _o1, name: 'Fries', linePosition: 2),
        ],
        mods: [
          _mod('m1', 'a1', 'Tomato', qty: 2, optionOrder: 2),
          _mod('m2', 'a1', 'Onion'),
        ],
        edits: [
          _edit(
            _e1,
            _o1,
            1,
            reasonCode: 'other',
            reasonText: '  Guest is allergic  ',
          ),
        ],
      );
      final board = rows.map();
      expect(board, hasLength(1));
      final t = board.single;
      expect(t.kitchenTicketId, _original(_o1));
      expect(t.status, KitchenTicketStatus.newTicket);
      expect(t.items.map((i) => i.name), ['Fries']);
      expect(t.items.single.editMark, isNull);
      final change = t.change!;
      expect(t.requiresChangeAck, isTrue);
      expect(change.pendingEdits.single.editNumber, 1);
      expect(change.latest.createdAt, DateTime.parse(_tEdit1));
      expect(change.latest.reasonCode, 'other');
      expect(change.latest.reasonText, 'Guest is allergic');
      expect(change.upToEditNumber, 1);
      expect(change.alsoAcknowledges, isEmpty);
      expect(change.orderPendingEditNumbers, [1]);
      expect(change.standalone, isFalse);
      expect(change.emptied, isFalse);
      expect(t.changeAlertKey, '${_original(_o1)}|e1');
      final removed = change.removed.single;
      expect(removed.editNumber, 1);
      expect(removed.removedKitchenStage, 'submitted');
      expect(removed.remadeInRoundNumber, isNull);
      // The "was" text renders exactly like the live line did.
      expect(removed.line.name, 'Burger');
      expect(removed.line.quantity, 2);
      expect(removed.line.modifiers, ['Onion', 'Tomato ×2']);
      expect(removed.line.note, 'well done');
      expect(removed.line.orderItemId, 'a1');
      // The removed line no longer counts.
      expect(t.kitchenCounts, isEmpty);
    });

    test('3. reduce: the remainder is CHANGED, quantity only', () {
      final x = _item('x1', _o1, name: 'Burger', qty: 3);
      final rows = _Rows(
        orders: [_order(_o1, status: 'accepted', editCount: 1)],
        items: [
          _retired(x, by: _e1, stage: 'accepted'),
          _item('x2', _o1, name: 'Burger', qty: 2, editId: _e1, replaces: 'x1'),
        ],
        mods: [_mod('m1', 'x1', 'Tomato'), _mod('m2', 'x2', 'Tomato')],
        edits: [_edit(_e1, _o1, 1)],
      );
      final t = rows.map().single;
      final line = t.items.single;
      expect(line.editMark, KdsEditLineMark.changed);
      expect(line.editNumber, 1);
      expect(line.quantity, 2);
      expect(line.editWas!.quantity, 3);
      expect(line.editWas!.name, line.name);
      expect(line.editWas!.modifiers, line.modifiers);
      expect(t.change!.removed, isEmpty, reason: 'shown as the "was" line');
      expect(t.status, KitchenTicketStatus.acknowledged);
    });

    test('4. increase in place: the +N delta is INCREASED next to the kept '
        'line', () {
      final rows = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _item('x1', _o1, name: 'Burger', qty: 2),
          _item('x9', _o1, name: 'Burger', editId: _e1),
        ],
        edits: [_edit(_e1, _o1, 1)],
      );
      final t = rows.map().single;
      expect(t.items.map((i) => i.orderItemId), ['x1', 'x9']);
      expect(t.items.first.editMark, isNull);
      expect(t.items.last.editMark, KdsEditLineMark.increased);
      expect(t.items.last.quantity, 1);
      expect(t.items.last.editWas, isNull);
      expect(t.items.last.editNumber, 1);
      expect(t.change!.upToEditNumber, 1);
      expect(t.change!.removed, isEmpty);
    });
  });

  group('modify and add', () {
    test('5. modify "just 1 of 3": continuation and replacement are both '
        'CHANGED, was 3×', () {
      final t = _modifyOneOfThree(_o1).map().single;
      expect(t.items.map((i) => i.orderItemId), [
        'xc-$_o1',
        'xr-$_o1',
        'f-$_o1',
      ]);
      final cont = t.items[0];
      final repl = t.items[1];
      for (final line in [cont, repl]) {
        expect(line.editMark, KdsEditLineMark.changed);
        expect(line.editWas!.quantity, 3);
        expect(line.editWas!.modifiers, ['Tomato']);
        expect(line.editWas!.orderItemId, 'x-$_o1');
      }
      expect(cont.quantity, 2);
      expect(cont.modifiers, ['Tomato']);
      expect(repl.quantity, 1);
      expect(repl.modifiers, isEmpty);
      expect(t.items[2].editMark, isNull);
      expect(t.change!.removed, isEmpty);
    });

    test('6. modify excess: the no-replaces delta at the old position is '
        'grouped as CHANGED', () {
      final x = _item('x1', _o1, name: 'Burger', qty: 2);
      final rows = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _retired(x, by: _e1, stage: 'preparing'),
          _item('x2', _o1, name: 'Burger', qty: 2, editId: _e1, replaces: 'x1'),
          _item('x3', _o1, name: 'Burger', editId: _e1),
        ],
        mods: [_mod('m1', 'x1', 'Tomato')],
        edits: [_edit(_e1, _o1, 1)],
      );
      final t = rows.map().single;
      expect(t.items, hasLength(2));
      for (final line in t.items) {
        expect(line.editMark, KdsEditLineMark.changed);
        expect(line.editWas!.orderItemId, 'x1');
        expect(line.editWas!.modifiers, ['Tomato']);
      }
      expect(t.change!.removed, isEmpty);
    });

    test('7. add into the WAITING original ticket is ADDED', () {
      final rows = _Rows(
        orders: [_order(_o1, status: 'submitted', editCount: 1)],
        items: [
          _item('a1', _o1, name: 'Burger'),
          _item('y1', _o1, name: 'Fries', linePosition: 2, editId: _e1),
        ],
        edits: [_edit(_e1, _o1, 1, reasonCode: null)],
      );
      final t = rows.map().single;
      expect(t.items.first.editMark, isNull);
      expect(t.items.last.editMark, KdsEditLineMark.added);
      expect(t.items.last.editNumber, 1);
      expect(t.change!.latest.reasonCode, isNull);
    });

    test('8. add while in kitchen: an edit round labelled by the edit; a '
        'header only when the edit needs a "Got it"', () {
      Map<String, dynamic> y() => _item(
        'y1',
        _o1,
        name: 'Fries',
        linePosition: 3,
        round: _r2,
        editId: _e1,
        createdAt: _tEdit1,
      );
      // (a) a pure add opened a new ticket — no confirmation required.
      final noAck = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _item('a1', _o1, name: 'Burger'),
          y(),
        ],
        rounds: [_round(_r2, _o1, editId: _e1)],
        edits: [_edit(_e1, _o1, 1, ackRequired: false, reasonCode: null)],
      ).map();
      final round = _ticket(noAck, _roundKey(_o1, _r2));
      expect(round.openedByEditNumber, 1);
      expect(round.roundNumber, 2);
      expect(round.change, isNull);
      expect(round.items.single.editMark, isNull);
      expect(_ticket(noAck, _original(_o1)).change, isNull);

      // (b) the same edit also removed a line from the In-kitchen original
      // ticket, so it requires a "Got it": both cards get the header.
      final withAck = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _item('a1', _o1, name: 'Burger'),
          _retired(
            _item('b1', _o1, name: 'Soup', linePosition: 2),
            by: _e1,
            stage: 'preparing',
          ),
          y(),
        ],
        rounds: [_round(_r2, _o1, editId: _e1)],
        edits: [_edit(_e1, _o1, 1)],
      ).map();
      final round2 = _ticket(withAck, _roundKey(_o1, _r2));
      expect(round2.openedByEditNumber, 1);
      expect(round2.change!.upToEditNumber, 1);
      expect(round2.change!.removed, isEmpty);
      expect(round2.items.single.editMark, KdsEditLineMark.added);
      final original = _ticket(withAck, _original(_o1));
      expect(original.openedByEditNumber, isNull);
      expect(original.change!.removed.single.line.name, 'Soup');
    });
  });

  group('remake and emptied units', () {
    test('9. remake on Ready: the round line is a REMAKE and the Ready card '
        'shows the REMOVED line remade in Round 2', () {
      final board = _remakeOnReady(_o1).map();
      expect(board, hasLength(2));
      final round = _ticket(board, _roundKey(_o1, _r2));
      final remake = round.items.single;
      expect(remake.editMark, KdsEditLineMark.remake);
      expect(remake.editNumber, 1);
      expect(remake.editWas!.name, 'Burger');
      expect(remake.editWas!.modifiers, ['Tomato']);
      expect(remake.modifiers, isEmpty);
      expect(round.openedByEditNumber, 1);
      expect(round.change!.upToEditNumber, 1);

      final ready = _ticket(board, _original(_o1));
      expect(ready.status, KitchenTicketStatus.ready);
      expect(ready.items.map((i) => i.name), ['Fries']);
      final removed = ready.change!.removed.single;
      expect(removed.line.name, 'Burger');
      expect(removed.removedKitchenStage, 'ready');
      expect(removed.remadeInRoundNumber, 2);
    });

    test('10. emptied round: a standalone card with the same id, no items, '
        'no counts, in its former column', () {
      final board = _emptiedRound(_o1).map();
      expect(board, hasLength(2));
      final card = _ticket(board, _roundKey(_o1, _r3));
      expect(card.items, isEmpty);
      expect(card.kitchenCounts, isEmpty);
      expect(card.status, KitchenTicketStatus.inPreparation);
      expect(card.roundId, _r3);
      expect(card.roundNumber, 2);
      expect(card.submittedAt, DateTime.parse('2026-10-08T10:10:00Z'));
      expect(card.orderNumber, displayOrderCode(_o1));
      expect(card.tableLabel, 'T7');
      expect(card.customerName, 'Dana');
      expect(card.notes, 'Allergy: nuts');
      final change = card.change!;
      expect(change.standalone, isTrue);
      expect(change.emptied, isTrue);
      expect(change.formerStage, 'preparing');
      expect(change.removed.single.line.name, 'Fries');
      expect(card.changeAlertKey, '${_roundKey(_o1, _r3)}|e1');
      // The untouched original card is the base ticket, unchanged.
      expect(_ticket(board, _original(_o1)).change, isNull);
    });

    test('11. emptied ORIGINAL unit after the served jump: a standalone card '
        'plus the live round ticket', () {
      final rows = _Rows(
        orders: [_order(_o1, status: 'served', editCount: 1)],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger'),
            by: _e1,
            stage: 'ready',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2, round: _r2),
        ],
        rounds: [
          _round(
            _r2,
            _o1,
            status: 'accepted',
            createdAt: '2026-10-08T10:10:00Z',
          ),
        ],
        edits: [_edit(_e1, _o1, 1)],
      );
      final board = rows.map();
      expect(board, hasLength(2));
      final standalone = _ticket(board, _original(_o1));
      expect(standalone.change!.standalone, isTrue);
      expect(standalone.change!.emptied, isTrue);
      expect(standalone.status, KitchenTicketStatus.ready);
      expect(standalone.submittedAt, DateTime.parse(_t0));
      expect(standalone.roundId, isNull);
      final round = _ticket(board, _roundKey(_o1, _r2));
      expect(round.change, isNull);
      expect(round.items.single.name, 'Fries');
    });
  });

  group('admission and acknowledgement state', () {
    _Rows completed({String? ackAt}) => _Rows(
      orders: [_order(_o1, status: 'completed', editCount: 1)],
      items: [
        _retired(
          _item('a1', _o1, name: 'Burger'),
          by: _e1,
          stage: 'ready',
        ),
        _item('b1', _o1, name: 'Fries', linePosition: 2),
      ],
      edits: [_edit(_e1, _o1, 1, ackAt: ackAt)],
    );

    test('12. a COMPLETED order with a pending edit keeps its standalone '
        'card until it is acknowledged', () {
      final card = completed().map().single;
      expect(card.kitchenTicketId, _original(_o1));
      expect(card.items, isEmpty, reason: 'only edit-marked lines are shown');
      expect(card.change!.standalone, isTrue);
      expect(card.change!.emptied, isFalse, reason: 'Fries is still live');
      expect(card.change!.removed.single.line.name, 'Burger');
      expect(card.status, KitchenTicketStatus.ready);

      expect(completed(ackAt: _tAck).map(), isEmpty);
    });

    test('13. an ACKNOWLEDGED edit: no overlay, but the round label and the '
        'REMAKE stay', () {
      final board = _remakeOnReady(_o1, ackAt: _tAck).map();
      expect(board, hasLength(2));
      for (final t in board) {
        expect(t.change, isNull);
        expect(t.changeAlertKey, isNull);
      }
      final round = _ticket(board, _roundKey(_o1, _r2));
      expect(round.openedByEditNumber, 1);
      expect(round.items.single.editMark, KdsEditLineMark.remake);
      expect(round.items.single.editWas!.modifiers, ['Tomato']);
      final ready = _ticket(board, _original(_o1));
      expect(ready.items.single.editMark, isNull);
    });

    test('14. an edit that required NO "Got it" (served food only) leaves the '
        'board unchanged', () {
      final rows = _Rows(
        orders: [_order(_o1, status: 'served', editCount: 1)],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger'),
            by: _e1,
            stage: 'served',
          ),
          _item('a2', _o1, name: 'Cola', linePosition: 2),
          _item('b1', _o1, name: 'Fries', linePosition: 3, round: _r2),
        ],
        rounds: [_round(_r2, _o1, status: 'preparing')],
        edits: [_edit(_e1, _o1, 1, ackRequired: false)],
      );
      expect(_describe(rows.map()), _describe(rows.map(withEdits: false)));
      expect(rows.map().single.roundId, _r2);

      // The same served-food removal inside an edit that DOES need a "Got it"
      // (it also removed from the live round): the round card gets the
      // header, but the served original unit gets no standalone card.
      final mixed = _Rows(
        orders: rows.orders,
        items: [
          ...rows.items,
          _retired(
            _item('c1', _o1, name: 'Soup', linePosition: 4, round: _r2),
            by: _e1,
            stage: 'preparing',
          ),
        ],
        rounds: rows.rounds,
        edits: [_edit(_e1, _o1, 1)],
      ).map();
      expect(mixed.single.kitchenTicketId, _roundKey(_o1, _r2));
      expect(mixed.single.change!.removed.single.line.name, 'Soup');
    });
  });

  group('exclusions', () {
    test('15. a PAPER-channel edit adds nothing (no label, no remake)', () {
      final rows = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger', qty: 2),
            by: _e1,
            stage: 'printed',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2),
          _item(
            'a2',
            _o1,
            name: 'Burger',
            qty: 2,
            linePosition: 3,
            round: _r2,
            editId: _e1,
            replaces: 'a1',
          ),
        ],
        rounds: [_round(_r2, _o1, editId: _e1)],
        edits: [_edit(_e1, _o1, 1, channel: 'paper', ackRequired: false)],
      );
      final board = rows.map();
      expect(_describe(board), _describe(rows.map(withEdits: false)));
      expect(board.every((t) => t.openedByEditNumber == null), isTrue);
    });

    test('16. a VOIDED order with a pending edit: no change data; the red '
        'card excludes edit-retired lines and keeps round and edit-written '
        'lines', () {
      _Rows voided({String? voidAckAt}) => _Rows(
        orders: [
          _order(
            _o1,
            status: 'voided',
            editCount: 1,
            extra: {
              'kitchen_ack_required': true,
              'kitchen_ack_at': voidAckAt,
              'voided_at': '2026-10-08T10:40:00Z',
              'voided_from_status': 'preparing',
            },
          ),
        ],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger', status: 'voided'),
            by: _e1,
            stage: 'preparing',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2, status: 'voided'),
          _item(
            'c1',
            _o1,
            name: 'Soup',
            linePosition: 3,
            round: _r2,
            editId: _e1,
            status: 'voided',
          ),
        ],
        rounds: [_round(_r2, _o1, status: 'voided', editId: _e1)],
        edits: [_edit(_e1, _o1, 1)],
      );
      final card = voided().map().single;
      expect(card.status, KitchenTicketStatus.cancelled);
      expect(card.requiresAck, isTrue);
      expect(card.change, isNull);
      expect(card.requiresChangeAck, isFalse);
      expect(card.openedByEditNumber, isNull);
      expect(card.items.map((i) => i.name), ['Fries', 'Soup']);
      expect(card.items.every((i) => i.editMark == null), isTrue);
      // An acknowledged void leaves the board, edits or not.
      expect(voided(voidAckAt: _tAck).map(), isEmpty);
    });

    test('17. a direct_print order with edit rows gets nothing', () {
      final rows = _Rows(
        orders: [
          _order(
            _o1,
            status: 'submitted',
            dispatchMode: 'direct_print',
            editCount: 1,
          ),
        ],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger'),
            by: _e1,
            stage: 'submitted',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2, editId: _e1),
        ],
        edits: [_edit(_e1, _o1, 1)],
      );
      expect(rows.map(), isEmpty);
    });
  });

  group('multiple edits and acknowledgement', () {
    _Rows twoRemovals({required bool second}) => _Rows(
      orders: [_order(_o1, editCount: second ? 2 : 1)],
      items: [
        _retired(
          _item('a1', _o1, name: 'Burger'),
          by: _e1,
          stage: 'preparing',
        ),
        if (second)
          _retired(
            _item('b1', _o1, name: 'Fries', linePosition: 2),
            by: _e2,
            stage: 'preparing',
          )
        else
          _item('b1', _o1, name: 'Fries', linePosition: 2),
        _item('c1', _o1, name: 'Soup', linePosition: 3),
      ],
      edits: [
        _edit(_e1, _o1, 1),
        if (second) _edit(_e2, _o1, 2, createdAt: _tEdit2),
      ],
    );

    test('18. two pending edits on one card: [1, 2], and the alert key moves '
        'from e1 to e2', () {
      final first = twoRemovals(second: false).map().single;
      expect(first.changeAlertKey, '${_original(_o1)}|e1');
      final t = twoRemovals(second: true).map().single;
      expect(t.change!.pendingEdits.map((e) => e.editNumber), [1, 2]);
      expect(t.change!.latest.editNumber, 2);
      expect(t.change!.latest.createdAt, DateTime.parse(_tEdit2));
      expect(t.changeAlertKey, '${_original(_o1)}|e2');
      expect(t.changeAlertKey, isNot(first.changeAlertKey));
      // Both numbers are on this card, so "Got it" confirms nothing extra.
      expect(t.change!.alsoAcknowledges, isEmpty);
      expect(t.change!.removed.map((r) => (r.line.name, r.editNumber)), [
        ('Burger', 1),
        ('Fries', 2),
      ]);
      expect(t.items.map((i) => i.name), ['Soup']);
    });

    test('19. a chain X -> X1 -> X2 collapses to was X while both edits are '
        'pending, and to was X1 once E1 is acknowledged', () {
      _Rows chain({String? e1Ack}) => _Rows(
        orders: [_order(_o1, editCount: 2)],
        items: [
          _retired(
            _item('x0', _o1, name: 'Burger', qty: 3),
            by: _e1,
            stage: 'preparing',
          ),
          _retired(
            _item(
              'x1',
              _o1,
              name: 'Burger',
              qty: 3,
              editId: _e1,
              replaces: 'x0',
            ),
            by: _e2,
            stage: 'preparing',
          ),
          _item('x2', _o1, name: 'Burger', qty: 3, editId: _e2, replaces: 'x1'),
        ],
        mods: [_mod('m0', 'x0', 'Tomato'), _mod('m2', 'x2', 'Cheese')],
        edits: [
          _edit(_e1, _o1, 1, ackAt: e1Ack),
          _edit(_e2, _o1, 2, createdAt: _tEdit2),
        ],
      );
      final both = chain().map().single;
      final line = both.items.single;
      expect(line.editMark, KdsEditLineMark.changed);
      expect(line.editNumber, 2);
      expect(line.editWas!.orderItemId, 'x0');
      expect(line.editWas!.modifiers, ['Tomato']);
      expect(line.modifiers, ['Cheese']);
      expect(both.change!.pendingEdits.map((e) => e.editNumber), [1, 2]);
      expect(both.change!.removed, isEmpty, reason: 'no double listing');

      final afterAck = chain(e1Ack: _tAck).map().single;
      expect(afterAck.items.single.editWas!.orderItemId, 'x1');
      expect(afterAck.items.single.editWas!.modifiers, isEmpty);
      expect(afterAck.change!.pendingEdits.map((e) => e.editNumber), [2]);
      expect(afterAck.change!.orderPendingEditNumbers, [2]);
      expect(afterAck.change!.removed, isEmpty);
    });

    test('20. a line added then removed by two pending edits still shows as '
        'REMOVED', () {
      final rows = _Rows(
        orders: [_order(_o1, status: 'submitted', editCount: 2)],
        items: [
          _item('a1', _o1, name: 'Burger'),
          _retired(
            _item('y1', _o1, name: 'Fries', linePosition: 2, editId: _e1),
            by: _e2,
            stage: 'submitted',
          ),
        ],
        edits: [
          _edit(_e1, _o1, 1, reasonCode: null),
          _edit(_e2, _o1, 2, createdAt: _tEdit2),
        ],
      );
      final t = rows.map().single;
      expect(t.items.single.name, 'Burger');
      expect(t.items.single.editMark, isNull);
      final removed = t.change!.removed.single;
      expect(removed.line.name, 'Fries');
      expect(removed.editNumber, 2);
      expect(t.change!.pendingEdits.map((e) => e.editNumber), [1, 2]);
    });

    test('21. cross-card: the round card confirms up to 2 and also 1; the '
        'original card confirms up to 1', () {
      final board = _crossCard(_o1).map();
      final round = _ticket(board, _roundKey(_o1, _r2));
      expect(round.change!.pendingEdits.map((e) => e.editNumber), [2]);
      expect(round.change!.upToEditNumber, 2);
      expect(round.change!.alsoAcknowledges, [1]);
      expect(round.change!.orderPendingEditNumbers, [1, 2]);
      expect(round.change!.removed.single.line.name, 'Soup');
      final original = _ticket(board, _original(_o1));
      expect(original.change!.upToEditNumber, 1);
      expect(original.change!.alsoAcknowledges, isEmpty);
      expect(original.change!.removed.single.line.name, 'Burger');
    });
  });

  group('robustness', () {
    test('22. an unknown edit id (a page still draining) gives no overlay and '
        'no crash; the overlay appears once the edit row arrives', () {
      final rows = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _retired(
            _item('x1', _o1, name: 'Burger', qty: 2),
            by: _e1,
            stage: 'preparing',
          ),
          _item('x2', _o1, name: 'Burger', editId: _e1, replaces: 'x1'),
        ],
        // Only an unrelated order's edit has arrived so far.
        edits: [_edit(_e9, _o2, 1)],
      );
      final partial = rows.map().single;
      expect(partial.change, isNull);
      expect(partial.items.single.editMark, isNull);
      expect(_describe([partial]), _describe(rows.map(withEdits: false)));

      final complete = rows.withEdits([_edit(_e1, _o1, 1)]).map().single;
      expect(complete.items.single.editMark, KdsEditLineMark.changed);
      expect(complete.change!.upToEditNumber, 1);
    });

    test('23. malformed edit rows are ignored', () {
      final good = _edit(_e1, _o1, 1);
      final malformed = <Map<String, dynamic>>[
        {...good, 'edit_number': '1'},
        {...good, 'edit_number': 0},
        {...good, 'kitchen_channel': 'fax'},
        {...good}..remove('id'),
        {...good, 'order_id': 42},
        {...good, 'deleted_at': _tAck},
        {...good, 'kitchen_ack_at': 'not-a-time'},
      ];
      for (final row in malformed) {
        expect(KdsOrderEdit.tryParse(row), isNull, reason: '$row');
      }
      final rows = _Rows(
        orders: [_order(_o1, editCount: 1)],
        items: [
          _retired(
            _item('a1', _o1, name: 'Burger'),
            by: _e1,
            stage: 'preparing',
          ),
          _item('b1', _o1, name: 'Fries', linePosition: 2),
        ],
        edits: malformed,
      );
      expect(_describe(rows.map()), _describe(rows.map(withEdits: false)));

      final parsed = KdsOrderEdit.tryParse(good)!;
      expect(parsed.id, _e1);
      expect(parsed.orderId, _o1);
      expect(parsed.editNumber, 1);
      expect(parsed.channel, KdsEditChannel.kds);
      expect(parsed.ackRequired, isTrue);
      expect(parsed.ackAt, isNull);
      expect(parsed.awaitsKitchenAck, isTrue);
      expect(parsed.createdAt, DateTime.parse(_tEdit1));
      // created_at missing -> client_created_at.
      final fallback = KdsOrderEdit.tryParse({...good, 'created_at': null})!;
      expect(fallback.createdAt, DateTime.parse(_tEdit1));
      final paper = KdsOrderEdit.tryParse({
        ...good,
        'kitchen_channel': 'paper',
        'kitchen_ack_required': false,
      })!;
      expect(paper.awaitsKitchenAck, isFalse);
    });

    test('24. source scan: the edit model and the overlay never read a staff, '
        'session, device or money key', () {
      final forbidden = RegExp(
        r'employee|membership|pin_session|device|local_operation|'
        r'kitchen_ack_by|bill_presented|(^|_)minor($|_)|receipt',
      );
      for (final relative in [
        'lib/src/kds_order_edit.dart',
        'lib/src/kds_order_edit_overlay.dart',
        'lib/src/kds_row_views.dart',
      ]) {
        final code = _codeOnly(_packageSource(relative));
        final literals = RegExp(
          r"'([^'\\\n]*)'",
        ).allMatches(code).map((m) => m.group(1)!).toList();
        expect(literals, isNotEmpty, reason: '$relative was read');
        for (final literal in literals) {
          expect(
            forbidden.hasMatch(literal),
            isFalse,
            reason: '$relative reads the key "$literal"',
          );
        }
      }
    });

    test('25. kitchen counts are exactly the base counts', () {
      final rows = _modifyOneOfThree(_o1) + _emptiedRound(_o2);
      final base = {
        for (final t in rows.map(withEdits: false)) t.kitchenTicketId: t,
      };
      final overlaid = rows.map();
      for (final t in overlaid) {
        final before = base[t.kitchenTicketId];
        if (before == null) {
          expect(t.change!.standalone, isTrue);
          expect(t.kitchenCounts, isEmpty);
          continue;
        }
        expect(
          [for (final c in t.kitchenCounts) '${c.label}|${c.quantity}'],
          [for (final c in before.kitchenCounts) '${c.label}|${c.quantity}'],
        );
      }
      // 2 + 1 patties on the modified card (the retired 3× no longer counts).
      expect(
        _ticket(overlaid, _original(_o1)).kitchenCounts.single.quantity,
        3,
      );
    });

    test('26. standalone cards take their FIFO place', () {
      final rows =
          _Rows(
            orders: [
              _order(
                _o1,
                status: 'completed',
                createdAt: '2026-10-08T09:00:00Z',
                editCount: 1,
              ),
            ],
            items: [
              _retired(
                _item('a1', _o1, name: 'Burger'),
                by: _e1,
                stage: 'ready',
              ),
              _item('b1', _o1, name: 'Fries', linePosition: 2),
            ],
            edits: [_edit(_e1, _o1, 1)],
          ) +
          _Rows(
            orders: [_order(_o2, createdAt: '2026-10-08T09:30:00Z')],
            items: [_item('c1', _o2, name: 'Soup')],
          ) +
          _emptiedRound(_o3, roundId: _r3);
      final board = rows.map();
      expect(board.map((t) => t.kitchenTicketId), [
        _original(_o1), // standalone, 09:00
        _original(_o2), // base, 09:30
        _original(_o3), // base, 10:00
        _roundKey(_o3, _r3), // standalone round, 10:10
      ]);
    });

    test('27. a legacy line_position 0 delta degrades to ADDED', () {
      for (final deltaPosition in [0, 5]) {
        final rows = _Rows(
          orders: [_order(_o1, editCount: 1)],
          items: [
            _item('x1', _o1, name: 'Burger', qty: 2, linePosition: 0),
            _item(
              'x9',
              _o1,
              name: 'Burger',
              linePosition: deltaPosition,
              editId: _e1,
            ),
          ],
          edits: [_edit(_e1, _o1, 1)],
        );
        final t = rows.map().single;
        final delta = t.items.singleWhere((i) => i.orderItemId == 'x9');
        expect(delta.editMark, KdsEditLineMark.added, reason: '$deltaPosition');
      }
    });

    test('28. shuffled input gives an identical board', () {
      final rows =
          _modifyOneOfThree(_o1) +
          _remakeOnReady(_o2) +
          _emptiedRound(_o3) +
          _crossCard(
            '77777777-0000-4000-8000-0000000000a7',
            roundId: '44444444-0000-4000-8000-0000000000b7',
          );
      final expected = _describe(rows.map());
      for (var seed = 1; seed <= 8; seed++) {
        final random = Random(seed);
        List<Map<String, dynamic>> shuffled(List<Map<String, dynamic>> l) =>
            [...l]..shuffle(random);
        final board = KdsTicketMapper.map(
          orders: shuffled(rows.orders),
          orderItems: shuffled(rows.items),
          modifiers: shuffled(rows.mods),
          tables: _tables,
          serviceRounds: shuffled(rows.rounds),
          orderEdits: shuffled(rows.edits),
        );
        expect(_describe(board), expected, reason: 'seed $seed');
      }
    });
  });
}

/// Reads a feature_kitchen source file whether the test runs from the package
/// or from the repository root (never passes vacuously).
String _packageSource(String relative) {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    for (final candidate in [
      '${dir.path}/$relative',
      '${dir.path}/packages/feature_kitchen/$relative',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) return file.readAsStringSync();
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate $relative from ${Directory.current.path}');
}

/// Drops full-line `//` / `///` comments so a prose mention never trips the
/// scan, while every real key (a string literal in code) still does.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');
