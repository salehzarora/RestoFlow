import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_pos/src/media/clear_pairing_media.dart';
import 'package:restoflow_pos/src/media/pos_media_image.dart';

class _Resolver implements DeviceImageUrlResolver {
  int calls = 0;

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    calls++;
    return {
      for (final key in objectKeys)
        key: 'https://media.example/$key?token=test-$calls',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('H5 shared pairing cleanup removes cached signed URLs', () async {
    final inner = _Resolver();
    final resolver = CachingDeviceImageUrlResolver(inner);
    final before = await resolver.signedUrlsFor(['menu/old-device.png']);
    expect(await resolver.signedUrlsFor(['menu/old-device.png']), before);
    expect(inner.calls, 1);

    clearPosPairingMedia(resolver);

    final after = await resolver.signedUrlsFor(['menu/old-device.png']);
    expect(inner.calls, 2);
    expect(after['menu/old-device.png'], isNot(before['menu/old-device.png']));
  });

  test(
    'H5 shared pairing cleanup removes the existing persistent media bytes',
    () async {
      // Exercise the real desktop/CI cache backend in its own temporary root.
      // The same public emptyCache path is used by the mobile cache backend.
      final directory = await Directory.systemTemp.createTemp(
        'bizbot-device-session-media-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getTemporaryDirectory' ||
            call.method == 'getApplicationSupportDirectory') {
          return directory.path;
        }
        throw MissingPluginException(call.method);
      });
      final cache = PosMediaCache.instance;
      addTearDown(() async {
        await cache.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        final target = path.normalize(path.absolute(directory.path));
        final expectedParent = path.normalize(
          path.absolute(Directory.systemTemp.path),
        );
        if (!path.isWithin(expectedParent, target) ||
            !path.basename(target).startsWith('bizbot-device-session-media-')) {
          throw StateError('Refusing to delete an unexpected test directory');
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      const url = 'https://media.example/menu/old-device.png?token=test-token';
      final key = stableMediaCacheKey(url);
      final file = await cache.putFile(
        url,
        Uint8List.fromList([1, 2, 3, 4]),
        key: key,
        fileExtension: 'png',
      );
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect(await cache.getFileFromCache(key), isNotNull);

      // A non-caching/null URL resolver must not prevent persistent byte cleanup.
      clearPosPairingMedia(null);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (await file.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await file.exists(), isFalse);
      expect(await cache.getFileFromCache(key), isNull);
    },
    skip: Platform.isMacOS
        ? 'Desktop byte-cache fixture uses the Windows/Linux backend'
        : false,
  );
}
