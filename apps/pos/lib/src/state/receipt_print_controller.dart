import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../print/print_document.dart';

/// The HONEST lifecycle of a prepared print job (device settings sprint,
/// Part D). This build has NO physical print transport (a print bridge /
/// native app is required), so:
///
///  * [prepared] means exactly that — the payload exists and is previewable;
///    it is NEVER presented as printed.
///  * [printed] is reachable ONLY when a real transport confirms success —
///    i.e. never in this build. It exists so the bridge can light it up
///    later without a UI contract change.
///  * [failed] = building/sending the job failed; the ORDER is unaffected.
///  * [notConfigured] = no enabled printer of the needed role is assigned.
enum PrintJobStatus { notConfigured, prepared, printed, failed }

/// One prepared (or refused) print job + its payload.
class ReceiptPrintJob {
  const ReceiptPrintJob({required this.status, this.document});

  final PrintJobStatus status;
  final PrintDocument? document;
}

/// Holds the receipt print job per ORDER NUMBER (device settings sprint).
///
/// [prepare] is IDEMPOTENT per order — payment-state rebuilds and repeated
/// listens can never double-prepare (and later, with a bridge, never
/// double-print). Nothing here talks to a printer: preparing builds the
/// document via the existing receipt builder and records the honest status.
class ReceiptPrintController extends Notifier<Map<String, ReceiptPrintJob>> {
  @override
  Map<String, ReceiptPrintJob> build() => const {};

  /// Prepares the receipt job for [orderNumber] once. No enabled printer =>
  /// an honest [PrintJobStatus.notConfigured] marker; a throwing builder =>
  /// [PrintJobStatus.failed] (the paid order itself is unaffected).
  void prepare({
    required String orderNumber,
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
  }) {
    if (state.containsKey(orderNumber)) return; // idempotent per order
    if (!hasEnabledPrinter) {
      state = {
        ...state,
        orderNumber: const ReceiptPrintJob(
          status: PrintJobStatus.notConfigured,
        ),
      };
      return;
    }
    try {
      final document = buildDocument();
      state = {
        ...state,
        orderNumber: ReceiptPrintJob(
          status: PrintJobStatus.prepared,
          document: document,
        ),
      };
    } catch (_) {
      state = {
        ...state,
        orderNumber: const ReceiptPrintJob(status: PrintJobStatus.failed),
      };
    }
  }

  ReceiptPrintJob? jobFor(String orderNumber) => state[orderNumber];
}

final receiptPrintControllerProvider =
    NotifierProvider<ReceiptPrintController, Map<String, ReceiptPrintJob>>(
      ReceiptPrintController.new,
    );
