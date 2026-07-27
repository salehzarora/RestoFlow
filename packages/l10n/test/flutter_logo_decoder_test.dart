import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// Build real PNG bytes from a straight-alpha RGBA buffer via `dart:ui` (no
/// third-party encoder). Deterministic fixtures generated at test time.
Future<Uint8List> buildPng(Uint8List rgba, int w, int h) async {
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

Uint8List solidRgba(
  int w,
  int h, {
  int r = 0,
  int g = 0,
  int b = 0,
  int a = 255,
}) {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }
  return rgba;
}

Future<LogoValidationError?> errorFor(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } on LogoDecodeException catch (e) {
    return e.error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const decoder = FlutterLogoDecoder();

  test('decodes a valid opaque PNG into straight-alpha RGBA', () async {
    final png = await buildPng(solidRgba(64, 48, r: 10, g: 10, b: 10), 64, 48);
    final decoded = await decoder.decode(png);
    expect(decoded.width, 64);
    expect(decoded.height, 48);
    expect(decoded.rgba.length, 64 * 48 * 4);
    // opaque dark pixel: alpha 255, near-black colour.
    expect(decoded.rgba[3], 255);
    expect(decoded.rgba[0], lessThan(40));
  });

  test('decodes a transparent-background logo with ink', () async {
    // left half opaque black, right half transparent.
    final rgba = Uint8List(64 * 32 * 4);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 64; x++) {
        final p = (y * 64 + x) * 4;
        if (x < 32) {
          rgba[p + 3] = 255; // opaque black
        } else {
          rgba[p + 3] = 0; // transparent
        }
      }
    }
    final png = await buildPng(rgba, 64, 32);
    final decoded = await decoder.decode(png);
    expect(decoded.width, 64);
    // a transparent pixel round-trips to alpha 0.
    final transparentPixel = (0 * 64 + 40) * 4;
    expect(decoded.rgba[transparentPixel + 3], 0);
  });

  test('decodeAndRasterize produces a print-ready raster', () async {
    final png = await buildPng(solidRgba(120, 60, r: 5, g: 5, b: 5), 120, 60);
    final raster = await decoder.decodeAndRasterize(
      png,
      MediaProfile.label80x80,
    );
    expect(raster.widthDots, 576);
    expect(raster.data.length, raster.widthBytes * raster.heightDots);
    expect(raster.data.any((byte) => byte != 0), isTrue); // has ink
  });

  test('rejects empty bytes => emptyFile', () async {
    expect(
      await errorFor(() => decoder.decode(Uint8List(0))),
      LogoValidationError.emptyFile,
    );
  });

  test('rejects non-image bytes => unsupportedFormat', () async {
    expect(
      await errorFor(
        () => decoder.decode(Uint8List.fromList(List.filled(64, 0x42))),
      ),
      LogoValidationError.unsupportedFormat,
    );
  });

  test('rejects corrupt PNG (valid magic, bad body) => decodeFailed', () async {
    final corrupt = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
      ...List.filled(40, 0x01), // garbage
    ]);
    expect(
      await errorFor(() => decoder.decode(corrupt)),
      LogoValidationError.decodeFailed,
    );
  });

  test('rejects a fully transparent PNG => transparentImage', () async {
    final png = await buildPng(solidRgba(64, 64, a: 0), 64, 64);
    expect(
      await errorFor(() => decoder.decode(png)),
      LogoValidationError.transparentImage,
    );
  });

  test('rejects an all-white PNG => blankImage', () async {
    final png = await buildPng(
      solidRgba(64, 64, r: 255, g: 255, b: 255),
      64,
      64,
    );
    expect(
      await errorFor(() => decoder.decode(png)),
      LogoValidationError.blankImage,
    );
  });

  test('rejects a too-small PNG => tooSmall', () async {
    final png = await buildPng(solidRgba(16, 8, r: 0, g: 0, b: 0), 16, 8);
    expect(
      await errorFor(() => decoder.decode(png)),
      LogoValidationError.tooSmall,
    );
  });
}
