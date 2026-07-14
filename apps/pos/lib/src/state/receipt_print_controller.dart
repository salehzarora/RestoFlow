import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitOutcome, BridgeSubmitResult, PrinterErrorCategory;

import '../print/print_document.dart';

/// The HONEST lifecycle of a prepared print job (RF-115).
///
///  * [prepared] — the payload exists and is previewable; it is NEVER presented
///    as printed. With NO print bridge configured a job STAYS here (the prior
///    honest behavior — unchanged for demo/tests).
///  * [sentToPrinter] — a LOCAL print bridge CONFIRMED it wrote the bytes to the
///    printer transport (RAW 9100 socket write). This is the strongest truthful
///    terminal state; ESC/POS over a socket has no paper acknowledgement, so it
///    is delivery-to-printer, NOT a hardware "printed" confirmation.
///  * [bridgeUnavailable] — a bridge was expected but could not be reached; the
///    job was prepared but not delivered.
///  * [failed] — building/sending the job failed (see [ReceiptPrintJob.failureCategory]);
///    the ORDER is unaffected.
///  * [notConfigured] — no enabled printer of the needed role is assigned.
///  * [printed] — a HARDWARE-confirmed print. It is UNREACHABLE by design: no
///    transport can confirm a physical print, so nothing ever sets it. Kept only
///    so a future hardware-ack transport could light it up without a UI change.
enum PrintJobStatus {
  notConfigured,
  prepared,
  sentToPrinter,
  bridgeUnavailable,
  printed,
  failed,
}

/// One prepared (or refused / dispatched) print job + its payload.
class ReceiptPrintJob {
  const ReceiptPrintJob({
    required this.status,
    this.document,
    this.failureCategory,
    this.failureMessage,
    this.at,
  });

  final PrintJobStatus status;
  final PrintDocument? document;

  /// The bridge failure category when [status] is [PrintJobStatus.failed].
  final PrinterErrorCategory? failureCategory;

  /// A developer-facing failure diagnostic (never UI chrome).
  final String? failureMessage;

  /// When the last bridge outcome was recorded (drives the "last job" row).
  final DateTime? at;

  ReceiptPrintJob copyWith({
    PrintJobStatus? status,
    PrinterErrorCategory? failureCategory,
    String? failureMessage,
    DateTime? at,
  }) => ReceiptPrintJob(
    status: status ?? this.status,
    document: document,
    failureCategory: failureCategory,
    failureMessage: failureMessage,
    at: at ?? this.at,
  );
}

/// Submits an already-built receipt [PrintDocument] to a LOCAL print bridge and
/// returns the honest outcome. Null (the default) => no bridge, the job stays
/// [PrintJobStatus.prepared].
typedef ReceiptBridgeSubmit =
    Future<BridgeSubmitResult> Function(PrintDocument document);

/// Holds the receipt print job per ORDER IDENTITY (RF-115).
///
/// POS-OPERATIONS-SYNC-001 (second review correction): these jobs were keyed by the
/// DISPLAY code. Because [prepare] is idempotent per key, a second order sharing a
/// `#XXXXXX` found a job already there and NEVER GOT ITS OWN RECEIPT — while the status
/// line on its confirmation screen showed the OTHER order's print result. A receipt is
/// a financial document; it belongs to exactly one order, identified by
/// [PosOrderIdentity.key] and never by the code printed on it.
///
/// [prepare] stays IDEMPOTENT per order (payment-state rebuilds + repeated
/// listens never double-prepare, and — with a bridge — never double-send).
/// Preparing builds the document; dispatching (when a bridge is wired) encodes
/// + submits it and flips the job to [PrintJobStatus.sentToPrinter] on a
/// confirmed transport write, or an honest failure otherwise. It NEVER claims a
/// hardware-confirmed print.
class ReceiptPrintController extends Notifier<Map<String, ReceiptPrintJob>> {
  @override
  Map<String, ReceiptPrintJob> build() => const {};

  /// Prepares the receipt job for [orderKey] once. No enabled printer =>
  /// an honest [PrintJobStatus.notConfigured] marker; a throwing builder =>
  /// [PrintJobStatus.failed] (the paid order itself is unaffected).
  void prepare({
    required String orderKey,
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
  }) {
    if (state.containsKey(orderKey)) return; // idempotent per order
    if (!hasEnabledPrinter) {
      state = {
        ...state,
        orderKey: const ReceiptPrintJob(status: PrintJobStatus.notConfigured),
      };
      return;
    }
    try {
      final document = buildDocument();
      state = {
        ...state,
        orderKey: ReceiptPrintJob(
          status: PrintJobStatus.prepared,
          document: document,
        ),
      };
    } catch (_) {
      state = {
        ...state,
        orderKey: const ReceiptPrintJob(status: PrintJobStatus.failed),
      };
    }
  }

  /// Prepares (idempotently) then — if newly prepared and a [submitToBridge] is
  /// wired — dispatches to the local bridge. With no bridge the job stays
  /// [PrintJobStatus.prepared]. Safe to call repeatedly (dispatches once).
  Future<void> prepareAndDispatch({
    required String orderKey,
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
    ReceiptBridgeSubmit? submitToBridge,
  }) async {
    final alreadyExisted = state.containsKey(orderKey);
    prepare(
      orderKey: orderKey,
      hasEnabledPrinter: hasEnabledPrinter,
      buildDocument: buildDocument,
    );
    if (alreadyExisted) return; // already dispatched once
    await _dispatch(orderKey, submitToBridge);
  }

