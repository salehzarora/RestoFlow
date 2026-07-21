import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/print/print_bridge.dart'
    show receiptToEscPosDocument;
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/receipt_print_preview.dart'
    show buildReceiptDocument;

/// PILOT-PRINT-FIDELITY-001 — the EXACT physical-print pre-TCP raster:
/// `buildReceiptDocument` → `receiptToEscPosDocument` → the REAL
/// `FlutterReceiptRasterizer`, over representative content matching the
/// photographed failure (Arabic names, ×-quantities, two-column amounts,
/// several modifiers, totals below). Asserts, per logical line, that the
/// generated monochrome bitmap carries ink inside that line's own rows —
/// the photographed defect (height-reserving blank body) fails these.
///
/// Also emits the diagnostic metrics the ticket requires (dimensions, body
/// band bounds, per-section black-pixel counts) and a PNG dump under the
/// gitignored build/ output for visual inspection. CI caveat: the test font
/// draws solid boxes, so a device-only font-fallback miss may not reproduce
/// here — hardware remains the final arbiter for glyph fidelity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppLocalizations> l10n(String locale) =>
      AppLocalizations.delegate.load(Locale(locale));

  CashPayment payment() => CashPayment(
    paymentId: 'pay-1',
    orderNumber: '#A1B2C3',
    deviceId: 'd1',
    localOperationId: 'op1',
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    amountMinor: 6800,
    tenderedMinor: 7000,
    changeMinor: 200,
    currencyCode: 'ILS',
    receiptNumber: 'R-9',
    paidAt: DateTime.utc(2026, 7, 19, 14, 30),
  );

  SubmittedOrderView arabicOrder() => SubmittedOrderView(
    orderNumber: '#A1B2C3',
    orderType: OrderType.dineIn,
    tableLabel: 'T3',
    customerName: 'محمد',
    currencyCode: 'ILS',
    subtotalMinor: 6800,
    lines: const [
      SubmittedLineView(
        name: 'كباب حلبي',
        quantity: 2,
        lineTotalMinor: 5000,
        currencyCode: 'ILS',
        modifiers: ['إضافة ثوم ×2', 'بدون بصل'],
        note: 'بدون فلفل',
      ),
      SubmittedLineView(
        name: 'حمص بالطحينة',
        quantity: 1,
        lineTotalMinor: 1800,
        currencyCode: 'ILS',
        modifiers: [],
      ),
    ],
  );

  Future<ReceiptRasterRender> renderPhysicalPath(
    AppLocalizations strings,
    SubmittedOrderView order,
  ) async {
    final document = buildReceiptDocument(
      strings,
      order,
      payment(),
      isDemo: false,
    );
    final escpos = receiptToEscPosDocument(document);
    final textLines = escpos.lines.whereType<pp.PrintTextLine>().toList();
    final lines = [for (final l in textLines) l.text];
    return const FlutterReceiptRasterizer().rasterizeDetailed(
      pp.ReceiptRasterRequest(
        lines: lines,
        styles: [for (final l in textLines) l.style],
        widthDots: pp.kNativeRasterWidthDots,
        direction: pp.baseDirectionForLines(lines),
        localeTag: escpos.localeTag ?? '',
      ),
    );
  }

  int inkIn(ReceiptRasterRender r, Iterable<ReceiptRasterBand> bands) =>
      bands.fold(0, (sum, b) => sum + r.inkInBand(b));

  test('DIAGNOSTIC + PIN: the Arabic physical-path raster carries ink in the '
      'header, EVERY item/modifier body line, and the totals', () async {
    final r = await renderPhysicalPath(await l10n('ar'), arabicOrder());
    final bands = r.bands;

    final headerBands = bands
        .where(
          (b) =>
              b.style == pp.PrintLineStyle.headingLarge ||
              b.style == pp.PrintLineStyle.centered,
        )
        .toList();
    final bodyBands = bands
        .where(
          (b) =>
              b.style == pp.PrintLineStyle.item ||
              b.style == pp.PrintLineStyle.sub,
        )
        .toList();
    final totalsBands = bands
        .where(
          (b) =>
              b.style == pp.PrintLineStyle.total ||
              b.style == pp.PrintLineStyle.normal,
        )
        .toList();

    // The body genuinely exists in the document: 2 items + 2 modifiers + 1
    // note.
    expect(
      bodyBands.where((b) => b.style == pp.PrintLineStyle.item),
      hasLength(2),
    );
    expect(
      bodyBands.where((b) => b.style == pp.PrintLineStyle.sub),
      hasLength(3),
    );
    expect(totalsBands, isNotEmpty);
    expect(headerBands, isNotEmpty);

    // REQUIRED DIAGNOSTIC OUTPUT (dimensions, body bounds, per-band ink).
    final bodyStart = bodyBands.first.startRow;
    final bodyEnd = bodyBands.last.endRow;
    final headerInk = inkIn(r, headerBands);
    final bodyInk = inkIn(r, bodyBands);
    final totalsInk = inkIn(r, totalsBands);
    // ignore: avoid_print
    print(
      'PILOT-PRINT-FIDELITY-001 raster: '
      'width=${r.image.widthBytes * 8}dots height=${r.image.heightDots}rows '
      'body=[$bodyStart..$bodyEnd) '
      'ink(header)=$headerInk ink(body)=$bodyInk ink(totals)=$totalsInk',
    );

    // THE PIN: the photographed defect (blank body band) must fail here.
    expect(headerInk, greaterThan(0));
    expect(totalsInk, greaterThan(0));
    for (final band in bodyBands) {
      expect(
        r.inkInBand(band),
        greaterThan(0),
        reason:
            'body line ${band.index} (${band.style.name}) '
            '"${band.text.trim()}" is BLANK in rows '
            '${band.startRow}..${band.endRow} — the photographed defect',
      );
    }

    // Diagnostic PNG under the gitignored build/ output (never committed).
    final png = await _to1BppPng(r.image);
    final file = File('build/test-output/pilot_print_fidelity_receipt_ar.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png);
    // ignore: avoid_print
    print('PILOT-PRINT-FIDELITY-001 raster PNG: ${file.absolute.path}');
  });

  test(
    'the English ×-quantity receipt (raster-forced) keeps body ink too',
    () async {
      final r = await renderPhysicalPath(
        await l10n('en'),
        SubmittedOrderView(
          orderNumber: '#B2C3D4',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 5000,
          lines: const [
            SubmittedLineView(
              name: 'Burger',
              quantity: 2,
              lineTotalMinor: 5000,
              currencyCode: 'ILS',
              modifiers: ['Extra cheese'],
            ),
          ],
        ),
      );
      for (final band in r.bands.where(
        (b) =>
            b.style == pp.PrintLineStyle.item ||
            b.style == pp.PrintLineStyle.sub,
      )) {
        expect(r.inkInBand(band), greaterThan(0));
      }
    },
  );
}

/// Expand the 1bpp raster to RGBA and encode a PNG via dart:ui (no deps).
Future<List<int>> _to1BppPng(pp.ReceiptRasterImage image) async {
  final width = image.widthBytes * 8;
  final rgba = List<int>.filled(width * image.heightDots * 4, 0xFF);
  for (var y = 0; y < image.heightDots; y++) {
    for (var x = 0; x < width; x++) {
      final black =
          (image.data[y * image.widthBytes + (x >> 3)] & (0x80 >> (x & 7))) !=
          0;
      if (black) {
        final i = (y * width + x) * 4;
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
      }
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(rgba),
    width,
    image.heightDots,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final uiImage = await completer.future;
  try {
    final bytes = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    uiImage.dispose();
  }
}
