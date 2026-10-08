import 'dart:convert' show json, utf8;
import 'dart:typed_data';

import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:test/test.dart';

/// ORDER-EDIT-001C — the spool type and the CLOSED decoder for the paper
/// channel's `order_edit` dispatch (API_CONTRACT §4.45.9, D-044).
///
/// Both fixtures are REAL server output: `app.kitchen_dispatch_payload_order_edit`
/// run through `public.sync_push` (`order.edit`) in a rolled-back transaction on
/// a local database with every migration applied, using the
/// `order_edit_001a_dispatch_test` fixture (order #00A001 on a printer-only
/// branch). Only `created_at` is pinned. The key order is the server's
/// (`jsonb` text), which is irrelevant to the map comparisons below.
///
/// [_serverMinimal] is the payload a second till pulled after the acting till's
/// lease lapsed (no table, customer, note or reason text). [_serverRich] is the
/// same edit with a table, a customer name, an order note, a reason text, an
/// item note and an item prep component, so every optional key is exercised.
const String _serverMinimal = r'''
{"v": 1, "kind": "order_edit", "order_now": [{"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}, {"qty": 1, "name": "cheese"}]}, {"qty": 1, "name": "Cola", "modifiers": []}, {"qty": 1, "name": "Cola", "modifiers": []}, {"qty": 1, "name": "Lemonade", "modifiers": []}, {"qty": 2, "name": "Lemonade", "modifiers": []}, {"qty": 1, "name": "Water", "modifiers": []}], "created_at": "2026-10-08T22:33:30.46448+00:00", "edit_lines": [{"op": "modify", "now": [{"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}], "was": {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "tomato"}, {"qty": 1, "name": "cucumber"}]}}, {"op": "remove", "was": {"qty": 1, "name": "Fries", "modifiers": []}}, {"op": "set_quantity", "was": {"qty": 3, "name": "Cola", "modifiers": []}, "now_qty": 1}, {"op": "set_quantity", "was": {"qty": 1, "name": "Lemonade", "modifiers": []}, "now_qty": 3}, {"op": "modify", "now": [{"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}, {"qty": 1, "name": "cheese"}]}], "was": {"qty": 2, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}}, {"op": "add", "now": [{"qty": 1, "name": "Water", "modifiers": []}]}], "order_code": "#00A001", "order_type": "dine_in", "staff_name": "Dana", "edit_number": 1, "reason_code": "entry_mistake"}
''';

const String _serverRich = r'''
{"v": 1, "kind": "order_edit", "reason": "Guest asked twice", "order_now": [{"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "prep": [{"name": "Patty", "unit": "pc", "quantity": 1}], "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}, {"qty": 1, "name": "cheese"}]}, {"qty": 1, "name": "Cola", "modifiers": []}, {"qty": 1, "name": "Cola", "modifiers": []}, {"qty": 1, "name": "Lemonade", "modifiers": []}, {"qty": 2, "name": "Lemonade", "modifiers": []}, {"qty": 1, "name": "Water", "modifiers": []}], "created_at": "2026-10-08T22:33:30.46448+00:00", "edit_lines": [{"op": "modify", "now": [{"qty": 1, "name": "Burger", "prep": [{"name": "Patty", "unit": "pc", "quantity": 1}], "modifiers": [{"qty": 1, "name": "cucumber"}]}], "was": {"qty": 1, "name": "Burger", "prep": [{"name": "Patty", "unit": "pc", "quantity": 1}], "modifiers": [{"qty": 1, "name": "tomato"}, {"qty": 1, "name": "cucumber"}]}}, {"op": "remove", "was": {"qty": 1, "name": "Fries", "note": "no salt", "modifiers": []}}, {"op": "set_quantity", "was": {"qty": 3, "name": "Cola", "modifiers": []}, "now_qty": 1}, {"op": "set_quantity", "was": {"qty": 1, "name": "Lemonade", "modifiers": []}, "now_qty": 3}, {"op": "modify", "now": [{"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}, {"qty": 1, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}, {"qty": 1, "name": "cheese"}]}], "was": {"qty": 2, "name": "Burger", "modifiers": [{"qty": 1, "name": "cucumber"}]}}, {"op": "add", "now": [{"qty": 1, "name": "Water", "modifiers": []}]}], "order_code": "#00A001", "order_note": "Allergy: nuts", "order_type": "dine_in", "staff_name": "Dana", "edit_number": 1, "reason_code": "entry_mistake", "table_label": "12", "customer_display_name": "Noa"}
''';

