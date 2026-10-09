import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';

/// ORDER-EDIT-001E — the POS detail parser reads the ORDER-EDIT-001B additions
/// to `pos_order_detail` (API_CONTRACT §4.45.10):
///
///  * per item `unit_status`, `legacy`, `edit_id`;
///  * per order `dispatch_mode`, `kitchen_channel`, `edit_count`,
///    `has_active_round`;
///  * the envelope's `edits[]` and `branch_features`.
///
/// Every one is a TOLERANT, money-free pluck: an older server (no keys) or a
/// malformed value degrades to the default and NEVER fails the detail, while
/// every money field stays exactly as strict as before.

Map<String, Object?> _item({
  String id = 'oi-burger',
  String unitStatus = 'preparing',
  Object? legacy = false,
  Object? editId,
  String? roundId,
  bool with001B = true,
}) => {
  'order_item_id': id,
  'menu_item_id': 'mi-burger',
  'menu_item_name_snapshot': 'Burger',
  'quantity': 2,
  'unit_price_minor_snapshot': 4000,
  'line_discount_minor': 0,
  'line_total_minor': 8000,
  'category_display_order_snapshot': 1,
  'item_display_order_snapshot': 1,
  'line_position': 1,
  'status': 'pending',
  'notes': null,
  'service_round_id': roundId,
  'round_number': roundId == null ? null : 2,
  'prep_snapshot': null,
  'modifiers': const <Object?>[],
  if (with001B) 'unit_status': unitStatus,
  if (with001B) 'legacy': legacy,
  if (with001B) 'edit_id': editId,
};

Map<String, Object?> _edit(int n, {bool pending = false, String? ackAt}) => {
  'order_edit_id': 'edit-$n',
  'edit_number': n,
  'created_at': '2026-10-08T12:0$n:00Z',
  'reason_code': 'customer_changed_mind',
  'reason_text': n == 2 ? 'no onions' : null,
  'kitchen_channel': 'kds',
  'kitchen_ack_required': true,
  'kitchen_ack_at': ackAt,
  'kitchen_ack_pending': pending,
};

/// The full ORDER-EDIT-001B envelope shape (migration 20261008190000,
/// app.pos_order_detail).
Map<String, Object?> _detail001B({
  List<Object?>? rounds,
  bool hasActiveRound = true,
  Object? edits,
  Object? branchFeatures,
}) => {
  'ok': true,
  'entity': 'order_detail',
  'server_ts': '2026-10-08T12:10:00Z',
  'order': {
    'order_id': 'order-1',
    'order_code': '#ABC123',
    'order_type': 'takeaway',
    'status': 'served',
    'revision': 4,
    'table_label': null,
    'customer_name': null,
    'customer_phone': null,
    'currency_code': 'ILS',
    'subtotal_minor': 9500,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 9500,
    'receipt_number': null,
    'created_at': '2026-10-08T11:50:00Z',
    'updated_at': '2026-10-08T12:05:00Z',
    'dispatch_mode': 'kds',
    'edit_count': 2,
    'has_active_round': hasActiveRound,
    'kitchen_channel': 'kds',
  },
  'items': [
    _item(unitStatus: 'served', legacy: true),
    _item(
      id: 'oi-fries',
      unitStatus: 'preparing',
      legacy: false,
      editId: 'edit-2',
      roundId: 'r-2',
    ),
  ],
  'rounds':
      rounds ??
      [
        {
          'round_id': 'r-2',
          'round_number': 2,
          'status': 'preparing',
          'ready_at': null,
          'created_at': '2026-10-08T12:02:00Z',
        },
      ],
  'payment': null,
  'edits':
      edits ??
      [_edit(2, pending: true), _edit(1, ackAt: '2026-10-08T12:03:00Z')],
  'branch_features':
      branchFeatures ??
      {
        'order_edit_enabled': true,
        'order_edit_finished_food_manager_only': false,
      },
};

/// The same order as a server predating ORDER-EDIT-001B would send it.
Map<String, Object?> _detailPre001B() {
  final raw = _detail001B();
  final order = Map<String, Object?>.of(raw['order']! as Map<String, Object?>)
    ..remove('dispatch_mode')
    ..remove('edit_count')
    ..remove('has_active_round')
    ..remove('kitchen_channel');
  return {
      ...raw,
      'order': order,
      'items': [
        _item(with001B: false),
        _item(id: 'oi-fries', roundId: 'r-2', with001B: false),
      ],
    }
    ..remove('edits')
    ..remove('branch_features');
}

Map<String, Object?> _round(String id, int n, String status) => {
  'round_id': id,
  'round_number': n,
  'status': status,
};

PosOrderDetail _withRounds(List<Object?> rounds, {bool flag = true}) =>
    PosOrderDetail.fromJson(_detail001B(rounds: rounds, hasActiveRound: flag))!;

