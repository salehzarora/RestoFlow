import '../print_document.dart';

/// Builds a minimal ESC/POS "Test print" [PrintDocument] for a printer-setup
/// diagnostic (ANDROID-002).
///
/// Deliberately ASCII/English-only: the ESC/POS text layer maps every non-ASCII
/// code unit to '?', and localized (Arabic/Hebrew, RTL) receipts go through the
/// raster path (RF-073, OPEN QUESTION Q-015), which this diagnostic does not
/// exercise. It is MONEY-FREE — a test print carries no totals. [printerName]
/// and [deviceLabel] are optional context lines (any non-ASCII in them prints
/// as '?', never a crash).
PrintDocument escPosNetworkTestDocument({
  String? printerName,
  String? deviceLabel,
}) {
  final name = printerName?.trim() ?? '';
  final label = deviceLabel?.trim() ?? '';
  return PrintDocument([
    const PrintTextLine(
      'RestoFlow',
      alignment: PrintAlignment.center,
      emphasis: TextEmphasis.bold,
    ),
    const PrintTextLine('Printer test', alignment: PrintAlignment.center),
    const PrintTextLine('------------------------------'),
    if (name.isNotEmpty) PrintTextLine('Printer: $name'),
    if (label.isNotEmpty) PrintTextLine('Device: $label'),
    const PrintTextLine('Transport: network (TCP)'),
    const PrintTextLine('If you can read this line,'),
    const PrintTextLine('network printing works.'),
    const PrintFeedLine(3),
    const PrintCutLine(),
  ]);
}
