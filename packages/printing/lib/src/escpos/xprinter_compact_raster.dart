import 'dart:math' as math;
import 'dart:typed_data';

import '../print_document.dart';
import 'escpos_command_builder.dart';

typedef CompactRasterEncoder = Uint8List Function(PrintRasterImageLine image);
typedef _Span = ({int row, int left, int right});
typedef _Crop = ({int left, int width, PrintAlignment align});

// ESC a justifies graphics within the configured 576-dot print area.
_Crop _crop(int first, int last, int pageWidth) {
  if (last < first) return (left: 0, width: 1, align: PrintAlignment.left);
  final leftWidth = last + 1;
  final rightWidth = pageWidth - first;
  final inset = math.min(first, pageWidth - leftWidth);
  final centerWidth = pageWidth - 2 * inset;
  if (centerWidth < leftWidth && centerWidth < rightWidth) {
    return (left: inset, width: centerWidth, align: PrintAlignment.center);
  }
  if (rightWidth < leftWidth) {
    return (left: first, width: rightWidth, align: PrintAlignment.right);
  }
  return (left: 0, width: leftWidth, align: PrintAlignment.left);
}

// Both encoders send the same black dots at the same paper coordinates. A
// one-byte-wide white GS v 0 band still advances the exact number of rows.
List<_Span> _scan(PrintRasterImageLine image, {required bool splitBlankRuns}) {
  final width = image.widthBytes;
  final spans = <_Span>[];
  var start = 0;
  var left = width;
  var right = -1;
  var previousFirst = width;
  var previousLast = -1;
  for (var row = 0; row < image.heightDots; row++) {
    final offset = row * width;
    var first = 0;
    while (first < width && image.data[offset + first] == 0) {
      first++;
    }
    var last = first == width ? -1 : width - 1;
    while (last > first && image.data[offset + last] == 0) {
      last--;
    }
    final blankTransition = (last < 0) != (previousLast < 0);
    final widthChange = first != previousFirst || last != previousLast;
    final boundary = splitBlankRuns
        ? blankTransition || row % 16 == 0 || (row % 8 == 0 && widthChange)
        : row % 8 == 0;
    if (row > start && boundary) {
      spans.add((row: start, left: left, right: right));
      start = row;
      left = width;
      right = -1;
    }
    left = math.min(left, first);
    right = math.max(right, last);
    previousFirst = first;
    previousLast = last;
  }
  spans.add((row: start, left: left, right: right));
  return spans;
}

Uint8List _encodeBands(
  PrintRasterImageLine image,
  List<_Span> spans, {
  required int commandPenalty,
  required int maxRows,
  required bool allowSingleFullRaster,
}) {
  final width = image.widthBytes;
  final height = image.heightDots;
  final count = spans.length;
  final cost = List.filled(count + 1, 0);
  final next = List.filled(count, 0);
  final crops = List<_Crop?>.filled(count, null);
  int rowAt(int index) => index == count ? height : spans[index].row;

  // A raster command costs time at the print head as well as bytes on the
  // wire. The bounded lookahead keeps planning linear in receipt length.
  for (var start = count - 1; start >= 0; start--) {
    var left = width;
    var right = -1;
    for (var end = start + 1; end <= count; end++) {
      final rows = rowAt(end) - spans[start].row;
      if (rows > maxRows) break;
      final span = spans[end - 1];
      left = math.min(left, span.left);
      right = math.max(right, span.right);
      final crop = _crop(left, right, width);
      final score = rows * crop.width + 8 + 3 + commandPenalty + cost[end];
      if (next[start] == 0 || score <= cost[start]) {
        cost[start] = score;
        next[start] = end;
        crops[start] = crop;
      }
    }
  }
  final commands = EscPosCommandBuilder();
  if (allowSingleFullRaster &&
      height <= 0xffff &&
      cost.first + 3 >= image.data.length + 8 + commandPenalty) {
    return (commands..rasterImage(
          data: image.data,
          widthBytes: width,
          heightDots: height,
        ))
        .bytes();
  }
  var alignment = PrintAlignment.left;
  for (var start = 0; start < count; start = next[start]) {
    final crop = crops[start]!;
    if (alignment != crop.align) {
      commands.align(crop.align);
      alignment = crop.align;
    }
    final y = spans[start].row;
    final rows = rowAt(next[start]) - y;
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
  if (alignment != PrintAlignment.left) commands.align(PrintAlignment.left);
  return commands.bytes();
}

/// Fixed eight-row tiles keep the field-tested KDS and Kiosk band layout.
Uint8List encodeXprinterCompactRaster(PrintRasterImageLine image) =>
    _encodeBands(
      image,
      _scan(image, splitBlankRuns: false),
      commandPenalty: 1024,
      maxRows: 512,
      allowSingleFullRaster: true,
    );

/// For POS, split at the actual boundaries of blank runs. Prefer the original
/// encoding on ties and whenever splitting would produce a larger packet.
Uint8List encodeXprinterSparseRaster(PrintRasterImageLine image) {
  final sparse = _encodeBands(
    image,
    _scan(image, splitBlankRuns: true),
    commandPenalty: 512,
    maxRows: 1024,
    allowSingleFullRaster: false,
  );
  final compact = encodeXprinterCompactRaster(image);
  return sparse.length < compact.length ? sparse : compact;
}
