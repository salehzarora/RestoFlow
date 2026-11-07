import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

import 'support/raster_commands.dart';

const _adapter = EscPosPrintAdapter();
const _printer = PrinterProfile.escPos80mm;
const _trailer = [0x1b, 0x64, 3, 0x1d, 0x56, 1];

ReceiptRasterImage _image(int widthBytes, int height) {
  final data = Uint8List.fromList([
    for (var i = 0; i < widthBytes * height; i++)
      ((i * 37) ^ (i >> 3) ^ (i >> 11)) & 0xff,
  ]);
  // A command signature inside pixels must never be mistaken for a header.
  if (data.length >= 12) data.setRange(8, 12, [0x1d, 0x76, 0x30, 0]);
  return ReceiptRasterImage(
    data: data,
    widthBytes: widthBytes,
    heightDots: height,
  );
}

class _Rasterizer implements ReceiptRasterizer {
  _Rasterizer(this.image);
  final ReceiptRasterImage image;
  final requests = <ReceiptRasterRequest>[];

  @override
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request) async {
    requests.add(request);
    return image;
  }
}

/// Model a broken rasterizer result without relying on constructor assertions.
class _MalformedImage implements ReceiptRasterImage {
  _MalformedImage(int length) : data = Uint8List(length);
  @override
  final Uint8List data;
  @override
  int get widthBytes => 3;
  @override
  int get heightDots => 257;
  @override
  PrintRasterImageLine toPrintLine() => throw UnimplementedError();
}

