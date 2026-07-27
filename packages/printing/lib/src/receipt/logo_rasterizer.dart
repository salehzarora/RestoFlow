/// PRINT-BRANDING-LOGO-001 — pure, deterministic receipt-logo rasterization.
///
/// This is the SHARED, platform-free half of the logo pipeline: it turns an
/// already-decoded, orientation-normalized [DecodedLogoImage] (RGBA) into a
/// centered 1-bit-per-pixel monochrome bitmap sized for a thermal head. The
/// Flutter/`dart:ui` DECODER (which produces the RGBA + normalizes EXIF
/// orientation) lives in `packages/l10n`; nothing here touches a platform API,
/// so the whole algorithm is unit-testable and reproducible byte-for-byte.
///
/// The output is a full-media-width canvas (a multiple of 8 dots) with the
/// aspect-preserved, dithered logo centered horizontally — so it prints centered
/// regardless of whether a given printer honours ESC/POS raster alignment.
library;

import 'dart:typed_data';

import '../media_profile.dart';
import '../print_document.dart';

/// The pre-processing algorithm version. It is part of the POS raster-cache key
/// (§15): bumping it invalidates every cached raster so an algorithm change
/// never serves a stale bitmap. Bump this whenever the rasterization output for
/// the same input could change.
const int kLogoRasterPreprocessingVersion = 1;

// ---- Input limits (§12). Shared so the Dashboard validator and the POS decoder
//      enforce the SAME bounds. ------------------------------------------------

/// Maximum accepted compressed image size (2 MiB) — matches the storage bucket.
const int kMaxLogoBytes = 2 * 1024 * 1024;

/// Maximum accepted decoded width or height in pixels.
const int kMaxLogoDimension = 4096;

/// Maximum accepted decoded pixel count (guards memory before allocation).
const int kMaxLogoPixels = 16000000;

/// Minimum useful decoded width / height in pixels.
const int kMinLogoWidth = 32;
const int kMinLogoHeight = 16;

/// The permitted aspect-ratio bound: neither side may exceed 8× the other.
const int kMaxLogoAspectRatio = 8;

/// The luminance below which a flattened pixel is treated as ink (0..255).
/// Matches the receipt text rasterizer's threshold so a logo and text agree on
/// what "black" means.
const int kLogoLuminanceThreshold = 128;

/// A near-white cutoff: a flattened image whose every pixel is at or above this
/// is treated as "effectively all white" (no printable ink) and rejected.
const int kLogoBlankLuminance = 250;

/// Why an image was rejected. The Dashboard maps each to a localized message
/// (§12/§23); the class itself carries no user-facing text.
enum LogoValidationError {
  /// No bytes at all.
  emptyFile,

  /// Compressed size exceeds [kMaxLogoBytes].
  tooLarge,

  /// The magic bytes are not PNG / JPEG / WebP (extension/MIME is not trusted).
  unsupportedFormat,

  /// The bytes could not be decoded into a valid image.
  decodeFailed,

  /// A decoded side exceeds [kMaxLogoDimension].
  dimensionTooLarge,

  /// The decoded pixel count exceeds [kMaxLogoPixels].
  tooManyPixels,

  /// The decoded image is smaller than [kMinLogoWidth] × [kMinLogoHeight].
  tooSmall,

  /// One side is more than 8× the other.
  extremeAspectRatio,

  /// Every pixel is fully transparent (no visible content).
  transparentImage,

  /// Flattened onto white, the image has no printable ink (effectively blank).
  blankImage,
}

/// A decoded, orientation-normalized RGBA image (row-major, 4 bytes/pixel,
/// straight — NOT premultiplied — alpha). Produced by the Flutter decoder.
class DecodedLogoImage {
  DecodedLogoImage({
    required this.width,
    required this.height,
    required this.rgba,
  }) : assert(width > 0 && height > 0),
       assert(
         rgba.length == width * height * 4,
         'rgba length must equal width * height * 4',
       );

  final int width;
  final int height;
  final Uint8List rgba;
}

/// The maximum printable logo box for a media profile (§14).
class ReceiptLogoBounds {
  const ReceiptLogoBounds({
    required this.maxWidthDots,
    required this.maxHeightDots,
  }) : assert(maxWidthDots > 0 && maxHeightDots > 0);

  /// Maximum logo raster width in dots.
  final int maxWidthDots;

  /// Maximum logo raster height in dots.
  final int maxHeightDots;

  /// The §14 bounds derived from the media profile's dot width:
  ///  * 384-dot profiles (50×50 label)  -> 320 × 144
  ///  * 576-dot profiles (80×80 / cont.) -> 480 × 216
  factory ReceiptLogoBounds.forProfile(MediaProfile profile) {
    if (profile.widthDots <= 384) {
      return const ReceiptLogoBounds(maxWidthDots: 320, maxHeightDots: 144);
    }
    return const ReceiptLogoBounds(maxWidthDots: 480, maxHeightDots: 216);
  }
}

