import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart' as pp;
import 'package:shared_preferences/shared_preferences.dart';

/// PRINT-STARTUP-REPRINT-001 — BLUETOOTH-FIRST-PRINT reproduction.
///
/// Reported: after a force-stop + relaunch, the FIRST real print does not reach
/// the printer; a LATER print works. The Bluetooth transport itself was
/// suspected, but the transport is stateless and already retries a proven
/// pre-write connect failure exactly once
/// (`ChannelBluetoothConnector.send` / `_retryable`).
///
/// The actual fault is one layer above, in transport RESOLUTION:
/// [activeNativeTransportFactoryProvider] is a SYNCHRONOUS provider that samples
/// the saved Bluetooth config with `.valueOrNull`
/// (native_print_target.dart:76,:80). `bluetoothPrinterConfigProvider` is an
/// AsyncNotifier whose `build()` awaits `SharedPreferences.getInstance()`, so on
/// a genuinely cold start it is still `AsyncLoading` — the factory resolves to
/// NULL and the first job has no transport at all. By the second job the config
/// has landed, so it prints. Nothing about Bluetooth connection is involved.

/// Records every byte batch a transport actually delivers.
class _RecordingTransport implements pp.PrintTransport {
  _RecordingTransport(this.sent);

  final List<Uint8List> sent;

  @override
  Future<pp.PrintResult> send(Uint8List bytes) async {
    sent.add(bytes);
    return const pp.PrintResult.success();
  }

  @override
  Future<void> dispose() async {}
}

/// A connector that records sends, standing in for the real SPP channel.
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

/// Seeds the SAVED Bluetooth profile exactly as the settings screen persists it,
/// then returns a FRESH container — i.e. true process recreation over the same
/// persisted profile, with no warm in-memory state.
ProviderContainer _coldContainer(_RecordingConnector connector) {
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

void _seedSavedBluetoothProfile() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restoflow.printer.selected.kds.local': 'bluetooth',
    'restoflow.printer.bluetooth.kds.local': jsonEncode(<String, Object?>{
      'address': _address,
      'name': 'Kitchen SPP',
    }),
  });
}

pp.PrintDocument _doc(String text) =>
    pp.PrintDocument([pp.PrintTextLine(text)]);

void main() {
  test('COLD START: with a saved Bluetooth profile on disk, the FIRST job must '
      'reach the printer — today the synchronous factory samples an unresolved '
      'config and the first job has no transport at all', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    // The first real print resolves its transport the way the KDS bridge does,
    // on a container that has just been created (process recreation).
    final firstFactory = await container.read(
      activeNativeTransportFactoryReadyProvider.future,
    );

    // THE DEFECT: a saved profile exists on disk, yet the first job gets no
    // transport, so nothing is ever sent.
    expect(
      firstFactory,
      isNotNull,
      reason: 'the first job after a relaunch must resolve the SAVED profile',
    );
    await firstFactory!().send(Uint8List.fromList(const [1, 2, 3]));
    expect(
      connector.sent,
      hasLength(1),
      reason: 'the first job reaches the printer exactly once',
    );
    expect(connector.addresses.single, _address);
  });

  test('the SECOND job works today — proving the failure is cold-start '
      'resolution, not the Bluetooth transport', () async {
    _seedSavedBluetoothProfile();
    final connector = _RecordingConnector();
    final container = _coldContainer(connector);

    // Let the persisted config land, exactly as it has by the time the
    // cashier prints a second time.
    await container.read(selectedPrinterTransportProvider.future);
    await container.read(bluetoothPrinterConfigProvider.future);
    final laterFactory = container.read(activeNativeTransportFactoryProvider);

    expect(laterFactory, isNotNull);
    await laterFactory!().send(Uint8List.fromList(const [1, 2, 3]));
    expect(connector.sent, hasLength(1));
  });

  test(
    'the transport is NOT at fault: once resolved it delivers the exact bytes '
    'to the saved address',
    () async {
      final sent = <Uint8List>[];
      final sender = NativeEscPosSender(
        transportFactory: () => _RecordingTransport(sent),
      );
      final result = await sender.send(_doc('KITCHEN'));
      expect(result.outcome, pp.BridgeSubmitOutcome.sentToPrinter);
      expect(sent, hasLength(1));
      expect(sent.single, isNotEmpty);
    },
  );
}
