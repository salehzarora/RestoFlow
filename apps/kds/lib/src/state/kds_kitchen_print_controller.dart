import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

import '../print/print_document.dart';

/// The HONEST lifecycle of a prepared kitchen print job (device settings
/// sprint, Part D). This build has NO physical print transport (a print
/// bridge / native app is required), so [prepared] is never presented as
/// printed; [printed] is reachable only when a real transport confirms —
/// i.e. never in this build. Money-free by construction (the ticket views
/// carry no money — T-003).
enum KdsPrintJobStatus { notConfigured, prepared, printed, failed }

class KdsPrintJob {
  const KdsPrintJob({required this.status, this.document});

  final KdsPrintJobStatus status;
  final PrintDocument? document;
}

/// Holds the kitchen-ticket print job per ORDER (device settings sprint).
///
/// Keyed by the ticket's order id (kitchen-ticket id for demo fixtures), so
/// [prepareForTicket] is IDEMPOTENT across poll refreshes and repeated
/// acknowledge taps: the board rebuilds its `KdsTicketView`s on every pull,
/// but a key that was already prepared never re-prepares (no double print).
class KdsKitchenPrintController extends Notifier<Map<String, KdsPrintJob>> {
  @override
  Map<String, KdsPrintJob> build() => const {};

  /// The idempotency key for [ticket].
  static String keyFor(KdsTicketView ticket) =>
      ticket.orderId ?? ticket.kitchenTicketId;

  /// Prepares the kitchen job for [ticket] once. No enabled kitchen printer
  /// => an honest [KdsPrintJobStatus.notConfigured] marker; a throwing
  /// builder => [KdsPrintJobStatus.failed] (the ticket is unaffected).
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

  KdsPrintJob? jobFor(KdsTicketView ticket) => state[keyFor(ticket)];
}

final kdsKitchenPrintControllerProvider =
    NotifierProvider<KdsKitchenPrintController, Map<String, KdsPrintJob>>(
      KdsKitchenPrintController.new,
    );
