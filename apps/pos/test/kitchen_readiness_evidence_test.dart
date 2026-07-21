import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show KitchenReadinessPaperWidth, KitchenReadinessTransportKind;
import 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show BluetoothPrinterConfig, NetworkPrinterConfig;
import 'package:restoflow_pos/src/spool/kitchen_readiness_evidence.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';

/// KITCHEN-MODE-001C3A — the pure printer-evidence derivation: D2 selection
/// (server assignment authority) with honest as-is paper-width reporting and
/// the SHARED canonical routing fingerprint. Endpoint-free by construction.
AssignedPrinter _printer({
  String id = 'pr-1',
  String role = 'kitchen',
  String? configuredRole,
  List<String> purposes = const ['kitchen_ticket'],
  String connectionType = 'network',
  String paperWidth = '80mm',
  bool isEnabled = true,
}) => AssignedPrinter(
  id: id,
  displayName: 'Kitchen Printer',
  role: role,
  connectionType: connectionType,
  paperWidth: paperWidth,
  isEnabled: isEnabled,
  configuredRole: configuredRole,
  supportedPurposes: purposes,
);

DevicePrinterAssignments _assignments(List<AssignedPrinter> printers) =>
    DevicePrinterAssignments(
      fetchedAt: DateTime.utc(2026, 7, 21),
      printers: printers,
    );

