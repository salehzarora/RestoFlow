import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show receiptToEscPosDocument;
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildBillDocument, buildReceiptDocument;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

typedef _Page = ({Uint8List pixels, int rows, List<int> bandAlignments});

int _word(Uint8List bytes, int at) => bytes[at] + (bytes[at + 1] << 8);

// A separate decoder interpreting ESC a and GS v 0 on a fixed-width paper.
// Justification is in dots, including a four-dot offset on odd center crops.
_Page _readPrintedArea(Uint8List packet, int pageBytes) {
  var align = 0;
  final pixels = BytesBuilder(copy: false);
  final bandAlignments = <int>[];
  var rows = 0;
  for (var pos = 0; pos < packet.length;) {
    if (packet[pos] == 0x1b) {
      expect(packet[pos + 1], 0x61, reason: 'Unexpected command at $pos');
      align = packet[pos + 2];
      expect(align, inInclusiveRange(0, 2));
      pos += 3;
      continue;
    }
    expect(packet.sublist(pos, pos + 4), [0x1d, 0x76, 0x30, 0]);
    final width = _word(packet, pos + 4);
    final height = _word(packet, pos + 6);
    expect(width, inInclusiveRange(1, pageBytes));
    expect(height, isPositive);
    pos += 8;
    final startDot = [
      0,
      (pageBytes - width) * 4,
      (pageBytes - width) * 8,
    ][align];
    final band = Uint8List(pageBytes * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width * 8; x++) {
        if ((packet[pos + y * width + (x ~/ 8)] & (0x80 >> (x % 8))) != 0) {
          final dest = startDot + x;
          band[y * pageBytes + (dest ~/ 8)] |= 0x80 >> (dest % 8);
        }
      }
    }
    pixels.add(band);
    bandAlignments.add(align);
    pos += width * height;
    rows += height;
  }
  expect(align, 0, reason: 'Restore left alignment after the image');
  return (
    pixels: pixels.takeBytes(),
    rows: rows,
    bandAlignments: bandAlignments,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'blank, dense, asymmetric and narrow rasters retain every dot and row',
    () {
      for (final width in [1, 3, 17, 72]) {
        for (final height in [1, 17, 131]) {
          for (var pattern = 0; pattern < 4; pattern++) {
            final data = Uint8List(width * height);
            for (var y = 0; y < height; y++) {
              for (var x = 0; x < width; x++) {
                data[y * width + x] = switch (pattern) {
                  0 => 0,
                  1 => 0xff,
                  2 => (x == width - 1 && y % 3 != 0) ? 0x41 : 0,
                  _ => ((y * 23 + x * 29) % 256),
                };
              }
            }
            final image = pp.PrintRasterImageLine(
              data: data,
              widthBytes: width,
              heightDots: height,
            );
            for (final encode in [
              pp.encodeXprinterCompactRaster,
              pp.encodeXprinterSparseRaster,
            ]) {
              final packet = encode(image);
              final page = _readPrintedArea(packet, width);
              expect(page.rows, height);
              expect(listEquals(page.pixels, data), isTrue);
              expect(packet.length, lessThanOrEqualTo(8 + width * height));
            }
          }
        }
      }
    },
  );

  test(
    'off-centre ink, blank gaps and changing alignments retain their positions',
    () {
      const width = 72;
      const height = 261;
      final data = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        final group = y ~/ 52;
        if (group == 1) continue;
        final x = switch (group) {
          0 => 0,
          2 => 35,
          3 => 70,
          _ => 2,
        };
        data[y * width + x] = (y % 2 == 0) ? 0x81 : 0x1b;
        data[y * width + x + 1] = (y % 3 == 0) ? 0x76 : 0x8f;
      }
      final packet = pp.encodeXprinterCompactRaster(
        pp.PrintRasterImageLine(
          data: data,
          widthBytes: width,
          heightDots: height,
        ),
      );
      final page = _readPrintedArea(packet, width);
      expect(page.rows, height);
      expect(listEquals(page.pixels, data), isTrue);
      expect(page.bandAlignments, containsAll([0, 1, 2]));
      expect(packet.length, lessThan(data.length));
    },
  );

  for (final entry in {
    'ar': 'ساندويتش',
    'he': 'כריך',
    'en': 'Sandwich',
  }.entries) {
    test(
      '40-item ${entry.key} customer bill and paid receipt preserve all printed dots and feed past the footer',
      () async {
        final l10n = await AppLocalizations.delegate.load(Locale(entry.key));
        final order = SubmittedOrderView(
          orderNumber: '#ABC',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 40000,
          lines: [
            for (var i = 0; i < 40; i++)
              SubmittedLineView(
                name: '${entry.value} ${i + 1}',
                quantity: 1,
                lineTotalMinor: 1000,
                currencyCode: 'ILS',
              ),
          ],
        );
        final payment = CashPayment(
          paymentId: 'p',
          orderNumber: '#ABC',
          deviceId: 'd',
          localOperationId: 'op',
          method: PaymentMethod.cash,
          status: PaymentStatus.completed,
          amountMinor: 40000,
          tenderedMinor: 40000,
          changeMinor: 0,
          currencyCode: 'ILS',
          receiptNumber: 'R1',
          paidAt: DateTime.utc(2026, 7, 7),
        );
        final logo = ReceiptLogoAsset(
          sourceBytes: Uint8List(0),
          sourceMime: 'image/png',
          raster: pp.LogoRaster(
            widthDots: 576,
            widthBytes: 72,
            heightDots: 3,
            data: Uint8List(72 * 3)..[36] = 0xa5,
          ),
        );
        const renderer = FlutterReceiptRasterizer();
        const media = pp.MediaProfile.continuous80;
        const profile = pp.PrinterProfile.escPos80mm;
        for (final doc in [
          buildBillDocument(l10n, order),
          buildReceiptDocument(l10n, order, payment, branding: logo),
        ]) {
          final source = receiptToEscPosDocument(doc, columns: media.columns);
          final preamble = pp.leadingPreambleLines(source);
          final prefix = const pp.EscPosPrintAdapter().encode(
            pp.PrintDocument(preamble),
            profile,
          );
          final expected = await pp.rasterizeTextDocument(
            source,
            rasterizer: renderer,
            widthDots: media.widthDots,
          );
          final full =
              expected.lines[preamble.length] as pp.PrintRasterImageLine;
          final output = pp.InMemoryPrintTransport();
          final result = await NativeTransportPrintBridge(
            transportFactory: () => output,
            compactReceipt: true,
            rasterizer: renderer,
          ).submit(doc);
          expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
          final job = output.batches.single;
          expect(job.take(prefix.length), orderedEquals(prefix));
          const tail = [
            0x1b,
            0x64,
            3,
            0x1b,
            0x40,
            0x1b,
            0x64,
            2,
            0x1d,
            0x56,
            1,
          ];
          expect(job.sublist(job.length - tail.length), tail);
          final packet = Uint8List.sublistView(
            job,
            prefix.length,
            job.length - tail.length,
          );
          final decoded = _readPrintedArea(packet, media.widthBytes);
          expect(packet, orderedEquals(pp.encodeXprinterSparseRaster(full)));
          expect(
            packet.length,
            lessThan(pp.encodeXprinterCompactRaster(full).length),
          );
          expect(decoded.rows, full.heightDots);
          expect(listEquals(decoded.pixels, full.data), isTrue);
          expect(decoded.bandAlignments.length, greaterThan(1));
          expect(packet.length, lessThan(full.data.length));
        }
      },
    );
  }
}
