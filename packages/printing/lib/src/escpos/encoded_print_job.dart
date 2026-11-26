import 'dart:typed_data';

import '../media_profile.dart';
import '../print_adapter.dart';
import '../print_document.dart';
import '../printer_profile.dart';
import '../receipt/receipt_rasterizer.dart';
import '../receipt/rtl_raster.dart';
import 'escpos_command_builder.dart';
import 'escpos_print_adapter.dart';
import 'xprinter_compact_raster.dart';

/// A prepared packet. Use the faster Bluetooth write only if the compact
/// renderer actually produced it, including after a pre-dispatch fallback.
typedef EncodedPrintJob = ({Uint8List bytes, bool wholeJob});

/// Prepares the same app-font roll bitmap as the field-tested POS renderer.
/// A null result leaves the caller free to use its original encoder and pacing.
Future<Uint8List?> tryEncodeCompactRoll(
  PrintDocument document, {
  required MediaProfile mediaProfile,
  required PrinterProfile profile,
  required ReceiptRasterizer? rasterizer,
  PrintAdapter adapter = const EscPosPrintAdapter(),
}) async {
  if (rasterizer == null ||
      mediaProfile.id != MediaProfileId.continuous80 ||
      mediaProfile.widthDots != MediaProfile.continuous80.widthDots ||
      mediaProfile.paginates ||
      profile.paperWidth != PaperWidth.mm80 ||
      !profile.capabilities.supportsRaster ||
      !document.lines.any((line) => line is PrintTextLine)) {
    return null;
  }

  // No transport has been constructed or dispatched yet. Preserve the old
  // encoding even if the renderer, logo or custom adapter cannot prepare this
  // packet. Never attempt a different encoding after a physical send.
  try {
    final rendered = await rasterizeTextDocument(
      document,
      rasterizer: rasterizer,
      widthDots: mediaProfile.widthDots,
    );
    final preamble = leadingPreambleLines(document);
    final body = rendered.lines[preamble.length] as PrintRasterImageLine;
    if (body.widthBytes != mediaProfile.widthBytes) return null;
    final tail = EscPosCommandBuilder()..feed(mediaProfile.feedLines);
    if (profile.capabilities.supportsCut) {
      tail
        ..init()
        ..feed(2)
        ..cut();
    }
    return (BytesBuilder(copy: false)
          ..add(adapter.encode(PrintDocument(preamble), profile))
          ..add(encodeXprinterCompactRaster(body))
          ..add(tail.bytes()))
        .takeBytes();
  } catch (_) {
    return null;
  }
}

/// Prepares a native document while preserving fixed-media rendering,
/// pagination and the existing printer-text fallback.
Future<EncodedPrintJob> encodePrintJob(
  PrintDocument document, {
  required bool compact,
  required MediaProfile mediaProfile,
  required ReceiptRasterizer? rasterizer,
  PrinterProfile profile = PrinterProfile.escPos80mm,
  PrintAdapter adapter = const EscPosPrintAdapter(),
  PageLineLabel? pageLabel,
  PageLineLabel? continuationHeader,
}) async {
  if (compact) {
    final bytes = await tryEncodeCompactRoll(
      document,
      mediaProfile: mediaProfile,
      profile: profile,
      rasterizer: rasterizer,
      adapter: adapter,
    );
    if (bytes != null) return (bytes: bytes, wholeJob: true);
  }
  PrintDocument rendered;
  try {
    rendered = await rasterizeForMediaProfile(
      document,
      rasterizer: rasterizer,
      profile: mediaProfile,
      pageLabel: pageLabel,
      continuationHeader: continuationHeader,
    );
  } catch (_) {
    rendered = document;
  }
  return (bytes: adapter.encode(rendered, profile), wholeJob: false);
}