String _fp(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

void main() {
  KitchenReadinessPrinterEvidence build({
    PosPrinterTransportKind? transport = PosPrinterTransportKind.network,
    NetworkPrinterConfig? network = const NetworkPrinterConfig(
      host: '10.0.0.5',
    ),
    BluetoothPrinterConfig? bluetooth,
    DevicePrinterAssignments? assignments,
  }) => buildKitchenReadinessPrinterEvidence(
    selectedTransport: transport,
    networkConfig: network,
    bluetoothConfig: bluetooth,
    assignments: assignments,
  );

  test('no assignments / no kitchen-capable / disabled / receipt-only all '
      'block with kitchen_printer_assignment_missing', () {
    for (final assignments in [
      null,
      _assignments(const []),
      _assignments([_printer(isEnabled: false)]),
      _assignments([
        _printer(role: 'receipt', purposes: const ['customer_receipt']),
      ]),
    ]) {
      final evidence = build(assignments: assignments);
      expect(evidence, isA<BlockedKitchenPrinterEvidence>());
      expect(
        (evidence as BlockedKitchenPrinterEvidence).reasonCode,
        'kitchen_printer_assignment_missing',
      );
    }
  });

  test('no selected transport / missing endpoint config block with '
      'kitchen_printer_not_selected', () {
    final assignments = _assignments([_printer()]);
    expect(
      (build(transport: null, assignments: assignments)
              as BlockedKitchenPrinterEvidence)
          .reasonCode,
      'kitchen_printer_not_selected',
    );
    expect(
      (build(network: null, assignments: assignments)
              as BlockedKitchenPrinterEvidence)
          .reasonCode,
      'kitchen_printer_not_selected',
    );
  });

  test('transport mismatch blocks (network printer, bluetooth selected)', () {
    final evidence = build(
      transport: PosPrinterTransportKind.bluetooth,
      bluetooth: const BluetoothPrinterConfig(address: 'DC:0D:30:AA:BB:CC'),
      assignments: _assignments([_printer(connectionType: 'network')]),
    );
    expect(
      (evidence as BlockedKitchenPrinterEvidence).reasonCode,
      'kitchen_transport_mismatch',
    );
  });

  test('network evidence: SHARED canonical fingerprint (trim+lowercase), '
      'never the endpoint text; roles kitchen AND both qualify', () {
    for (final printer in [
      _printer(),
      _printer(role: 'receipt', configuredRole: 'both'),
    ]) {
      final evidence =
          build(
                network: const NetworkPrinterConfig(
                  host: '  Printer.LOCAL ',
                  port: 9100,
                ),
                assignments: _assignments([printer]),
              )
              as ReadyKitchenPrinterEvidence;
      expect(evidence.transportKind, KitchenReadinessTransportKind.network);
      expect(evidence.paperWidth, KitchenReadinessPaperWidth.mm80);
      expect(
        evidence.printerFingerprint,
        _fp('network|printer.local|9100'),
        reason: 'must match the import-path canonical derivation',
      );
      expect(evidence.printerFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(evidence.printerFingerprint, isNot(contains('printer.local')));
    }
  });

  test('bluetooth evidence: canonical lowercase address fingerprint', () {
    final evidence =
        build(
              transport: PosPrinterTransportKind.bluetooth,
              bluetooth: const BluetoothPrinterConfig(
                address: 'DC:0D:30:AA:BB:CC',
              ),
              assignments: _assignments([
                _printer(connectionType: 'bluetooth'),
              ]),
            )
            as ReadyKitchenPrinterEvidence;
    expect(evidence.transportKind, KitchenReadinessTransportKind.bluetooth);
    expect(evidence.printerFingerprint, _fp('bluetooth|dc:0d:30:aa:bb:cc'));
  });

  test(
    'F1: a 58mm-only assignment reports HONESTLY as 58mm with a NULL '
    'assignment id, but keeps its transport + fingerprint — so it is stored '
    'as a diagnostic report (never blocked locally, never activation-ready)',
    () {
      final evidence =
          build(
                network: const NetworkPrinterConfig(
                  host: '10.0.0.7',
                  port: 9100,
                ),
                assignments: _assignments([
                  _printer(id: 'pr-58', paperWidth: '58mm'),
                ]),
              )
              as ReadyKitchenPrinterEvidence;
      expect(evidence.paperWidth, KitchenReadinessPaperWidth.mm58);
      // F1: a non-80mm assignment can never be a qualifying pinned identity, so
      // the id is NULL — the truthful evidence still carries transport + a
      // fingerprint from that assignment's endpoint.
      expect(evidence.printerAssignmentId, isNull);
      expect(evidence.transportKind, KitchenReadinessTransportKind.network);
      expect(evidence.printerFingerprint, _fp('network|10.0.0.7|9100'));
    },
  );

  test('an 80mm assignment is PREFERRED when both widths exist', () {
    final evidence =
        build(
              assignments: _assignments([
                _printer(id: 'pr-58', paperWidth: '58mm'),
                _printer(id: 'pr-80'),
              ]),
            )
            as ReadyKitchenPrinterEvidence;
    expect(evidence.paperWidth, KitchenReadinessPaperWidth.mm80);
  });

  test('001C3B1A: the selected assignment id is carried, and it comes from '
      'the SAME assignment as the fingerprint/width', () {
    final evidence =
        build(assignments: _assignments([_printer(id: 'pr-abc')]))
            as ReadyKitchenPrinterEvidence;
    expect(evidence.printerAssignmentId, 'pr-abc');
  });

  test('001C3B1A: DETERMINISTIC selection — permuting the SAME collection of '
      'multiple same-transport 80mm printers selects the SAME id (lowest id, '
      'never list order)', () {
    final printers = [
      _printer(id: 'pr-c'),
      _printer(id: 'pr-a'),
      _printer(id: 'pr-b'),
    ];
    String? pick(List<AssignedPrinter> order) =>
        (build(assignments: _assignments(order)) as ReadyKitchenPrinterEvidence)
            .printerAssignmentId;
    // Every permutation of the same three 80mm printers selects 'pr-a' — and
    // pins its stable id (80mm, so eligible to be a qualifying identity).
    expect(pick(printers), 'pr-a');
    expect(pick(printers.reversed.toList()), 'pr-a');
    expect(pick([printers[1], printers[2], printers[0]]), 'pr-a');
    expect(pick([printers[2], printers[0], printers[1]]), 'pr-a');
  });

  test('001C3B1A: an 80mm printer wins over a lower-id 58mm printer (width '
      'dominates the id tie-break)', () {
    final evidence =
        build(
              assignments: _assignments([
                _printer(id: 'pr-a', paperWidth: '58mm'),
                _printer(id: 'pr-z', paperWidth: '80mm'),
              ]),
            )
            as ReadyKitchenPrinterEvidence;
    expect(evidence.printerAssignmentId, 'pr-z');
    expect(evidence.paperWidth, KitchenReadinessPaperWidth.mm80);
  });
}
