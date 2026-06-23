import 'dart:typed_data';

import '../print_adapter.dart';
import '../print_document.dart';
import '../printer_profile.dart';
import 'escpos_command_builder.dart';

/// The first [PrintAdapter] implementation: ESC/POS (RF-070, DECISION D-009).
///
/// Deterministic byte rendering of a [PrintDocument] for a [PrinterProfile]:
/// `init` → select code page → one command sequence per line → trailing cut if
/// requested. Profile capabilities are respected — an unsupported cut / drawer
/// kick / raster line is OMITTED (not emitted), bounding ESC/POS variation
/// (RISK R-001). Each text line sets its own alignment + emphasis explicitly so
/// output never depends on prior state.
class EscPosPrintAdapter implements PrintAdapter {
  const EscPosPrintAdapter();

  @override
  Uint8List encode(PrintDocument document, PrinterProfile profile) {
    final b = EscPosCommandBuilder()
      ..init()
      ..selectCodePage(profile.codePage);

    for (final line in document.lines) {
      switch (line) {
        case PrintTextLine():
          b
            ..align(line.alignment)
            ..bold(line.emphasis == TextEmphasis.bold)
            ..text(line.text)
            ..lineFeed();
        case PrintFeedLine():
          if (line.lines > 0) b.feed(line.lines);
        case PrintCutLine():
          if (profile.capabilities.supportsCut) b.cut();
        case PrintDrawerKickLine():
          if (profile.capabilities.supportsDrawerKick) b.drawerKick();
        case PrintRasterImageLine():
          if (profile.capabilities.supportsRaster) {
            b.rasterImage(
              data: line.data,
              widthBytes: line.widthBytes,
              heightDots: line.heightDots,
            );
          }
      }
    }
    return b.bytes();
  }
}
