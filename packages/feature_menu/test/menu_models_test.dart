import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('MenuItem.fromJson', () {
    test('parses snake_case row with integer-minor money', () {
      final item = MenuItem.fromJson(const {
        'id': 'item-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': 'branch-1',
        'menu_category_id': 'cat-1',
        'name': 'Espresso',
        'description': 'Double shot',
        'base_price_minor': 350,
        'currency_code': 'USD',
        'default_station_id': null,
        'display_order': 2,
        'is_active': true,
        'deleted_at': null,
      });
      expect(item.id, 'item-1');
      expect(item.basePriceMinor, 350);
      expect(item.currencyCode, 'USD');
      expect(item.branchId, 'branch-1');
      expect(item.isActive, isTrue);
      expect(item.isDeleted, isFalse);
    });

    test('image_path parses when present and stays null when absent '
        '(old envelopes still parse)', () {
      final withImage = MenuItem.fromJson(const {
        'id': 'item-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': 'branch-1',
        'menu_category_id': 'cat-1',
        'name': 'Espresso',
        'base_price_minor': 350,
        'currency_code': 'USD',
        'image_path': 'org-1/rest-1/branch-1/menu_item/item-1/img-1.png',
      });
      expect(
        withImage.imagePath,
        'org-1/rest-1/branch-1/menu_item/item-1/img-1.png',
      );

      final withoutImage = MenuItem.fromJson(const {
        'id': 'item-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': 'branch-1',
        'menu_category_id': 'cat-1',
        'name': 'Espresso',
        'base_price_minor': 350,
        'currency_code': 'USD',
      });
      expect(withoutImage.imagePath, isNull);
    });

    test('rich attributes roundtrip: item_type/tags/prep/sku/note/attributes '
        'parse when present and default when absent', () {
      final rich = MenuItem.fromJson(const {
        'id': 'item-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': 'branch-1',
        'menu_category_id': 'cat-1',
        'name': 'Burger',
        'base_price_minor': 4200,
        'currency_code': 'ILS',
        'item_type': 'food',
        'tags': ['spicy', 'popular'],
        'prep_minutes': 12,
        'sku': 'BRG-01',
        'kitchen_note': 'No onions.',
        'attributes': {
          'portion_label': 'Single',
          'patty_count': 2,
          'patty_weight_grams': 160,
        },
      });
      expect(rich.itemType, 'food');
      expect(rich.tags, ['spicy', 'popular']);
      expect(rich.prepMinutes, 12);
      expect(rich.sku, 'BRG-01');
      expect(rich.kitchenNote, 'No onions.');
      // Typed accessors over the generic bag (snake_case wire keys).
      expect(rich.portionLabel, 'Single');
      expect(rich.pattyCount, 2);
      expect(rich.pattyWeightGrams, 160);

      // Old envelopes (no rich keys) still parse — safe defaults.
      final plain = MenuItem.fromJson(const {
        'id': 'item-2',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': null,
        'menu_category_id': 'cat-1',
        'name': 'Tea',
        'base_price_minor': 900,
        'currency_code': 'ILS',
      });
      expect(plain.itemType, isNull);
      expect(plain.tags, isEmpty);
      expect(plain.prepMinutes, isNull);
      expect(plain.sku, isNull);
      expect(plain.kitchenNote, isNull);
      expect(plain.attributes, isEmpty);
      expect(plain.portionLabel, isNull);
      expect(plain.pattyCount, isNull);
      expect(plain.pattyWeightGrams, isNull);
    });

    test('malformed rich fields fail closed (wrong-typed tags/attributes)', () {
      const base = {
        'id': 'item-1',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': null,
        'menu_category_id': 'cat-1',
        'name': 'Burger',
        'base_price_minor': 4200,
        'currency_code': 'ILS',
      };
      expect(
        () => MenuItem.fromJson({...base, 'tags': 'spicy'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MenuItem.fromJson({
          ...base,
          'tags': ['spicy', 3],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MenuItem.fromJson({
          ...base,
          'attributes': ['not', 'an', 'object'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('buildAttributes omits unset values and trims the portion label', () {
      expect(
        MenuItem.buildAttributes(
          portionLabel: ' Family ',
          pattyCount: 2,
          pattyWeightGrams: 90,
        ),
        {'portion_label': 'Family', 'patty_count': 2, 'patty_weight_grams': 90},
      );
      expect(MenuItem.buildAttributes(portionLabel: '  '), isEmpty);
      expect(MenuItem.buildAttributes(), isEmpty);
    });

    test('copyWith carries the rich attributes through (tombstoning keeps '
        'the full row)', () {
      const item = MenuItem(
        id: 'item-1',
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: null,
        menuCategoryId: 'cat-1',
        name: 'Burger',
        description: null,
        basePriceMinor: 4200,
        currencyCode: 'ILS',
        defaultStationId: null,
        displayOrder: 0,
        isActive: true,
        itemType: 'food',
        tags: ['popular'],
        prepMinutes: 8,
        sku: 'B-1',
        kitchenNote: 'Rest 2 min.',
        attributes: {'patty_count': 1},
      );
      final deleted = item.copyWith(deletedAt: DateTime.utc(2026, 7, 3));
      expect(deleted.itemType, 'food');
      expect(deleted.tags, ['popular']);
      expect(deleted.prepMinutes, 8);
      expect(deleted.sku, 'B-1');
      expect(deleted.kitchenNote, 'Rest 2 min.');
      expect(deleted.pattyCount, 1);
      expect(deleted.isDeleted, isTrue);
    });

    test('null branch_id stays null (restaurant-scoped); tombstone parsed', () {
      final item = MenuItem.fromJson(const {
        'id': 'item-2',
        'organization_id': 'org-1',
        'restaurant_id': 'rest-1',
        'branch_id': null,
        'menu_category_id': 'cat-1',
        'name': 'Croissant',
        'base_price_minor': 400,
        'currency_code': 'USD',
        'deleted_at': '2026-06-25T10:00:00Z',
      });
      expect(item.branchId, isNull);
      expect(item.isDeleted, isTrue);
    });

    test('missing required field fails closed', () {
      expect(
        () => MenuItem.fromJson(const {'id': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('MenuWriteResult.fromOkEnvelope', () {
    test('parses {ok, entity, id, action}', () {
      final result = MenuWriteResult.fromOkEnvelope(const {
        'ok': true,
        'entity': 'menu_item',
        'id': 'item-1',
        'action': 'created',
      });
      expect(result.entity, MenuEntityType.item);
      expect(result.id, 'item-1');
      expect(result.action, MenuWriteAction.created);
    });

    test('soft_deleted action', () {
      final result = MenuWriteResult.fromOkEnvelope(const {
        'ok': true,
        'entity': 'menu_category',
        'id': 'cat-1',
        'action': 'soft_deleted',
      });
      expect(result.action, MenuWriteAction.softDeleted);
    });

    test('unknown entity/action throws FormatException', () {
      expect(
        () => MenuWriteResult.fromOkEnvelope(const {
          'ok': true,
          'entity': 'nope',
          'id': 'x',
          'action': 'created',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
