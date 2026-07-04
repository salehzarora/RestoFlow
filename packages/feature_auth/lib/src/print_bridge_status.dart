/// Shared, app-agnostic view-model for the device-settings "print bridge" row
/// (RF-115). The POS/KDS apps compute this from their local print-bridge client
/// and pass it into [PrinterAssignmentsSection]; feature_auth owns only the
/// SHAPE so the row reaches both device-settings surfaces from one place.
///
/// Deliberately money-free and connection-detail-free: it carries only whether
/// a configured LOCAL bridge is reachable and when the last job was submitted —
/// never a printer IP (the app never learns it — RF-115 security model).
library;

/// Whether a configured local print bridge is currently reachable.
enum PrintBridgeConnectivity {
  /// The bridge answered `/health` as a valid RestoFlow bridge.
  connected,

  /// No bridge answered, or it answered but not as a valid bridge.
  unavailable,
}

/// A snapshot of the local print bridge for the device-settings row.
class PrinterBridgeStatus {
  const PrinterBridgeStatus({required this.connectivity, this.lastJobAt});

  final PrintBridgeConnectivity connectivity;

  /// When the most recent print job was dispatched to the bridge, or null if
  /// none has been submitted this session.
  final DateTime? lastJobAt;
}