/// A rasterized, print-ready logo bitmap. [data] is row-major, 1bpp, MSB-first
/// (bit 1 == black dot) — exactly the [PrintRasterImageLine] contract. It is a
/// full-media-width canvas ([widthDots], a multiple of 8) with the logo centered.
class LogoRaster {
  LogoRaster({
    required this.widthDots,
    required this.widthBytes,
    required this.heightDots,
    required this.data,
  }) : assert(widthDots > 0 && widthDots % 8 == 0),
       assert(widthBytes == (widthDots + 7) ~/ 8),
       assert(heightDots > 0),
       assert(
         data.length == widthBytes * heightDots,
         'data length must equal widthBytes * heightDots',
       );

  /// Full canvas width in dots (a multiple of 8).
  final int widthDots;

  /// Bytes per row (`widthDots / 8`).
  final int widthBytes;

  /// Rendered height in dots.
  final int heightDots;

  /// 1bpp MSB-first row-major payload (bit 1 == black).
  final Uint8List data;

  /// Convert to the render-neutral print line (same 1bpp contract).
  PrintRasterImageLine toPrintLine() => PrintRasterImageLine(
    data: data,
    widthBytes: widthBytes,
    heightDots: heightDots,
  );
}

/// Validates candidate logo bytes/images against the shared [§12] limits. Pure —
/// operates on raw bytes and decoded pixels only; returns a typed error (or null
/// when acceptable), never a user-facing string.
class LogoImageValidator {
  const LogoImageValidator();

  /// Sniff the format from the leading magic bytes (never the file extension or
  /// the browser-reported MIME). Returns the canonical MIME or null.
  String? sniffMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return 'image/webp';
    }
    return null;
  }

  /// Validate the raw compressed bytes (before decoding). Returns null when the
  /// bytes are a non-empty, in-size, recognised PNG/JPEG/WebP.
  LogoValidationError? validateBytes(Uint8List bytes) {
    if (bytes.isEmpty) return LogoValidationError.emptyFile;
    if (bytes.length > kMaxLogoBytes) return LogoValidationError.tooLarge;
    if (sniffMime(bytes) == null) return LogoValidationError.unsupportedFormat;
    return null;
  }

  /// Validate a decoded image (dimensions, aspect, and visible content). Returns
  /// null when the image is acceptable for rasterization.
  LogoValidationError? validateDecoded(DecodedLogoImage image) {
    final w = image.width, h = image.height;
    if (w > kMaxLogoDimension || h > kMaxLogoDimension) {
      return LogoValidationError.dimensionTooLarge;
    }
    if (w * h > kMaxLogoPixels) return LogoValidationError.tooManyPixels;
    if (w < kMinLogoWidth || h < kMinLogoHeight) {
      return LogoValidationError.tooSmall;
    }
    final longSide = w > h ? w : h;
    final shortSide = w > h ? h : w;
    if (longSide > shortSide * kMaxLogoAspectRatio) {
      return LogoValidationError.extremeAspectRatio;
    }
    // Content checks over the pixels: reject fully-transparent and effectively
    // all-white (after flattening onto white); allow all-black / line-art.
    final rgba = image.rgba;
    var anyOpaque = false;
    var anyInk = false;
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a != 0) anyOpaque = true;
      // flatten onto white, then luminance.
      final r = (rgba[i] * a + 255 * (255 - a)) ~/ 255;
      final g = (rgba[i + 1] * a + 255 * (255 - a)) ~/ 255;
      final b = (rgba[i + 2] * a + 255 * (255 - a)) ~/ 255;
      final lum = (r * 30 + g * 59 + b * 11) ~/ 100;
      if (lum < kLogoBlankLuminance) anyInk = true;
      if (anyOpaque && anyInk) break; // both satisfied — no need to scan on
    }
    if (!anyOpaque) return LogoValidationError.transparentImage;
    if (!anyInk) return LogoValidationError.blankImage;
    return null;
  }
}

/// The pure, deterministic logo rasterizer (§13). No platform APIs, no async —
/// the same input always yields byte-identical output.
class LogoRasterizer {
  const LogoRasterizer();

  /// Rasterize [source] for a media [profile]: aspect-preserving downscale into
  /// the profile's §14 bounds, Floyd–Steinberg dither, centered into a
  /// full-profile-width 1bpp canvas.
  LogoRaster rasterizeForProfile(
    DecodedLogoImage source,
    MediaProfile profile,
  ) {
    final bounds = ReceiptLogoBounds.forProfile(profile);
    return rasterize(
      source,
      canvasWidthDots: profile.widthDots,
      maxWidthDots: bounds.maxWidthDots,
      maxHeightDots: bounds.maxHeightDots,
    );
  }

