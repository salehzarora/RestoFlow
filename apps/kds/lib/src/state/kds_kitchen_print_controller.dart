import 'dart:math' show max, min;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show KitchenTicketStatus;
import 'package:restoflow_feature_kitchen/kitchen_print.dart'
    show OrderChangeSlipView;
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_printing/restoflow_printing.dart'
    show BridgeSubmitOutcome, BridgeSubmitResult, PrinterErrorCategory;

import '../print/kds_change_chit.dart';
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

/// ORDER-EDIT-001D: the edit watermarks of a work unit's papers on the
/// kitchen rail — the NEWEST and the OLDEST [KdsPrintJob.printedThroughEdit]
/// among them (0 for a paper printed with no unconfirmed change).
typedef KdsPaperWatermarks = ({int newestThrough, int oldestThrough});

class KdsPrintJob {
  const KdsPrintJob({
    required this.status,
    this.document,
    this.failureCategory,
    this.failureMessage,
    this.at,
    this.printedThroughEdit,
    this.earlierPapers,
  });

  final KdsPrintJobStatus status;
  final PrintDocument? document;

  /// The bridge failure category when [status] is [KdsPrintJobStatus.failed].
  final PrinterErrorCategory? failureCategory;

  /// A developer-facing failure diagnostic (never UI chrome).
  final String? failureMessage;

  /// When the last bridge outcome was recorded (drives the "last job" row).
  final DateTime? at;

  /// ORDER-EDIT-001D: the newest unconfirmed sent-order edit this job's paper
  /// already shows (the printed ticket's `change.upToEditNumber`), or null.
  /// A later change chit never repeats lines of edits at or below it.
  final int? printedThroughEdit;

  /// ORDER-EDIT-001D: the watermarks of the EARLIER papers of this work unit
  /// that a Retry / Reprint replaced in the job map but that are still on the
  /// kitchen rail; null when no earlier job reached the print path. A later
  /// change chit keeps their REMOVED and Was/Now news (see
  /// [KdsKitchenPrintController.printFactsFor]).
  final KdsPaperWatermarks? earlierPapers;

  KdsPrintJob copyWith({
    KdsPrintJobStatus? status,
    PrinterErrorCategory? failureCategory,
    String? failureMessage,
    DateTime? at,
    KdsPaperWatermarks? earlierPapers,
  }) => KdsPrintJob(
    status: status ?? this.status,
    document: document,
    failureCategory: failureCategory,
    failureMessage: failureMessage,
    at: at ?? this.at,
    printedThroughEdit: printedThroughEdit,
    earlierPapers: earlierPapers ?? this.earlierPapers,
  );
}

/// Submits an already-built kitchen [PrintDocument] to a LOCAL print bridge and
/// returns the honest outcome. Null (the default) => no bridge, the job stays
/// [KdsPrintJobStatus.prepared].
typedef KdsBridgeSubmit =
    Future<BridgeSubmitResult> Function(PrintDocument document);

/// Holds the kitchen-ticket print job per KITCHEN WORK UNIT (RF-115).
///
/// Keyed by [keyFor] — order + station + round (kitchen-ticket id for demo
/// fixtures) — so [prepareForTicket] is IDEMPOTENT across poll refreshes and
/// repeated acknowledge taps: the board rebuilds its `KdsTicketView`s on every
/// pull, but a key that was already prepared never re-prepares (no double
/// print/send). DEFERRED-ORDER-AMENDMENTS-001: one ORDER can own several work
/// units — the initial ticket plus a ticket per service round, and one per
/// station — and each has to print on its own.
class KdsKitchenPrintController extends Notifier<Map<String, KdsPrintJob>> {
  @override
  Map<String, KdsPrintJob> build() {
    _chitThrough.clear();
    return const {};
  }

  /// ORDER-EDIT-001D: per WORK UNIT ([keyFor]), the newest edit number a
  /// change chit printed by THIS device already covered — so a second "Got
  /// it" before the pull clears the first change never repeats its lines.
  /// In memory only: after a restart the stage proxy may print a line twice,
  /// never omit one.
  final Map<String, int> _chitThrough = {};

