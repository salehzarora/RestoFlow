import 'package:restoflow_printing/restoflow_printing.dart';

/// An active item that could not be routed to any station (RF-072 flag).
///
/// A money-free mirror of RF-033's unroutable-item flag. RF-072 re-declares it
/// locally because the domain's `UnroutableOrderItem` is reachable through
/// `KitchenRoutingResult` but not re-exported from `restoflow_domain`; copying
/// the (already public) fields keeps this package from importing domain `src/`
/// and avoids any change to `packages/domain`.
class UnroutableKitchenItem {
  const UnroutableKitchenItem({
    required this.orderId,
    required this.orderItemId,
    required this.menuItemId,
    required this.itemNameSnapshot,
    required this.reason,
  });

  final String orderId;
  final String orderItemId;
  final String menuItemId;
  final String itemNameSnapshot;

  /// Short, safe explanation of why the item is unroutable (from RF-033).
  final String reason;
}

/// The outcome of dispatching an order's kitchen tickets to the spool (RF-072).
///
/// Misroutes are FLAGGED here, never silently dropped (AC1): [unroutableItems]
/// are active items with no station rule (RF-033), and [noDestinationStations]
/// are routed stations with no printer destination — neither is enqueued.
class KitchenPrintResult {
  KitchenPrintResult({
    required List<PrintJob> enqueuedJobs,
    required List<UnroutableKitchenItem> unroutableItems,
    required List<String> noDestinationStations,
  }) : enqueuedJobs = List.unmodifiable(enqueuedJobs),
       unroutableItems = List.unmodifiable(unroutableItems),
       noDestinationStations = List.unmodifiable(noDestinationStations);

  /// One enqueued `kitchenTicket` job per routed station that HAS a destination.
  final List<PrintJob> enqueuedJobs;

  /// Active items that could not be routed to any station (RF-033 flag).
  final List<UnroutableKitchenItem> unroutableItems;

  /// Routed stations that have no printer destination (flagged, not enqueued).
  final List<String> noDestinationStations;

  /// Whether everything routed cleanly (nothing flagged).
  bool get isFullyRouted =>
      unroutableItems.isEmpty && noDestinationStations.isEmpty;
}
