import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

import 'support/raster_commands.dart';

/// Preserve every generated row while bounding continuous-roll commands.
void main() {
  Future<(List<int>, ReceiptRasterImage)> encodeRasterDoc({
    int lines = 40,
  }) async {
    final rasterizer = FakeReceiptRasterizer();
    final doc = await rasterizeTextDocument(
      PrintDocument([
        for (var i = 0; i < lines; i++) PrintTextLine('سطر إيصال رقم $i'),
      ]),
      rasterizer: rasterizer,
    );
    final image = await FakeReceiptRasterizer().rasterize(
      rasterizer.requests.single,
    );
    return (
      const EscPosPrintAdapter().encode(doc, PrinterProfile.escPos80mm),
      image,
    );
  }

  test('each continuous-roll band has an independent raster command', () async {
    final (bytes, _) = await encodeRasterDoc();
    expect(readRasterRun(bytes).map((c) => c.heightDots), [256, 256, 256, 216]);
  });

  test(
    'headers preserve 576-dot width and the complete total height',
    () async {
      final (bytes, image) = await encodeRasterDoc();
      final commands = readRasterRun(bytes);
      expect(commands.every((c) => c.widthBytes == image.widthBytes), isTrue);
      expect(commands.every((c) => c.widthBytes == 72), isTrue);
      expect(commands.every((c) => c.heightDots <= 256), isTrue);
      expect(
        commands.fold<int>(0, (n, c) => n + c.heightDots),
        image.heightDots,
      );
    },
  );

  test(
    'concatenated command bodies contain every generated row in order',
    () async {
      final (bytes, image) = await encodeRasterDoc();
      final commands = readRasterRun(bytes);
      expect(commands.expand((c) => c.data), orderedEquals(image.data));
      for (final command in commands) {
        expect(command.data.length, command.widthBytes * command.heightDots);
      }
    },
  );

  test(
    'only adjacent raster commands precede one final feed and cut',
    () async {
      final (bytes, image) = await encodeRasterDoc();
      expect(bytes.take(5), [0x1b, 0x40, 0x1b, 0x74, 0]);
      final commands = readRasterRun(bytes);
      expect(bytes.sublist(commands.last.end), [0x1b, 0x64, 3, 0x1d, 0x56, 1]);
      expect(bytes.length, 5 + 8 * commands.length + image.data.length + 6);
    },
  );

  test(
    'a 200-line receipt retains all pixels across bounded commands',
    () async {
      final (bytes, image) = await encodeRasterDoc(lines: 200);
      final commands = readRasterRun(bytes);
      expect(commands, hasLength((image.heightDots + 255) ~/ 256));
      expect(commands.every((c) => c.heightDots <= 256), isTrue);
      expect(commands.expand((c) => c.data), orderedEquals(image.data));
      expect(bytes.sublist(commands.last.end), [0x1b, 0x64, 3, 0x1d, 0x56, 1]);
    },
  );
}
