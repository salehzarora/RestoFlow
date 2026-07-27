import 'dart:typed_data';

/// PRINT-LAYOUT-001 — the non-white content bounding box of a 1-bit-per-pixel,
/// MSB-first, row-major raster (the [PrintRasterImageLine] layout). Pure Dart, so
/// tests can assert every generated page keeps its ink inside the profile's safe
/// margins (contentLeft >= safeLeft, contentRight <= width - safeRight, etc.)
/// without a real printer.
class RasterInkBounds {
  const RasterInkBounds({
    required this.hasInk,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// True when at least one black dot was found.
  final bool hasInk;

  /// Leftmost inked column (inclusive); -1 when [hasInk] is false.
  final int left;

  /// Rightmost inked column (inclusive); -1 when [hasInk] is false.
  final int right;

  /// Topmost inked row (inclusive); -1 when [hasInk] is false.
  final int top;

  /// Bottommost inked row (inclusive); -1 when [hasInk] is false.
  final int bottom;

  /// The empty bounds (no ink).
  static const RasterInkBounds empty = RasterInkBounds(
    hasInk: false,
    left: -1,
    right: -1,
    top: -1,
    bottom: -1,
  );
}

/// Scans a 1bpp raster ([data] row-major, MSB-first, [widthBytes] bytes/row,
/// [heightDots] rows; bit 1 == black) for its inked bounding box.
RasterInkBounds measureRasterInkBounds({
  required Uint8List data,
  required int widthBytes,
  required int heightDots,
}) {
  var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
  for (var y = 0; y < heightDots; y++) {
    final rowBase = y * widthBytes;
    for (var b = 0; b < widthBytes; b++) {
      final byte = data[rowBase + b];
      if (byte == 0) continue;
      // At least one inked bit in this byte — resolve the exact columns.
      for (var bit = 0; bit < 8; bit++) {
        if ((byte & (0x80 >> bit)) != 0) {
          final x = b * 8 + bit;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return RasterInkBounds.empty;
  return RasterInkBounds(
    hasInk: true,
    left: minX,
    right: maxX,
    top: minY,
    bottom: maxY,
  );
}
