@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:restoflow_pos/src/print/native_print_bridges.dart';
import 'package:restoflow_pos/src/print/print_document.dart';
import 'package:restoflow_pos/src/print/receipt_logo_asset.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart'
    show posNativePrintingAvailableProvider;
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 (BLUETOOTH-FIRST-PRINT) — POS integration.
///
/// The FIRST paid customer receipt after process recreation must reach the
/// Bluetooth printer exactly once, on the SAME job, without a second order to
/// warm anything. Pre-fix the bridge was captured eagerly from a synchronous
/// provider that samples async printer configs, so it was null on the first read
/// of a fresh process and the receipt stopped at `prepared` with no Retry.

class _RecordingConnector implements BluetoothPrinterConnector {
  final List<Uint8List> sent = <Uint8List>[];
  final List<String> addresses = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<BluetoothPairedResult> pairedDevices() async =>
      const BluetoothPairedResult.ok(<BluetoothDeviceInfo>[]);

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    addresses.add(address);
    sent.add(bytes);
    return const pp.PrintResult.success();
  }
}

/// A connector whose FIRST connect fails before any byte is written (the classic
/// cold RFCOMM refusal), and whose later attempts succeed.
class _ColdThenWarmConnector extends _RecordingConnector {
  int attempts = 0;

  @override
  Future<pp.PrintResult> send({
    required String address,
    required Uint8List bytes,
    Duration timeout = kBluetoothPrintTimeout,
  }) async {
    attempts++;
    if (attempts == 1) {
      // failure BEFORE write: nothing reached the printer.
      return const pp.PrintResult.failure(
        pp.PrinterErrorCategory.unreachable,
        'cold connect refused',
      );
    }
    return super.send(address: address, bytes: bytes, timeout: timeout);
  }
}

const _address = '66:32:1E:0A:BB:CD';
const _orderKey = 'order-1';

void _seedSavedBluetoothProfile() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restoflow.printer.selected.pos.local': 'bluetooth',
    'restoflow.printer.bluetooth.pos.local': jsonEncode(<String, Object?>{
      'address': _address,
      'name': 'Counter SPP',
    }),
  });
}

/// A FRESH container over the same persisted profile — true process recreation,
/// with no warm in-memory transport state.
ProviderContainer _coldContainer(BluetoothPrinterConnector connector) {
  final container = ProviderContainer(
    overrides: [
      posNativePrintingAvailableProvider.overrideWithValue(true),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

PrintDocument _receipt() => PrintDocument(
  title: 'RECEIPT',
  lines: [PrintLine.title('RESTOFLOW'), PrintLine.center('#3F7A2C')],
);

/// Requests a receipt exactly the way the paid-order path does: readiness first,
/// then the bridge resolved AFTER it, on the same job.
Future<void> _payAndPrint(
  ProviderContainer c,
  String orderKey, {
  PrintDocument Function()? document,
}) => c
    .read(receiptPrintControllerProvider.notifier)
    .requestReceipt(
      orderKey: orderKey,
      resolveReadiness: c.read(posReceiptReadinessResolverProvider),
      buildDocument: document ?? _receipt,
      resolveBridge: () async =>
          (await c.read(posActivePrintBridgeReadyProvider.future))?.submit,
    );

void main() {
  test('B. COLD START: the FIRST paid receipt reaches the Bluetooth printer '
      'exactly once — no second order needed to warm anything', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    await _payAndPrint(container, _orderKey);

    final job = container
        .read(receiptPrintControllerProvider.notifier)
        .jobFor(_orderKey);
    expect(job, isNotNull, reason: 'the paid receipt is never dropped');
    expect(
      job!.status,
      PrintJobStatus.sentToPrinter,
      reason: 'THE DEFECT: pre-fix this stopped at `prepared` (no Retry)',
    );
    expect(connector.sent, hasLength(1), reason: 'exactly one physical send');
    expect(connector.addresses.single, _address);
  });

  test('the FIRST receipt still carries its rendered content (logo line '
      'included) — readiness and branding are unaffected', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    await _payAndPrint(
      container,
      _orderKey,
      document: () => PrintDocument(
        title: 'RECEIPT',
        lines: [PrintLine.headerImage(_logo), PrintLine.title('RESTOFLOW')],
      ),
    );

    expect(connector.sent, hasLength(1));
    expect(
      connector.sent.single,
      isNotEmpty,
      reason: 'the logo-bearing document encoded and was delivered',
    );
    expect(
      container
          .read(receiptPrintControllerProvider.notifier)
          .jobFor(_orderKey)!
          .document!
          .lines
          .any((l) => l.kind == PrintLineKind.headerImage),
      isTrue,
    );
  });

  test('D. a failure BEFORE write leaves ONE visible actionable job and does '
      'not double-send on a manual retry', () async {
    _seedSavedBluetoothProfile();
    final connector = _ColdThenWarmConnector();
    final container = _coldContainer(connector);
    final controller = container.read(receiptPrintControllerProvider.notifier);

    await _payAndPrint(container, _orderKey);

    // The pre-write refusal is surfaced, not swallowed, and is retryable:
    // both `failed` and `bridgeUnavailable` offer the Retry affordance, unlike
    // the `prepared` dead end this defect used to produce.
    final failed = controller.jobFor(_orderKey)!;
    expect(
      failed.status,
      anyOf(PrintJobStatus.failed, PrintJobStatus.bridgeUnavailable),
    );
    expect(failed.status, isNot(PrintJobStatus.prepared));
    expect(connector.sent, isEmpty, reason: 'nothing physically printed yet');

    await controller.retryReceipt(
      orderKey: _orderKey,
      resolveReadiness: container.read(posReceiptReadinessResolverProvider),
      buildDocument: _receipt,
      resolveBridge: () async => (await container.read(
        posActivePrintBridgeReadyProvider.future,
      ))?.submit,
    );

    expect(controller.jobFor(_orderKey)!.status, PrintJobStatus.sentToPrinter);
    expect(
      connector.sent,
      hasLength(1),
      reason: 'exactly ONE physical send across the failure and the retry',
    );
  });

  test(
    'D. repeated dispatch signals for one order never double-send',
    () async {
      _seedSavedBluetoothProfile();
      final connector = _RecordingConnector();
      final container = _coldContainer(connector);

      await Future.wait([
        for (var i = 0; i < 4; i++) _payAndPrint(container, _orderKey),
      ]);

      expect(connector.sent, hasLength(1));
      expect(container.read(receiptPrintControllerProvider), hasLength(1));
    },
  );

  test('E. PROCESS RECREATION: a brand-new container over the same persisted '
      'profile still sends the first job once', () async {
    _seedSavedBluetoothProfile();
    // First "process".
    final first = _RecordingConnector();
    await _payAndPrint(_coldContainer(first), _orderKey);
    expect(first.sent, hasLength(1));

    // Force-stop + relaunch: everything in memory is gone, the profile is not.
    final second = _RecordingConnector();
    await _payAndPrint(_coldContainer(second), 'order-2');
    expect(
      second.sent,
      hasLength(1),
      reason: 'no warm in-memory state is required for the first job',
    );
    expect(second.addresses.single, _address);
  });
}

final _logo = ReceiptLogoAsset(
  sourceBytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
  sourceMime: 'image/png',
);