/// A fresh, independently mutable copy of a server fixture.
Map<String, Object?> _server(String raw) =>
    json.decode(raw) as Map<String, Object?>;

/// The fixture's `edit_lines[index]`, for in-place mutation.
Map<String, Object?> _line(Map<String, Object?> dispatch, int index) =>
    (dispatch['edit_lines']! as List)[index] as Map<String, Object?>;

Map<String, Object?> _envelope(Map<String, Object?> dispatch) => {
  'v': 1,
  'purpose': 'kitchen_ticket',
  'dispatch': dispatch,
  'destination': {'kind': 'network', 'host': '10.0.0.5', 'port': 9100},
  'paper_width': '80mm',
  'document_version': 1,
  'raster_version': 1,
};

/// A minimal, valid `order_edit` dispatch for the strictness cases.
Map<String, Object?> _editDispatch({List<Object?>? editLines}) => {
  'v': 1,
  'kind': 'order_edit',
  'order_code': '#AB12CD',
  'order_type': 'takeaway',
  'created_at': '2026-10-08T10:00:00Z',
  'edit_number': 2,
  'edit_lines':
      editLines ??
      [
        {
          'op': 'remove',
          'was': {'qty': 1, 'name': 'Fries', 'modifiers': <Object?>[]},
        },
      ],
  'order_now': [
    {'qty': 1, 'name': 'Burger', 'modifiers': <Object?>[]},
  ],
};

Map<String, Object?> _item(String name, {int qty = 1}) => {
  'qty': qty,
  'name': name,
  'modifiers': <Object?>[],
};

final Matcher _typed = throwsA(isA<KitchenSpoolPayloadFormatException>());

