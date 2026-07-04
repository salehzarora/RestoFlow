import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitOutcome, BridgeSubmitResult, PrinterErrorCategory;

import '../print/print_document.dart';
import 'kds_auto_print_prefs.dart';
import 'kds_printer_assignments.dart';

/// The HONEST lifecycle of a prepared kitchen print job (RF-115).
///
///  * [prepared] — the payload exists; NEVER presented as printed. With NO
///    print bridge configured a job STAYS here (the prior honest behavior).
///  * [sentToPrinter] — a LOCAL print bridge CONFIRMED it wrote the bytes to the
///    printer transport. Delivery-to-printer, NOT a hardware print (ESC/POS over
///    a socket has no paper acknowledgement).
///  * [bridgeUnavailable] — a bridge was expected but could not be reached.
///  * [failed] — building/sending failed; the ticket is unaffected.
///  * [notConfigured] — no enabled kitchen printer assigned.
///  * [printed] — a HARDWARE-confirmed print. UNREACHABLE by design (nothing can
///    confirm a physical print); kept only for a future hardware-ack transport.
///
/// Money-free by construction (the ticket views carry no money — T-003).
enum KdsPrintJobStatus {
  notConfigured,
  prepared,
  sentToPrinter,
  bridgeUnavailable,
  printed,
  failed,
}

class KdsPrintJob {
  const KdsPrintJob({
    required this.status,
    this.document,
    this.failureCategory,
    this.failureMessage,
    this.at,
  });

  final KdsPrintJobStatus status;
  final PrintDocument? document;

  /// The bridge failure category when [status] is [KdsPrintJobStatus.failed].
  final PrinterErrorCategory? failureCategory;

  /// A developer-facing failure diagnostic (never UI chrome).
  final String? failureMessage;

  /// When the last bridge outcome was recorded (drives the "last job" row).
  final DateTime? at;

  KdsPrintJob copyWith({
    KdsPrintJobStatus? status,
    PrinterErrorCategory? failureCategory,
    String? failureMessage,
    DateTime? at,
  }) => KdsPrintJob(
    status: status ?? this.status,
    document: document,
    failureCategory: failureCategory,
    failureMessage: failureMessage,
    at: at ?? this.at,
  );
}

/// Submits an already-built kitchen [PrintDocument] to a LOCAL print bridge and
/// returns the honest outcome. Null (the default) => no bridge, the job stays
/// [KdsPrintJobStatus.prepared].
typedef KdsBridgeSubmit =
    Future<BridgeSubmitResult> Function(PrintDocument document);

/// Holds the kitchen-ticket print job per ORDER (RF-115).
///
/// Keyed by the ticket's order id (kitchen-ticket id for demo fixtures), so
/// [prepareForTicket] is IDEMPOTENT across poll refreshes and repeated
/// acknowledge taps: the board rebuilds its `KdsTicketView`s on every pull, but
/// a key that was already prepared never re-prepares (no double print/send).
class KdsKitchenPrintController extends Notifier<Map<String, KdsPrintJob>> {
  @override
  Map<String, KdsPrintJob> build() => const {};

  /// The idempotency key for [ticket].
  static String keyFor(KdsTicketView ticket) =>
      ticket.orderId ?? ticket.kitchenTicketId;

  /// Prepares the kitchen job for [ticket] once. No enabled kitchen printer
  /// => an honest [KdsPrintJobStatus.notConfigured] marker; a throwing builder
  /// => [KdsPrintJobStatus.failed] (the ticket is unaffected).
  void prepareForTicket(
    KdsTicketView ticket, {
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
  }) {
    final key = keyFor(ticket);
    if (state.containsKey(key)) return; // idempotent per order
    if (!hasEnabledPrinter) {
      state = {
        ...state,
        key: const KdsPrintJob(status: KdsPrintJobStatus.notConfigured),
      };
      return;
    }
    try {
      final document = buildDocument();
      state = {
        ...state,
        key: KdsPrintJob(
          status: KdsPrintJobStatus.prepared,
          document: document,
        ),
      };
    } catch (_) {
      state = {
        ...state,
        key: const KdsPrintJob(status: KdsPrintJobStatus.failed),
      };
    }
  }