  /// The idempotency key for [ticket] — its WORK UNIT, not its order.
  ///
  /// DEFERRED-ORDER-AMENDMENTS-001: this used to be the bare `orderId`, which
  /// collapsed distinct work units onto one key. A PSC-001C round ticket carries
  /// the PARENT order's id (correctly — the round belongs to that order), so once
  /// the initial ticket had printed, every later ADDITION was reported as already
  /// handled and the kitchen silently never received the added food. The same
  /// collapse hid every station after the first on a station-routed board.
  ///
  /// The key is therefore the full composite: order + station + round. Built from
  /// the parts rather than reusing `kitchenTicketId` (which the mapper happens to
  /// compose the same way today) so it stays correct for a hand-built or
  /// POS-built view whose ticket id is just an order code. A ticket with NO order
  /// id (demo fixtures) keeps the `kitchenTicketId` fallback.
  static String keyFor(KdsTicketView ticket) {
    final orderId = ticket.orderId;
    if (orderId == null) return ticket.kitchenTicketId;
    final roundId = ticket.roundId;
    final base = '$orderId|station:${ticket.stationId}';
    return roundId == null ? base : '$base|round:$roundId';
  }

  /// Prepares the kitchen job for [ticket] once. No enabled kitchen printer
  /// => an honest [KdsPrintJobStatus.notConfigured] marker; a throwing builder
  /// => [KdsPrintJobStatus.failed] (the ticket is unaffected).
  void prepareForTicket(
    KdsTicketView ticket, {
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
  }) {
    final key = keyFor(ticket);
    if (state.containsKey(key)) return; // idempotent per WORK UNIT
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
          // ORDER-EDIT-001D: the paper carries the live lines of the
          // unconfirmed edits the ticket shows, so a later chit skips them.
          printedThroughEdit: ticket.change?.upToEditNumber,
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
  /// Idempotent per WORK UNIT (a re-tap or the next poll never double-prepares
  /// or double-sends). The caller passes [buildDocument] (the widget owns l10n);
  /// the payload is money-free (T-003).
  Future<void> prepareOnAcknowledge(
    KdsTicketView ticket, {
    required PrintDocument Function() buildDocument,
    KdsBridgeSubmit? submitToBridge,
    bool nativePrinterConfigured = false,
  }) async {
    final stored = ref.read(kdsAutoPrintAcknowledgeProvider).valueOrNull;
    if (stored == false) return; // the staff turned it off
    final assignments = switch (ref
        .read(kdsPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    // ANDROID-004: a device-LOCAL native printer (Wi-Fi/Bluetooth configured on
    // THIS display) IS this device's enabled printer, so it prints regardless of
    // the server kitchen-printer assignment. Without one the prior policy holds:
    // a demo / unconfigured / failed assignment read => nothing (never a fake job).
    if (assignments == null && !nativePrinterConfigured) return;
    final key = keyFor(ticket);
    final alreadyExisted = state.containsKey(key);
    prepareForTicket(
      ticket,
      hasEnabledPrinter:
          (assignments?.hasEnabledPrinter ?? false) || nativePrinterConfigured,
      buildDocument: buildDocument,
    );
    if (alreadyExisted) return; // already dispatched once
    await _dispatch(key, submitToBridge);
  }

  /// Re-runs a job (failed / bridge-unavailable / not-configured) for [ticket]:
  /// clears the existing entry, re-prepares with the given printer availability,
  /// and re-dispatches. Called from the ticket's explicit Retry action, so it
  /// does NOT re-check the auto-print toggle.
  ///
  /// ORDER-EDIT-001D: the replaced job's paper (and any paper before it)
  /// stays on the kitchen rail, so its watermarks move to the new job's
  /// [KdsPrintJob.earlierPapers] — a Reprint of a changed card must not hide
  /// the REMOVED and Was/Now lines that earlier paper still needs.
  Future<void> retry(
    KdsTicketView ticket, {
    required bool hasEnabledPrinter,
    required PrintDocument Function() buildDocument,
    KdsBridgeSubmit? submitToBridge,
  }) async {
    final key = keyFor(ticket);
    final earlierPapers = _papersOnRail(state[key]);
    state = {...state}..remove(key);
    prepareForTicket(
      ticket,
      hasEnabledPrinter: hasEnabledPrinter,
      buildDocument: buildDocument,
    );
    final job = state[key];
    if (earlierPapers != null && job != null) {
      state = {...state, key: job.copyWith(earlierPapers: earlierPapers)};
    }
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

  /// ORDER-EDIT-001D: the change chit's idempotency key — one chit per (order,
  /// "Got it" number). It can never equal a [keyFor] key, which always
  /// carries `|station:` (or is a bare demo ticket id).
  static String chitKeyFor(String orderId, int upToEditNumber) =>
      '$orderId|chit:e$upToEditNumber';

  /// Job statuses that mean this device's ticket went down its print path.
  static const Set<KdsPrintJobStatus> _paperJobStatuses = {
    KdsPrintJobStatus.prepared,
    KdsPrintJobStatus.sentToPrinter,
    KdsPrintJobStatus.printed,
  };

  /// Unit stages that were printed on Acknowledge (the proxy after a restart,
  /// or when another display printed the ticket).
  static const Set<KitchenTicketStatus> _printedTicketStatuses = {
    KitchenTicketStatus.acknowledged,
    KitchenTicketStatus.inPreparation,
    KitchenTicketStatus.ready,
  };

  /// ORDER-EDIT-001D: the watermarks of every paper of a unit still on the
  /// rail — [job]'s own when it reached the print path, plus the
  /// [KdsPrintJob.earlierPapers] it replaced — or null when none did.
  static KdsPaperWatermarks? _papersOnRail(KdsPrintJob? job) {
    if (job == null) return null;
    final earlier = job.earlierPapers;
    if (!_paperJobStatuses.contains(job.status)) return earlier;
    final own = job.printedThroughEdit ?? 0;
    if (earlier == null) return (newestThrough: own, oldestThrough: own);
    return (
      newestThrough: max(earlier.newestThrough, own),
      oldestThrough: min(earlier.oldestThrough, own),
    );
  }

  /// ORDER-EDIT-001D: what this device knows about [unit]'s paper — its own
  /// job(s) when one exists, else the unit's stage — plus the edit
  /// watermarks: ADD / "+N" lines are on the NEWEST paper, but REMOVED and
  /// Was/Now lines never reach a later paper, so they use the OLDEST paper
  /// still on the rail (a Reprint never raises it). An earlier chit covers
  /// both.
  KdsUnitPrintFacts printFactsFor(KdsTicketView unit) {
    final key = keyFor(unit);
    final job = state[key];
    final chit = _chitThrough[key] ?? 0;
    if (job != null) {
      final papers = _papersOnRail(job);
      return (
        printed: papers != null,
        fromLocalJob: true,
        through: max(papers?.newestThrough ?? 0, chit),
        removalThrough: max(papers?.oldestThrough ?? 0, chit),
      );
    }
    return (
      printed: _printedTicketStatuses.contains(unit.status),
      fromLocalJob: false,
      through: chit,
      removalThrough: chit,
    );
  }

  /// ORDER-EDIT-001D (design §7.2): after a "Got it" that STAMPED edits up to
  /// [upToEditNumber] of [orderId], prints ONE money-free change chit for the
  /// order's units already on paper (see [kdsChangeChitView]). [board] is the
  /// board the cook confirmed — taken BEFORE the ack's refresh clears the
  /// change.
  ///
  /// The SAME gating as [prepareOnAcknowledge] (toggle off, no assignment
  /// read and no device printer, or no enabled printer => nothing — no marker,
  /// since no card would show it once the change clears). Idempotent per
  /// [chitKeyFor]. A builder throw or a bridge failure is recorded ONLY under
  /// the chit key; the card's own job is never touched.
  Future<void> printChangeChit({
    required String orderId,
    required int upToEditNumber,
    required List<KdsTicketView> board,
    required PrintDocument Function(OrderChangeSlipView view) buildDocument,
    KdsBridgeSubmit? submitToBridge,
    bool nativePrinterConfigured = false,
  }) async {
    final stored = ref.read(kdsAutoPrintAcknowledgeProvider).valueOrNull;
    if (stored == false) return; // the staff turned auto-print off
    final assignments = switch (ref
        .read(kdsPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    if (assignments == null && !nativePrinterConfigured) return;
    final hasEnabledPrinter =
        (assignments?.hasEnabledPrinter ?? false) || nativePrinterConfigured;
    if (!hasEnabledPrinter) return;
    final key = chitKeyFor(orderId, upToEditNumber);
    if (state.containsKey(key)) return; // idempotent per (order, N)
    final view = kdsChangeChitView(
      orderId: orderId,
      upToEditNumber: upToEditNumber,
      board: board,
      facts: printFactsFor,
    );
    if (view == null) return; // nothing already on paper changed
    final PrintDocument document;
    try {
      document = buildDocument(view);
    } catch (_) {
      state = {
        ...state,
        key: const KdsPrintJob(status: KdsPrintJobStatus.failed),
      };
      return;
    }
    state = {
      ...state,
      key: KdsPrintJob(status: KdsPrintJobStatus.prepared, document: document),
    };
    // The chit covers every unconfirmed edit up to N of this order's units.
    for (final unit in board) {
      if (unit.orderId != orderId || unit.change == null || unit.requiresAck) {
        continue;
      }
      final unitKey = keyFor(unit);
      _chitThrough[unitKey] = max(_chitThrough[unitKey] ?? 0, upToEditNumber);
    }
    await _dispatch(key, submitToBridge);
  }
}

final kdsKitchenPrintControllerProvider =
    NotifierProvider<KdsKitchenPrintController, Map<String, KdsPrintJob>>(
      KdsKitchenPrintController.new,
    );
