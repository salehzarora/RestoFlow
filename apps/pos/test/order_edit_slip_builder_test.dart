@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:restoflow_data_local/kitchen_dispatch_document.dart'
    show KitchenDispatchDocument, rejectHostileKitchenKeys;
import 'package:restoflow_feature_kitchen/kitchen_print.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart'
    show KdsEditLineMark, KdsItemView;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';
import 'package:restoflow_pos/src/data/order_edit_slip.dart';
import 'package:restoflow_pos/src/data/round_print_claim_store.dart';

import 'support/pos_package_root.dart';

/// ORDER-EDIT-001F — the POS's HAND-BUILT paper change slip, held to BYTE
/// PARITY with the slip the spool decodes from the server's stored payload.
///
/// The fixtures are REAL paper edits captured on a local PostgreSQL build of
/// supabase/migrations (`test/fixtures/order_edit_slip/capture_probe.sql`):
/// `app.edit_order` through `public.sync_push`, `pos_order_detail` before and
/// after, and the STORED `kitchen_print_dispatches.money_free_payload`. For
/// each, the hand-built view (entry baseline + frozen payload + envelope +
/// post-apply detail) must equal `orderChangeSlipViewFromKitchenDispatch` of
/// the stored payload — field by field, and in the rendered ESC/POS bytes in
/// en / ar / he.

const _parityCases = ['a_every_op', 'a_second_edit', 'b_legacy_ranks_add'];

