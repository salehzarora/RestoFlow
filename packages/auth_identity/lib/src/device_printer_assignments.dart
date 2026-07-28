import 'package:restoflow_core/restoflow_core.dart';

/// The SAFE printer metadata a paired POS/KDS device may see for its own
/// branch (device settings sprint) — the projection of
/// `public.get_device_printer_assignments`.
///
/// Deliberately minimal: identity/role/capability fields only. NO
/// `connection_config` (LAN host/port stays server-side), no secrets, no
/// money, no cross-branch or cross-org data. The server filters by the
/// TOKEN-PROVEN device session: POS devices see receipt printers only, KDS
/// devices kitchen printers only (T-014-style role scoping).
class AssignedPrinter {
  const AssignedPrinter({
    required this.id,
    required this.displayName,
    required this.role,
    required this.connectionType,
    required this.paperWidth,
    required this.isEnabled,
    this.configuredRole,
    this.supportedPurposes = const [],
  });

  final String id;
  final String displayName;

  /// `'receipt'` or `'kitchen'` (the LEGACY narrowed value).
  final String role;

  /// `'network'`, `'usb'`, or `'bluetooth'` — capability display only; this
  /// build has no physical transport (print bridge required).
  final String connectionType;

  /// `'58mm'` or `'80mm'`.
  final String paperWidth;

  /// False = configured but disabled by the owner in the Dashboard.
  final bool isEnabled;

  /// KITCHEN-MODE-001C2B (additive, from the 001B server keys): the owner's
  /// UN-narrowed configured role (`receipt` / `kitchen` / `both`) — null when
  /// an older server omits it.
  final String? configuredRole;

  /// KITCHEN-MODE-001C2B (additive): the purposes this printer serves
  /// (`customer_receipt` / `kitchen_ticket`); empty when the server omits it.
  final List<String> supportedPurposes;

  /// Whether this printer may serve KITCHEN TICKETS (KITCHEN-MODE-001B
  /// purpose model, with a legacy-role fallback for older envelopes).
  bool get servesKitchenTickets =>
      supportedPurposes.contains('kitchen_ticket') ||
      (supportedPurposes.isEmpty &&
          (configuredRole ?? role) != 'receipt' &&
          ((configuredRole ?? role) == 'kitchen' ||
              (configuredRole ?? role) == 'both'));
}

/// One station→printer routing edge of the device's branch.
class PrinterRoute {
  const PrinterRoute({
    required this.stationId,
    required this.printerDeviceId,
    required this.isEnabled,
  });

  final String stationId;
  final String printerDeviceId;
  final bool isEnabled;
}

/// A station referenced by the returned routes (id + display name only).
class PrinterStation {
  const PrinterStation({required this.id, required this.name});

  final String id;
  final String name;
}

/// The device's printer-assignment snapshot + its own display context.
class DevicePrinterAssignments {
  const DevicePrinterAssignments({
    required this.fetchedAt,
    this.deviceLabel,
    this.deviceType,
    this.branchName,
    this.restaurantName,
    this.organizationId,
    this.restaurantId,
    this.receiptLogoPath,
    this.receiptLogoEnabled = false,
    this.receiptLogoVersion = 0,
    this.printers = const <AssignedPrinter>[],
    this.routes = const <PrinterRoute>[],
    this.stations = const <PrinterStation>[],
  });

  final DateTime fetchedAt;
  final String? deviceLabel;
  final String? deviceType;
  final String? branchName;
  final String? restaurantName;

  /// PRINT-BRANDING-LOGO-001 (additive; server-derived, never client-asserted):
  /// the device's own proven tenant scope, used as part of the offline
  /// receipt-logo raster-cache key. Null when an older server omits them.
  final String? organizationId;
  final String? restaurantId;

  /// PRINT-BRANDING-LOGO-001 (additive): the CURRENT restaurant receipt-logo
  /// pointer. [receiptLogoPath] is the private-bucket object key (null = none);
  /// [receiptLogoEnabled] gates printing; [receiptLogoVersion] (>=0) drives
  /// cache invalidation. Default-safe (null/false/0) for a legacy server.
  final String? receiptLogoPath;
  final bool receiptLogoEnabled;
  final int receiptLogoVersion;

  final List<AssignedPrinter> printers;
  final List<PrinterRoute> routes;
  final List<PrinterStation> stations;

  /// True when a logo is configured AND enabled AND we know the tenant scope
  /// needed to fetch + cache it. The receipt prints the logo only in this case.
  bool get hasReceiptLogo =>
      receiptLogoEnabled &&
      (receiptLogoPath != null && receiptLogoPath!.isNotEmpty) &&
      organizationId != null &&
      restaurantId != null;

  /// The names of the stations routed to [printer] (KDS routing display).
  List<String> stationNamesFor(AssignedPrinter printer) {
    final ids = <String>{
      for (final route in routes)
        if (route.printerDeviceId == printer.id && route.isEnabled)
          route.stationId,
    };
    return [
      for (final station in stations)
        if (ids.contains(station.id)) station.name,
    ];
  }

  /// Whether any ENABLED printer is assigned (the auto-print toggles key on
  /// this — a disabled printer cannot be a print target).
  bool get hasEnabledPrinter => printers.any((p) => p.isEnabled);
}

/// Why the assignments could not be loaded (all fail-safe, none fatal).
enum DevicePrinterAssignmentsFailure { invalidSession, network, unknown }

/// Read-only seam: fetch THIS device's printer assignments (token-proven
/// server-side). Implemented over Supabase in `feature_auth`; faked in tests.
abstract class DevicePrinterAssignmentsReader {
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load();
}
