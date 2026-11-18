import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_file.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_models.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_storage.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_welcome_video_upload.dart';

import 'storefront_welcome_video_publisher_test.dart' show org, restaurant;

class VideoStorage implements StorefrontWelcomeVideoStorage {
  final writes = <({String key, Uint8List bytes})>[];
  Completer<void>? wait;
  @override
  Future<void> uploadWelcomeVideo({
    required String objectKey,
    required Uint8List bytes,
  }) async {
    writes.add((key: objectKey, bytes: bytes));
    if (wait != null) await wait!.future;
  }

  @override
  Uri publicWelcomeVideoUrl(String key) => Uri.parse(
    'https://project.supabase.co/storage/v1/object/public/storefront-welcome-videos/$key',
  );
}

const imageId = '66666666-6666-4666-8666-666666666666';
PickedWelcomeVideo clientFile([int bytes = 16, String mime = 'video/mp4']) =>
    PickedWelcomeVideo(bytes: Uint8List(bytes), mimeType: mime);
StorefrontWelcomeVideoUpload upload(
  VideoStorage storage,
  Future<PickedWelcomeVideo?> Function() picker,
) => StorefrontWelcomeVideoUpload(
  storage: storage,
  organizationId: org,
  restaurantId: restaurant,
  picker: picker,
  pickerSupported: true,
  ids: () => imageId,
);

void main() {
  test(
    'one bounded private upload uses scoped immutable key; no selection or publication',
    () async {
      final storage = VideoStorage();
      final key = await upload(
        storage,
        () async => clientFile(),
      ).pickAndUpload(isCurrent: () => true);
      expect(key, '$org/$restaurant/$imageId.mp4');
      expect(storage.writes.single.key, key);
      expect(storage.writes.single.bytes.length, 16);
    },
  );
  test(
    'cancel and membership change while file picker is open do not upload',
    () async {
      final storage = VideoStorage();
      expect(
        await upload(
          storage,
          () async => null,
        ).pickAndUpload(isCurrent: () => true),
        isNull,
      );
      final picked = Completer<PickedWelcomeVideo?>();
      var current = true;
      final pending = upload(
        storage,
        () => picked.future,
      ).pickAndUpload(isCurrent: () => current);
      current = false;
      picked.complete(clientFile());
      expect(await pending, isNull);
      expect(storage.writes, isEmpty);
    },
  );
  test(
    'late private-upload result after binding change cannot start publication',
    () async {
      final storage = VideoStorage()..wait = Completer<void>();
      var current = true;
      final pending = upload(
        storage,
        () async => clientFile(),
      ).pickAndUpload(isCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      storage.wait!.complete();
      expect(await pending, isNull);
      expect(storage.writes, hasLength(1));
    },
  );
  test('MIME, zero-size and oversize fail before storage writes', () async {
    final storage = VideoStorage();
    for (final file in [
      clientFile(0),
      clientFile(10, 'image/png'),
      clientFile(welcomeVideoMaxBytes + 1),
    ]) {
      await expectLater(
        upload(storage, () async => file).pickAndUpload(isCurrent: () => true),
        throwsFormatException,
      );
    }
    expect(storage.writes, isEmpty);
  });
  test(
    'invalid scope or generated identifier cannot write outside fixed path',
    () async {
      final storage = VideoStorage();
      final bad = StorefrontWelcomeVideoUpload(
        storage: storage,
        organizationId: '../other',
        restaurantId: restaurant,
        picker: () async => clientFile(),
        pickerSupported: true,
        ids: () => imageId,
      );
      await expectLater(
        bad.pickAndUpload(isCurrent: () => true),
        throwsFormatException,
      );
      expect(storage.writes, isEmpty);
    },
  );
}
