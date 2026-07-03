import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';

import '../print/print_document.dart';
import 'kds_auto_print_prefs.dart';
import 'kds_printer_assignments.dart';

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

  /// The acknowledge-trigger POLICY (device settings sprint, Part F): prepare
  /// a kitchen print job for a just-ACKNOWLEDGED [ticket], honoring the
  /// per-device toggle and the branch's kitchen-printer assignment.
  ///
  ///  * Toggle explicitly OFF => nothing at all.
  ///  * Demo / unconfigured / failed assignment read => nothing (never a fake
  ///    job when we cannot know the printer state).
  ///  * Enabled kitchen printer => a PREPARED job (no bridge transport in this
  ///    build, so never "printed").
  ///  * No enabled printer => an honest notConfigured marker.
  ///
  /// Delegates to [prepareForTicket], so it is idempotent per order id (a
  /// re-tap or the next poll never double-prepares). The caller passes
  /// [buildDocument] (the widget owns l10n); the payload is money-free (T-003).
  void prepareOnAcknowledge(
    KdsTicketView ticket, {
    required PrintDocument Function() buildDocument,
  }) {
    final stored = ref.read(kdsAutoPrintAcknowledgeProvider).valueOrNull;
    if (stored == false) return; // the staff turned it off
    final assignments = switch (ref
        .read(kdsPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    if (assignments == null) return; // demo / unconfigured / failed read
    prepareForTicket(
      ticket,
      hasEnabledPrinter: assignments.hasEnabledPrinter,
      buildDocument: buildDocument,
    );
  }

  KdsPrintJob? jobFor(KdsTicketView ticket) => state[keyFor(ticket)];
}

final kdsKitchenPrintControllerProvider =
    NotifierProvider<KdsKitchenPrintController, Map<String, KdsPrintJob>>(
      KdsKitchenPrintController.new,
    );
