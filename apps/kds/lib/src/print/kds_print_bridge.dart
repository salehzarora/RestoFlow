import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrintBridgeConnectivity, PrinterBridgeStatus;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/kds_kitchen_print_controller.dart';
import 'print_document.dart' as app;

/// RF-115: the KDS kitchen-ticket print-bridge glue.
///
/// The KDS builds an HTML-oriented [app.PrintDocument] for preview; to reach a
/// real printer through a LOCAL bridge it is converted to the render-neutral
/// ESC/POS [pp.PrintDocument], encoded, and submitted. The kitchen payload is
/// MONEY-FREE by construction (T-003) — this glue only carries text through and
/// never invents any money.

/// Converts the app kitchen-ticket document into a render-neutral ESC/POS
/// document. [columns] matches the printer profile (48 for 80mm).
pp.PrintDocument kitchenTicketToEscPosDocument(
  app.PrintDocument doc, {
  int columns = 48,
}) {
  final lines = <pp.PrintLine>[];
  for (final line in doc.lines) {
    // PRINT-RASTER-STYLE-001: tag each ESC/POS line with its raster style. The
    // ESC/POS text + loopback paths ignore it. MONEY-FREE: there is NO `total`
    // style on the kitchen ticket (a money row never exists here — T-003).
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
            style: pp.PrintLineStyle.normal,
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

String _twoColumn(String? left, String? right, int columns) {
  final l = left ?? '';
  final r = right ?? '';
  final pad = columns - l.length - r.length;
  return pad < 1 ? '$l $r' : '$l${' ' * pad}$r';
}

/// The KDS kitchen print-bridge seam. Null by default (dormant) so demo mode and
/// existing tests are unaffected.
abstract class KdsPrintBridge {
  /// Encodes + submits a kitchen-ticket document, returning the honest outcome.
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document);

  /// Probes the bridge's reachability for the device-settings status row.
  Future<pp.BridgeHealth> health();
}

/// The default ESC/POS-over-bridge implementation.
class EscPosKitchenBridge implements KdsPrintBridge {
  const EscPosKitchenBridge({required this.dispatcher, this.columns = 48});

  final pp.PrintBridgeDispatcher dispatcher;
  final int columns;

  @override
  Future<pp.BridgeSubmitResult> submit(app.PrintDocument document) => dispatcher
      .dispatch(kitchenTicketToEscPosDocument(document, columns: columns));

  @override
  Future<pp.BridgeHealth> health() => dispatcher.health();
}

/// The configured KDS print bridge, or null (the DEFAULT — no physical print
/// path; jobs stay `prepared`). `main.dart` overrides it when a loopback bridge
/// URL is provided; tests inject a fake.
final kdsPrintBridgeProvider = Provider<KdsPrintBridge?>((ref) => null);

/// The device-settings print-bridge status (health + last submitted job), or
/// null when no bridge is configured (the row is then hidden).
final kdsPrintBridgeStatusProvider = FutureProvider<PrinterBridgeStatus?>((
  ref,
) async {
  final bridge = ref.watch(kdsPrintBridgeProvider);
  if (bridge == null) return null;
  final health = await bridge.health();
  final jobs = ref.watch(kdsKitchenPrintControllerProvider);
  return PrinterBridgeStatus(
    connectivity: health == pp.BridgeHealth.connected
        ? PrintBridgeConnectivity.connected
        : PrintBridgeConnectivity.unavailable,
    lastJobAt: _latestJobAt(jobs),
  );
});

DateTime? _latestJobAt(Map<String, KdsPrintJob> jobs) {
  DateTime? latest;
  for (final job in jobs.values) {
    final at = job.at;
    if (at == null) continue;
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}
