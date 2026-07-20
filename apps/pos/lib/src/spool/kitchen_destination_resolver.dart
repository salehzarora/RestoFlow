import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert' show utf8;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';

import '../state/pos_printer_transport.dart';

/// KITCHEN-MODE-001C2B — kitchen-ticket destination resolution + pinning
/// (LOCKED D2: the SERVER printer-assignment row is the paper-width and
/// kitchen-purpose authority; local endpoint config alone proves nothing).
///
/// The assignment model deliberately carries NO endpoints (server strips
/// `connection_config`), so "the local selected printer corresponds to the
/// assigned kitchen printer" is bound by: an ENABLED assignment that serves
/// `kitchen_ticket`, whose `connection_type` matches the locally selected
/// transport kind, with paper width EXACTLY `80mm`. Endpoints (host/port/BT
/// address) live ONLY inside the encrypted payload; the plaintext columns
/// get a sanitized label and a NON-SECRET SHA-256 routing fingerprint.
///
/// ACCEPTED LIMITATION — printer identity (CORRECTION-001, reviewed): the
/// current assignment contract exposes NO stable local↔server per-printer
/// identity, so this binding is attribute-based, NOT a strong identity
/// binding. It is accepted for the ONE-kitchen-printer pilot; multiple
/// same-transport kitchen printers on one branch remain ambiguous until a
/// later additive server/client contract (001C3+) exposes a stable
/// assignment id. Do not claim strong identity binding anywhere.
///
/// ACCEPTED LIMITATION — routing fingerprint (CORRECTION-001, reviewed):
/// the plaintext SHA-256 fingerprint is a NON-SECRET routing identifier,
/// not a confidentiality boundary — LAN endpoints have tiny dictionaries,
/// so the input is recoverable by brute force. That is accepted for the
/// backup-excluded on-device database: the endpoints themselves remain ONLY
/// inside the AES-GCM payload, and the fingerprint is never logged next to
/// endpoint hints. No HMAC/keyed variant here (would add key-lifecycle
/// complexity without a real boundary gain).
sealed class KitchenDestinationResolution {
  const KitchenDestinationResolution();
}

final class ResolvedKitchenDestination extends KitchenDestinationResolution {
  const ResolvedKitchenDestination({
    required this.destination,
    required this.fingerprint,
    required this.displayLabel,
    required this.transportKind,
    required this.paperWidth,
  });

  /// Goes INSIDE the encrypted payload only.
  final KitchenSpoolDestination destination;

  /// NON-SECRET routing digest (plaintext column).
  final String fingerprint;

  /// Raw label; the store sanitizes before persisting.
  final String displayLabel;

  /// `network` / `bluetooth`.
  final String transportKind;

  /// Always `80mm` when resolved (D2).
  final String paperWidth;
}

final class BlockedKitchenDestination extends KitchenDestinationResolution {
  const BlockedKitchenDestination(this.reasonCode);

  /// Safe, typed, endpoint-free reason code.
  final String reasonCode;
}

final class KitchenDestinationResolver {
  const KitchenDestinationResolver();

  KitchenDestinationResolution resolve({
    required PosPrinterTransportKind? selectedTransport,
    required NetworkPrinterConfig? networkConfig,
    required BluetoothPrinterConfig? bluetoothConfig,
    required DevicePrinterAssignments? assignments,
  }) {
    // D2: the server assignment list is the authority — no assignments, no
    // kitchen printing.
    final kitchenCapable = [
      for (final printer in assignments?.printers ?? const <AssignedPrinter>[])
        if (printer.isEnabled && printer.servesKitchenTickets) printer,
    ];
    if (kitchenCapable.isEmpty) {
      return const BlockedKitchenDestination(
        'kitchen_printer_assignment_missing',
      );
    }

    final transport = selectedTransport;
    if (transport == null) {
      return const BlockedKitchenDestination('kitchen_printer_not_selected');
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
      return const BlockedKitchenDestination('kitchen_transport_mismatch');
    }
    final assignment = matchingTransport.firstWhere(
      (printer) => printer.paperWidth == '80mm',
      orElse: () => matchingTransport.first,
    );
    if (assignment.paperWidth != '80mm') {
      return const BlockedKitchenDestination('kitchen_paper_width_not_80mm');
    }

    switch (transport) {
      case PosPrinterTransportKind.network:
        final config = networkConfig;
        if (config == null) {
          return const BlockedKitchenDestination(
            'kitchen_printer_not_selected',
          );
        }
        final host = config.host.trim().toLowerCase();
        return ResolvedKitchenDestination(
          destination: NetworkKitchenDestination(
            host: config.host,
            port: config.port,
          ),
          fingerprint: _fingerprint('network|$host|${config.port}'),
          displayLabel: config.name ?? assignment.displayName,
          transportKind: 'network',
          paperWidth: '80mm',
        );
      case PosPrinterTransportKind.bluetooth:
        final config = bluetoothConfig;
        if (config == null) {
          return const BlockedKitchenDestination(
            'kitchen_printer_not_selected',
          );
        }
        final address = config.address.trim().toLowerCase();
        return ResolvedKitchenDestination(
          destination: BluetoothKitchenDestination(address: config.address),
          fingerprint: _fingerprint('bluetooth|$address'),
          displayLabel: config.name ?? assignment.displayName,
          transportKind: 'bluetooth',
          paperWidth: '80mm',
        );
    }
  }

  static String _fingerprint(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString();
}
