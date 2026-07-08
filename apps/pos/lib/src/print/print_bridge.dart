import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrintBridgeConnectivity, PrinterBridgeStatus;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/receipt_print_controller.dart';
import 'print_document.dart' as app;

/// RF-115: the POS receipt print-bridge glue.
///
/// The POS builds an HTML-oriented [app.PrintDocument] for preview; to reach a
/// real printer through a LOCAL bridge it is converted to the render-neutral
/// ESC/POS [pp.PrintDocument], encoded, and submitted. Money values are ALREADY
/// formatted by the receipt builder — nothing here computes or derives money
/// (DECISION D-007/D-008).

/// Converts the app receipt document into a render-neutral ESC/POS document.
/// [columns] matches the printer profile (48 for 80mm). Already-formatted text
/// (incl. money) passes through verbatim.
pp.PrintDocument receiptToEscPosDocument(
  app.PrintDocument doc, {
  int columns = 48,
}) {
  final lines = <pp.PrintLine>[];
  for (final line in doc.lines) {
    // PRINT-RASTER-STYLE-001: tag each ESC/POS line with its semantic style so
    // the raster renderer can size/center/emphasise it. The ESC/POS text +
    // loopback paths ignore `style` (they use alignment + emphasis as before).
    switch (line.kind) {
      case app.PrintLineKind.title:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            emphasis: pp.TextEmphasis.bold,
            style: pp.PrintLineStyle.headingLarge,
          ),
        );
      case app.PrintLineKind.center:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            style: pp.PrintLineStyle.centered,
          ),
        );
      case app.PrintLineKind.keyValue:
        lines.add(
          pp.PrintTextLine(
            _twoColumn(line.left, line.right, columns),
            emphasis: line.emphasised
                ? pp.TextEmphasis.bold
                : pp.TextEmphasis.normal,
            // An emphasised money row is the receipt TOTAL.
            style: line.emphasised
                ? pp.PrintLineStyle.total
                : pp.PrintLineStyle.normal,
          ),
        );
      case app.PrintLineKind.item:
        lines.add(
          pp.PrintTextLine(
            _twoColumn(line.left, line.right, columns),
            emphasis: line.emphasised
                ? pp.TextEmphasis.bold
                : pp.TextEmphasis.normal,
            style: pp.PrintLineStyle.item,
          ),
        );
      case app.PrintLineKind.sub:
        lines.add(
          pp.PrintTextLine(
            '  ${line.left ?? ''}',
            style: pp.PrintLineStyle.sub,
          ),
        );
      case app.PrintLineKind.note:
        lines.add(
          pp.PrintTextLine(
            line.left ?? '',
            alignment: pp.PrintAlignment.center,
            style: pp.PrintLineStyle.note,
          ),
        );
      case app.PrintLineKind.rule:
        lines.add(
          pp.PrintTextLine('-' * columns, style: pp.PrintLineStyle.separator),
        );
    }
  }
  lines.add(const pp.PrintFeedLine(3));
  lines.add(const pp.PrintCutLine());
  return pp.PrintDocument(lines);
}

/// Lays out a label/value pair across [columns] monospace columns; falls back to
/// a single space when the two do not fit (best-effort — Arabic/Hebrew glyphs
/// raster via RF-073, not here).
String _twoColumn(String? left, String? right, int columns) {
  final l = left ?? '';
  final r = right ?? '';
  final pad = columns - l.length - r.length;
  return pad < 1 ? '$l $r' : '$l${' ' * pad}$r';
}

/// The POS receipt print-bridge seam. Null by default (dormant) so demo mode and
/// existing tests are unaffected.
abstract class PosPrintBridge {
  /// Encodes + submits a receipt document to the bridge, returning the honest
  /// outcome (accepted / sentToPrinter / failed).
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document);

  /// Probes the bridge's reachability for the device-settings status row.
  Future<pp.BridgeHealth> health();
}

/// The default ESC/POS-over-bridge implementation.
class EscPosReceiptBridge implements PosPrintBridge {
  const EscPosReceiptBridge({required this.dispatcher, this.columns = 48});

  final pp.PrintBridgeDispatcher dispatcher;
  final int columns;

  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) =>
      dispatcher.dispatch(receiptToEscPosDocument(document, columns: columns));

  @override
  Future<pp.BridgeHealth> health() => dispatcher.health();
}

/// The configured POS print bridge, or null (the DEFAULT — no physical print
/// path; jobs stay `prepared`). `main.dart` overrides it when a loopback bridge
/// URL is provided; tests inject a fake.
final posPrintBridgeProvider = Provider<PosPrintBridge?>((ref) => null);

/// The device-settings print-bridge status (health + last submitted job), or
/// null when no bridge is configured (the row is then hidden).
final posPrintBridgeStatusProvider = FutureProvider<PrinterBridgeStatus?>((
  ref,
) async {
  final bridge = ref.watch(posPrintBridgeProvider);
  if (bridge == null) return null;
  final health = await bridge.health();
  final jobs = ref.watch(receiptPrintControllerProvider);
  return PrinterBridgeStatus(
    connectivity: health == pp.BridgeHealth.connected
        ? PrintBridgeConnectivity.connected
        : PrintBridgeConnectivity.unavailable,
    lastJobAt: _latestJobAt(jobs),
  );
});

DateTime? _latestJobAt(Map<String, ReceiptPrintJob> jobs) {
  DateTime? latest;
  for (final job in jobs.values) {
    final at = job.at;
    if (at == null) continue;
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}
