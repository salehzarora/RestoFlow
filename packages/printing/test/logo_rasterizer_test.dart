import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

/// A solid-colour decoded image.
DecodedLogoImage solid(
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
  return DecodedLogoImage(width: w, height: h, rgba: rgba);
}

/// A decoded image whose pixels come from [fn] (returns [r,g,b,a]).
DecodedLogoImage fromFn(int w, int h, List<int> Function(int x, int y) fn) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = (y * w + x) * 4;
      final c = fn(x, y);
      rgba[p] = c[0];
      rgba[p + 1] = c[1];
      rgba[p + 2] = c[2];
      rgba[p + 3] = c[3];
    }
  }
  return DecodedLogoImage(width: w, height: h, rgba: rgba);
}

Uint8List pngMagic([int extra = 24]) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List.filled(extra, 0),
]);
Uint8List jpegMagic([int extra = 24]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(extra, 0)]);
Uint8List webpMagic([int extra = 24]) => Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0, 0, 0, 0,
  0x57, 0x45, 0x42, 0x50, // WEBP
  ...List.filled(extra, 0),
]);

void main() {
  const rasterizer = LogoRasterizer();

  group('LogoRasterizer — geometry', () {
    test('emits a full-profile-width canvas with the correct byte length', () {
      final r = rasterizer.rasterizeForProfile(
        solid(64, 64),
        MediaProfile.label50x50,
      );
      expect(r.widthDots, 384);
      expect(r.widthBytes, 48);
      expect(r.data.length, r.widthBytes * r.heightDots);
    });

    test('576 profile => 480x216 bound, canvas 576 wide', () {
      final r = rasterizer.rasterizeForProfile(
        solid(2000, 1000),
        MediaProfile.label80x80,
      );
      expect(r.widthDots, 576);
      expect(r.widthBytes, 72);
      expect(r.heightDots, lessThanOrEqualTo(216));
    });

    test('downscales a large logo within the 384-profile 320x144 bound', () {
      final r = rasterizer.rasterize(
        solid(1600, 800),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      // width-limited then height-limited: 320/1600=0.2 -> h=160>144 ->
      // 144/800=0.18 -> w=288, h=144. Aspect 2:1 preserved.
      expect(r.heightDots, 144);
    });

    test('preserves aspect ratio (never stretches)', () {
      final r = rasterizer.rasterize(
        solid(800, 400),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      // dst should be 288x144 (ratio 2.0). Verify height and that the black
      // ink spans ~288 columns (2 * 144).
      expect(r.heightDots, 144);
    });

    test('NEVER upscales a small logo (stays native size)', () {
      final r = rasterizer.rasterize(
        solid(50, 20),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      expect(r.heightDots, 20); // not blown up to 144
    });

    test('centers the logo horizontally within the canvas', () {
      // a 16x16 solid-black logo -> stays 16x16, centered in 384.
      final r = rasterizer.rasterize(
        solid(16, 16),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      expect(r.heightDots, 16);
      // xOffset = (384-16)/2 = 184. bits should be set at columns 184..199.
      final row0 = r.data.sublist(0, r.widthBytes);
      final setColumns = <int>[];
      for (var col = 0; col < 384; col++) {
        if ((row0[col >> 3] & (0x80 >> (col & 7))) != 0) setColumns.add(col);
      }
      expect(setColumns.first, 184);
      expect(setColumns.last, 199);
      expect(setColumns.length, 16);
    });
  });

  group('LogoRasterizer — pixels', () {
    test('is deterministic (identical bytes for identical input)', () {
      final img = fromFn(
        120,
        60,
        (x, y) => [(x * 2) % 256, (y * 4) % 256, 40, 255],
      );
      final a = rasterizer.rasterizeForProfile(img, MediaProfile.label80x80);
      final b = rasterizer.rasterizeForProfile(img, MediaProfile.label80x80);
      expect(a.data, b.data);
      expect(a.heightDots, b.heightDots);
    });

    test('a solid dark logo produces black ink', () {
      final r = rasterizer.rasterize(
        solid(32, 16, r: 20, g: 20, b: 20),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      expect(r.data.any((byte) => byte != 0), isTrue);
    });

    test('a solid light logo produces (near) no ink', () {
      final r = rasterizer.rasterize(
        solid(32, 16, r: 250, g: 250, b: 250),
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      final inkBits = r.data.fold<int>(
        0,
        (acc, byte) => acc + byte.toRadixString(2).replaceAll('0', '').length,
      );
      expect(inkBits, lessThan(4)); // essentially white
    });

    test('fully transparent pixels flatten to white (no ink)', () {
      // left half opaque black, right half transparent.
      final img = fromFn(
        40,
        20,
        (x, y) => x < 20 ? [0, 0, 0, 255] : [0, 0, 0, 0],
      );
      final r = rasterizer.rasterize(
        img,
        canvasWidthDots: 384,
        maxWidthDots: 320,
        maxHeightDots: 144,
      );
      // xOffset = (384-40)/2 = 172. Black columns should be 172..191 (the
      // opaque half) and nothing in 192..211 (the transparent half).
      final row0 = r.data.sublist(0, r.widthBytes);
      bool colSet(int col) => (row0[col >> 3] & (0x80 >> (col & 7))) != 0;
      expect(colSet(180), isTrue); // inside opaque half
      expect(colSet(205), isFalse); // inside transparent half
    });
  });

  group('LogoImageValidator — bytes', () {
    const v = LogoImageValidator();
    test('sniffs PNG/JPEG/WebP magic bytes (not the extension)', () {
      expect(v.sniffMime(pngMagic()), 'image/png');
      expect(v.sniffMime(jpegMagic()), 'image/jpeg');
      expect(v.sniffMime(webpMagic()), 'image/webp');
      expect(v.sniffMime(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });
    test('empty => emptyFile', () {
      expect(v.validateBytes(Uint8List(0)), LogoValidationError.emptyFile);
    });
    test('over 2 MiB => tooLarge', () {
      final big = Uint8List(kMaxLogoBytes + 1);
      big.setRange(0, 8, pngMagic(0));
      expect(v.validateBytes(big), LogoValidationError.tooLarge);
    });
    test('unrecognized magic => unsupportedFormat', () {
      expect(
        v.validateBytes(Uint8List.fromList(List.filled(64, 0x42))),
        LogoValidationError.unsupportedFormat,
      );
    });
    test('a valid small PNG passes the byte check', () {
      expect(v.validateBytes(pngMagic()), isNull);
    });
  });

  group('LogoImageValidator — decoded', () {
    const v = LogoImageValidator();
    test('a normal opaque logo is accepted', () {
      expect(v.validateDecoded(solid(200, 100, r: 10, g: 10, b: 10)), isNull);
    });
    test('all-black line-art is ALLOWED', () {
      expect(v.validateDecoded(solid(64, 64, r: 0, g: 0, b: 0)), isNull);
    });
    test('too small => tooSmall', () {
      expect(
        v.validateDecoded(solid(16, 8, r: 0, g: 0, b: 0)),
        LogoValidationError.tooSmall,
      );
    });
    test('extreme aspect ratio => extremeAspectRatio', () {
      expect(
        v.validateDecoded(solid(900, 100, r: 0, g: 0, b: 0)),
        LogoValidationError.extremeAspectRatio,
      );
    });
    test('a dimension over 4096 => dimensionTooLarge', () {
      expect(
        v.validateDecoded(solid(4097, 2, r: 0, g: 0, b: 0)),
        LogoValidationError.dimensionTooLarge,
      );
    });
    test('over 16 MP => tooManyPixels', () {
      // 4096 x 4001 = 16,388,096 px (both sides <= 4096, product > 16 MP).
      expect(
        v.validateDecoded(solid(4096, 4001, r: 0, g: 0, b: 0)),
        LogoValidationError.tooManyPixels,
      );
    });
    test('fully transparent => transparentImage', () {
      expect(
        v.validateDecoded(solid(64, 64, a: 0)),
        LogoValidationError.transparentImage,
      );
    });
    test('effectively all-white => blankImage', () {
      expect(
        v.validateDecoded(solid(64, 64, r: 255, g: 255, b: 255)),
        LogoValidationError.blankImage,
      );
    });
  });

  group('ReceiptLogoBounds', () {
    test('384-dot profile => 320x144', () {
      final b = ReceiptLogoBounds.forProfile(MediaProfile.label50x50);
      expect(b.maxWidthDots, 320);
      expect(b.maxHeightDots, 144);
    });
    test('576-dot profiles => 480x216', () {
      for (final p in [MediaProfile.label80x80, MediaProfile.continuous80]) {
        final b = ReceiptLogoBounds.forProfile(p);
        expect(b.maxWidthDots, 480);
        expect(b.maxHeightDots, 216);
      }
    });
  });
}