  /// Re-runs a job (failed / bridge-unavailable / not-configured): clears the
  /// existing entry so [prepareAndDispatch] rebuilds and re-sends it.
  Future<void> retry({
    required String orderKey,
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
    ReceiptBridgeSubmit? submitToBridge,
  }) async {
    state = {...state}..remove(orderKey);
    await prepareAndDispatch(
      orderKey: orderKey,
      hasEnabledPrinter: hasEnabledPrinter,
      buildDocument: buildDocument,
      submitToBridge: submitToBridge,
    );
  }

  /// PRINT-STABILITY-001 / POS-ORDERS-AND-PAYMENT-001: reprints the receipt for
  /// [orderKey] — re-submits a receipt [PrintDocument] snapshot through the
  /// bridge WITHOUT rebuilding it from live data. It never creates a new order or
  /// payment and never recomputes money (the document is a snapshot). A no-op
  /// when there is no document (stored or supplied) or no bridge.
  ///
  /// Used by "Reprint last receipt" (stored, same-session) AND the recent-orders
  /// surface's per-order reprint — which supplies [document] (freshly built from
  /// the STORED order+payment) so an order settled in a PRIOR session, whose
  /// print job is no longer in memory, can still be reprinted.
  Future<void> reprint({
    required String orderKey,
    ReceiptBridgeSubmit? submitToBridge,
    PrintDocument? document,
  }) async {
    final doc = document ?? state[orderKey]?.document;
    if (doc == null || submitToBridge == null) return;
    // Reset to prepared with the (stored or supplied) document so _dispatch
    // re-sends it.
    state = {
      ...state,
      orderKey: ReceiptPrintJob(status: PrintJobStatus.prepared, document: doc),
    };
    await _dispatch(orderKey, submitToBridge);
  }

  Future<void> _dispatch(
    String orderKey,
    ReceiptBridgeSubmit? submitToBridge,
  ) async {
    if (submitToBridge == null) return; // no bridge -> stays prepared
    final job = state[orderKey];
    if (job == null ||
        job.status != PrintJobStatus.prepared ||
        job.document == null) {
      return;
    }
    final BridgeSubmitResult result;
    try {
      result = await submitToBridge(job.document!);
    } catch (_) {
      markBridgeUnavailable(orderKey);
      return;
    }
    switch (result.outcome) {
      case BridgeSubmitOutcome.sentToPrinter:
        markSentToPrinter(orderKey);
      case BridgeSubmitOutcome.accepted:
        // A demo/sink bridge RECEIVED it but did NOT reach hardware — stay
        // honestly [prepared]; only record that a job was submitted.
        _recordDispatch(orderKey);
      case BridgeSubmitOutcome.failed:
        if (result.category == PrinterErrorCategory.unreachable) {
          markBridgeUnavailable(orderKey);
        } else {
          markFailed(
            orderKey,
            category: result.category,
            message: result.message,
          );
        }
    }
  }

  /// Flips an existing job to [PrintJobStatus.sentToPrinter] (bridge confirmed
  /// the transport write — NOT a hardware print acknowledgement).
  void markSentToPrinter(String orderKey) {
    final job = state[orderKey];
    if (job == null) return;
    state = {
      ...state,
      orderKey: job.copyWith(
        status: PrintJobStatus.sentToPrinter,
        at: DateTime.now(),
      ),
    };
  }

  /// Flips an existing job to [PrintJobStatus.failed] with a [category]/[message].
  void markFailed(
    String orderKey, {
    PrinterErrorCategory? category,
    String? message,
  }) {
    final job = state[orderKey];
    if (job == null) return;
    state = {
      ...state,
      orderKey: job.copyWith(
        status: PrintJobStatus.failed,
        failureCategory: category,
        failureMessage: message,
        at: DateTime.now(),
      ),
    };
  }

  /// Flips an existing job to [PrintJobStatus.bridgeUnavailable].
  void markBridgeUnavailable(String orderKey) {
    final job = state[orderKey];
    if (job == null) return;
    state = {
      ...state,
      orderKey: job.copyWith(
        status: PrintJobStatus.bridgeUnavailable,
        at: DateTime.now(),
      ),
    };
  }

  void _recordDispatch(String orderKey) {
    final job = state[orderKey];
    if (job == null) return;
    state = {...state, orderKey: job.copyWith(at: DateTime.now())};
  }

  ReceiptPrintJob? jobFor(String orderKey) => state[orderKey];
}

final receiptPrintControllerProvider =
    NotifierProvider<ReceiptPrintController, Map<String, ReceiptPrintJob>>(
      ReceiptPrintController.new,
    );

/// PRINT-STABILITY-001: the IDENTITY KEY of the most-recent order that has a BUILT
/// receipt document (map insertion order — the last one wins), or null when none has
/// been prepared this session. Drives the "Reprint last receipt" action's
/// enabled/hidden state, and is handed straight back to [ReceiptPrintController.reprint]
/// — an opaque key, never shown to a cashier. In-memory only (a receipt is a transient
/// print artifact).
final lastReceiptOrderKeyProvider = Provider<String?>((ref) {
  final jobs = ref.watch(receiptPrintControllerProvider);
  String? last;
  for (final entry in jobs.entries) {
    if (entry.value.document != null) last = entry.key;
  }
  return last;
});