Map<String, Object?> _fixture(String name) {
  final root = locatePosPackageRoot();
  final file = File(
    p.join(root.path, 'test', 'fixtures', 'order_edit_slip', '$name.json'),
  );
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

Map<String, Object?> _map(Object? raw) => (raw as Map).cast<String, Object?>();

/// Everything one captured edit gives the hand-built path.
class _Case {
  _Case(String name) : raw = _fixture(name);

  final Map<String, Object?> raw;

  Map<String, Object?> get payload => _map(raw['payload']);
  String get staff => raw['staff_display_name']! as String;

  PosOrderDetail get before => PosOrderDetail.fromJson(raw['before'])!;
  PosOrderDetail get after => PosOrderDetail.fromJson(raw['after'])!;

  OrderEditBaseline get baseline =>
      OrderEditBaseline.fromDetail(before).baseline!;

  OrderEditApplied get applied => classifyOrderEditResponse(
    raw['envelope'],
    localOperationId: raw['local_operation_id']! as String,
    orderId: payload['order_id']! as String,
  ).applied!;

  Map<String, OrderEditSlipItem> get was =>
      orderEditSlipWasLines(baseline, payload);

  OrderChangeSlipView? handBuilt({
    PosOrderDetail? fresh,
    Map<String, Object?>? payloadOverride,
    OrderEditApplied? appliedOverride,
    Map<String, OrderEditSlipItem>? wasOverride,
    String? orderCode,
  }) => buildOrderEditChangeSlip(
    orderCode: orderCode ?? before.orderCode,
    applied: appliedOverride ?? applied,
    payload: payloadOverride ?? payload,
    was: wasOverride ?? was,
    fresh: fresh ?? after,
    staffDisplayName: staff,
  );

  /// The SERVER's slip, exactly as the spool decodes it.
  OrderChangeSlipView get server {
    final dispatch = _map(raw['dispatch']);
    rejectHostileKitchenKeys(dispatch, path: 'dispatch');
    return orderChangeSlipViewFromKitchenDispatch(
      KitchenDispatchDocument.fromJson(dispatch),
    );
  }
}

/// A canonical, comparable dump of every field a slip carries.
Object? _dump(OrderChangeSlipView v) => {
  'orderCode': v.orderCode,
  'editNumber': v.editNumber,
  'orderType': v.orderType,
  'tableLabel': v.tableLabel,
  'customerName': v.customerName,
  'orderNote': v.orderNote,
  'editedAt': v.editedAt?.toUtc().toIso8601String(),
  'editedAtIsLocal': v.editedAt == null ? null : !v.editedAt!.isUtc,
  'reasonCode': v.reasonCode,
  'reasonText': v.reasonText,
  'staffFirstName': v.staffFirstName,
  'changes': [
    for (final e in v.changes)
      switch (e) {
        OrderChangeRemoved(:final was) => {'remove': _item(was)},
        OrderChangeQuantity(:final was, :final nowQuantity) => {
          'set_quantity': _item(was),
          'now': nowQuantity,
        },
        OrderChangeModified(:final was, :final now) => {
          'modify': _item(was),
          'now': [for (final i in now) _item(i)],
        },
        OrderChangeAdded(:final now) => {
          'add': [for (final i in now) _item(i)],
        },
      },
  ],
  'orderNow': [for (final i in v.orderNow) _item(i)],
};

Object? _item(KdsItemView i) => {
  'name': i.name,
  'quantity': i.quantity,
  'modifiers': i.modifiers,
  'note': i.note,
  'prep': [for (final c in i.prepComponents) c.toJson()],
  'categoryDisplayOrder': i.categoryDisplayOrder,
  'itemDisplayOrder': i.itemDisplayOrder,
  'linePosition': i.linePosition,
  'orderItemId': i.orderItemId,
  'editMark': i.editMark?.name,
  'editNumber': i.editNumber,
};

/// The printed document, line by line (exact strings, ar/he included).
List<String> _document(OrderChangeSlipView slip, String lang) {
  final doc = buildOrderChangeSlipPrintDocument(
    slip: slip,
    labels: kitchenTicketPrintLabelsForLanguageCode(lang),
    changeLabels: kitchenChangeSlipLabelsForLanguageCode(lang),
    restaurantName: 'Slip Parity',
  );
  return [
    doc.title,
    for (final l in doc.lines)
      '${l.kind.name}|${l.left}|${l.right}|${l.emphasised}',
  ];
}

Future<List<int>> _bytes(OrderChangeSlipView slip, String lang) =>
    renderOrderChangeSlipBytes(
      slip: slip,
      labels: kitchenTicketPrintLabelsForLanguageCode(lang),
      changeLabels: kitchenChangeSlipLabelsForLanguageCode(lang),
      restaurantName: 'Slip Parity',
    );

PosOrderDetail _detailWith(
  Map<String, Object?> raw,
  void Function(Map<String, Object?> copy) edit,
) {
  final copy = _map(jsonDecode(jsonEncode(raw)));
  edit(copy);
  return PosOrderDetail.fromJson(copy)!;
}

void main() {
  group('parity with the server slip (real captured paper edits)', () {
    for (final name in _parityCases) {
      test('$name: the hand-built view equals the decoded stored payload', () {
        final c = _Case(name);
        final hand = c.handBuilt();
        expect(hand, isNotNull);
        expect(_dump(hand!), _dump(c.server));
      });

      test('$name: the printed document and the ESC/POS bytes are identical '
          'in en / ar / he', () async {
        final c = _Case(name);
        final hand = c.handBuilt()!;
        final server = c.server;
        for (final lang in ['en', 'ar', 'he']) {
          expect(_document(hand, lang), _document(server, lang), reason: lang);
          expect(await _bytes(hand, lang), await _bytes(server, lang));
        }
      });
    }

    test('the fixtures cover every op and every projection rule', () {
      final ops = <String>{};
      var increase = false;
      var reduce = false;
      var split = false;
      for (final name in _parityCases) {
        final server = _Case(name).server;
        for (final e in server.changes) {
          switch (e) {
            case OrderChangeRemoved():
              ops.add('remove');
            case final OrderChangeQuantity q:
              ops.add('set_quantity');
              if (q.isIncrease) increase = true;
              if (q.delta < 0) reduce = true;
            case OrderChangeModified(:final now):
              ops.add('modify');
              if (now.length > 1) split = true;
            case OrderChangeAdded():
              ops.add('add');
          }
        }
      }
      expect(ops, {'remove', 'set_quantity', 'modify', 'add'});
      expect(increase && reduce && split, isTrue);

      final a = _Case('a_every_op').server;
      final lines = [
        ...a.orderNow,
        for (final e in a.changes)
          if (e case OrderChangeModified(:final was)) was,
      ];
      // "name ×N" modifiers, a space-trimmed note, a fractional prep count.
      expect(lines.any((l) => l.modifiers.contains('tomato ×2')), isTrue);
      expect(lines.map((l) => l.note), containsAll(['no salt', 'well done']));
      expect(
        lines.expand((l) => l.prepComponents).map((c) => c.quantity),
        contains(1.5),
      );
      expect(a.tableLabel, 'T4');
      expect(a.customerName, 'Noa Levi'); // stored '  Noa Levi  '
      expect(a.reasonCode, 'other');
      expect(a.reasonText, 'guest asked twice');
      // The staff caps: 40 characters, and an Arabic first token.
      expect(
        _Case('a_second_edit').server.staffFirstName,
        'Bartholomew-Alexander-Maximilian-Fitzger',
      );
      expect(_Case('b_legacy_ranks_add').server.staffFirstName, 'سارة');
      // Legacy rank-0 lines sort FIRST, ahead of ranked ones.
      expect(_Case('b_legacy_ranks_add').server.orderNow.map((i) => i.name), [
        'Fries',
        'Lemonade',
        'Burger',
      ]);
    });

    test('ORDER NOW is re-sorted into the builder order: the detail lists '
        'equal ranks the same way, but its own order is NOT relied on', () {
      final c = _Case('a_every_op');
      final reversed = _detailWith(_map(c.raw['after']), (copy) {
        copy['items'] = (copy['items']! as List).reversed.toList();
      });
      // Reversing the detail reorders lines with DIFFERENT ranks back into
      // place; only exact ties (same rank and position) keep detail order.
      final hand = c.handBuilt(fresh: reversed)!;
      final server = c.server;
      String key(KdsItemView i) => '${i.quantity}|${i.name}|${i.modifiers}';
      expect(hand.orderNow.map(key).toSet(), server.orderNow.map(key).toSet());
      expect(hand.orderNow.first.name, server.orderNow.first.name);
      expect(hand.orderNow.last.name, server.orderNow.last.name);
    });

    test('GAP G1: an order note never reaches the hand-built slip (the read '
        'surface lacks it); every other field is identical', () {
      final c = _Case('c_order_note');
      final hand = c.handBuilt()!;
      final server = c.server;
      expect(server.orderNote, 'allergy: nuts');
      expect(hand.orderNote, isNull);
      final serverWithoutNote = decodeOrderChangeSlipView(
        encodeOrderChangeSlipView(server)..remove('order_note'),
      );
      expect(_dump(hand), _dump(serverWithoutNote));
    });
  });

  group('fail closed: a missing fact yields no slip, never a partial one', () {
    late _Case c;
    setUp(() => c = _Case('a_every_op'));

    test('a row the envelope names is missing from the fresh detail', () {
      final modifyRow = c.applied.changes.first.newOrderItemIds.single;
      final fresh = _detailWith(_map(c.raw['after']), (copy) {
        copy['items'] = [
          for (final i in copy['items']! as List)
            if ((i as Map)['order_item_id'] != modifyRow) i,
        ];
      });
      expect(c.handBuilt(fresh: fresh), isNull);
    });

    test('a retired line has no frozen "was" projection', () {
      final was = Map.of(c.was)..remove(c.was.keys.first);
      expect(c.handBuilt(wasOverride: was), isNull);
      expect(c.handBuilt(wasOverride: const {}), isNull);
    });

    test('the fresh detail does not list the edit, or numbers it '
        'differently', () {
      expect(
        c.handBuilt(
          fresh: _detailWith(_map(c.raw['after']), (copy) {
            copy['edits'] = <Object?>[];
          }),
        ),
        isNull,
      );
      expect(
        c.handBuilt(
          fresh: _detailWith(_map(c.raw['after']), (copy) {
            final edits = copy['edits']! as List;
            (edits.first as Map)['edit_number'] = 9;
          }),
        ),
        isNull,
      );
    });

    test('the request and the envelope disagree (order, op or line)', () {
      final swapped = Map.of(c.payload)
        ..['changes'] = (c.payload['changes']! as List).reversed.toList();
      expect(c.handBuilt(payloadOverride: swapped), isNull);
      final shorter = Map.of(c.payload)
        ..['changes'] = (c.payload['changes']! as List).skip(1).toList();
      expect(c.handBuilt(payloadOverride: shorter), isNull);
      final otherLine = _map(jsonDecode(jsonEncode(c.payload)));
      (((otherLine['changes']! as List)[1]) as Map)['order_item_id'] =
          'fed00000-0000-0000-0000-0000000a1003';
      expect(c.handBuilt(payloadOverride: otherLine), isNull);
    });

    test('a set_quantity without a usable quantity', () {
      for (final bad in [null, 0, 1000, '2', 2.0]) {
        final payload = _map(jsonDecode(jsonEncode(c.payload)));
        final reduce = (payload['changes']! as List)[2] as Map;
        if (bad == null) {
          reduce.remove('quantity');
        } else {
          reduce['quantity'] = bad;
        }
        expect(c.handBuilt(payloadOverride: payload), isNull, reason: '$bad');
      }
    });

    test('an applied answer without its changes (an older envelope)', () {
      final a = c.applied;
      final bare = OrderEditApplied(
        orderEditId: a.orderEditId,
        editNumber: a.editNumber,
        revision: a.revision,
        kitchenChannel: a.kitchenChannel,
        kitchenAckRequired: a.kitchenAckRequired,
        kitchenDispatch: a.kitchenDispatch,
      );
      expect(c.handBuilt(appliedOverride: bare), isNull);
    });

    test('another order, or an order with no live line', () {
      expect(c.handBuilt(orderCode: '#FFFFFF'), isNull);
      expect(
        c.handBuilt(
          fresh: _detailWith(_map(c.raw['after']), (copy) {
            copy['items'] = <Object?>[];
          }),
        ),
        isNull,
      );
    });
  });

  group('the staff first name (the server rule)', () {
    test('first space-separated token, capped at 40 characters', () {
      expect(orderEditSlipStaffFirstName('Dana Cashier'), 'Dana');
      expect(orderEditSlipStaffFirstName('  Dana  Cashier '), 'Dana');
      expect(orderEditSlipStaffFirstName('سارة أحمد'), 'سارة');
      expect(orderEditSlipStaffFirstName('${'x' * 45} Jones'), 'x' * 40);
      expect(orderEditSlipStaffFirstName(null), isNull);
      expect(orderEditSlipStaffFirstName('   '), isNull);
    });

    test('counts CHARACTERS: an astral character is never split', () {
      final name = '😀' * 41;
      final first = orderEditSlipStaffFirstName(name)!;
      expect(first.runes.length, 40);
      expect(first, '😀' * 40);
    });

    test('only SPACES delimit and trim, like split_part / btrim', () {
      expect(orderEditSlipStaffFirstName('Dana\tCashier'), 'Dana\tCashier');
      expect(orderEditSlipStaffFirstName('\tDana'), '\tDana');
    });
  });

  group('the ORDER-NOW-only slip', () {
    test('headed by the LATEST edit, no change sections, no staff, every live '
        'line in the server order', () async {
      final c = _Case('a_second_edit');
      final slip = orderNowSlipFromDetail(c.after)!;
      final latest = c.after.edits!.last;
      expect(slip.changes, isEmpty);
      expect(slip.editNumber, 2);
      expect(slip.editedAt, latest.createdAt!.toLocal());
      expect(slip.reasonCode, 'entry_mistake');
      expect(slip.staffFirstName, isNull);
      expect(slip.orderCode, '#00A001');
      expect(slip.tableLabel, 'T4');
      expect(slip.customerName, 'Noa Levi');
      expect(
        [for (final i in slip.orderNow) _item(i)],
        [for (final i in c.server.orderNow) _item(i)],
      );
      final doc = _document(slip, 'en');
      expect(doc.join('\n'), contains('Change 2'));
      expect(doc.join('\n'), isNot(contains('REMOVED')));
      expect(await _bytes(slip, 'en'), isNotEmpty);
    });

    test('null when no edit is known or no line is live', () {
      final c = _Case('a_every_op');
      expect(
        orderNowSlipFromDetail(
          _detailWith(_map(c.raw['after']), (copy) {
            copy['edits'] = <Object?>[];
            (copy['order']! as Map)['edit_count'] = 0;
          }),
        ),
        isNull,
      );
      expect(
        orderNowSlipFromDetail(
          _detailWith(_map(c.raw['after']), (copy) {
            copy['items'] = <Object?>[];
          }),
        ),
        isNull,
      );
    });
  });

  group('the strict money-free codec', () {
    for (final name in _parityCases) {
      test('$name: a persisted slip reprints byte-identically', () async {
        final hand = _Case(name).handBuilt()!;
        final stored = jsonEncode(encodeOrderChangeSlipView(hand));
        final back = decodeOrderChangeSlipView(jsonDecode(stored));
        expect(_dump(back), _dump(hand));
        for (final lang in ['en', 'ar', 'he']) {
          expect(await _bytes(back, lang), await _bytes(hand, lang));
        }
      });
    }

    test('money-free: no money or hostile kitchen key at any depth', () {
      for (final name in _parityCases) {
        final c = _Case(name);
        final encoded = encodeOrderChangeSlipView(c.handBuilt()!);
        expect(
          () => rejectHostileKitchenKeys(encoded, path: 'slip'),
          returnsNormally,
        );
        expect(jsonEncode(encoded), isNot(contains('_minor')));
        for (final item in c.was.values) {
          expect(
            () => rejectHostileKitchenKeys(item.toJson(), path: 'item'),
            returnsNormally,
          );
        }
        for (final line in orderEditSlipLines(
          applied: c.applied,
          payload: c.payload,
        )!) {
          expect(
            () => rejectHostileKitchenKeys(line.toJson(), path: 'line'),
            returnsNormally,
          );
        }
      }
    });

    test('an unknown key is rejected BY NAME, never echoing a value', () {
      final good = encodeOrderChangeSlipView(_Case('a_every_op').handBuilt()!);
      Map<String, Object?> copy() => _map(jsonDecode(jsonEncode(good)));

      void expectRejected(Map<String, Object?> raw, String key) {
        expect(
          () => decodeOrderChangeSlipView(raw),
          throwsA(
            isA<FormatException>()
                .having((e) => e.message, 'message', contains(key))
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('SECRET-VALUE')),
                ),
          ),
        );
      }

      expectRejected(copy()..['price_minor'] = 'SECRET-VALUE', 'price_minor');
      final inEntry = copy();
      ((inEntry['entries']! as List).first as Map)['total'] = 'SECRET-VALUE';
      expectRejected(inEntry, 'total');
      final inItem = copy();
      ((inItem['order_now']! as List).first as Map)['amount'] = 'SECRET-VALUE';
      expectRejected(inItem, 'amount');
    });

    test('wrong types, an unknown op or version, or a missing key throw', () {
      final good = encodeOrderChangeSlipView(_Case('a_every_op').handBuilt()!);
      Map<String, Object?> copy() => _map(jsonDecode(jsonEncode(good)));
      final cases = <Map<String, Object?>>[
        copy()..['v'] = 2,
        copy()..remove('order_code'),
        copy()..['edit_number'] = '1',
        copy()..['edited_at'] = 'yesterday',
        copy()..['order_now'] = 'all of it',
        copy()..['customer_name'] = '',
      ];
      final badOp = copy();
      ((badOp['entries']! as List).first as Map)['op'] = 'remake';
      cases.add(badOp);
      final badQty = copy();
      ((badQty['order_now']! as List).first as Map)['qty'] = 0;
      cases.add(badQty);
      final emptyNow = copy();
      for (final e in emptyNow['entries']! as List) {
        if ((e as Map)['op'] == 'add') e['now'] = <Object?>[];
      }
      cases.add(emptyNow);
      for (final raw in cases) {
        expect(
          () => decodeOrderChangeSlipView(raw),
          throwsFormatException,
          reason: jsonEncode(raw).substring(0, 60),
        );
      }
      expect(() => decodeOrderChangeSlipView('slip'), throwsFormatException);
    });

    test('a line carrying a KDS overlay mark is refused, never dropped', () {
      final slip = OrderChangeSlipView(
        orderCode: '#ABC123',
        editNumber: 1,
        orderNow: [
          const KdsItemView(
            name: 'Burger',
            quantity: 1,
          ).withEdit(mark: KdsEditLineMark.added, editNumber: 1),
        ],
      );
      expect(() => encodeOrderChangeSlipView(slip), throwsArgumentError);
    });

    test('slip items and slip lines round-trip strictly', () {
      final c = _Case('a_every_op');
      for (final item in c.was.values) {
        final back = OrderEditSlipItem.fromJson(
          jsonDecode(jsonEncode(item.toJson())),
        );
        expect(_item(back.toKdsItemView()), _item(item.toKdsItemView()));
      }
      final lines = orderEditSlipLines(applied: c.applied, payload: c.payload)!;
      expect(lines.map((l) => l.op), [
        OrderEditSlipOp.modify,
        OrderEditSlipOp.remove,
        OrderEditSlipOp.setQuantity,
        OrderEditSlipOp.setQuantity,
        OrderEditSlipOp.modify,
        OrderEditSlipOp.add,
      ]);
      expect(lines[2].nowQty, 1);
      expect(lines[3].nowQty, 3);
      expect(lines[4].newOrderItemIds, hasLength(2));
      for (final line in lines) {
        final back = OrderEditSlipLine.fromJson(
          jsonDecode(jsonEncode(line.toJson())),
        );
        expect(back.toJson(), line.toJson());
      }
      // The same slip from the zipped lines (the durable record's input).
      expect(
        _dump(
          buildOrderEditChangeSlipFromLines(
            orderCode: c.before.orderCode,
            orderEditId: c.applied.orderEditId,
            editNumber: c.applied.editNumber,
            lines: [
              for (final l in lines)
                OrderEditSlipLine.fromJson(jsonDecode(jsonEncode(l.toJson()))),
            ],
            was: {
              for (final e in c.was.entries)
                e.key: OrderEditSlipItem.fromJson(
                  jsonDecode(jsonEncode(e.value.toJson())),
                ),
            },
            fresh: c.after,
            staffDisplayName: c.staff,
          )!,
        ),
        _dump(c.server),
      );
    });

    test('slip lines and items reject an unknown key or a wrong shape', () {
      expect(
        () => OrderEditSlipLine.fromJson({
          'op': 'remove',
          'order_item_id': 'x',
          'new_order_item_ids': <Object?>[],
          'price': 1,
        }),
        throwsFormatException,
      );
      for (final bad in <Map<String, Object?>>[
        {'op': 'add', 'order_item_id': 'x', 'new_order_item_ids': <Object?>[]},
        {'op': 'remove', 'new_order_item_ids': <Object?>[]},
        {
          'op': 'set_quantity',
          'order_item_id': 'x',
          'new_order_item_ids': <Object?>[],
        },
        {
          'op': 'remove',
          'order_item_id': 'x',
          'now_qty': 2,
          'new_order_item_ids': <Object?>[],
        },
        {
          'op': 'remake',
          'order_item_id': 'x',
          'new_order_item_ids': <Object?>[],
        },
      ]) {
        expect(() => OrderEditSlipLine.fromJson(bad), throwsFormatException);
      }
      expect(
        () => OrderEditSlipItem.fromJson({
          'qty': 1,
          'name': 'Cola',
          'modifiers': <Object?>[],
          'unit_price_minor': 800,
        }),
        throwsFormatException,
      );
      expect(
        () => OrderEditSlipItem.fromJson({
          'qty': 1,
          'name': 'Cola',
          'modifiers': [
            {'qty': 1, 'name': 'ice', 'price_minor': 0},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('the edit claim keys', () {
    test('the guard key and the spool mirror have their documented shapes', () {
      expect(
        posOrderEditKitchenPrintGuardKey(orderId: 'o-1', orderEditId: 'e-1'),
        'o-1|edit:e-1',
      );
      expect(posOrderEditDispatchClaimKey('d-1'), 'edit-dispatch:d-1');
    });

    test('neither shape can equal any other claim key for the same ids', () {
      const id = 'fed00000-0000-0000-0000-00000000a001';
      final others = {
        id,
        '$id|round:$id',
        posInitialKitchenPrintClaimKey(id),
        posLocalKitchenDispatchClaimKey(deviceId: id, localOperationId: id),
      };
      final guard = posOrderEditKitchenPrintGuardKey(
        orderId: id,
        orderEditId: id,
      );
      final mirror = posOrderEditDispatchClaimKey(id);
      expect(others, isNot(contains(guard)));
      expect(others, isNot(contains(mirror)));
      expect(guard, isNot(mirror));
    });
  });
}