void main() {
  group('the full 001B envelope', () {
    test('order-level fields', () {
      final d = PosOrderDetail.fromJson(_detail001B())!;
      expect(d.dispatchMode, 'kds');
      expect(d.kitchenChannel, PosKitchenChannel.kds);
      expect(d.editCount, 2);
      expect(d.hasActiveRound, isTrue);
      expect(d.branchFeatures?.orderEditEnabled, isTrue);
      expect(d.branchFeatures?.finishedFoodManagerOnly, isFalse);
    });

    test('item-level fields', () {
      final items = PosOrderDetail.fromJson(_detail001B())!.items;
      expect(items.map((i) => i.unitStatus), ['served', 'preparing']);
      expect(items.map((i) => i.legacy), [true, false]);
      expect(items.map((i) => i.editId), [null, 'edit-2']);
    });

    test('edits: oldest first, verbatim, the pending verdict taken as is', () {
      final edits = PosOrderDetail.fromJson(_detail001B())!.edits!;
      expect(edits.map((e) => e.editNumber), [1, 2]);
      expect(edits.map((e) => e.orderEditId), ['edit-1', 'edit-2']);
      final first = edits.first;
      expect(first.createdAt, DateTime.utc(2026, 10, 8, 12, 1));
      expect(first.reasonCode, 'customer_changed_mind');
      expect(first.reasonText, isNull);
      expect(first.kitchenChannel, PosKitchenChannel.kds);
      expect(first.kitchenAckRequired, isTrue);
      expect(first.kitchenAckAt, DateTime.utc(2026, 10, 8, 12, 3));
      expect(first.kitchenAckPending, isFalse);
      expect(edits.last.reasonText, 'no onions');
      expect(edits.last.kitchenAckPending, isTrue);
    });

    test('paper channel and an unresolvable channel', () {
      final paper = _detail001B();
      (paper['order']! as Map<String, Object?>)['kitchen_channel'] = 'paper';
      expect(
        PosOrderDetail.fromJson(paper)!.kitchenChannel,
        PosKitchenChannel.paper,
      );
      final unresolvable = _detail001B();
      (unresolvable['order']! as Map<String, Object?>)['kitchen_channel'] =
          null;
      expect(PosOrderDetail.fromJson(unresolvable)!.kitchenChannel, isNull);
    });

    test('an order with no edits reads an empty list, not unknown', () {
      final d = PosOrderDetail.fromJson(_detail001B(edits: const <Object?>[]))!;
      expect(d.edits, isEmpty);
    });
  });

  group('a pre-001B envelope parses with the defaults', () {
    test('every new field is its default; the money is unchanged', () {
      final d = PosOrderDetail.fromJson(_detailPre001B())!;
      expect(d.dispatchMode, isNull);
      expect(d.kitchenChannel, isNull);
      expect(d.editCount, 0);
      expect(d.hasActiveRound, isFalse);
      expect(d.edits, isNull);
      expect(d.branchFeatures, isNull);
      for (final i in d.items) {
        expect(i.unitStatus, isNull);
        expect(i.legacy, isNull);
        expect(i.editId, isNull);
      }
      expect(d.grandTotalMinor, 9500);
      expect(d.items.map((i) => i.lineTotalMinor), [8000, 8000]);
    });
  });

  group('malformed new keys never fail the detail', () {
    test('order and envelope keys', () {
      final raw = _detail001B(edits: 'x', branchFeatures: const <Object?>[]);
      final order = raw['order']! as Map<String, Object?>;
      order['dispatch_mode'] = 7;
      order['kitchen_channel'] = 'fax';
      order['edit_count'] = 1.5;
      order['has_active_round'] = 'true';
      final d = PosOrderDetail.fromJson(raw);
      expect(d, isNotNull);
      expect(d!.dispatchMode, isNull);
      expect(d.kitchenChannel, isNull);
      expect(d.editCount, 0);
      expect(d.hasActiveRound, isFalse);
      expect(d.edits, isNull);
      expect(d.branchFeatures, isNull);
    });

    test('a negative edit_count reads 0', () {
      final raw = _detail001B();
      (raw['order']! as Map<String, Object?>)['edit_count'] = -1;
      expect(PosOrderDetail.fromJson(raw)!.editCount, 0);
    });

    test('item keys', () {
      final raw = _detail001B();
      raw['items'] = [
        {..._item(), 'unit_status': 5, 'legacy': 'true', 'edit_id': ''},
      ];
      final item = PosOrderDetail.fromJson(raw)!.items.single;
      expect(item.unitStatus, isNull);
      expect(item.legacy, isNull, reason: 'null = legacy for consumers');
      expect(item.editId, isNull);
    });

    test('ONE unreadable edits[] element makes the history unknown', () {
      for (final bad in <Object?>[
        {'order_edit_id': 'edit-9'}, // no edit_number
        {'order_edit_id': 'edit-9', 'edit_number': 0},
        {'order_edit_id': 'edit-9', 'edit_number': '3'},
        {'order_edit_id': '', 'edit_number': 3},
        {'edit_number': 3},
        'edit',
      ]) {
        final d = PosOrderDetail.fromJson(_detail001B(edits: [_edit(1), bad]));
        expect(d, isNotNull, reason: '$bad');
        expect(d!.edits, isNull, reason: '$bad');
      }
    });

    test('tolerant edit fields degrade without dropping the edit', () {
      final edits = PosOrderDetailEdit.listFromJson([
        {
          'order_edit_id': 'edit-1',
          'edit_number': 1,
          'created_at': 'not a time',
          'reason_code': 5,
          'reason_text': '',
          'kitchen_channel': 'fax',
          'kitchen_ack_required': 'yes',
          'kitchen_ack_at': 3,
          'kitchen_ack_pending': 1,
        },
      ])!;
      final e = edits.single;
      expect(e.createdAt, isNull);
      expect(e.reasonCode, isNull);
      expect(e.reasonText, isNull);
      expect(e.kitchenChannel, isNull);
      expect(e.kitchenAckRequired, isFalse);
      expect(e.kitchenAckAt, isNull);
      expect(e.kitchenAckPending, isFalse);
    });

    test('the money-strict failures are unchanged', () {
      final noTotal = _detail001B();
      (noTotal['order']! as Map<String, Object?>).remove('grand_total_minor');
      expect(PosOrderDetail.fromJson(noTotal), isNull);

      final floatLine = _detail001B();
      floatLine['items'] = [
        {..._item(), 'line_total_minor': 8000.0},
      ];
      expect(PosOrderDetail.fromJson(floatLine), isNull);

      final badRound = _detail001B(
        rounds: [
          {'round_id': 'r-2', 'status': 'preparing'},
        ],
      );
      expect(PosOrderDetail.fromJson(badRound), isNull);
    });
  });

  group('activeRoundStage', () {
    test('no rounds and no flag: nothing is active', () {
      expect(_withRounds(const [], flag: false).activeRoundStage, isNull);
    });

    test('only voided or served rounds: nothing is active', () {
      expect(
        _withRounds([
          _round('r-2', 2, 'voided'),
          _round('r-3', 3, 'served'),
        ], flag: false).activeRoundStage,
        isNull,
      );
    });

    test('a preparing round is In kitchen', () {
      expect(
        _withRounds([_round('r-2', 2, 'preparing')]).activeRoundStage,
        PosRoundStage.inKitchen,
      );
    });

    test('a submitted round is In kitchen', () {
      expect(
        _withRounds([_round('r-2', 2, 'submitted')]).activeRoundStage,
        PosRoundStage.inKitchen,
      );
    });

    test('every active round ready is Ready', () {
      expect(
        _withRounds([
          _round('r-2', 2, 'ready'),
          _round('r-3', 3, 'ready'),
          _round('r-4', 4, 'served'),
        ]).activeRoundStage,
        PosRoundStage.ready,
      );
    });

    test('ready + accepted is still In kitchen', () {
      expect(
        _withRounds([
          _round('r-2', 2, 'ready'),
          _round('r-3', 3, 'accepted'),
        ]).activeRoundStage,
        PosRoundStage.inKitchen,
      );
    });

    test('the server flag with no round parsed reads In kitchen', () {
      expect(_withRounds(const []).activeRoundStage, PosRoundStage.inKitchen);
    });
  });

  group('posLineStageFor', () {
    test('KDS: the raw unit status maps to the stage', () {
      const expected = {
        'submitted': PosLineStage.waiting,
        'accepted': PosLineStage.inKitchen,
        'preparing': PosLineStage.inKitchen,
        'ready': PosLineStage.ready,
        'served': PosLineStage.served,
      };
      for (final entry in expected.entries) {
        expect(
          posLineStageFor(
            unitStatus: entry.key,
            channel: PosKitchenChannel.kds,
          ),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('an unknown or missing status shows no stage', () {
      for (final s in <String?>['completed', 'voided', 'queued', null]) {
        expect(
          posLineStageFor(unitStatus: s, channel: PosKitchenChannel.kds),
          isNull,
          reason: '$s',
        );
      }
      expect(
        posLineStageFor(unitStatus: 'preparing', channel: null),
        PosLineStage.inKitchen,
        reason: 'an unresolvable channel still has a unit status',
      );
    });

    test('paper: every line is Printed, whatever its raw status', () {
      for (final s in <String?>['submitted', 'ready', 'served', null]) {
        expect(
          posLineStageFor(unitStatus: s, channel: PosKitchenChannel.paper),
          PosLineStage.printed,
          reason: '$s',
        );
      }
    });
  });

  test('PosKitchenChannel.fromWire never coerces', () {
    expect(PosKitchenChannel.fromWire('kds'), PosKitchenChannel.kds);
    expect(PosKitchenChannel.fromWire('paper'), PosKitchenChannel.paper);
    for (final raw in <Object?>[null, 'KDS', 'printer_only', 1]) {
      expect(PosKitchenChannel.fromWire(raw), isNull, reason: '$raw');
    }
  });
}
