import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_pos/src/data/receipt_logo_raster_cache.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

Future<Uint8List> _buildPngFrom(Uint8List rgba, int w, int h) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> buildPng(int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i + 3] = 255; // opaque black
  }
  return _buildPngFrom(rgba, w, h);
}

class _FakeReader implements DeviceReceiptLogoReader {
  _FakeReader(this._bytes);
  final Uint8List? _bytes;
  int calls = 0;

  @override
  Future<ReceiptLogoBytes?> load(String objectPath) async {
    calls++;
    if (_bytes == null) return null;
    return ReceiptLogoBytes(bytes: _bytes, mime: 'image/png');
  }
}

const _config = PosReceiptLogoConfig(
  organizationId: 'org1',
  restaurantId: 'rest1',
  path: 'org1/rest1/logo/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.png',
  version: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = pp.MediaProfile.label80x80;

  test('downloads, rasterizes, caches, and exposes an asset', () async {
    final png = await buildPng(64, 32);
    final reader = _FakeReader(png);
    final cache = InMemoryReceiptLogoRasterCache();
    final controller = PosReceiptLogoController(cache: cache, reader: reader);
    await controller.resolve(_config, profile);
    expect(controller.state, isNotNull);
    expect(controller.state!.raster, isNotNull); // native raster produced
    expect(controller.state!.sourceBytes, png); // source kept for HTML/preview
    expect(reader.calls, 1);
    // The raster was persisted under the fully-qualified key.
    final cached = await cache.read(
      ReceiptLogoCacheKey(
        organizationId: 'org1',
        restaurantId: 'rest1',
        logoVersion: 2,
        mediaProfileId: profile.idKey,
        widthDots: profile.widthDots,
        preprocessingVersion: pp.kLogoRasterPreprocessingVersion,
      ),
    );
    expect(cached, isNotNull);
  });

  test(
    'serves from cache WITHOUT downloading (cache-first / offline)',
    () async {
      final png = await buildPng(64, 32);
      final cache = InMemoryReceiptLogoRasterCache();
      // Warm the cache via a first controller.
      await PosReceiptLogoController(
        cache: cache,
        reader: _FakeReader(png),
      ).resolve(_config, profile);
      // A second controller whose reader would THROW proves the cache is used.
      final offlineReader = _FakeReader(null);
      final controller = PosReceiptLogoController(
        cache: cache,
        reader: offlineReader,
      );
      await controller.resolve(_config, profile);
      expect(controller.state, isNotNull);
      expect(offlineReader.calls, 0, reason: 'served from cache, no download');
    },
  );

  group('F5 §13-14: publish an asset ONLY after a successful decode', () {
    Future<void> expectNoAsset(Uint8List bytes) async {
      final controller = PosReceiptLogoController(
        cache: InMemoryReceiptLogoRasterCache(),
        reader: _FakeReader(bytes),
      );
      await controller.resolve(_config, profile);
      expect(
        controller.state,
        isNull,
        reason: 'a failed decode must not publish source-bytes-only',
      );
    }

    test('corrupt PNG (valid magic, bad body) => no asset', () async {
      await expectNoAsset(
        Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
          ...List.filled(48, 0x01), // garbage
        ]),
      );
    });

    test('non-image bytes => no asset', () async {
      await expectNoAsset(Uint8List.fromList(List.filled(64, 0x42)));
    });

    test('an all-white image => no asset (rejected content)', () async {
      final white = Uint8List(64 * 64 * 4);
      for (var i = 0; i < white.length; i++) {
        white[i] = 0xFF; // opaque white
      }
      // Encode to a real PNG then feed it back through the reader/decoder.
      await expectNoAsset(await _buildPngFrom(white, 64, 64));
    });

    test('a valid image DOES publish an asset (control)', () async {
      final controller = PosReceiptLogoController(
        cache: InMemoryReceiptLogoRasterCache(),
        reader: _FakeReader(await buildPng(64, 32)),
      );
      await controller.resolve(_config, profile);
      expect(controller.state, isNotNull);
    });
  });

  test('offline with a cold cache => null asset (text-only)', () async {
    final controller = PosReceiptLogoController(
      cache: InMemoryReceiptLogoRasterCache(),
      reader: _FakeReader(null), // download returns null
    );
    await controller.resolve(_config, profile);
    expect(controller.state, isNull);
  });

  test('no reader seam => null asset (demo/unconfigured)', () async {
    final controller = PosReceiptLogoController(
      cache: InMemoryReceiptLogoRasterCache(),
      reader: null,
    );
    await controller.resolve(_config, profile);
    expect(controller.state, isNull);
  });

  test('null config => null asset', () async {
    final controller = PosReceiptLogoController(
      cache: InMemoryReceiptLogoRasterCache(),
      reader: _FakeReader(await buildPng(64, 32)),
    );
    await controller.resolve(null, profile);
    expect(controller.state, isNull);
  });

  test('a superseding resolve wins (epoch guard, version race)', () async {
    final png = await buildPng(64, 32);
    final controller = PosReceiptLogoController(
      cache: InMemoryReceiptLogoRasterCache(),
      reader: _FakeReader(png),
    );
    // Kick off a resolve then immediately supersede with a null config.
    final first = controller.resolve(_config, profile);
    final second = controller.resolve(null, profile);
    await Future.wait([first, second]);
    // The LAST resolve (null config) is authoritative.
    expect(controller.state, isNull);
  });
}