  /// The acknowledge-trigger POLICY (RF-115): prepare — and, if a bridge is
  /// wired, dispatch — a kitchen print job for a just-ACKNOWLEDGED [ticket],
  /// honoring the per-device toggle and the branch's kitchen-printer assignment.
  ///
  ///  * Toggle explicitly OFF => nothing at all.
  ///  * Demo / unconfigured / failed assignment read => nothing (never a fake
  ///    job when we cannot know the printer state).
  ///  * Enabled kitchen printer => a PREPARED job; then, when [submitToBridge]
  ///    is wired, an encode+submit that flips it to [sentToPrinter] on a
  ///    confirmed transport write (never a fabricated hardware print).
  ///  * No enabled printer => an honest notConfigured marker.
  ///
  /// Idempotent per order id (a re-tap or the next poll never double-prepares
  /// or double-sends). The caller passes [buildDocument] (the widget owns l10n);
  /// the payload is money-free (T-003).
  Future<void> prepareOnAcknowledge(
    KdsTicketView ticket, {
    required PrintDocument Function() buildDocument,
    KdsBridgeSubmit? submitToBridge,
  }) async {
    final stored = ref.read(kdsAutoPrintAcknowledgeProvider).valueOrNull;
    if (stored == false) return; // the staff turned it off
    final assignments = switch (ref
        .read(kdsPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    if (assignments == null) return; // demo / unconfigured / failed read
    final key = keyFor(ticket);
    final alreadyExisted = state.containsKey(key);
    prepareForTicket(
      ticket,
      hasEnabledPrinter: assignments.hasEnabledPrinter,
      buildDocument: buildDocument,
    );
    if (alreadyExisted) return; // already dispatched once
    await _dispatch(key, submitToBridge);
  }

  /// Re-runs a job (failed / bridge-unavailable / not-configured) for [ticket]:
  /// clears the existing entry, re-prepares with the given printer availability,
  /// and re-dispatches. Called from the ticket's explicit Retry action, so it
  /// does NOT re-check the auto-print toggle.
  Future<void> retry(
    KdsTicketView ticket, {
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
    KdsBridgeSubmit? submitToBridge,
  }) async {
    final key = keyFor(ticket);
    state = {...state}..remove(key);
    prepareForTicket(
      ticket,
      hasEnabledPrinter: hasEnabledPrinter,
      buildDocument: buildDocument,
    );
    await _dispatch(key, submitToBridge);
  }

  Future<void> _dispatch(String key, KdsBridgeSubmit? submitToBridge) async {
    if (submitToBridge == null) return; // no bridge -> stays prepared
    final job = state[key];
    if (job == null ||
        job.status != KdsPrintJobStatus.prepared ||
        job.document == null) {
      return;
    }
    final BridgeSubmitResult result;
    try {
      result = await submitToBridge(job.document!);
    } catch (_) {
      markBridgeUnavailable(key);
      return;
    }
    switch (result.outcome) {
      case BridgeSubmitOutcome.sentToPrinter:
        markSentToPrinter(key);
      case BridgeSubmitOutcome.accepted:
        // A demo/sink bridge RECEIVED it but did NOT reach hardware — stay
        // honestly [prepared]; only record that a job was submitted.
        _recordDispatch(key);
      case BridgeSubmitOutcome.failed:
        if (result.category == PrinterErrorCategory.unreachable) {
          markBridgeUnavailable(key);
        } else {
          markFailed(key, category: result.category, message: result.message);
        }
    }
  }

  /// Flips an existing job to [KdsPrintJobStatus.sentToPrinter] (bridge confirmed
  /// the transport write — NOT a hardware print acknowledgement).
  void markSentToPrinter(String key) {
    final job = state[key];
    if (job == null) return;
    state = {
      ...state,
      key: job.copyWith(
        status: KdsPrintJobStatus.sentToPrinter,
        at: DateTime.now(),
      ),
    };
  }

  /// Flips an existing job to [KdsPrintJobStatus.failed] with a [category]/[message].
  void markFailed(
    String key, {
    PrinterErrorCategory? category,
    String? message,
  }) {
    final job = state[key];
    if (job == null) return;
    state = {
      ...state,
      key: job.copyWith(
        status: KdsPrintJobStatus.failed,
        failureCategory: category,
        failureMessage: message,
        at: DateTime.now(),
      ),
    };
  }

  /// Flips an existing job to [KdsPrintJobStatus.bridgeUnavailable].
  void markBridgeUnavailable(String key) {
    final job = state[key];
    if (job == null) return;
    state = {
      ...state,
      key: job.copyWith(
        status: KdsPrintJobStatus.bridgeUnavailable,
        at: DateTime.now(),
      ),
    };
  }

  void _recordDispatch(String key) {
    final job = state[key];
    if (job == null) return;
    state = {...state, key: job.copyWith(at: DateTime.now())};
  }

  KdsPrintJob? jobFor(KdsTicketView ticket) => state[keyFor(ticket)];
}

final kdsKitchenPrintControllerProvider =
    NotifierProvider<KdsKitchenPrintController, Map<String, KdsPrintJob>>(
      KdsKitchenPrintController.new,
    );