void main() {
  group('KitchenSpoolDispatchType (ORDER-EDIT-001C)', () {
    test('order_edit is a closed wire value that round-trips', () {
      expect(
        KitchenSpoolDispatchType.fromWire('order_edit'),
        KitchenSpoolDispatchType.orderEdit,
      );
      expect(KitchenSpoolDispatchType.orderEdit.wireName, 'order_edit');
      // The enum mirrors the server ledger's four-value CHECK exactly.
      expect(KitchenSpoolDispatchType.values.map((v) => v.wireName).toSet(), {
        'initial_order',
        'service_round',
        'void',
        'order_edit',
      });
      expect(
        () => KitchenSpoolDispatchType.fromWire('order_edits'),
        throwsArgumentError,
      );
    });

    test('the Drift converter stores and reads order_edit as wire text', () {
      const converter = KitchenSpoolDispatchTypeConverter();
      expect(converter.toSql(KitchenSpoolDispatchType.orderEdit), 'order_edit');
      expect(
        converter.fromSql('order_edit'),
        KitchenSpoolDispatchType.orderEdit,
      );
    });
  });

  group('contract fixture (real server payload)', () {
    test('the server payload passes the hostile-key scan', () {
      rejectHostileKitchenKeys(_server(_serverMinimal), path: 'dispatch');
      rejectHostileKitchenKeys(_server(_serverRich), path: 'dispatch');
    });

    test('decodes to a typed order_edit document', () {
      final doc = KitchenDispatchDocument.fromJson(_server(_serverMinimal));
      expect(doc.kind, KitchenSpoolDispatchType.orderEdit);
      expect(doc.serverPayloadVersion, 1);
      expect(doc.orderCode, '#00A001');
      expect(doc.orderType, 'dine_in');
      expect(doc.createdAt, '2026-10-08T22:33:30.46448+00:00');
      expect(doc.editNumber, 1);
      expect(doc.reasonCode, 'entry_mistake');
      expect(doc.staffName, 'Dana');
      expect(doc.reason, isNull);
      expect(doc.tableLabel, isNull);
      expect(doc.customerDisplayName, isNull);
      expect(doc.orderNote, isNull);
      // None of the item / round / void fields exist on an edit.
      expect(doc.items, isEmpty);
      expect(doc.roundId, isNull);
      expect(doc.roundNumber, isNull);
      expect(doc.voidMarker, isFalse);
      expect(doc.voidedAt, isNull);
      expect(doc.affectedItemCount, isNull);

      expect(doc.editLines.map((l) => l.op), [
        'modify',
        'remove',
        'set_quantity',
        'set_quantity',
        'modify',
        'add',
      ]);
      expect(doc.editLines.map((l) => l.runtimeType), [
        KitchenDispatchEditModify,
        KitchenDispatchEditRemove,
        KitchenDispatchEditSetQuantity,
        KitchenDispatchEditSetQuantity,
        KitchenDispatchEditModify,
        KitchenDispatchEditAdd,
      ]);

      final modifyOne = doc.editLines[0] as KitchenDispatchEditModify;
      expect(modifyOne.was.qty, 1);
      expect(modifyOne.was.modifiers.map((m) => m.name), [
        'tomato',
        'cucumber',
      ]);
      expect(modifyOne.now.single.modifiers.single.name, 'cucumber');

      final remove = doc.editLines[1] as KitchenDispatchEditRemove;
      expect(remove.was.name, 'Fries');
      expect(remove.was.qty, 1);

      final cola = doc.editLines[2] as KitchenDispatchEditSetQuantity;
      expect(cola.was.name, 'Cola');
      expect(cola.was.qty, 3);
      expect(cola.nowQty, 1);
      expect(cola.delta, -2);
      expect(cola.isIncrease, isFalse);

      final lemonade = doc.editLines[3] as KitchenDispatchEditSetQuantity;
      expect(lemonade.was.name, 'Lemonade');
      expect(lemonade.nowQty, 3);
      expect(lemonade.delta, 2);
      expect(lemonade.isIncrease, isTrue);

      final modifyTwo = doc.editLines[4] as KitchenDispatchEditModify;
      expect(modifyTwo.was.qty, 2);
      expect(modifyTwo.now, hasLength(2));
      expect(modifyTwo.now.last.modifiers.map((m) => m.name), [
        'cucumber',
        'cheese',
      ]);

      final add = doc.editLines[5] as KitchenDispatchEditAdd;
      expect(add.now.single.name, 'Water');

      // ORDER NOW keeps the server's canonical order, split lines included.
      expect(doc.orderNow.map((i) => '${i.qty}x${i.name}'), [
        '1xBurger',
        '1xBurger',
        '1xBurger',
        '1xCola',
        '1xCola',
        '1xLemonade',
        '2xLemonade',
        '1xWater',
      ]);
    });

    test('the rich fixture decodes every optional key', () {
      final doc = KitchenDispatchDocument.fromJson(_server(_serverRich));
      expect(doc.tableLabel, '12');
      expect(doc.customerDisplayName, 'Noa');
      expect(doc.orderNote, 'Allergy: nuts');
      expect(doc.reason, 'Guest asked twice');
      final remove = doc.editLines[1] as KitchenDispatchEditRemove;
      expect(remove.was.note, 'no salt');
      final modifyOne = doc.editLines[0] as KitchenDispatchEditModify;
      expect(modifyOne.was.prep.single.name, 'Patty');
      expect(modifyOne.was.prep.single.quantity, 1);
      expect(modifyOne.was.prep.single.unit, 'pc');
      expect(modifyOne.now.single.prep.single.name, 'Patty');
      expect(doc.orderNow[1].prep.single.name, 'Patty');
    });

    test('toJson re-encodes to exactly the server map (no empty prep '
        'arrays in the fixtures), and re-decoding is stable', () {
      for (final raw in [_serverMinimal, _serverRich]) {
        final server = _server(raw);
        final doc = KitchenDispatchDocument.fromJson(_server(raw));
        final reencoded =
            json.decode(json.encode(doc.toJson())) as Map<String, Object?>;
        expect(reencoded, server);
        final again = KitchenDispatchDocument.fromJson(reencoded);
        expect(again.toJson(), doc.toJson());
      }
    });

    test('the encrypted local envelope round-trips through bytes, '
        're-running the hostile-key scan', () {
      for (final raw in [_serverMinimal, _serverRich]) {
        final payload = KitchenSpoolLocalPayload.fromJson(
          _envelope(_server(raw)),
        );
        final round = KitchenSpoolLocalPayload.fromBytes(payload.toBytes());
        expect(round.toJson(), payload.toJson());
        expect(round.dispatch.kind, KitchenSpoolDispatchType.orderEdit);
        expect(round.dispatch.editLines, hasLength(6));
        expect(round.dispatch.orderNow, hasLength(8));
        expect(json.decode(json.encode(round.dispatch.toJson())), _server(raw));
      }
    });

    test('a hand-built document serializes to the decoder shape', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.orderEdit,
        orderCode: '#AB12CD',
        orderType: 'takeaway',
        createdAt: '2026-10-08T10:00:00Z',
        editNumber: 3,
        reasonCode: 'other',
        reason: 'guest request',
        staffName: 'Mona',
        editLines: [
          KitchenDispatchEditSetQuantity(
            was: KitchenDispatchItem(qty: 2, name: 'Tea'),
            nowQty: 1,
          ),
          KitchenDispatchEditAdd(
            now: [KitchenDispatchItem(qty: 1, name: 'Cake')],
          ),
        ],
        orderNow: [
          KitchenDispatchItem(qty: 1, name: 'Tea'),
          KitchenDispatchItem(qty: 1, name: 'Cake'),
        ],
      );
      final encoded = doc.toJson();
      expect(encoded['edit_number'], 3);
      expect(encoded['reason_code'], 'other');
      expect(encoded['staff_name'], 'Mona');
      expect(encoded.containsKey('items'), isFalse);
      expect(encoded['edit_lines'], [
        {
          'op': 'set_quantity',
          'was': {'qty': 2, 'name': 'Tea', 'modifiers': <Object?>[]},
          'now_qty': 1,
        },
        {
          'op': 'add',
          'now': [
            {'qty': 1, 'name': 'Cake', 'modifiers': <Object?>[]},
          ],
        },
      ]);
      final decoded = KitchenDispatchDocument.fromJson(
        json.decode(json.encode(encoded)) as Map<String, Object?>,
      );
      expect(decoded.toJson(), encoded);
      // The serialized edit keys stay clear of the hostile vocabulary.
      rejectHostileKitchenKeys(encoded, path: 'dispatch');
    });
  });

  group('per-op strictness (typed, never echoing a value)', () {
    void rejects(Map<String, Object?> line, String reason) {
      expect(
        () =>
            KitchenDispatchDocument.fromJson(_editDispatch(editLines: [line])),
        _typed,
        reason: reason,
      );
    }

    test('remove: needs was, takes nothing else', () {
      rejects({'op': 'remove'}, 'remove without was');
      rejects({'op': 'remove', 'was': 'Fries'}, 'was not an object');
      rejects({
        'op': 'remove',
        'was': _item('Fries'),
        'now': [_item('Fries')],
      }, 'remove with now');
      rejects({
        'op': 'remove',
        'was': _item('Fries'),
        'now_qty': 2,
      }, 'remove with now_qty');
    });

    test('set_quantity: needs was and a positive integer now_qty', () {
      rejects({'op': 'set_quantity', 'was': _item('Cola')}, 'no now_qty');
      rejects({'op': 'set_quantity', 'now_qty': 2}, 'no was');
      for (final bad in <Object?>[0, -1, '2', 1.5, true]) {
        rejects({
          'op': 'set_quantity',
          'was': _item('Cola'),
          'now_qty': bad,
        }, 'now_qty $bad');
      }
      rejects({
        'op': 'set_quantity',
        'was': _item('Cola'),
        'now_qty': 2,
        'now': [_item('Cola')],
      }, 'set_quantity with now');
    });

    test('modify: needs was and a non-empty now', () {
      rejects({'op': 'modify', 'was': _item('Burger')}, 'no now');
      rejects({
        'op': 'modify',
        'was': _item('Burger'),
        'now': <Object?>[],
      }, 'empty now');
      rejects({
        'op': 'modify',
        'was': _item('Burger'),
        'now': _item('Burger'),
      }, 'now not an array');
      rejects({
        'op': 'modify',
        'now': [_item('Burger')],
      }, 'no was');
      rejects({
        'op': 'modify',
        'was': _item('Burger'),
        'now': ['Burger'],
      }, 'now element not an object');
      rejects({
        'op': 'modify',
        'was': _item('Burger'),
        'now': [_item('Burger')],
        'now_qty': 1,
      }, 'modify with now_qty');
    });

    test('add: needs a non-empty now and no was', () {
      rejects({'op': 'add'}, 'no now');
      rejects({'op': 'add', 'now': <Object?>[]}, 'empty now');
      rejects({
        'op': 'add',
        'was': _item('Water'),
        'now': [_item('Water')],
      }, 'add with was');
    });

    test('an unknown or malformed op is typed and never echoed', () {
      try {
        KitchenDispatchDocument.fromJson(
          _editDispatch(
            editLines: [
              {'op': 'sneaky_replace_op', 'was': _item('Fries')},
            ],
          ),
        );
        fail('expected a typed rejection');
      } on KitchenSpoolPayloadFormatException catch (e) {
        expect(e.toString(), isNot(contains('sneaky_replace_op')));
      }
      rejects({'op': 7, 'was': _item('Fries')}, 'non-string op');
      rejects({'was': _item('Fries')}, 'missing op');
    });

    test('unknown keys are rejected at every level of an edit line', () {
      rejects({
        'op': 'remove',
        'was': _item('Fries'),
        'station': 'grill',
      }, 'unknown key on the line');
      rejects({
        'op': 'remove',
        'was': {..._item('Fries'), 'surprise': 1},
      }, 'unknown key on was');
      rejects({
        'op': 'add',
        'now': [
          {
            ..._item('Water'),
            'modifiers': [
              {'qty': 1, 'name': 'ice', 'surprise': true},
            ],
          },
        ],
      }, 'unknown key on a now modifier');
      expect(
        () => KitchenDispatchDocument.fromJson(
          _editDispatch(editLines: ['remove']),
        ),
        _typed,
        reason: 'edit line not an object',
      );
    });

    test('item strictness applies to was / now / order_now items', () {
      rejects({
        'op': 'remove',
        'was': {'qty': 0, 'name': 'Fries', 'modifiers': <Object?>[]},
      }, 'zero quantity on was');
      final orderNow = _editDispatch()
        ..['order_now'] = [
          {'qty': 1, 'name': '', 'modifiers': <Object?>[]},
        ];
      expect(() => KitchenDispatchDocument.fromJson(orderNow), _typed);
    });
  });

  group('kind gating, both ways', () {
    test('an order_edit rejects the item / round / void keys', () {
      for (final entry in <String, Object?>{
        'items': [_item('Burger')],
        'round_id': 'r1000000-0000-0000-0000-000000000001',
        'round_number': 2,
        'void': true,
        'voided_at': '2026-10-08T10:05:00Z',
        'affected_item_count': 1,
      }.entries) {
        final dispatch = _editDispatch()..[entry.key] = entry.value;
        expect(
          () => KitchenDispatchDocument.fromJson(dispatch),
          _typed,
          reason: 'order_edit with ${entry.key}',
        );
      }
    });

    test('an order_edit requires a positive edit_number and non-empty '
        'edit_lines / order_now', () {
      for (final bad in <Object?>[null, 0, -1, '1', 1.0]) {
        final dispatch = _editDispatch();
        if (bad == null) {
          dispatch.remove('edit_number');
        } else {
          dispatch['edit_number'] = bad;
        }
        expect(
          () => KitchenDispatchDocument.fromJson(dispatch),
          _typed,
          reason: 'edit_number $bad',
        );
      }
      for (final key in ['edit_lines', 'order_now']) {
        expect(
          () => KitchenDispatchDocument.fromJson(_editDispatch()..remove(key)),
          _typed,
          reason: 'missing $key',
        );
        expect(
          () => KitchenDispatchDocument.fromJson(
            _editDispatch()..[key] = <Object?>[],
          ),
          _typed,
          reason: 'empty $key',
        );
        expect(
          () => KitchenDispatchDocument.fromJson(
            _editDispatch()..[key] = {'qty': 1},
          ),
          _typed,
          reason: '$key not an array',
        );
      }
    });

    test('optional edit strings must be non-empty strings when present', () {
      for (final key in ['reason_code', 'reason', 'staff_name']) {
        expect(
          () => KitchenDispatchDocument.fromJson(_editDispatch()..[key] = ''),
          _typed,
          reason: 'empty $key',
        );
        expect(
          () => KitchenDispatchDocument.fromJson(_editDispatch()..[key] = 3),
          _typed,
          reason: 'non-string $key',
        );
      }
    });

    test('reason_code is NOT allowlisted: a code this build does not know '
        'still decodes (it costs only its label)', () {
      final doc = KitchenDispatchDocument.fromJson(
        _editDispatch()..['reason_code'] = 'a_future_reason',
      );
      expect(doc.reasonCode, 'a_future_reason');
    });

    test('initial_order, service_round and void reject every edit key', () {
      final older = <String, Map<String, Object?>>{
        'initial_order': {
          'v': 1,
          'kind': 'initial_order',
          'order_code': '#AB12CD',
          'order_type': 'dine_in',
          'items': [_item('Burger')],
        },
        'service_round': {
          'v': 1,
          'kind': 'service_round',
          'order_code': '#AB12CD',
          'order_type': 'dine_in',
          'round_id': 'r1000000-0000-0000-0000-000000000001',
          'round_number': 2,
          'items': [_item('Burger')],
        },
        'void': {
          'v': 1,
          'kind': 'void',
          'order_code': '#AB12CD',
          'order_type': 'dine_in',
          'reason': 'changed mind',
          'void': true,
          'voided_at': '2026-10-08T10:05:00Z',
          'affected_item_count': 1,
        },
      };
      final editKeys = <String, Object?>{
        'edit_lines': [
          {'op': 'remove', 'was': _item('Fries')},
        ],
        'order_now': [_item('Burger')],
        'edit_number': 1,
        'staff_name': 'Dana',
        'reason_code': 'entry_mistake',
      };
      for (final kind in older.entries) {
        // Each older kind still decodes and serializes byte-identically.
        final doc = KitchenDispatchDocument.fromJson(Map.of(kind.value));
        expect(doc.toJson(), kind.value, reason: kind.key);
        expect(doc.editNumber, isNull);
        expect(doc.editLines, isEmpty);
        expect(doc.orderNow, isEmpty);
        for (final edit in editKeys.entries) {
          final dispatch = Map.of(kind.value)..[edit.key] = edit.value;
          expect(
            () => KitchenDispatchDocument.fromJson(dispatch),
            _typed,
            reason: '${kind.key} with ${edit.key}',
          );
        }
      }
    });

    test('an older kind never serializes edit keys, even if set', () {
      final doc = KitchenDispatchDocument(
        serverPayloadVersion: 1,
        kind: KitchenSpoolDispatchType.initialOrder,
        orderCode: '#AB12CD',
        orderType: 'dine_in',
        items: [KitchenDispatchItem(qty: 1, name: 'Burger')],
        editNumber: 4,
        staffName: 'Dana',
        orderNow: [KitchenDispatchItem(qty: 1, name: 'Burger')],
      );
      expect(doc.toJson().keys, {
        'v',
        'kind',
        'order_code',
        'order_type',
        'items',
      });
    });
  });

  group('hostile keys deep inside an edit (defence in depth)', () {
    test('money / PII keys nested in edit lines or order_now are rejected '
        'before typed decoding', () {
      final mutations = <String, void Function(Map<String, Object?>)>{
        'was.modifiers[].unit_price_minor': (d) {
          final was = _line(d, 0)['was']! as Map<String, Object?>;
          ((was['modifiers']! as List).first
                  as Map<String, Object?>)['unit_price_minor'] =
              300;
        },
        'now[].prep[].price': (d) {
          final now =
              (_line(d, 0)['now']! as List).first as Map<String, Object?>;
          ((now['prep']! as List).first as Map<String, Object?>)['price'] = 1;
        },
        'edit_lines[].change': (d) => _line(d, 2)['change'] = 2,
        'order_now[].lineTotal': (d) =>
            ((d['order_now']! as List)[3]
                    as Map<String, Object?>)['lineTotal'] =
                800,
        'add.now[].customer_phone': (d) =>
            ((_line(d, 5)['now']! as List).first
                    as Map<String, Object?>)['customer_phone'] =
                '050',
      };
      for (final entry in mutations.entries) {
        final dispatch = _server(_serverRich);
        entry.value(dispatch);
        expect(
          () => rejectHostileKitchenKeys(dispatch, path: 'dispatch'),
          _typed,
          reason: entry.key,
        );
        expect(
          () => KitchenSpoolLocalPayload.fromJson(_envelope(dispatch)),
          _typed,
          reason: entry.key,
        );
      }
    });

    test('the encrypted envelope bytes of an edit carry no money key', () {
      final payload = KitchenSpoolLocalPayload.fromJson(
        _envelope(_server(_serverRich)),
      );
      final text = utf8.decode(payload.toBytes());
      for (final token in ['_minor', 'price', 'total', 'change']) {
        expect(text, isNot(contains(token)), reason: token);
      }
    });
  });

  group('legacy KitchenTicketRenderer fails closed on an edit', () {
    test('buildDocument and renderToBytes refuse order_edit', () async {
      final doc = KitchenDispatchDocument.fromJson(_server(_serverRich));
      const renderer = KitchenTicketRenderer();
      expect(() => renderer.buildDocument(doc), throwsUnsupportedError);
      await expectLater(renderer.renderToBytes(doc), throwsUnsupportedError);
    });

    test('initial and void documents still render', () async {
      const renderer = KitchenTicketRenderer();
      final initial = KitchenDispatchDocument.fromJson({
        'v': 1,
        'kind': 'initial_order',
        'order_code': '#AB12CD',
        'order_type': 'dine_in',
        'items': [_item('Burger')],
      });
      final voidDoc = KitchenDispatchDocument.fromJson({
        'v': 1,
        'kind': 'void',
        'order_code': '#AB12CD',
        'order_type': 'dine_in',
        'reason': 'changed mind',
        'void': true,
      });
      for (final doc in [initial, voidDoc]) {
        expect(renderer.buildDocument(doc).lines, isNotEmpty);
        final Uint8List bytes = await renderer.renderToBytes(doc);
        expect(bytes, isNotEmpty);
      }
    });
  });
}
