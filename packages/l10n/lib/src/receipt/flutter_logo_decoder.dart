import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-BRANDING-LOGO-001 — the Flutter/`dart:ui` half of the logo pipeline:
/// decode compressed image bytes (PNG/JPEG/WebP) into a straight-alpha RGBA
/// [DecodedLogoImage] the pure [LogoRasterizer] can process.
///
/// Lives in `packages/l10n` (the shared Flutter-bound rendering owner, alongside
/// [FlutterReceiptRasterizer]) because `dart:ui` decoding requires Flutter's
/// engine, which pure-Dart `packages/printing` cannot import. Both the POS
/// (on-device rasterization) and the Dashboard (upload validation) depend on
/// l10n and reuse this one decoder.
///
/// It uses only the Flutter SDK — no third-party image dependency. On NATIVE,
/// decoded pixel/memory limits are enforced from the encoded header
/// ([ui.ImageDescriptor]) BEFORE the full frame is allocated, so an oversized
/// image is rejected without materializing its pixels. On WEB the header-only
/// `ImageDescriptor.width`/`.height` accessors are unsupported (they throw
/// `UnsupportedError`), so the browser decodes via [ui.instantiateImageCodec] and
/// the limits are enforced on the decoded frame — bounded by the shared 2 MiB
/// byte cap already applied to the input. EXIF orientation IS normalized by the
/// dart:ui codec
/// (`ImageDescriptor.encoded` + `instantiateCodec` return the display-oriented
/// frame — verified in flutter_logo_decoder_test with a real orientation=6 JPEG),
/// and both the Dashboard validator and the POS processor use THIS one decoder,
/// so they agree on the normalized geometry.
class LogoDecodeException implements Exception {
  const LogoDecodeException(this.error);

  /// The typed reason, mapped to a localized message by the UI.
  final LogoValidationError error;

  @override
  String toString() => 'LogoDecodeException(${error.name})';
}

/// Decodes and validates a candidate logo. Pure-Flutter; deterministic given the
/// same bytes and platform codec.
class FlutterLogoDecoder {
  const FlutterLogoDecoder({this.validator = const LogoImageValidator()});

  final LogoImageValidator validator;

