import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('FakeMenuImageStorage (the deferred storage seam)', () {
    test(
      'upload records the object key (no real I/O, no production claim)',
      () async {
        final storage = FakeMenuImageStorage();
        final key = buildMenuImageObjectKey(
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: null,
          menuItemId: 'item-1',
          imageId: const FixedImageIdGenerator('img-1').newImageId(),
          extension: 'png',
        );

        final upload = await storage.upload(
          objectKey: key,
          bytes: const [1, 2, 3],
          mimeType: 'image/png',
        );

        expect(
          upload.objectKey,
          'org-1/rest-1/global/menu_item/item-1/img-1.png',
        );
        expect(storage.uploads.single.objectKey, key);
      },
    );

    test('createSignedUrl returns a signed (non-public) URL', () async {
      final storage = FakeMenuImageStorage();
      final url = await storage.createSignedUrl(
        'org-1/rest-1/global/menu_item/item-1/img-1.png',
      );
      // Private bucket: a signed URL, never a durable public/getPublicUrl link.
      expect(url.toString(), startsWith('fake-signed://'));
      expect(url.toString(), isNot(contains('public')));
    });
  });
}
