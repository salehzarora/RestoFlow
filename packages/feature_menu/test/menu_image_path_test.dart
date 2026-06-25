import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('buildMenuImageObjectKey', () {
    test('branch path', () {
      final key = buildMenuImageObjectKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        menuItemId: 'item-1',
        imageId: 'img-1',
        extension: 'png',
      );
      expect(key, 'org-1/rest-1/branch-1/menu_item/item-1/img-1.png');
    });

    test('null branch maps to the literal global', () {
      final key = buildMenuImageObjectKey(
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: null,
        menuItemId: 'item-1',
        imageId: 'img-1',
        extension: 'webp',
      );
      expect(key, 'org-1/rest-1/global/menu_item/item-1/img-1.webp');
    });

    test('extension is normalized (leading dot + case)', () {
      final key = buildMenuImageObjectKey(
        organizationId: 'o',
        restaurantId: 'r',
        branchId: 'b',
        menuItemId: 'm',
        imageId: 'i',
        extension: '.JPG',
      );
      expect(key, 'o/r/b/menu_item/m/i.jpg');
    });
  });

  group('image validation', () {
    test('allowed extensions', () {
      expect(isAllowedMenuImageExtension('png'), isTrue);
      expect(isAllowedMenuImageExtension('.JPG'), isTrue);
      expect(isAllowedMenuImageExtension('jpeg'), isTrue);
      expect(isAllowedMenuImageExtension('webp'), isTrue);
      expect(isAllowedMenuImageExtension('gif'), isFalse);
    });
    test('allowed MIME types', () {
      expect(isAllowedMenuImageMime('image/png'), isTrue);
      expect(isAllowedMenuImageMime('image/jpeg'), isTrue);
      expect(isAllowedMenuImageMime('image/webp'), isTrue);
      expect(isAllowedMenuImageMime('image/gif'), isFalse);
    });
    test('size limit is 5 MiB inclusive, positive', () {
      expect(kMaxMenuImageBytes, 5 * 1024 * 1024);
      expect(isWithinMenuImageSizeLimit(1), isTrue);
      expect(isWithinMenuImageSizeLimit(kMaxMenuImageBytes), isTrue);
      expect(isWithinMenuImageSizeLimit(kMaxMenuImageBytes + 1), isFalse);
      expect(isWithinMenuImageSizeLimit(0), isFalse);
    });
  });

  group('ImageIdGenerator', () {
    test('RandomImageIdGenerator emits an RFC-4122 v4 uuid', () {
      final id = RandomImageIdGenerator().newImageId();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'got $id',
      );
    });
    test('FixedImageIdGenerator returns the fixed id', () {
      expect(const FixedImageIdGenerator('fixed-1').newImageId(), 'fixed-1');
    });
  });
}
