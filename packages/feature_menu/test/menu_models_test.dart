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
