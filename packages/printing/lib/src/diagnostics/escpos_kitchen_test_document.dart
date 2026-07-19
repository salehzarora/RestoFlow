import '../print_document.dart';

/// Builds the harmless KITCHEN-TICKET test [PrintDocument]
/// (KITCHEN-MODE-001B).
///
/// STRUCTURALLY MONEY-FREE: this builder's inputs are display strings only —
/// there is no price, subtotal, total, paid amount, change, currency, payment
/// method, or any financial key anywhere in its signature or output. It is a
/// kitchen-ticket-SHAPED sample (quantity/item/modifier/note lines), NOT a
/// customer receipt with hidden totals. Every content line is clearly framed
/// by the TEST banner so a printed page can never be mistaken for a real
/// ticket, and no order or customer record is read or created.
///
/// Localization: callers pass ALREADY-LOCALIZED strings (Arabic/Hebrew/
/// English). Rendering rides the SHARED document pipeline — when the caller
/// runs the document through `maybeRasterizeForRtl` (the PRINT-RTL-001 shared
/// raster path, as the POS/KDS bridges do), Arabic/Hebrew lines print as a
/// bitmap; without a rasterizer the ESC/POS text layer prints ASCII and maps
/// other characters to '?' (the same documented behavior as the customer
/// printer diagnostic — never a crash).
PrintDocument escPosKitchenTestDocument({
  required String testBanner,
  required String title,
  required List<String> sampleLines,
  String? printerName,
  String? deviceLabel,
}) {
  final name = printerName?.trim() ?? '';
  final label = deviceLabel?.trim() ?? '';
  return PrintDocument([
    PrintTextLine(
      testBanner,
      alignment: PrintAlignment.center,
      emphasis: TextEmphasis.bold,
    ),
    PrintTextLine(title, alignment: PrintAlignment.center),
    const PrintTextLine('------------------------------'),
    for (final line in sampleLines) PrintTextLine(line),
    const PrintTextLine('------------------------------'),
    if (name.isNotEmpty) PrintTextLine(name),
    if (label.isNotEmpty) PrintTextLine(label),
    PrintTextLine(
      testBanner,
      alignment: PrintAlignment.center,
      emphasis: TextEmphasis.bold,
    ),
    const PrintFeedLine(3),
    const PrintCutLine(),
  ]);
}