  /// Decode [bytes] into a straight-alpha [DecodedLogoImage], enforcing the
  /// shared §12 limits. Throws [LogoDecodeException] with a typed
  /// [LogoValidationError] for any rejected input (empty / too large /
  /// unsupported / corrupt / oversized / too small / extreme aspect /
  /// transparent-only / effectively blank).
  Future<DecodedLogoImage> decode(
    Uint8List bytes, {
    // TEST-ONLY seam: force the web/native frame-decode strategy so the
    // browser-only code path can be exercised executably on the VM test runner
    // (`ui.instantiateImageCodec` works on both). Production always resolves to
    // [kIsWeb]. Never pass this outside tests.
    @visibleForTesting bool? webStrategyOverride,
  }) async {
    // 1. Cheap pre-decode checks on the raw bytes (magic bytes, size).
    final bytesError = validator.validateBytes(bytes);
    if (bytesError != null) throw LogoDecodeException(bytesError);

    // 2. Decode the bytes into a `ui.Image`.
    //
    // WEB: the header-only `ui.ImageDescriptor.width`/`.height` accessors throw
    // `UnsupportedError` ("ImageDescriptor.width is not supported on web") — the
    // browser cannot report dimensions without decoding. Reading them (as the
    // old native path did) rejected EVERY valid browser-selected image as
    // "could not read the image". On web we therefore decode with the
    // cross-platform `ui.instantiateImageCodec` and enforce the size limits on
    // the DECODED frame; the shared 2 MiB byte cap ([kMaxLogoBytes], enforced by
    // the caller + [validator.validateBytes]) already bounds the transient bitmap.
    //
    // NATIVE: keep the header pre-check so an oversized image is rejected BEFORE
    // its full pixel buffer is ever allocated (behavior unchanged).
    final ui.Image image = (webStrategyOverride ?? kIsWeb)
        ? await _decodeFrameWeb(bytes)
        : await _decodeFrameNative(bytes);
    final width = image.width;
    final height = image.height;

    // 3. Enforce the dimension / pixel-count limits on the DECODED frame. On
    //    native this is a cheap re-check (the header pre-check already rejected
    //    oversized inputs); on web it is the only dimension guard.
    if (width > kMaxLogoDimension || height > kMaxLogoDimension) {
      image.dispose();
      throw const LogoDecodeException(LogoValidationError.dimensionTooLarge);
    }
    if (width * height > kMaxLogoPixels) {
      image.dispose();
      throw const LogoDecodeException(LogoValidationError.tooManyPixels);
    }

    // 4. Extract raw RGBA (rawRgba is supported on both web + native).
    ByteData? raw;
    try {
      raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } catch (_) {
      raw = null;
    }
    image.dispose();

    if (raw == null || raw.lengthInBytes != width * height * 4) {
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }

    // `rawRgba` is PREMULTIPLIED alpha; the pure rasterizer/validator assume
    // STRAIGHT alpha, so un-premultiply here once.
    final premultiplied = raw.buffer.asUint8List(
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final straight = Uint8List(width * height * 4);
    for (var i = 0; i < straight.length; i += 4) {
      final a = premultiplied[i + 3];
      if (a == 0) {
        // fully transparent: colour is irrelevant (flattens to white later).
        straight[i + 3] = 0;
      } else if (a == 255) {
        straight[i] = premultiplied[i];
        straight[i + 1] = premultiplied[i + 1];
        straight[i + 2] = premultiplied[i + 2];
        straight[i + 3] = 255;
      } else {
        straight[i] = _unpremul(premultiplied[i], a);
        straight[i + 1] = _unpremul(premultiplied[i + 1], a);
        straight[i + 2] = _unpremul(premultiplied[i + 2], a);
        straight[i + 3] = a;
      }
    }

    final decoded = DecodedLogoImage(
      width: width,
      height: height,
      rgba: straight,
    );

    // 4. Post-decode validation (dimensions/aspect/content).
    final decodedError = validator.validateDecoded(decoded);
    if (decodedError != null) throw LogoDecodeException(decodedError);
    return decoded;
  }

  /// Convenience: decode then rasterize for a media [profile] in one call
  /// (used by the POS to build a print-ready raster). Throws
  /// [LogoDecodeException] for an invalid image.
  Future<LogoRaster> decodeAndRasterize(
    Uint8List bytes,
    MediaProfile profile, {
    LogoRasterizer rasterizer = const LogoRasterizer(),
  }) async {
    final decoded = await decode(bytes);
    return rasterizer.rasterizeForProfile(decoded, profile);
  }

  /// NATIVE decode: reject an oversized image from its ENCODED header BEFORE the
  /// full frame is allocated, then decode it. Uses `ui.ImageDescriptor`, whose
  /// `width`/`height` accessors are only available off-web.
  Future<ui.Image> _decodeFrameNative(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      buffer.dispose();
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }
    final headerW = descriptor.width;
    final headerH = descriptor.height;
    if (headerW > kMaxLogoDimension || headerH > kMaxLogoDimension) {
      descriptor.dispose();
      buffer.dispose();
      throw const LogoDecodeException(LogoValidationError.dimensionTooLarge);
    }
    if (headerW * headerH > kMaxLogoPixels) {
      descriptor.dispose();
      buffer.dispose();
      throw const LogoDecodeException(LogoValidationError.tooManyPixels);
    }
    ui.Codec codec;
    try {
      codec = await descriptor.instantiateCodec();
    } catch (_) {
      descriptor.dispose();
      buffer.dispose();
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return image;
    } catch (_) {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }
  }

  /// WEB decode: the browser exposes no header-only dimension API, so decode via
  /// the cross-platform `ui.instantiateImageCodec` (which works on web + native)
  /// and let [decode] enforce the size limits on the decoded frame. This path
  /// NEVER touches `ui.ImageDescriptor.width`/`.height`.
  Future<ui.Image> _decodeFrameWeb(Uint8List bytes) async {
    ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();
      return image;
    } catch (_) {
      codec.dispose();
      throw const LogoDecodeException(LogoValidationError.decodeFailed);
    }
  }

  static int _unpremul(int channel, int alpha) {
    final v = (channel * 255 + (alpha ~/ 2)) ~/ alpha;
    return v > 255 ? 255 : v;
  }
}
