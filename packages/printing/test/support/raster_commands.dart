import 'package:test/test.dart';

/// Decode by declared body length: bitmap bytes may resemble ESC/POS commands.
typedef RasterCommand = ({
  int widthBytes,
  int heightDots,
  List<int> data,
  int end,
});

RasterCommand readRasterCommand(List<int> bytes, int offset) {
  expect(bytes.length, greaterThanOrEqualTo(offset + 8));
  expect(bytes.sublist(offset, offset + 4), [0x1d, 0x76, 0x30, 0]);
  final width = bytes[offset + 4] | (bytes[offset + 5] << 8);
  final height = bytes[offset + 6] | (bytes[offset + 7] << 8);
  expect(width, greaterThan(0));
  expect(height, greaterThan(0));
  final end = offset + 8 + width * height;
  expect(bytes.length, greaterThanOrEqualTo(end));
  return (
    widthBytes: width,
    heightDots: height,
    data: bytes.sublist(offset + 8, end),
    end: end,
  );
}

List<RasterCommand> readRasterRun(List<int> bytes, {int offset = 5}) {
  final commands = <RasterCommand>[];
  while (offset + 4 <= bytes.length &&
      bytes[offset] == 0x1d &&
      bytes[offset + 1] == 0x76 &&
      bytes[offset + 2] == 0x30 &&
      bytes[offset + 3] == 0) {
    final command = readRasterCommand(bytes, offset);
    commands.add(command);
    offset = command.end;
  }
  return commands;
}
