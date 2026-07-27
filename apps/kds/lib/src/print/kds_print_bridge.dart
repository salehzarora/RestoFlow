import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show PrintBridgeConnectivity, PrinterBridgeStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show kitchenTicketToEscPosDocument;
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../state/kds_kitchen_print_controller.dart';
import 'print_document.dart' as app;

/// RF-115: the KDS kitchen-ticket print-bridge glue.
///
/// The KDS builds an HTML-oriented [app.PrintDocument] for preview; to reach a
/// real printer through a LOCAL bridge it is converted to the render-neutral
/// ESC/POS [pp.PrintDocument], encoded, and submitted. KITCHEN-PRINT-DUAL-001B
/// moved the converter into `restoflow_feature_kitchen` so the POS direct
/// kitchen print uses the SAME layout; it is re-exported here so existing KDS
/// imports (`kds_native_printer`, tests) keep resolving it unchanged. The
/// kitchen payload is MONEY-FREE by construction (T-003) — this glue only
/// carries text through and never invents any money.

// KITCHEN-PRINT-DUAL-001B: `kitchenTicketToEscPosDocument` now lives in the
// shared kitchen-print library; re-export it from its historical home so
// callers that import it from this file are unaffected.
export 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show kitchenTicketToEscPosDocument;

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
