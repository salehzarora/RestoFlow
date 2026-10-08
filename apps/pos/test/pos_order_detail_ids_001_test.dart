import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';

/// POS-ORDER-DETAIL-IDS-001 (ORDER-EDIT slice 2) — the POS detail parser keeps
/// the identity fields `pos_order_detail` emits: per item `order_item_id`,
/// `menu_item_id` and `status`; per modifier `modifier_option_id` and the two
/// MENU-ORDER-001 display-order snapshots. They are tolerant, non-money plucks:
/// an older server (no keys) or a malformed value never fails the detail, and
/// every money field stays strict exactly as before.
Map<String, Object?> _modifier({
  required String option,
  required int price,
  Object? id,
  Object? group,
  Object? rank,
  bool withIdKeys = true,
}) => {
  'modifier_name_snapshot': 'Group',
  'option_name_snapshot': option,
  'price_minor_snapshot': price,
  'quantity': 1,
  'meat_snapshot': null,
  if (withIdKeys) 'modifier_option_id': id,
  if (withIdKeys) 'modifier_group_display_order_snapshot': group,
  if (withIdKeys) 'modifier_option_display_order_snapshot': rank,
};

Map<String, Object?> _detailJson({bool withIdKeys = true}) => {
  'ok': true,
  'entity': 'order_detail',
  'order': {
    'order_id': 'order-1',
    'order_code': '#ABC123',
    'order_type': 'takeaway',
    'status': 'submitted',
    'revision': 2,
    'currency_code': 'ILS',
    'subtotal_minor': 8600,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'grand_total_minor': 8600,
  },
  'items': [
    {
      'order_item_id': 'oi-burger',
      'menu_item_id': 'mi-burger',
      'menu_item_name_snapshot': 'Burger',
      'quantity': 2,
      'unit_price_minor_snapshot': 4000,
      'line_discount_minor': 0,
      'line_total_minor': 8600,
      'category_display_order_snapshot': 1,
      'item_display_order_snapshot': 1,
      'line_position': 1,
      'status': 'pending',
      'modifiers': [
        _modifier(
          option: '240g',
          price: 0,
          id: 'opt-240g',
          group: 1,
          rank: 1,
          withIdKeys: withIdKeys,
        ),
        _modifier(
          option: 'cheese',
          price: 300,
          id: 'opt-cheese',
          group: 2,
          rank: 1,
          withIdKeys: withIdKeys,
        ),
        _modifier(
          option: 'onion',
          price: 0,
          id: 'opt-onion',
          group: 2,
          rank: 2,
          withIdKeys: withIdKeys,
        ),
      ],
    },
  ],
  'rounds': const <Object?>[],
  'payment': null,
};

void main() {
  group('the parser keeps the identity fields', () {
    test('item: order_item_id, menu_item_id and status', () {
      final detail = PosOrderDetail.fromJson(_detailJson())!;
      final item = detail.items.single;
      expect(item.orderItemId, 'oi-burger');
      expect(item.menuItemId, 'mi-burger');
      expect(item.status, 'pending');
    });

    test(
      'modifiers: option id + group / option ranks, in the server order',
      () {
        final mods = PosOrderDetail.fromJson(
          _detailJson(),
        )!.items.single.modifiers;
        expect(mods.map((m) => m.optionName), ['240g', 'cheese', 'onion']);
        expect(mods.map((m) => m.modifierOptionId), [
          'opt-240g',
          'opt-cheese',
          'opt-onion',
        ]);
        expect(mods.map((m) => m.groupDisplayOrder), [1, 2, 2]);
        expect(mods.map((m) => m.optionDisplayOrder), [1, 1, 2]);
      },
    );

    test('an option the menu no longer knows keeps its id and rank 0', () {
      final item = PosOrderDetailItem.fromJson({
        'menu_item_name_snapshot': 'Old Burger',
        'quantity': 1,
        'unit_price_minor_snapshot': 0,
        'line_discount_minor': 0,
        'line_total_minor': 0,
        'modifiers': [
          _modifier(
            option: 'gone',
            price: 0,
            id: 'opt-gone',
            group: 0,
            rank: 0,
          ),
        ],
      })!;
      final mod = item.modifiers.single;
      expect(mod.modifierOptionId, 'opt-gone');
      expect(mod.groupDisplayOrder, 0);
      expect(mod.optionDisplayOrder, 0);
    });
  });

  group('backward compatible and tolerant (never fails the detail)', () {
    test('an older server without the keys parses exactly as before', () {
      final withKeys = PosOrderDetail.fromJson(_detailJson())!;
      final without = PosOrderDetail.fromJson(_detailJson(withIdKeys: false))!;
      final a = withKeys.items.single;
      final b = without.items.single;
      // Every pre-existing field is identical.
      expect(b.name, a.name);
      expect(b.quantity, a.quantity);
      expect(b.unitPriceMinor, a.unitPriceMinor);
      expect(b.lineDiscountMinor, a.lineDiscountMinor);
      expect(b.lineTotalMinor, a.lineTotalMinor);
      expect(b.linePosition, a.linePosition);
      expect(
        b.modifiers.map((m) => (m.optionName, m.priceMinor, m.quantity)),
        a.modifiers.map((m) => (m.optionName, m.priceMinor, m.quantity)),
      );
      expect(without.grandTotalMinor, withKeys.grandTotalMinor);
      // The new modifier fields fall back to null / 0.
      expect(b.modifiers.map((m) => m.modifierOptionId), [null, null, null]);
      expect(b.modifiers.map((m) => m.groupDisplayOrder), [0, 0, 0]);
      expect(b.modifiers.map((m) => m.optionDisplayOrder), [0, 0, 0]);
    });

    test('item identity keys absent => null, the line still parses', () {
      final item = PosOrderDetailItem.fromJson({
        'menu_item_name_snapshot': 'Fries',
        'quantity': 1,
        'unit_price_minor_snapshot': 1500,
        'line_discount_minor': 0,
        'line_total_minor': 1500,
      })!;
      expect(item.orderItemId, isNull);
      expect(item.menuItemId, isNull);
      expect(item.status, isNull);
    });

    test('malformed ids / ranks degrade to null / 0 instead of failing', () {
      final item = PosOrderDetailItem.fromJson({
        'order_item_id': 42,
        'menu_item_id': '',
        'status': null,
        'menu_item_name_snapshot': 'Fries',
        'quantity': 1,
        'unit_price_minor_snapshot': 1500,
        'line_discount_minor': 0,
        'line_total_minor': 1500,
        'modifiers': [
          _modifier(option: 'salt', price: 0, id: 7, group: 'x', rank: null),
        ],
      })!;
      expect(item.orderItemId, isNull);
      expect(item.menuItemId, isNull);
      expect(item.status, isNull);
      final mod = item.modifiers.single;
      expect(mod.modifierOptionId, isNull);
      expect(mod.groupDisplayOrder, 0);
      expect(mod.optionDisplayOrder, 0);
    });

    test('money stays strict: a modifier without its price still fails', () {
      final broken = _detailJson();
      final items = broken['items']! as List<Object?>;
      final item = items.single! as Map<String, Object?>;
      final mods = item['modifiers']! as List<Object?>;
      (mods.first! as Map<String, Object?>).remove('price_minor_snapshot');
      expect(PosOrderDetail.fromJson(broken), isNull);
    });
  });
}
