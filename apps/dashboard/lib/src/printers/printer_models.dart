/// Printer configuration models for the dashboard Printers surface (RF-150
/// backend: `printer_devices` + `printer_routes`). Pure Dart, no Flutter.
///
/// Money never appears here (printers carry no money). The connection config is
/// LAN-only transport data (host/port/identifiers) — never a secret/credential.
library;

/// `printer_devices.connection_type` (RF-150 CHECK: network | usb | bluetooth).
enum PrinterConnectionType {
  network('network'),
  usb('usb'),
  bluetooth('bluetooth');

  const PrinterConnectionType(this.wire);
  final String wire;

  static PrinterConnectionType? fromWire(String? wire) => switch (wire) {
    'network' => PrinterConnectionType.network,
    'usb' => PrinterConnectionType.usb,
    'bluetooth' => PrinterConnectionType.bluetooth,
    _ => null,
  };
}

/// `printer_devices.role` (RF-150 CHECK: receipt | kitchen).
enum PrinterRole {
  receipt('receipt'),
  kitchen('kitchen');

  const PrinterRole(this.wire);
  final String wire;

  static PrinterRole? fromWire(String? wire) => switch (wire) {
    'receipt' => PrinterRole.receipt,
    'kitchen' => PrinterRole.kitchen,
    _ => null,
  };
}

/// `printer_devices.paper_width` (RF-150 CHECK: 58mm | 80mm; 80mm default,
/// D-009 — better Arabic/Hebrew legibility).
const List<String> kPaperWidths = ['80mm', '58mm'];

/// One configured printer (a row of `printer_devices`).
class PrinterDevice {
  const PrinterDevice({
    required this.id,
    required this.displayName,
    required this.connectionType,
    required this.role,
    required this.paperWidth,
    required this.connectionConfig,
    required this.isEnabled,
  });

  final String id;
  final String displayName;
  final PrinterConnectionType connectionType;
  final PrinterRole role;
  final String paperWidth;

  /// Transport specifics (e.g. `{"host": "10.0.0.50", "port": 9100}` for
  /// network). LAN-only config; no tenant data, no secrets.
  final Map<String, Object?> connectionConfig;
  final bool isEnabled;

  String? get host => connectionConfig['host']?.toString();
  String? get port => connectionConfig['port']?.toString();
}

/// One station → printer routing edge (a row of `printer_routes`).
class PrinterRoute {
  const PrinterRoute({
    required this.id,
    required this.stationId,
    required this.printerDeviceId,
    required this.isEnabled,
  });

  final String id;
  final String stationId;
  final String printerDeviceId;
  final bool isEnabled;
}

/// A station of the active branch (routing target).
class StationInfo {
  const StationInfo({required this.id, required this.name});

  final String id;
  final String name;
}

/// Everything the Printers page needs in one load (`public.list_printers`).
class PrintersSnapshot {
  const PrintersSnapshot({
    required this.printers,
    required this.routes,
    required this.stations,
  });

  final List<PrinterDevice> printers;
  final List<PrinterRoute> routes;
  final List<StationInfo> stations;

  /// The stations a printer is currently routed to (live, enabled edges).
  List<StationInfo> stationsFor(String printerId) => [
    for (final r in routes)
      if (r.printerDeviceId == printerId && r.isEnabled)
        for (final s in stations)
          if (s.id == r.stationId) s,
  ];
}
