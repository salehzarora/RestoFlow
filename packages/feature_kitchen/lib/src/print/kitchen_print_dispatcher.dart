import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

import 'kitchen_print_result.dart';
import 'kitchen_ticket_print_builder.dart';
import 'station_printer_routing.dart';

/// Orchestrates kitchen-ticket printing for one order (RF-072): route → resolve
/// destination → build a money-free document → enqueue a durable print job.
///
/// Thin glue over RF-033 ([KitchenRouter]) + RF-070/RF-071 (printing/spool). It
/// owns NO transport, NO retry/drain, NO UI, and NO money/tax. The actual print
/// happens later when the RF-071 [PrintSpool] is drained against a real printer
/// (deferred, approved A6). Inputs come from the caller (a routed [LocalOrder] +
/// its [KitchenRoutingRules]); RF-072 does not read sync or the DB (A7).
class KitchenPrintDispatcher {
  KitchenPrintDispatcher({
    required StationPrinterRouting routing,
    required PrintSpool spool,
    required String deviceId,
    DateTime Function()? clock,
  }) : _routing = routing,
       _spool = spool,
       _deviceId = deviceId,
       _clock = clock ?? DateTime.now;

  final StationPrinterRouting _routing;
  final PrintSpool _spool;

  /// The paired device enqueuing the jobs (idempotency scope, D-022).
  final String _deviceId;
  final DateTime Function() _clock;

  /// Route [order] with [rules], build a ticket document per station, and enqueue
  /// one `kitchenTicket` job per routed station that resolves to a destination.
  ///
  /// Idempotent per (device, order, station): the job's `local_operation_id` is
  /// `kitchen:<orderId>:<stationId>` (D-022), so re-dispatching the same order
  /// collapses to the existing jobs in the spool (no duplicate tickets). Items
  /// with no station rule and stations with no destination are FLAGGED in the
  /// result, never silently dropped (AC1).
  Future<KitchenPrintResult> dispatch(
    LocalOrder order,
    KitchenRoutingRules rules,
  ) async {
    final branchId = order.branchId;
    if (branchId == null) {
      // Kitchen printing is branch-scoped (AC3); a branchless order cannot be
      // routed to a branch printer. This is a caller/programming error.
      throw ArgumentError.value(
        order.orderId,
        'order.branchId',
        'kitchen printing requires a branch (branch-scoped routing)',
      );
    }

    final routingResult = KitchenRouter.route(order, rules);
    final now = _clock();

    final enqueued = <PrintJob>[];
    final noDestination = <String>[];

    for (final ticket in routingResult.tickets) {
      final destination = _routing.destinationFor(ticket.stationId);
      if (destination == null) {
        noDestination.add(ticket.stationId); // flagged, not enqueued (AC1)
        continue;
      }

      final document = KitchenTicketPrintBuilder.build(
        ticket,
        order,
        at: now,
        destination: destination,
      );
      final localOperationId = 'kitchen:${order.orderId}:${ticket.stationId}';

      final job = await _spool.enqueue(
        PrintJob(
          id: localOperationId,
          organizationId: order.organizationId,
          branchId: branchId,
          deviceId: _deviceId,
          localOperationId: localOperationId,
          jobType: PrintJobType.kitchenTicket,
          document: document,
          stationId: ticket.stationId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      enqueued.add(job);
    }

    return KitchenPrintResult(
      enqueuedJobs: enqueued,
      unroutableItems: [
        for (final u in routingResult.unroutableItems)
          UnroutableKitchenItem(
            orderId: u.orderId,
            orderItemId: u.orderItemId,
            menuItemId: u.menuItemId,
            itemNameSnapshot: u.itemNameSnapshot,
            reason: u.reason,
          ),
      ],
      noDestinationStations: noDestination,
    );
  }
}