  /// Rasterize [source] into a [canvasWidthDots]-wide 1bpp canvas, with the logo
  /// downscaled (never upscaled, never cropped, never stretched) to fit within
  /// [maxWidthDots] × [maxHeightDots] and centered horizontally.
  LogoRaster rasterize(
    DecodedLogoImage source, {
    required int canvasWidthDots,
    required int maxWidthDots,
    required int maxHeightDots,
    int luminanceThreshold = kLogoLuminanceThreshold,
  }) {
    assert(canvasWidthDots > 0 && canvasWidthDots % 8 == 0);
    assert(maxWidthDots > 0 && maxHeightDots > 0);
    assert(maxWidthDots <= canvasWidthDots);

    final srcW = source.width, srcH = source.height;
    final rgba = source.rgba;

    // 1-2. flatten alpha onto white, then luminance grayscale (0..255).
    final gray = Uint8List(srcW * srcH);
    for (var p = 0, i = 0; p < gray.length; p++, i += 4) {
      final a = rgba[i + 3];
      final r = (rgba[i] * a + 255 * (255 - a)) ~/ 255;
      final g = (rgba[i + 1] * a + 255 * (255 - a)) ~/ 255;
      final b = (rgba[i + 2] * a + 255 * (255 - a)) ~/ 255;
      gray[p] = (r * 30 + g * 59 + b * 11) ~/ 100;
    }

    // 3. aspect-preserving scale factor — NEVER greater than 1 (no upscaling).
    var scale = 1.0;
    if (srcW > maxWidthDots) scale = maxWidthDots / srcW;
    if (srcH * scale > maxHeightDots) scale = maxHeightDots / srcH;
    var dstW = (srcW * scale).round();
    var dstH = (srcH * scale).round();
    if (dstW < 1) dstW = 1;
    if (dstH < 1) dstH = 1;
    if (dstW > maxWidthDots) dstW = maxWidthDots;
    if (dstH > maxHeightDots) dstH = maxHeightDots;

    // 4. area-average downscale (box filter) — deterministic; identity when same.
    final dstGray = _areaDownscale(gray, srcW, srcH, dstW, dstH);

    // 5. Floyd–Steinberg dither -> one bit per pixel (1 == black dot).
    final bits = _floydSteinberg(dstGray, dstW, dstH, luminanceThreshold);

    // 6. pack centered into a full-width 1bpp canvas (white padding on the sides).
    final widthBytes = (canvasWidthDots + 7) ~/ 8;
    var xOffset = (canvasWidthDots - dstW) ~/ 2;
    if (xOffset < 0) xOffset = 0;
    final data = Uint8List(widthBytes * dstH); // 0 == white
    for (var y = 0; y < dstH; y++) {
      final rowBase = y * widthBytes;
      final bitRow = y * dstW;
      for (var x = 0; x < dstW; x++) {
        if (bits[bitRow + x] == 1) {
          final col = xOffset + x;
          data[rowBase + (col >> 3)] |= (0x80 >> (col & 7));
        }
      }
    }

    return LogoRaster(
      widthDots: canvasWidthDots,
      widthBytes: widthBytes,
      heightDots: dstH,
      data: data,
    );
  }

  /// Box-average downscale of a grayscale buffer. Identity (returns the input)
  /// when the target equals the source size (never upscales — callers cap dst).
  Uint8List _areaDownscale(
    Uint8List gray,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (dstW == srcW && dstH == srcH) return gray;
    final out = Uint8List(dstW * dstH);
    for (var dy = 0; dy < dstH; dy++) {
      final sy0 = dy * srcH ~/ dstH;
      var sy1 = (dy + 1) * srcH ~/ dstH;
      if (sy1 <= sy0) sy1 = sy0 + 1;
      for (var dx = 0; dx < dstW; dx++) {
        final sx0 = dx * srcW ~/ dstW;
        var sx1 = (dx + 1) * srcW ~/ dstW;
        if (sx1 <= sx0) sx1 = sx0 + 1;
        var sum = 0, count = 0;
        for (var sy = sy0; sy < sy1; sy++) {
          final base = sy * srcW;
          for (var sx = sx0; sx < sx1; sx++) {
            sum += gray[base + sx];
            count++;
          }
        }
        out[dy * dstW + dx] = sum ~/ count;
      }
    }
    return out;
  }

  /// Floyd–Steinberg error diffusion over a grayscale buffer. Integer-only and
  /// single fixed traversal, so the output is fully deterministic. Returns one
  /// byte per pixel: 1 == black dot, 0 == white.
  Uint8List _floydSteinberg(Uint8List gray, int w, int h, int threshold) {
    final buf = Int32List(w * h);
    for (var i = 0; i < buf.length; i++) {
      buf[i] = gray[i];
    }
    final bits = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = y * w + x;
        final oldValue = buf[idx];
        final black = oldValue < threshold;
        bits[idx] = black ? 1 : 0;
        final newValue = black ? 0 : 255;
        final err = oldValue - newValue;
        if (x + 1 < w) buf[idx + 1] += err * 7 ~/ 16;
        if (y + 1 < h) {
          if (x - 1 >= 0) buf[idx + w - 1] += err * 3 ~/ 16;
          buf[idx + w] += err * 5 ~/ 16;
          if (x + 1 < w) buf[idx + w + 1] += err * 1 ~/ 16;
        }
      }
    }
    return bits;
  }
}
