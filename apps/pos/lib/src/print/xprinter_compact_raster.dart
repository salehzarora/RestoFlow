import 'dart:math' as math;
import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart' as pp;

typedef _Crop = ({int left, int width, pp.PrintAlignment align});

// ESC a justifies graphics within the configured print area. The caller selects
// this path only for a 576-dot printer with a matching input bitmap.
_Crop _crop(int first, int last, int pageWidth) {
  if (last < first) return (left: 0, width: 1, align: pp.PrintAlignment.left);
  final leftWidth = last + 1;
  final rightWidth = pageWidth - first;
  final inset = math.min(first, pageWidth - leftWidth);
  final centerWidth = pageWidth - 2 * inset;
  if (centerWidth < leftWidth && centerWidth < rightWidth) {
    return (left: inset, width: centerWidth, align: pp.PrintAlignment.center);
  }
  if (rightWidth < leftWidth) {
    return (left: first, width: rightWidth, align: pp.PrintAlignment.right);
  }
  return (left: 0, width: leftWidth, align: pp.PrintAlignment.left);
}

/// Sends the same black dots at the same paper coordinates as a full raster.
/// GS v 0 advances by its exact height, even for an all-white narrow strip.
/// The complete packet is prepared in memory for the existing whole-job send.
Uint8List encodeXprinterCompactRaster(pp.PrintRasterImageLine image) {
  final width = image.widthBytes;
  final height = image.heightDots;
  const rowsPerTile = 8;
  final tiles = (height + rowsPerTile - 1) ~/ rowsPerTile;
  final first = List.filled(tiles, width);
  final last = List.filled(tiles, -1);
  for (var y = 0; y < height; y++) {
    final tile = y ~/ rowsPerTile;
    final row = y * width;
    for (var x = 0; x < width; x++) {
      if (image.data[row + x] == 0) continue;
      first[tile] = math.min(first[tile], x);
      last[tile] = math.max(last[tile], x);
    }
  }

  // Each raster command can introduce work at the print head. Charge it a
  // planning penalty so tiny byte savings do not fragment the job. On the
  // 40-item reference this kept 17 bands versus 82 with a 256-byte penalty.
  // Look ahead at most 512 rows to keep planning linear in receipt length.
  const commandPenalty = 1024;
  const maxTilesPerBand = 64;
  final cost = List.filled(tiles + 1, 0);
  final next = List.filled(tiles, 0);
  final crops = List<_Crop?>.filled(tiles, null);
  for (var start = tiles - 1; start >= 0; start--) {
    var left = width;
    var right = -1;
    final limit = math.min(tiles, start + maxTilesPerBand);
    for (var end = start + 1; end <= limit; end++) {
      left = math.min(left, first[end - 1]);
      right = math.max(right, last[end - 1]);
      final crop = _crop(left, right, width);
      final rows = math.min(height, end * rowsPerTile) - start * rowsPerTile;
      final score = rows * crop.width + 8 + 3 + commandPenalty + cost[end];
      if (next[start] == 0 || score <= cost[start]) {
        cost[start] = score;
        next[start] = end;
        crops[start] = crop;
      }
    }
  }

  final commands = pp.EscPosCommandBuilder();
  if (height <= 0xffff &&
      cost.first + 3 >= image.data.length + 8 + commandPenalty) {
    return (commands..rasterImage(
          data: image.data,
          widthBytes: width,
          heightDots: height,
        ))
        .bytes();
  }
  var alignment = pp.PrintAlignment.left;
  for (var start = 0; start < tiles; start = next[start]) {
    final crop = crops[start]!;
    if (alignment != crop.align) {
      commands.align(crop.align);
      alignment = crop.align;
    }
    final y = start * rowsPerTile;
    final rows = math.min(height, next[start] * rowsPerTile) - y;
    final pixels = Uint8List(rows * crop.width);
    for (var row = 0; row < rows; row++) {
      final source = (y + row) * width + crop.left;
      pixels.setRange(
        row * crop.width,
        (row + 1) * crop.width,
        image.data,
        source,
      );
    }
    commands.rasterImage(
      data: pixels,
      widthBytes: crop.width,
      heightDots: rows,
    );
  }
  if (alignment != pp.PrintAlignment.left)
    commands.align(pp.PrintAlignment.left);
  return commands.bytes();
}
