@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_kitchen/kitchen_print.dart' as kit;
import 'package:restoflow_kds/src/print/kds_native_printer.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 (BLUETOOTH-FIRST-PRINT) — KDS integration.
///
/// After a force-stop + relaunch the FIRST real kitchen ticket must reach the
/// Bluetooth printer exactly once. Pre-fix the KDS bridge resolved through
/// [activeNativeTransportFactoryProvider], which samples the persisted printer
/// selection and config with `.valueOrNull`; on the first synchronous read of a
/// fresh process those AsyncNotifiers are still loading, so the bridge fell back
/// to the loopback bridge and the first ticket never reached the printer.

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

const _address = '66:32:1E:0A:BB:CD';

void _seedSavedBluetoothProfile() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restoflow.printer.selected.kds.local': 'bluetooth',
    'restoflow.printer.bluetooth.kds.local': jsonEncode(<String, Object?>{
      'address': _address,
      'name': 'Kitchen SPP',
    }),
  });
}

/// A FRESH container over the same persisted profile — process recreation.
ProviderContainer _coldContainer(BluetoothPrinterConnector connector) {
  final container = ProviderContainer(
    overrides: [
      nativePrintingAvailableProvider.overrideWithValue(true),
      bluetoothPrinterConnectorProvider.overrideWithValue(connector),
      nativePrinterNamespaceProvider.overrideWithValue('kds'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A money-free kitchen ticket document.
kit.PrintDocument _ticket(String orderCode) => kit.PrintDocument(
  title: 'Kitchen ticket',
  lines: [
    kit.PrintLine.title('KITCHEN'),
    kit.PrintLine.subtitle(orderCode),
    kit.PrintLine.item('1 x Classic Burger', null),
    kit.PrintLine.sub('+ Extra meat x2'),
  ],
);

/// The KDS production print: resolve the ACTIVE bridge, then submit.
Future<pp.BridgeSubmitResult?> _kitchenPrint(
  ProviderContainer c,
  String orderCode,
) async {
  final bridge = await c.read(kdsActivePrintBridgeReadyProvider.future);
  return bridge?.submit(_ticket(orderCode));
}

void main() {
  test(
    'C. COLD START: the FIRST real kitchen ticket reaches the Bluetooth '
    'printer exactly once — no second ticket needed to warm the connection',
    () async {
      _seedSavedBluetoothProfile();
      final connector = _RecordingConnector();
      final container = _coldContainer(connector);

      final result = await _kitchenPrint(container, '#3F7A2C');

      expect(
        result,
        isNotNull,
        reason: 'THE DEFECT: pre-fix the first ticket had no native bridge',
      );
      expect(result!.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
      expect(connector.sent, hasLength(1), reason: 'exactly one physical send');
      expect(connector.addresses.single, _address);
    },
  );

  test('C. a LATER second ticket also sends exactly once, and the first is '
      'not discarded or replayed', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    await _kitchenPrint(container, '#0001');
    expect(connector.sent, hasLength(1));

    await _kitchenPrint(container, '#0002');
    expect(
      connector.sent,
      hasLength(2),
      reason: 'each ticket sends once — the first is never replayed',
    );
  });

  test('C. the kitchen bytes carry NO money tokens', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    await _kitchenPrint(container, '#3F7A2C');

    final blob = String.fromCharCodes(connector.sent.single);
    for (final token in const [
      '45.00',
      '4500',
      r'$',
      '€',
      'Total',
      'Subtotal',
    ]) {
      expect(
        blob,
        isNot(contains(token)),
        reason: 'a kitchen ticket must never carry money (D-007): $token',
      );
    }
  });

  test('E. PROCESS RECREATION: a brand-new container over the same persisted '
      'profile still sends the first ticket once', () async {
    _seedSavedBluetoothProfile();
    final first = _RecordingConnector();
    await _kitchenPrint(_coldContainer(first), '#0001');
    expect(first.sent, hasLength(1));

    // Force-stop + relaunch: in-memory state gone, the saved profile remains.
    final second = _RecordingConnector();
    await _kitchenPrint(_coldContainer(second), '#0002');
    expect(
      second.sent,
      hasLength(1),
      reason: 'no warm in-memory state is required for the first ticket',
    );
    expect(second.addresses.single, _address);
  });

  test('with NO saved profile the KDS bridge stays honestly unwired rather '
      'than inventing a transport', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    final bridge = await container.read(
      kdsActivePrintBridgeReadyProvider.future,
    );
    expect(bridge, isNull);
    expect(connector.sent, isEmpty);
  });
}
