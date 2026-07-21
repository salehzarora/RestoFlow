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
    required this.transportKind,
    required this.paperWidth,
    required this.printerFingerprint,
  });

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
  // ONE selected assignment: prefer an 80mm row (the qualifying width),
  // mirroring the resolver's selection, then report the actual width.
  final assignment = matchingTransport.firstWhere(
    (printer) => printer.paperWidth == '80mm',
    orElse: () => matchingTransport.first,
  );
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
        transportKind: KitchenReadinessTransportKind.bluetooth,
        paperWidth: paperWidth,
        printerFingerprint: kitchenDestinationFingerprint('bluetooth|$address'),
      );
  }
}
