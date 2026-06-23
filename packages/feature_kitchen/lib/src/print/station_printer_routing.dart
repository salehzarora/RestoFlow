import 'package:restoflow_printing/restoflow_printing.dart';

/// A logical kitchen-printer destination for a station (RF-072).
///
/// Carries only a logical id + the [PrinterProfile] (58/80mm + capabilities) and
/// an optional human label. It holds NO transport address (IP/port/USB/BT) and
/// NO secret — real connectivity is deferred (PRINTERS §3; approved A5/A6).
class PrintDestination {
  const PrintDestination({
    required this.destinationId,
    required this.profile,
    this.label,
  });

  /// Stable logical id of the destination printer.
  final String destinationId;

  /// The paper/capability profile to render for (RF-070).
  final PrinterProfile profile;

  /// Optional display label (e.g. "Grill Station"); falls back to the station id.
  final String? label;
}

/// Resolves a kitchen `station_id` to its print [PrintDestination] (RF-072,
/// PRINTERS §6).
///
/// **Branch-scoped by construction**: a routing instance is built for ONE branch
/// (its map only contains that branch's stations), so the dispatcher can never
/// resolve a cross-branch destination (AC3). A station with no mapping returns
/// null and is FLAGGED by the dispatcher (never silently dropped, AC1). The real
/// per-branch `station_id -> destination` config (a DB/Drift table) is deferred
/// (A5); RF-072 ships this port + an in-memory implementation only.
abstract class StationPrinterRouting {
  /// The destination for [stationId] within this branch, or null if unmapped.
  PrintDestination? destinationFor(String stationId);
}

/// An in-memory [StationPrinterRouting] (RF-072): a fixed branch-scoped map.
class InMemoryStationPrinterRouting implements StationPrinterRouting {
  InMemoryStationPrinterRouting(Map<String, PrintDestination> byStation)
    : _byStation = Map.unmodifiable(byStation);

  final Map<String, PrintDestination> _byStation;

  @override
  PrintDestination? destinationFor(String stationId) => _byStation[stationId];
}