void main() {
  for (final length in [770, 772]) {
    test('malformed tall bitmap length $length fails before slicing', () async {
      await expectLater(
        rasterizeTextDocument(
          const PrintDocument([PrintTextLine('إيصال')]),
          rasterizer: _Rasterizer(_MalformedImage(length)),
          widthDots: 24,
        ),
        throwsArgumentError,
      );
    });
  }

  const expectedHeights = <int, List<int>>{
    1: [1],
    256: [256],
    257: [256, 1],
    512: [256, 256],
    513: [256, 256, 1],
  };
  for (final width in [3, 72, 257]) {
    for (final entry in expectedHeights.entries) {
      test(
        '${width}B rows, height ${entry.key}: exact pixels and framing',
        () async {
          final image = _image(width, entry.key);
          final rasterizer = _Rasterizer(image);
          final doc = await rasterizeTextDocument(
            const PrintDocument([PrintTextLine('إيصال קבלה')], localeTag: 'ar'),
            rasterizer: rasterizer,
            widthDots: width * 8,
          );
          expect(rasterizer.requests, hasLength(1));
          expect(rasterizer.requests.single.lines, ['إيصال קבלה', '']);
          final bands = doc.lines.whereType<PrintRasterImageLine>().toList();
          expect(bands.map((b) => b.heightDots), entry.value);
          expect(bands.every((b) => b.widthBytes == width), isTrue);
          expect(bands.expand((b) => b.data), orderedEquals(image.data));
          expect(bands.fold<int>(0, (n, b) => n + b.heightDots), entry.key);
          expect(doc.lines.length, bands.length + 2);
          expect(doc.lines[bands.length], isA<PrintFeedLine>());
          expect(doc.lines.last, isA<PrintCutLine>());

          final bytes = _adapter.encode(doc, _printer);
          expect(bytes.take(5), [0x1b, 0x40, 0x1b, 0x74, 0]);
          final commands = readRasterRun(bytes);
          expect(commands.map((c) => c.heightDots), entry.value);
          expect(commands.every((c) => c.widthBytes == width), isTrue);
          expect(commands.expand((c) => c.data), orderedEquals(image.data));
          expect(bytes.sublist(commands.last.end), _trailer);
          expect(bytes.length, 5 + 8 * bands.length + image.data.length + 6);

          if (entry.key <= 256) {
            expect(identical(bands.single.data, image.data), isTrue);
            final legacy = PrintDocument([
              image.toPrintLine(),
              const PrintFeedLine(3),
              const PrintCutLine(),
            ]);
            expect(bytes, _adapter.encode(legacy, _printer));
          }
        },
      );
    }
  }

  for (final text in ['طلب عربي', 'הזמנה בעברית']) {
    test(
      'long $text: content and bottom tail render once before banding',
      () async {
        final input = PrintDocument([
          for (var i = 0; i < 80; i++) PrintTextLine('$text $i'),
        ]);
        final image = _image(72, 2401);
        final rasterizer = _Rasterizer(image);
        final output = await rasterizeForMediaProfile(
          input,
          rasterizer: rasterizer,
          profile: MediaProfile.continuous80,
        );
        expect(rasterizer.requests, hasLength(1));
        expect(rasterizer.requests.single.lines, [
          ...input.lines.whereType<PrintTextLine>().map((l) => l.text),
          '',
        ]);
        final commands = readRasterRun(_adapter.encode(output, _printer));
        expect(commands, hasLength(10));
        expect(commands.last.heightDots, 97);
        expect(commands.expand((c) => c.data), orderedEquals(image.data));
      },
    );
  }

  test(
    'logo stays separate and once, before text bands and final trailer',
    () async {
      final logo = _image(72, 300).toPrintLine();
      final text = _image(72, 513);
      const logoFeed = PrintFeedLine(1);
      final output = await rasterizeTextDocument(
        PrintDocument([logo, logoFeed, const PrintTextLine('إيصال')]),
        rasterizer: _Rasterizer(text),
      );
      expect(identical(output.lines.first, logo), isTrue);
      expect(identical(output.lines[1], logoFeed), isTrue);
      final bytes = _adapter.encode(output, _printer);
      final logoCommand = readRasterCommand(bytes, 5);
      expect(logoCommand.heightDots, 300, reason: 'only text is banded');
      expect(logoCommand.data, logo.data);
      expect(bytes.sublist(logoCommand.end, logoCommand.end + 3), [
        0x1b,
        0x64,
        1,
      ]);
      final textCommands = readRasterRun(bytes, offset: logoCommand.end + 3);
      expect(textCommands.map((c) => c.heightDots), [256, 256, 1]);
      expect(textCommands.expand((c) => c.data), orderedEquals(text.data));
      expect(bytes.sublist(textCommands.last.end), _trailer);
    },
  );

  test(
    'ASCII-only roll retains the text document and identical bytes',
    () async {
      const input = PrintDocument([
        PrintTextLine('Synthetic receipt'),
        PrintFeedLine(3),
        PrintCutLine(),
      ]);
      final rasterizer = _Rasterizer(_image(72, 513));
      final output = await rasterizeForMediaProfile(
        input,
        rasterizer: rasterizer,
        profile: MediaProfile.continuous80,
      );
      expect(identical(output, input), isTrue);
      expect(rasterizer.requests, isEmpty);
      expect(
        _adapter.encode(output, _printer),
        _adapter.encode(input, _printer),
      );
    },
  );

  for (final profile in [MediaProfile.label50x50, MediaProfile.label80x80]) {
    test('${profile.id}: a 300-row fixed-label image stays unbanded', () async {
      final rasterizer = FakeReceiptRasterizer(dotsPerLine: 100);
      final output = await rasterizeForMediaProfile(
        const PrintDocument([PrintTextLine('طلب'), PrintTextLine('صنف')]),
        rasterizer: rasterizer,
        profile: profile,
      );
      expect(rasterizer.requests, hasLength(1));
      final image = await rasterizer.rasterize(rasterizer.requests.single);
      final expected = PrintDocument([
        image.toPrintLine(),
        PrintFeedLine(profile.feedLines),
        const PrintCutLine(),
      ]);
      final images = output.lines.whereType<PrintRasterImageLine>();
      expect(images, hasLength(1));
      expect(images.single.heightDots, 300);
      expect(
        _adapter.encode(output, _printer),
        _adapter.encode(expected, _printer),
      );
    });
  }
}
