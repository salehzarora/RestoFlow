import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenReadinessPaperWidth, KitchenReadinessTransportKind;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show BluetoothPrinterConfig, NetworkPrinterConfig;

import '../state/pos_printer_transport.dart';
import 'kitchen_destination_resolver.dart' show kitchenDestinationFingerprint;

/// KITCHEN-MODE-001C3A — printer-side readiness evidence.
///
/// Mirrors the D2 destination binding (server assignment authority: enabled +
/// serves kitchen_ticket + transport match) with ONE deliberate difference:
/// the paper width is REPORTED AS-IS instead of hard-failing on non-80mm —
/// a 58mm assignment files a truthful NON-QUALIFYING report so the server's
/// transition-readiness can name `paper_width_80mm_required` as the exact
/// deficiency. The endpoint itself never leaves the device: the report
/// carries only the shared NON-SECRET routing fingerprint.
sealed class KitchenReadinessPrinterEvidence {
  const KitchenReadinessPrinterEvidence();
}

final class ReadyKitchenPrinterEvidence
    extends KitchenReadinessPrinterEvidence {
  const ReadyKitchenPrinterEvidence({
    required this.printerAssignmentId,
    required this.transportKind,
    required this.paperWidth,
    required this.printerFingerprint,
  });

  /// KITCHEN-MODE-001C3B1A: the STABLE server assignment identity
  /// (`AssignedPrinter.id`) of the deterministically selected printer — the
  /// transport, width and fingerprint below all come from THIS assignment.
  ///
  /// F1 correction: NULL when the selected assignment is NOT exactly 80mm. A
  /// non-80mm assignment can never be a qualifying pinned identity (the server
  /// would reject a pinned non-80mm id as `invalid_printer_assignment`), so
  /// leaving the id NULL lets the truthful non-80mm evidence be STORED as a
  /// diagnostic report — which is what surfaces the precise
  /// `paper_width_80mm_required` blocker instead of a generic absence.
  final String? printerAssignmentId;

  final KitchenReadinessTransportKind transportKind;
  final KitchenReadinessPaperWidth paperWidth;

  /// The shared canonical routing fingerprint (lowercase hex, non-secret).
  final String printerFingerprint;
}

/// No report can be filed: a typed, endpoint-free local blocker.
final class BlockedKitchenPrinterEvidence
    extends KitchenReadinessPrinterEvidence {
  const BlockedKitchenPrinterEvidence(this.reasonCode);

  /// `kitchen_printer_assignment_missing` / `kitchen_printer_not_selected` /
  /// `kitchen_transport_mismatch` / `kitchen_paper_width_unsupported`.
  final String reasonCode;
}

/// Pure derivation — same inputs as the destination resolver; no IO.
KitchenReadinessPrinterEvidence buildKitchenReadinessPrinterEvidence({
  required PosPrinterTransportKind? selectedTransport,
  required NetworkPrinterConfig? networkConfig,
  required BluetoothPrinterConfig? bluetoothConfig,
  required DevicePrinterAssignments? assignments,
}) {
  final kitchenCapable = [
    for (final printer in assignments?.printers ?? const <AssignedPrinter>[])
      if (printer.isEnabled && printer.servesKitchenTickets) printer,
  ];
  if (kitchenCapable.isEmpty) {
    return const BlockedKitchenPrinterEvidence(
      'kitchen_printer_assignment_missing',
    );
  }
  final transport = selectedTransport;
  if (transport == null) {
    return const BlockedKitchenPrinterEvidence('kitchen_printer_not_selected');
  }
  final wantedConnection = switch (transport) {
    PosPrinterTransportKind.network => 'network',
    PosPrinterTransportKind.bluetooth => 'bluetooth',
  };
  final matchingTransport = [
    for (final printer in kitchenCapable)
      if (printer.connectionType == wantedConnection) printer,
  ];
  if (matchingTransport.isEmpty) {
    return const BlockedKitchenPrinterEvidence('kitchen_transport_mismatch');
  }
  // KITCHEN-MODE-001C3B1A: DETERMINISTIC selection — 80mm assignments first,
  // then the stable assignment id as the tie-breaker, so shuffling the same
  // collection always selects the SAME printer (never list arrival order).
  final ordered = [...matchingTransport]
    ..sort((a, b) {
      final aw = a.paperWidth == '80mm' ? 0 : 1;
      final bw = b.paperWidth == '80mm' ? 0 : 1;
      if (aw != bw) return aw.compareTo(bw);
      return a.id.compareTo(b.id);
    });
  final assignment = ordered.first;
  final KitchenReadinessPaperWidth paperWidth;
  switch (assignment.paperWidth) {
    case '80mm':
      paperWidth = KitchenReadinessPaperWidth.mm80;
    case '58mm':
      paperWidth = KitchenReadinessPaperWidth.mm58;
    default:
      return const BlockedKitchenPrinterEvidence(
        'kitchen_paper_width_unsupported',
      );
  }
  // F1 correction: the STABLE assignment identity is pinned ONLY for an
  // exactly-80mm assignment (the sole width a qualifying pinned assignment may
  // carry). For a 58mm selection the id stays NULL so the truthful 58mm
  // evidence is STORED as a diagnostic report (server accepts a NULL
  // assignment) and surfaces the precise paper_width_80mm_required blocker,
  // rather than being rejected and leaving a generic no_fresh_pos_readiness.
  final String? selectedAssignmentId =
      paperWidth == KitchenReadinessPaperWidth.mm80 ? assignment.id : null;

  switch (transport) {
    case PosPrinterTransportKind.network:
      final config = networkConfig;
      if (config == null) {
        return const BlockedKitchenPrinterEvidence(
          'kitchen_printer_not_selected',
        );
      }
      final host = config.host.trim().toLowerCase();
      return ReadyKitchenPrinterEvidence(
        printerAssignmentId: selectedAssignmentId,
        transportKind: KitchenReadinessTransportKind.network,
        paperWidth: paperWidth,
        printerFingerprint: kitchenDestinationFingerprint(
          'network|$host|${config.port}',
        ),
      );
    case PosPrinterTransportKind.bluetooth:
      final config = bluetoothConfig;
      if (config == null) {
        return const BlockedKitchenPrinterEvidence(
          'kitchen_printer_not_selected',
        );
      }
      final address = config.address.trim().toLowerCase();
      return ReadyKitchenPrinterEvidence(
        printerAssignmentId: selectedAssignmentId,
        transportKind: KitchenReadinessTransportKind.bluetooth,
        paperWidth: paperWidth,
        printerFingerprint: kitchenDestinationFingerprint('bluetooth|$address'),
      );
  }
}
