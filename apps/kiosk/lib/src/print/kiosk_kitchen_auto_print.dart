import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart'
    show
        KitchenDispatchDocument,
        KitchenTicketLabels,
        KitchenTicketRenderer,
        rejectHostileKitchenKeys;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenAckResult, KitchenImportAckStatus;
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;

import '../data/kiosk_order_submit.dart' show KioskClaimedKitchenDispatch;
import '../state/kiosk_flow_controller.dart' show KioskOrderSnapshot;
import 'kiosk_printer_purpose.dart';

/// KIOSK-PRINT-114B.2 — the kiosk KITCHEN TICKET auto-print lane.
///
/// Input: the kitchen dispatch THIS device's submit already CLAIMED (114B.1
/// claim-at-submit). The lane renders the claimed money-free payload with
/// the SHARED extracted printer_only renderer (the exact ticket the POS
/// drain prints), serializes the physical send through the ONE process-wide
/// destination gate, sends EXACTLY once, and acknowledges honestly:
///
///   accepted                          -> transport_accepted (completes)
///   definitelyNotSent / timeouts-before-write / unavailable / unsupported
///                                     -> failed_retryable (the LIVE lease
///                                        is kept server-side; retry() may
///                                        re-send under the SAME claim, and
///                                        natural expiry hands the work to
///                                        the POS drain)
///   ambiguous / timeoutAfterPossibleWrite
///                                     -> possibly_printed (the permanent
///                                        sticky no-reprint hold; retry()
///                                        REFUSES to resend)
///
/// The server claim is the durable cross-device exactly-once guarantee; the
/// in-memory latch only absorbs same-run hook replays. The customer receipt
/// lane (ledger, record-on-success) is completely independent — one lane's
/// failure never marks the other.

/// The kitchen ack seam (real root: the shared feature_auth repository over
/// the device credential; demo/tests: null / fakes).
typedef KioskKitchenAck =
    Future<KitchenAckResult> Function({
      required String dispatchId,
      required KitchenImportAckStatus status,
      String? errorCode,
    });

final kioskKitchenAckProvider = Provider<KioskKitchenAck?>((ref) => null);

/// The physical transport seam. Null (default) = the REAL kitchen-safe
/// senders: phase-aware TCP for network, single-attempt SPP for Bluetooth.
/// Tests override with a capturing fake — the gate still wraps whatever is
/// injected.
typedef KioskKitchenTransportSend =
    Future<pp.KitchenTransportOutcome> Function(
      Uint8List bytes,
      KioskKitchenPrintTarget target,
    );

final kioskKitchenTransportSendProvider = Provider<KioskKitchenTransportSend?>(
  (ref) => null,
);

/// Honest per-dispatch status for the settings surface.
enum KioskKitchenPrintOutcome {
  sent,
  failedRetryable,
  possiblyPrinted,
  notConfigured,
}

typedef KioskKitchenPrintStatus = ({
  String orderId,
  String dispatchId,
  KioskKitchenPrintOutcome outcome,
});

final kioskKitchenPrintStatusProvider = StateProvider<KioskKitchenPrintStatus?>(
  (ref) => null,
);

final kioskKitchenTicketPrinterProvider = Provider<KioskKitchenTicketPrinter>(
  KioskKitchenTicketPrinter.new,
);

class KioskKitchenTicketPrinter {
  KioskKitchenTicketPrinter(this._ref);

  final Ref _ref;
  final Set<String> _inFlight = {};
  final Set<String> _settledThisRun = {};

  /// The last failed-retryable work, kept so staff can retry the SAME
  /// dispatch under the SAME live claim (verified 114B.1 capability: the
  /// claim holder may move failed_retryable -> transport_accepted /
  /// possibly_printed before expiry). Never kept after possibly_printed.
  ({
    KioskOrderSnapshot order,
    String lang,
    KioskClaimedKitchenDispatch dispatch,
  })?
  _retryable;

  /// Fire-and-forget from the ACCEPTED submit branch only. Never throws.
  Future<void> onOrderAccepted({
    required KioskOrderSnapshot order,
    required String lang,
    required KioskClaimedKitchenDispatch? dispatch,
  }) async {
    if (dispatch == null) return; // no claim landed => nothing to own
    try {
      await _run(order: order, lang: lang, dispatch: dispatch);
    } catch (_) {
      // A print problem must NEVER surface as an order problem.
    }
  }

  /// Staff-controlled retry of the last failed-retryable dispatch — the SAME
  /// dispatch id under the SAME live claim; never a new claim, and never
  /// after a possibly_printed hold.
  Future<void> retry() async {
    final held = _retryable;
    if (held == null) return;
    _settledThisRun.remove(held.dispatch.id);
    try {
      await _run(order: held.order, lang: held.lang, dispatch: held.dispatch);
    } catch (_) {}
  }

