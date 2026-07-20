import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_local/restoflow_data_local.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_pos/src/spool/kitchen_destination_resolver.dart';

/// KITCHEN-MODE-001C2B — D2 binding tests: the SERVER assignment row is the
/// kitchen-purpose + paper-width authority; the locally selected transport
/// must match it; endpoints go only into the encrypted destination while the
/// plaintext side gets a sanitized label + a NON-SECRET routing fingerprint.
AssignedPrinter _printer({
  String id = 'prn-1',
  String connectionType = 'network',
  String paperWidth = '80mm',
  bool isEnabled = true,
  List<String> supportedPurposes = const ['kitchen_ticket'],
  String? configuredRole,
  String role = 'kitchen',
}) => AssignedPrinter(
  id: id,
  displayName: 'Kitchen Assigned',
  role: role,
  connectionType: connectionType,
  paperWidth: paperWidth,
  isEnabled: isEnabled,
  configuredRole: configuredRole,
  supportedPurposes: supportedPurposes,
);

DevicePrinterAssignments _assignments(List<AssignedPrinter> printers) =>
    DevicePrinterAssignments(
      fetchedAt: DateTime.utc(2026, 7, 20),
      printers: printers,
    );

String _expectedFingerprint(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

void main() {
  const resolver = KitchenDestinationResolver();

  test('network resolution pins endpoint + canonical fingerprint + 80mm', () {
    final resolution = resolver.resolve(
      selectedTransport: PrinterTransportKind.network,
      networkConfig: const NetworkPrinterConfig(
        host: '192.168.1.50',
        port: 9100,
        name: 'Kitchen TM-T20',
      ),
      bluetoothConfig: null,
      assignments: _assignments([_printer()]),
    );
    expect(resolution, isA<ResolvedKitchenDestination>());
    final resolved = resolution as ResolvedKitchenDestination;
    expect(resolved.transportKind, 'network');
    expect(resolved.paperWidth, '80mm');
    expect(resolved.displayLabel, 'Kitchen TM-T20');
    expect(
      resolved.fingerprint,
      _expectedFingerprint('network|192.168.1.50|9100'),
    );
    final destination = resolved.destination;
    expect(destination, isA<NetworkKitchenDestination>());
    expect((destination as NetworkKitchenDestination).host, '192.168.1.50');
    expect(destination.port, 9100);
  });

  test('fingerprint canonicalizes host case/whitespace; endpoint keeps the '
      'configured value', () {
    final resolution =
        resolver.resolve(
              selectedTransport: PrinterTransportKind.network,
              networkConfig: const NetworkPrinterConfig(
                host: ' KITCHEN.local ',
                port: 9100,
              ),
              bluetoothConfig: null,
              assignments: _assignments([_printer()]),
            )
            as ResolvedKitchenDestination;
    expect(
      resolution.fingerprint,
      _expectedFingerprint('network|kitchen.local|9100'),
    );
    expect(
      (resolution.destination as NetworkKitchenDestination).host,
      ' KITCHEN.local ',
    );
    // No local name -> the server assignment's display name.
    expect(resolution.displayLabel, 'Kitchen Assigned');
  });

  test('bluetooth resolution pins address + canonical fingerprint', () {
    final resolution = resolver.resolve(
      selectedTransport: PrinterTransportKind.bluetooth,
      networkConfig: null,
      bluetoothConfig: const BluetoothPrinterConfig(
        address: 'DC:0D:30:AA:BB:CC',
        name: 'BT Kitchen',
      ),
      assignments: _assignments([_printer(connectionType: 'bluetooth')]),
    );
    final resolved = resolution as ResolvedKitchenDestination;
    expect(resolved.transportKind, 'bluetooth');
    expect(
      resolved.fingerprint,
      _expectedFingerprint('bluetooth|dc:0d:30:aa:bb:cc'),
    );
    expect(
      (resolved.destination as BluetoothKitchenDestination).address,
      'DC:0D:30:AA:BB:CC',
    );
  });

  group('blocked variants (typed, endpoint-free reason codes)', () {
    test('no assignments at all -> assignment_missing', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: null,
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_printer_assignment_missing',
      );
    });

    test('a DISABLED kitchen printer does not count (D2)', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([_printer(isEnabled: false)]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_printer_assignment_missing',
      );
    });

    test('a receipt-only printer does not serve kitchen tickets', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([
          _printer(
            supportedPurposes: const ['customer_receipt'],
            configuredRole: 'receipt',
            role: 'receipt',
          ),
        ]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_printer_assignment_missing',
      );
    });

    test('no locally selected transport -> not_selected', () {
      final resolution = resolver.resolve(
        selectedTransport: null,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([_printer()]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_printer_not_selected',
      );
    });

    test('selected transport without its endpoint config -> not_selected', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: null,
        bluetoothConfig: null,
        assignments: _assignments([_printer()]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_printer_not_selected',
      );
    });

    test('local transport != assignment connection type -> mismatch', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([_printer(connectionType: 'bluetooth')]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_transport_mismatch',
      );
    });

    test('58mm-only kitchen assignment -> paper-width block (D2: exactly '
        '80mm)', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([_printer(paperWidth: '58mm')]),
      );
      expect(
        (resolution as BlockedKitchenDestination).reasonCode,
        'kitchen_paper_width_not_80mm',
      );
    });

    test('a mixed fleet picks the 80mm kitchen assignment', () {
      final resolution = resolver.resolve(
        selectedTransport: PrinterTransportKind.network,
        networkConfig: const NetworkPrinterConfig(host: 'h', port: 9100),
        bluetoothConfig: null,
        assignments: _assignments([
          _printer(id: 'prn-58', paperWidth: '58mm'),
          _printer(id: 'prn-80'),
        ]),
      );
      expect(resolution, isA<ResolvedKitchenDestination>());
      expect((resolution as ResolvedKitchenDestination).paperWidth, '80mm');
    });
  });
}
