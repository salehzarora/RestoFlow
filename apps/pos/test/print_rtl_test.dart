import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_document.dart' as app;

/// PRINT-RTL-001: the POS native receipt bridge renders Arabic/Hebrew (+ ₪/×)
/// receipts as an ESC/POS RASTER image so they print correctly; ASCII-only
/// content keeps the text path; no rasterizer => the ESC/POS text fallback.
/// Money formatting is untouched — the pre-formatted money string is only moved
/// into the bitmap, never recomputed.

class _RecordingTransport implements pp.PrintTransport {
  Uint8List? sent;
  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent = bytes;
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

bool _containsSeq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

app.PrintDocument _arabicReceipt() => app.PrintDocument(
  title: 'r',
  lines: [
    app.PrintLine.title('إيصال'),
    app.PrintLine.kv('رقم الطلب', '#3F7A2C'),
    app.PrintLine.kv('العميل', 'محمد عبد الله'),
    app.PrintLine.rule(),
    app.PrintLine.item('برجر كلاسيك', '2×'),
    app.PrintLine.kv('الإجمالي', '₪48.00', emphasised: true),
  ],
);

app.PrintDocument _englishAsciiReceipt() => app.PrintDocument(
  title: 'r',
  lines: [
    app.PrintLine.title('RestoFlow'),
    app.PrintLine.kv('Order', 'A1'),
    app.PrintLine.item('Burger', '2'),
  ],
);

void main() {
  test(
    'Arabic receipt over the native bridge -> ESC/POS RASTER bytes (GS v 0), '
    'delivered',
    () async {
      final transport = _RecordingTransport();
      final bridge = NativeTransportPrintBridge(
        transportFactory: () => transport,
        rasterizer: pp.FakeReceiptRasterizer(),
      );
      final result = await bridge.submit(_arabicReceipt());
      expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
      expect(_containsSeq(transport.sent!, [0x1D, 0x76, 0x30]), isTrue);
    },
  );

  test('the Arabic customer name + money string are rendered INTO the image '
      '(never emitted as ESC/POS text that would become "?????")', () async {
    final fake = pp.FakeReceiptRasterizer();
    await NativeTransportPrintBridge(
      transportFactory: () => _RecordingTransport(),
      rasterizer: fake,
    ).submit(_arabicReceipt());
    final rasterized = fake.requests.single.lines.join('\n');
    expect(rasterized.contains('محمد عبد الله'), isTrue);
    // Money is passed through as its already-formatted string (D-007/D-008).
    expect(rasterized.contains('₪48.00'), isTrue);
  });

  test(
    'PRINT-RASTER-STYLE-001: each line reaches the rasterizer tagged with its '
    'raster style (large heading, item, emphasised total, separator)',
    () async {
      final fake = pp.FakeReceiptRasterizer();
      await NativeTransportPrintBridge(
        transportFactory: () => _RecordingTransport(),
        rasterizer: fake,
      ).submit(_arabicReceipt());
      final req = fake.requests.single;
      pp.PrintLineStyle styleOf(String needle) =>
          req.styles[req.lines.indexWhere((l) => l.contains(needle))];
      expect(styleOf('إيصال'), pp.PrintLineStyle.headingLarge); // big heading
      expect(styleOf('برجر كلاسيك'), pp.PrintLineStyle.item); // item
      expect(styleOf('₪48.00'), pp.PrintLineStyle.total); // emphasised total
      expect(req.styles.contains(pp.PrintLineStyle.separator), isTrue); // rule
    },
  );

  test('no rasterizer -> ESC/POS TEXT fallback (no raster command)', () async {
    final transport = _RecordingTransport();
    await NativeTransportPrintBridge(
      transportFactory: () => transport,
    ).submit(_arabicReceipt());
    expect(_containsSeq(transport.sent!, [0x1D, 0x76, 0x30]), isFalse);
  });

  test(
    'a pure-ASCII English receipt stays TEXT even with a rasterizer',
    () async {
      final transport = _RecordingTransport();
      await NativeTransportPrintBridge(
        transportFactory: () => transport,
        rasterizer: pp.FakeReceiptRasterizer(),
      ).submit(_englishAsciiReceipt());
      expect(_containsSeq(transport.sent!, [0x1D, 0x76, 0x30]), isFalse);
    },
  );
}
