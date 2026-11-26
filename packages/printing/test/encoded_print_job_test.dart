import 'dart:typed_data';

import 'package:restoflow_printing/restoflow_printing.dart';
import 'package:test/test.dart';

class _IncorrectWidth implements ReceiptRasterizer {
  @override
  Future<ReceiptRasterImage> rasterize(ReceiptRasterRequest request) async =>
      ReceiptRasterImage(data: Uint8List(1), widthBytes: 1, heightDots: 1);
}

void main() {
  const adapter = EscPosPrintAdapter();
  const doc = PrintDocument([PrintTextLine('Ticket')]);
  const roll = MediaProfile.continuous80;
  const profile = PrinterProfile.escPos80mm;

  test(
    'whole-job transport requires an eligible 576-dot rendered body',
    () async {
      final rasterizer = FakeReceiptRasterizer();
      final fast = await encodePrintJob(
        doc,
        compact: true,
        mediaProfile: roll,
        rasterizer: rasterizer,
      );
      expect(fast.wholeJob, isTrue);
      expect(rasterizer.requests.single.lines.first, 'Ticket');
      for (final job in [
        await encodePrintJob(
          doc,
          compact: false,
          mediaProfile: roll,
          rasterizer: rasterizer,
        ),
        await encodePrintJob(
          doc,
          compact: true,
          mediaProfile: roll,
          rasterizer: null,
        ),
        await encodePrintJob(
          doc,
          compact: true,
          mediaProfile: roll,
          rasterizer: _IncorrectWidth(),
        ),
        await encodePrintJob(
          doc,
          compact: true,
          mediaProfile: roll,
          rasterizer: rasterizer,
          profile: PrinterProfile.escPos58mm,
        ),
        await encodePrintJob(
          doc,
          compact: true,
          mediaProfile: roll,
          rasterizer: rasterizer,
          profile: profile.copyWith(
            capabilities: const PrinterCapabilities(supportsRaster: false),
          ),
        ),
      ]) {
        expect(job.wholeJob, isFalse);
        expect(job.bytes, adapter.encode(doc, profile));
      }
    },
  );

  test(
    'fixed-media and control-only jobs retain original bytes and pacing',
    () async {
      final rasterizer = FakeReceiptRasterizer();
      for (final label in [MediaProfile.label50x50, MediaProfile.label80x80]) {
        final actual = await encodePrintJob(
          doc,
          compact: true,
          mediaProfile: label,
          rasterizer: rasterizer,
        );
        final canonical = await rasterizeForMediaProfile(
          doc,
          rasterizer: rasterizer,
          profile: label,
        );
        expect(actual.wholeJob, isFalse);
        expect(actual.bytes, adapter.encode(canonical, profile));
      }
      const kick = PrintDocument([PrintDrawerKickLine()]);
      final actual = await encodePrintJob(
        kick,
        compact: true,
        mediaProfile: roll,
        rasterizer: rasterizer,
      );
      expect(actual.wholeJob, isFalse);
      expect(actual.bytes, adapter.encode(kick, profile));
    },
  );
}
