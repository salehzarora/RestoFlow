import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_pos/src/data/receipt_logo_raster_cache.dart';
import 'package:restoflow_pos/src/state/pos_receipt_logo.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

Future<Uint8List> buildPng(int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i + 3] = 255; // opaque black
  }
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