  Future<void> _run({
    required KioskOrderSnapshot order,
    required String lang,
    required KioskClaimedKitchenDispatch dispatch,
  }) async {
    final orderId = order.orderId;
    if (orderId == null) return; // demo/fixture orders never print
    final dispatchId = dispatch.id;
    if (_settledThisRun.contains(dispatchId) || !_inFlight.add(dispatchId)) {
      return;
    }
    try {
      // Decode the CLAIMED payload with the same hostile-key validation the
      // POS import applies. An undecodable payload cannot be printed here:
      // record failed_retryable and let the lease machinery recover.
      KitchenDispatchDocument? doc;
      try {
        final json = Map<String, Object?>.from(dispatch.payload);
        rejectHostileKitchenKeys(json, path: 'dispatch');
        doc = KitchenDispatchDocument.fromJson(json);
      } catch (_) {
        doc = null;
      }
      if (doc == null) {
        _settledThisRun.add(dispatchId);
        _retryable = null;
        await _ack(
          dispatchId,
          KitchenImportAckStatus.failedRetryable,
          errorCode: 'kiosk_payload_undecodable',
        );
        _publish(orderId, dispatchId, KioskKitchenPrintOutcome.failedRetryable);
        return;
      }

      final target = await resolveKioskKitchenPrintTarget(_ref);
      if (target == null) {
        _settledThisRun.add(dispatchId);
        _retryable = null;
        await _ack(
          dispatchId,
          KitchenImportAckStatus.failedRetryable,
          errorCode: 'kiosk_kitchen_not_configured',
        );
        _publish(orderId, dispatchId, KioskKitchenPrintOutcome.notConfigured);
        return;
      }

      // The SHARED extracted printer_only renderer — the exact POS ticket.
      final renderer = KitchenTicketRenderer(
        labels: KitchenTicketLabels.forLanguageCode(lang),
        rasterizer: _ref.read(nativePrintRasterizerProvider),
      );
      final bytes = await renderer.renderToBytes(doc);

      // ONE physical attempt, serialized per destination by the process-wide
      // gate (a same-printer receipt never interleaves).
      final send = _ref.read(kioskKitchenTransportSendProvider) ?? _realSend;
      final gate = _ref.read(kioskPrinterDestinationSendGateProvider);
      final outcome = await gate.withDestination(
        target.destinationKey,
        () => send(bytes, target),
      );

      switch (outcome.kind) {
        case pp.KitchenTransportOutcomeKind.accepted:
          _settledThisRun.add(dispatchId);
          _retryable = null;
          await _ack(dispatchId, KitchenImportAckStatus.transportAccepted);
          _publish(orderId, dispatchId, KioskKitchenPrintOutcome.sent);
        case pp.KitchenTransportOutcomeKind.ambiguous:
        case pp.KitchenTransportOutcomeKind.timeoutAfterPossibleWrite:
          // Paper may exist: the permanent no-reprint hold. Never retried.
          _settledThisRun.add(dispatchId);
          _retryable = null;
          await _ack(
            dispatchId,
            KitchenImportAckStatus.possiblyPrinted,
            errorCode: outcome.reasonCode,
          );
          _publish(
            orderId,
            dispatchId,
            KioskKitchenPrintOutcome.possiblyPrinted,
          );
        case pp.KitchenTransportOutcomeKind.definitelyNotSent:
        case pp.KitchenTransportOutcomeKind.timeoutBeforeWrite:
        case pp.KitchenTransportOutcomeKind.unavailable:
        case pp.KitchenTransportOutcomeKind.unsupported:
          // Provably (or safely) unsent: record and keep the LIVE lease —
          // retry() may re-send under the same claim; natural expiry hands
          // the dispatch to the POS drain.
          _settledThisRun.add(dispatchId);
          _retryable = (order: order, lang: lang, dispatch: dispatch);
          await _ack(
            dispatchId,
            KitchenImportAckStatus.failedRetryable,
            errorCode: outcome.reasonCode,
          );
          _publish(
            orderId,
            dispatchId,
            KioskKitchenPrintOutcome.failedRetryable,
          );
      }
    } finally {
      _inFlight.remove(dispatchId);
    }
  }

  /// The REAL kitchen-safe physical send (no automatic resend of any kind).
  Future<pp.KitchenTransportOutcome> _realSend(
    Uint8List bytes,
    KioskKitchenPrintTarget target,
  ) async {
    final network = target.network;
    if (network != null) {
      return pp.sendKitchenBytesOverTcp(
        host: network.host,
        port: network.port,
        bytes: bytes,
      );
    }
    final connector = _ref.read(bluetoothPrinterConnectorProvider);
    if (connector is! ChannelBluetoothConnector) {
      return const pp.KitchenTransportOutcome(
        pp.KitchenTransportOutcomeKind.unsupported,
        'bluetooth_channel_missing',
      );
    }
    final attempt = await connector.sendOnceForKitchen(
      address: target.bluetooth!.address,
      bytes: bytes,
    );
    return classifyKitchenBluetoothAttempt(attempt);
  }

  Future<void> _ack(
    String dispatchId,
    KitchenImportAckStatus status, {
    String? errorCode,
  }) async {
    final ack = _ref.read(kioskKitchenAckProvider);
    if (ack == null) return;
    try {
      await ack(dispatchId: dispatchId, status: status, errorCode: errorCode);
    } catch (_) {
      // The server lease still governs: an unreachable ack simply leaves the
      // claim to expire into the POS recovery path.
    }
  }

  void _publish(
    String orderId,
    String dispatchId,
    KioskKitchenPrintOutcome outcome,
  ) {
    _ref.read(kioskKitchenPrintStatusProvider.notifier).state = (
      orderId: orderId,
      dispatchId: dispatchId,
      outcome: outcome,
    );
  }
}
