import 'dart:math' as math;

/// Same bounded CSS-pixel image area as the responsive Storefront. Null means
/// automatic ratio only after the owner explicitly enables responsive layout.
double storefrontResponsiveBannerHeight({
  required bool phone,
  required num viewportWidth,
  required num imageWidth,
  required num imageHeight,
  int? customHeight,
}) {
  final low = phone ? 320 : 240,
      high = customHeight == null ? (phone ? 640 : 480) : (phone ? 640 : 560);
  final ratioHeight =
      viewportWidth.isFinite &&
          viewportWidth > 0 &&
          imageWidth.isFinite &&
          imageWidth > 0 &&
          imageHeight.isFinite &&
          imageHeight > 0
      ? viewportWidth * imageHeight / imageWidth
      : low.toDouble();
  return (customHeight?.toDouble() ?? ratioHeight).clamp(low, high).toDouble();
}

/// Physical CSS image-fit geometry. X is measured from the left even in RTL.
/// Clipped distances are original-image pixels; offsets are logical CSS pixels.
class StorefrontBannerCrop {
  const StorefrontBannerCrop._({
    required this.naturalWidth,
    required this.naturalHeight,
    required this.viewWidth,
    required this.viewHeight,
    required this.documentHeight,
    required this.scale,
    required this.renderedWidth,
    required this.renderedHeight,
    required this.offsetX,
    required this.offsetY,
    required this.sourceLeft,
    required this.sourceTop,
    required this.clippedX,
    required this.clippedY,
    required this.imageLoaded,
  });

  factory StorefrontBannerCrop.cover(
    num imageWidth,
    num imageHeight,
    num viewWidth,
    num viewHeight,
    num x,
    num y, {
    bool imageLoaded = true,
    num? documentHeight,
    bool contain = false,
  }) {
    double dimension(num n) => n.isFinite && n > 0 ? n.toDouble() : 0;
    final iw = dimension(imageWidth), ih = dimension(imageHeight);
    final vw = dimension(viewWidth), vh = dimension(viewHeight);
    final loaded = imageLoaded && iw > 0 && ih > 0 && vw > 0 && vh > 0;
    final scale = loaded
        ? (contain ? math.min(vw / iw, vh / ih) : math.max(vw / iw, vh / ih))
        : 0.0;
    final rw = iw * scale, rh = ih * scale;
    double point(num n) => n.isFinite ? n.clamp(0, 100).toDouble() / 100 : .5;
    final dx = loaded ? (vw - rw) * point(x) : 0.0;
    final dy = loaded ? (vh - rh) * point(y) : 0.0;
    return StorefrontBannerCrop._(
      naturalWidth: iw,
      naturalHeight: ih,
      viewWidth: vw,
      viewHeight: vh,
      documentHeight: dimension(documentHeight ?? vh),
      scale: scale,
      renderedWidth: rw,
      renderedHeight: rh,
      offsetX: dx,
      offsetY: dy,
      sourceLeft: loaded ? math.max(0, -dx / scale) : 0,
      sourceTop: loaded ? math.max(0, -dy / scale) : 0,
      clippedX: loaded ? math.max(0, iw - vw / scale) : 0,
      clippedY: loaded ? math.max(0, ih - vh / scale) : 0,
      imageLoaded: loaded,
    );
  }

  final double naturalWidth, naturalHeight, viewWidth, viewHeight;
  final double documentHeight, scale, renderedWidth, renderedHeight;
  final double offsetX, offsetY, sourceLeft, sourceTop, clippedX, clippedY;
  final bool imageLoaded;

  /// Stable observer comparison: subpixel noise does not cause parent rebuilds.
  bool sameAs(StorefrontBannerCrop? other) {
    if (other == null || imageLoaded != other.imageLoaded) return false;
    final a = [
      naturalWidth,
      naturalHeight,
      viewWidth,
      viewHeight,
      documentHeight,
      scale,
      renderedWidth,
      renderedHeight,
      offsetX,
      offsetY,
      sourceLeft,
      sourceTop,
      clippedX,
      clippedY,
    ];
    final b = [
      other.naturalWidth,
      other.naturalHeight,
      other.viewWidth,
      other.viewHeight,
      other.documentHeight,
      other.scale,
      other.renderedWidth,
      other.renderedHeight,
      other.offsetX,
      other.offsetY,
      other.sourceLeft,
      other.sourceTop,
      other.clippedX,
      other.clippedY,
    ];
    return List.generate(
      a.length,
      (i) => (a[i] - b[i]).abs() < .001,
    ).every((v) => v);
  }
}
